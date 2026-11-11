import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';

DateTime at(int minute, [int second = 0]) =>
    DateTime.utc(2026, 1, 1, 9, minute, second);

CandleAggregator minuteFeed({
  bool fillGaps = false,
  int? maxCandles,
  List<Candle> initialCandles = const [],
}) =>
    CandleAggregator(
      interval: const Duration(minutes: 1),
      fillGaps: fillGaps,
      maxCandles: maxCandles,
      initialCandles: initialCandles,
    );

void main() {
  test('trades in the same period update one candle', () {
    final feed = minuteFeed()
      ..addTrade(10, volume: 1, time: at(0, 5))
      ..addTrade(12, volume: 2, time: at(0, 30))
      ..addTrade(9, time: at(0, 59));
    expect(feed.candles, [
      Candle(time: at(0), open: 10, high: 12, low: 9, close: 9, volume: 3),
    ]);
  });

  test('a trade in a new period starts a new candle', () {
    final feed = minuteFeed()
      ..addTrade(10, time: at(0, 10))
      ..addTrade(11, volume: 4, time: at(1));
    expect(feed.candles, hasLength(2));
    expect(feed.candles.last, Candle.flat(time: at(1), price: 11, volume: 4));
  });

  test('periods line up with the interval', () {
    final fiveMinutes = CandleAggregator(interval: const Duration(minutes: 5));
    expect(fiveMinutes.periodStart(DateTime.utc(2026, 1, 1, 10, 3, 20)),
        DateTime.utc(2026, 1, 1, 10));
    expect(fiveMinutes.periodStart(DateTime.utc(1969, 12, 31, 23, 58)),
        DateTime.utc(1969, 12, 31, 23, 55));

    final daily = CandleAggregator(interval: const Duration(days: 1));
    expect(daily.periodStart(DateTime.utc(2026, 3, 5, 14, 30)),
        DateTime.utc(2026, 3, 5));

    final weekly = CandleAggregator(
      interval: const Duration(days: 7),
      origin: DateTime.utc(1970, 1, 5), // A Monday.
    );
    expect(weekly.periodStart(DateTime.utc(2026, 11, 11, 8)),
        DateTime.utc(2026, 11, 9));
  });

  test('new candles use the same kind of time as existing ones', () {
    final feed =
        minuteFeed(initialCandles: [Candle.flat(time: at(0), price: 10)])
          ..addTrade(11, time: at(5).toLocal());
    expect(feed.candles.last.time.isUtc, isTrue);
    expect(feed.candles.last.time, at(5));
  });

  test('fillGaps adds flat candles for quiet periods', () {
    final filled = minuteFeed(fillGaps: true)
      ..addTrade(10, volume: 1, time: at(0))
      ..addTrade(12, volume: 1, time: at(3));
    expect(filled.candles.map((c) => c.time), [at(0), at(1), at(2), at(3)]);
    expect(filled.candles[1], Candle.flat(time: at(1), price: 10));

    final skipped = minuteFeed()
      ..addTrade(10, time: at(0))
      ..addTrade(12, time: at(3));
    expect(skipped.candles, hasLength(2));
  });

  test('maxCandles drops the oldest candles', () {
    final feed = minuteFeed(maxCandles: 3);
    for (var i = 0; i < 5; i++) {
      feed.addTrade(10.0 + i, time: at(i));
    }
    expect(feed.candles.map((c) => c.time), [at(2), at(3), at(4)]);
  });

  test('fillGaps never fills more than maxCandles', () {
    final feed = minuteFeed(fillGaps: true, maxCandles: 5)
      ..addTrade(10, time: at(0))
      ..addTrade(11, time: at(50));
    expect(feed.candles.map((c) => c.time),
        [at(46), at(47), at(48), at(49), at(50)]);
  });

  test('a late trade stretches an older candle but keeps its close', () {
    final feed = minuteFeed()
      ..addTrade(10, volume: 1, time: at(0))
      ..addTrade(11, time: at(1))
      ..addTrade(15, volume: 2, time: at(0, 30));
    expect(feed.candles.first,
        Candle(time: at(0), open: 10, high: 15, low: 10, close: 10, volume: 3));
  });

  test('a late trade for a period that is not in the list is ignored', () {
    final feed = minuteFeed()
      ..addTrade(10, time: at(0))
      ..addTrade(11, time: at(5))
      ..addTrade(99, time: at(2));
    expect(feed.candles, hasLength(2));
    expect(feed.candles.every((c) => c.high < 99), isTrue);
  });

  test('trades without a time use the clock', () {
    final feed = CandleAggregator(
      interval: const Duration(minutes: 1),
      clock: () => at(7, 42),
    )..addTrade(10);
    expect(feed.candles.single.time, at(7));
  });

  test('addCandle replaces, appends and inserts by time', () {
    final feed = minuteFeed(initialCandles: [
      Candle.flat(time: at(0), price: 1),
      Candle.flat(time: at(2), price: 3),
    ])
      ..addCandle(Candle.flat(time: at(2), price: 4))
      ..addCandle(Candle.flat(time: at(3), price: 5))
      ..addCandle(Candle.flat(time: at(1), price: 2));
    expect(feed.candles.map((c) => c.close), [1, 2, 4, 5]);
  });

  test('addHistory adds only older candles, in order, first one per time', () {
    final feed =
        minuteFeed(initialCandles: [Candle.flat(time: at(10), price: 10)])
          ..addHistory([
            Candle.flat(time: at(12), price: 12),
            Candle.flat(time: at(5), price: 5),
            Candle.flat(time: at(7), price: 7),
            Candle.flat(time: at(6), price: 6),
            Candle.flat(time: at(7), price: 7.5),
          ]);
    expect(feed.candles.map((c) => c.close), [5, 6, 7, 10]);
  });

  test('candles is read-only and clear empties it', () {
    final feed = minuteFeed()..addTrade(10, time: at(0));
    expect(() => feed.candles.add(Candle.flat(time: at(1), price: 1)),
        throwsUnsupportedError);
    feed.clear();
    expect(feed.candles, isEmpty);
  });
}
