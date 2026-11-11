import 'dart:async';
import 'dart:math';

import 'package:market_chart/market_chart.dart';

import 'price_feed.dart';

/// Made-up prices, shown when Binance can't be reached: a trade four times a
/// second, built into 5-second candles by [CandleAggregator.addTrade].
class SimulatedFeed extends PriceFeed {
  /// Creates a feed with 400 candles of made-up history.
  SimulatedFeed({Random? random, DateTime? now})
      : _random = random ?? Random(7) {
    final current = Candle.flat(
        time: _feed.periodStart(now ?? DateTime.now()), price: 64000);
    _feed.addHistory([
      ...simulateCandlesBefore(current, 400, interval, _random),
      current,
    ]);
  }

  final Random _random;
  late final _feed = CandleAggregator(interval: interval);
  Timer? _timer;
  var _loadingOlder = false;
  var _disposed = false;

  @override
  String get name => 'BTC/USD (simulated)';

  @override
  Duration get interval => const Duration(seconds: 5);

  @override
  List<Candle> get candles => _feed.candles;

  @override
  FeedStatus get status => FeedStatus.live;

  @override
  Object? get error => null;

  @override
  bool get loadingOlder => _loadingOlder;

  @override
  Future<void> start() async {
    _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      final last = _feed.candles.last.close;
      _feed.addTrade(
        last * (1 + (_random.nextDouble() - 0.5) * 0.0012),
        volume: _random.nextDouble() * 3,
      );
      notifyListeners();
    });
  }

  @override
  Future<void> loadOlder() async {
    if (_loadingOlder) return;
    _loadingOlder = true;
    notifyListeners();
    // Pretend to fetch older candles from a server.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (_disposed) return;
    _feed.addHistory(
        simulateCandlesBefore(_feed.candles.first, 300, interval, _random));
    _loadingOlder = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// [count] simulated candles that end just before [next], walking the price
/// backwards so the last one closes where [next] opens.
List<Candle> simulateCandlesBefore(
  Candle next,
  int count,
  Duration interval,
  Random random,
) {
  final candles = <Candle>[];
  var close = next.open;
  for (var i = 1; i <= count; i++) {
    final open = close * (1 + (random.nextDouble() - 0.5) * 0.004);
    candles.add(Candle(
      time: next.time.subtract(interval * i),
      open: open,
      high: max(open, close) * (1 + random.nextDouble() * 0.0015),
      low: min(open, close) * (1 - random.nextDouble() * 0.0015),
      close: close,
      volume: 20 + random.nextDouble() * 80,
    ));
    close = open;
  }
  return candles.reversed.toList();
}
