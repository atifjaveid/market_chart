import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:market_chart/market_chart.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'price_feed.dart';

/// Candle lengths offered by Binance that line up with [CandleAggregator]'s
/// periods. (Binance's weekly and monthly candles don't.)
enum Timeframe {
  m1('1m', Duration(minutes: 1)),
  m5('5m', Duration(minutes: 5)),
  m15('15m', Duration(minutes: 15)),
  h1('1h', Duration(hours: 1)),
  h4('4h', Duration(hours: 4)),
  d1('1d', Duration(days: 1));

  const Timeframe(this.code, this.duration);

  /// Binance's name for it, such as `1m`.
  final String code;

  /// The time between candles.
  final Duration duration;
}

/// Opens a WebSocket and completes once it is connected. Tests pass a fake.
typedef Connect = Future<StreamChannel<dynamic>> Function(Uri url);

/// Opens a real WebSocket.
Future<StreamChannel<dynamic>> connectWebSocket(Uri url) async {
  final channel = WebSocketChannel.connect(url);
  try {
    await channel.ready.timeout(const Duration(seconds: 10));
  } catch (_) {
    unawaited(channel.sink.close());
    rethrow;
  }
  return channel;
}

/// 1, 2, 4, 8, 16, then 30 seconds between reconnection attempts.
Duration defaultRetryDelay(int attempt) =>
    Duration(seconds: min(30, 1 << min(attempt, 5)));

/// Binance answered, but not with candles.
class BinanceException implements Exception {
  /// Creates an exception for an HTTP [statusCode].
  const BinanceException(this.statusCode);

  /// The HTTP status code Binance answered with.
  final int statusCode;

  @override
  String toString() => switch (statusCode) {
        451 => "Binance isn't available in this location",
        418 || 429 => 'Too many requests to Binance. Try again in a minute',
        400 => "Binance doesn't know this market",
        _ => 'Binance answered with HTTP $statusCode',
      };
}

/// A short explanation of why a feed failed, for showing to users.
String describeFeedError(Object? error) => switch (error) {
      BinanceException() => error.toString(),
      TimeoutException() => "Binance didn't answer in time",
      http.ClientException() => "Couldn't connect to Binance",
      FormatException() => 'Binance sent something unexpected',
      _ => "Couldn't load prices",
    };

/// Turns a candle from Binance's REST API (`[openTime, "open", "high",
/// "low", "close", "volume", ...]`) into a [Candle].
Candle candleFromRow(Object? row) {
  if (row
      case [
        final int time,
        final String open,
        final String high,
        final String low,
        final String close,
        final String volume,
        ...
      ]) {
    return Candle(
      time: DateTime.fromMillisecondsSinceEpoch(time),
      open: double.parse(open),
      high: double.parse(high),
      low: double.parse(low),
      close: double.parse(close),
      volume: double.parse(volume),
    );
  }
  throw FormatException('Unexpected candle: $row');
}

