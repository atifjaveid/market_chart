import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart_example/binance_feed.dart';
import 'package:market_chart_example/price_feed.dart';

import 'fake_binance.dart';

DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

void main() {
  late FakeBinance binance;
  // The last candle the server has when a test starts.
  final last = t0 + 599 * minute;

  setUp(() {
    binance = FakeBinance([
      for (var i = 0; i < 600; i++) row(t0 + i * minute, 100.0 + i),
    ]);
  });

  test('loads the latest 500 candles, then goes live', () async {
    final feed = binance.feed();
    expect(feed.name, 'BTC/USDT');
    expect(feed.status, FeedStatus.loading);
    await feed.start();

    final url = binance.requests.single;
    expect(url.host, 'data-api.binance.vision');
    expect(url.path, '/api/v3/klines');
    expect(url.queryParameters,
        {'symbol': 'BTCUSDT', 'interval': '1m', 'limit': '500'});
    expect(feed.candles, hasLength(500));
    expect(feed.candles.last.time, at(last));
    expect(feed.candles.last.close, 699);
    expect(feed.status, FeedStatus.live);
    expect(binance.socketUrls.single.toString(),
        'wss://data-stream.binance.vision/stream?streams=btcusdt@kline_1m/btcusdt@aggTrade');
  });

  test('uses the chosen timeframe', () async {
    final feed = binance.feed(symbol: 'ETHUSDT', timeframe: Timeframe.h4);
    await feed.start();
    expect(binance.requests.single.queryParameters['interval'], '4h');
    expect(binance.socketUrls.single.query,
        'streams=ethusdt@kline_4h/ethusdt@aggTrade');
    expect(feed.interval, const Duration(hours: 4));
  });

  test('candle messages keep candles exact', () async {
    final feed = binance.feed();
    await feed.start();
    binance.send(kline(last, 700.5, event: last + 10000, volume: 42));
    await settle();
    expect(feed.candles.last.close, 700.5);
    expect(feed.candles.last.volume, 42);
    expect(feed.candles, hasLength(500));

    binance.send(kline(last + minute, 701, event: last + minute + 500));
    await settle();
    expect(feed.candles, hasLength(501));
    expect(feed.candles.last.time, at(last + minute));
    expect(feed.candles.last.close, 701);
  });

  test('trades move the price between candle messages', () async {
    final feed = binance.feed();
    await feed.start();
    binance.send(kline(last, 700, event: last + 10000, volume: 42));
    binance.send(trade(705, last + 11000));
    await settle();
    expect(feed.candles.last.close, 705);
    expect(feed.candles.last.high, greaterThanOrEqualTo(705));
    // Volume comes only from candle messages.
    expect(feed.candles.last.volume, 42);

    // A candle snapshot taken before that trade doesn't undo it...
    binance.send(kline(last, 703, event: last + 10500, volume: 43));
    await settle();
    expect(feed.candles.last.close, 705);
    expect(feed.candles.last.volume, 43);

    // ...but a newer one wins.
    binance.send(kline(last, 704, event: last + 12000, volume: 44));
    await settle();
    expect(feed.candles.last.close, 704);
    expect(feed.candles.last.volume, 44);
  });

  test('a trade in a new period starts a new candle', () async {
    final feed = binance.feed();
    await feed.start();
    binance.send(trade(710, last + minute + 100));
    await settle();
    expect(feed.candles, hasLength(501));
    expect(feed.candles.last.time, at(last + minute));
    expect(feed.candles.last.open, 710);
  });

  test('ignores messages it does not understand', () async {
    final feed = binance.feed();
    await feed.start();
    binance.send('not json');
    binance.send(jsonEncode({'result': null, 'id': 1}));
    binance.send(jsonEncode({
      'data': {'e': 'kline', 'E': 1, 'k': 'oops'}
    }));
    binance.send(jsonEncode({
      'data': {'e': 'aggTrade', 'p': 'NaN?', 'T': last}
    }));
    await settle();
    expect(feed.candles.last.close, 699);
    expect(feed.status, FeedStatus.live);
  });

  test('loads older candles until there are none', () async {
    final feed = binance.feed();
    await feed.start();
    final first = feed.candles.first.time.millisecondsSinceEpoch;

    final loading = feed.loadOlder();
    expect(feed.loadingOlder, isTrue);
    await loading;
    expect(feed.loadingOlder, isFalse);
    expect(binance.requests.last.queryParameters['endTime'], '${first - 1}');
    expect(feed.candles, hasLength(600));
    expect(feed.candles.first.time, at(t0));

    await feed.loadOlder(); // Finds nothing older...
    final asked = binance.requests.length;
    await feed.loadOlder(); // ...so it stops asking.
    expect(binance.requests.length, asked);
  });

  test('reconnects and catches up when the connection drops', () async {
    final feed = binance.feed();
    await feed.start();
    final statuses = <FeedStatus>[];
    feed.addListener(() => statuses.add(feed.status));

    // Two more candles happen while the connection is down.
    binance.history
      ..add(row(last + minute, 800))
      ..add(row(last + 2 * minute, 801));
    await binance.sockets.single.foreign.sink.close();
    await settle();

    expect(statuses, contains(FeedStatus.reconnecting));
    expect(binance.sockets, hasLength(2));
    expect(binance.requests.last.queryParameters['startTime'], '$last');
    expect(feed.candles, hasLength(502));
    expect(feed.candles.last.close, 801);
    expect(feed.status, FeedStatus.live);
  });

  test('keeps trying while the socket cannot connect', () async {
    binance.refuseSockets = true;
    final feed = binance.feed();
    await feed.start();
    await settle();
    expect(feed.status, FeedStatus.reconnecting);
    expect(feed.candles, hasLength(500));
    expect(binance.socketUrls.length, greaterThan(1));

    binance.refuseSockets = false;
    await settle();
    expect(feed.status, FeedStatus.live);
  });

  test('treats a silent connection as lost', () async {
    final feed = binance.feed(silenceTimeout: const Duration(milliseconds: 20));
    await feed.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(binance.sockets.length, greaterThan(1));
  });

  test('reports why loading failed', () async {
    binance.statusCode = 451;
    final feed = binance.feed();
    await feed.start();
    expect(feed.status, FeedStatus.failed);
    expect(feed.error, isA<BinanceException>());
    expect(describeFeedError(feed.error),
        "Binance isn't available in this location");
    expect(binance.sockets, isEmpty);
  });

  test('closes the socket when disposed', () async {
    final feed = BinanceFeed(
      symbol: 'BTCUSDT',
      client: binance.client,
      connect: binance.connect,
    );
    await feed.start();
    var closed = false;
    binance.sockets.single.foreign.stream
        .listen(null, onDone: () => closed = true);
    feed.dispose();
    await settle();
    expect(closed, isTrue);
  });

  test('candleFromRow reads REST candles', () {
    final candle = candleFromRow(jsonDecode(jsonEncode(row(t0, 64000.5))));
    expect(candle.time, at(t0));
    expect(candle.open, 64000.5);
    expect(candle.high, 64001.5);
    expect(candle.low, 63999.5);
    expect(candle.volume, 1);
    expect(() => candleFromRow([1, 2]), throwsFormatException);
  });
}