/// Live prices from Binance's public market data. No account or API key is
/// needed.
///
/// History comes from the REST API. Two WebSocket streams then keep it live:
/// Binance's candle stream (every 2 seconds) keeps each candle exact, and
/// the trade stream moves the price with every trade in between.
class BinanceFeed extends PriceFeed {
  /// Creates a feed for [symbol], such as `BTCUSDT`.
  BinanceFeed({
    required this.symbol,
    this.timeframe = Timeframe.m1,
    http.Client? client,
    Connect? connect,
    this.retryDelay = defaultRetryDelay,
    this.silenceTimeout = const Duration(seconds: 10),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _connect = connect ?? connectWebSocket;

  static const _restUrl = 'https://data-api.binance.vision/api/v3/klines';
  static const _socketUrl = 'wss://data-stream.binance.vision/stream';

  /// The market, such as `BTCUSDT`.
  final String symbol;

  /// The time between candles.
  final Timeframe timeframe;

  /// How long to wait before reconnection attempt number `attempt` (from 0).
  final Duration Function(int attempt) retryDelay;

  /// How long without any message before the connection counts as lost.
  /// Binance sends candles every 2 seconds, so silence means trouble.
  final Duration silenceTimeout;

  final http.Client _client;
  final bool _ownsClient;
  final Connect _connect;
  late final _feed = CandleAggregator(interval: timeframe.duration);

  StreamChannel<dynamic>? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _silenceTimer;
  var _attempt = 0;
  var _missedUpdates = false;
  var _status = FeedStatus.loading;
  Object? _error;
  var _loadingOlder = false;
  var _reachedStart = false;
  var _disposed = false;
  ({double price, int time})? _lastTrade;

  @override
  String get name => symbol.endsWith('USDT')
      ? '${symbol.substring(0, symbol.length - 4)}/USDT'
      : symbol;

  @override
  Duration get interval => timeframe.duration;

  @override
  List<Candle> get candles => _feed.candles;

  @override
  FeedStatus get status => _status;

  @override
  Object? get error => _error;

  @override
  bool get loadingOlder => _loadingOlder;

  @override
  Future<void> start() async {
    try {
      final history = await _fetch(limit: 500);
      if (_disposed) return;
      if (history.isEmpty) throw const FormatException('No candles');
      _feed.addHistory(history);
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      _error = error;
      _setStatus(FeedStatus.failed);
      return;
    }
    await _openSocket();
  }

  @override
  Future<void> loadOlder() async {
    if (_loadingOlder || _reachedStart || candles.isEmpty) return;
    _loadingOlder = true;
    notifyListeners();
    try {
      final first = candles.first.time.millisecondsSinceEpoch;
      final older = await _fetch(limit: 500, endTime: first - 1);
      if (_disposed) return;
      if (older.isEmpty) _reachedStart = true;
      _feed.addHistory(older);
    } catch (_) {
      // Nothing to do: the chart asks again when the user scrolls back.
    } finally {
      _loadingOlder = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<List<Candle>> _fetch({
    required int limit,
    int? startTime,
    int? endTime,
  }) async {
    final url = Uri.parse(_restUrl).replace(queryParameters: {
      'symbol': symbol,
      'interval': timeframe.code,
      'limit': '$limit',
      if (startTime != null) 'startTime': '$startTime',
      if (endTime != null) 'endTime': '$endTime',
    });
    final response =
        await _client.get(url).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw BinanceException(response.statusCode);
    }
    final rows = jsonDecode(response.body);
    if (rows is! List) throw const FormatException('Expected a list');
    return [for (final row in rows) candleFromRow(row)];
  }

  Future<void> _openSocket() async {
    // The candle and trade streams, combined on one connection.
    final stream = symbol.toLowerCase();
    final url = Uri.parse(
        '$_socketUrl?streams=$stream@kline_${timeframe.code}/$stream@aggTrade');
    final StreamChannel<dynamic> channel;
    try {
      channel = await _connect(url);
    } catch (_) {
      _reconnectLater();
      return;
    }
    if (_disposed) {
      unawaited(channel.sink.close());
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object _) => _reconnectLater(),
      onDone: _reconnectLater,
      cancelOnError: true,
    );
    _watchForSilence();
    if (_missedUpdates) await _catchUp();
    if (!_disposed && _channel == channel) _setStatus(FeedStatus.live);
  }

  /// Fetches the candles that changed while the connection was down.
  Future<void> _catchUp() async {
    if (candles.isEmpty) return;
    try {
      final missed = await _fetch(
          limit: 1000, startTime: candles.last.time.millisecondsSinceEpoch);
      if (_disposed) return;
      missed.forEach(_feed.addCandle);
      _missedUpdates = false;
      notifyListeners();
    } catch (_) {
      // Try again after the next reconnection.
    }
  }

  void _reconnectLater() {
    if (_disposed) return;
    _closeSocket();
    _missedUpdates = true;
    _setStatus(FeedStatus.reconnecting);
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay(_attempt++), _openSocket);
  }

  void _closeSocket() {
    _silenceTimer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }

  void _watchForSilence() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(silenceTimeout, _reconnectLater);
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final json = jsonDecode(message);
      final data = json is Map && json['data'] is Map ? json['data'] : json;
      switch (data) {
        case {
            'e': 'kline',
            'E': final int eventTime,
            'k': {
              't': final int time,
              'o': final String open,
              'h': final String high,
              'l': final String low,
              'c': final String close,
              'v': final String volume,
            },
          }:
          _onCandle(
            Candle(
              time: DateTime.fromMillisecondsSinceEpoch(time),
              open: double.parse(open),
              high: double.parse(high),
              low: double.parse(low),
              close: double.parse(close),
              volume: double.parse(volume),
            ),
            eventTime,
          );
        case {'e': 'aggTrade', 'p': final String price, 'T': final int time}:
          _onTrade(double.parse(price), time);
        default:
          return;
      }
    } on FormatException {
      return;
    }
    // Messages are arriving, so the connection is fine.
    _attempt = 0;
    _watchForSilence();
    notifyListeners();
  }

  /// A snapshot of a candle, taken at [eventTime].
  void _onCandle(Candle candle, int eventTime) {
    _feed.addCandle(candle);
    // A trade that came in after the snapshot was taken has already moved
    // the price on, so keep it.
    final trade = _lastTrade;
    final start = candle.time.millisecondsSinceEpoch;
    if (trade != null &&
        trade.time > eventTime &&
        trade.time >= start &&
        trade.time < start + interval.inMilliseconds) {
      _feed.addTrade(trade.price,
          time: DateTime.fromMillisecondsSinceEpoch(trade.time));
    }
  }

  void _onTrade(double price, int time) {
    _lastTrade = (price: price, time: time);
    // No volume here: the candle stream has the exact volume.
    _feed.addTrade(price, time: DateTime.fromMillisecondsSinceEpoch(time));
  }

  void _setStatus(FeedStatus status) {
    if (status == _status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _closeSocket();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
