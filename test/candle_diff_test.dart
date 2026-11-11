import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';
import 'package:market_chart/src/candle_diff.dart';

/// One-minute candles from minute [from]. The same minute always gives an
/// equal candle.
List<Candle> minutes(int from, int count, {double base = 100}) => [
      for (var i = from; i < from + count; i++)
        Candle(
          time: DateTime.utc(2026, 1, 1, 9).add(Duration(minutes: i)),
          open: base + i,
          high: base + i + 2,
          low: base + i - 2,
          close: base + i + 1,
          volume: 1,
        ),
    ];

void main() {
  group('diffCandles', () {
    test('finds no change in the same or an equal list', () {
      final a = minutes(0, 5);
      expect(diffCandles(a, a).hasChanges, isFalse);
      expect(diffCandles(a, List.of(a)).hasChanges, isFalse);
      expect(diffCandles(a, minutes(0, 5)).hasChanges, isFalse);
      expect(diffCandles(const [], const []).hasChanges, isFalse);
    });

    test('latest candle updated', () {
      final a = minutes(0, 5);
      final b = [...a.take(4), a.last.applyTrade(500)];
      final change = diffCandles(a, b);
      expect(change.isReset, isFalse);
      expect(change.shift, 0);
      expect(change.firstChanged, 4);
      expect(change.addedAtEnd, 0);
    });

    test('candles added at the end', () {
      final change = diffCandles(minutes(0, 5), minutes(0, 7));
      expect(change.shift, 0);
      expect(change.firstChanged, 5);
      expect(change.addedAtEnd, 2);
    });

    test('latest candle updated and a new one added', () {
      final a = minutes(0, 5);
      final b = [...a.take(4), a.last.applyTrade(500), ...minutes(5, 1)];
      final change = diffCandles(a, b);
      expect(change.firstChanged, 4);
      expect(change.addedAtEnd, 1);
    });

    test('older candles added at the start', () {
      final change = diffCandles(minutes(10, 5), minutes(0, 15));
      expect(change.isReset, isFalse);
      expect(change.shift, 10);
      expect(change.addedAtEnd, 0);
      expect(change.firstChanged, 15);
      expect(change.hasChanges, isTrue);
    });

    test('oldest candles dropped while new ones arrive', () {
      final change = diffCandles(minutes(0, 10), minutes(2, 10));
      expect(change.shift, -2);
      expect(change.addedAtEnd, 2);
      expect(change.firstChanged, 8);
    });

    test('candles removed at the end', () {
      final change = diffCandles(minutes(0, 5), minutes(0, 3));
      expect(change.addedAtEnd, -2);
      expect(change.firstChanged, 3);
      expect(change.hasChanges, isTrue);
    });

    test('a change in the middle', () {
      final a = minutes(0, 5);
      final b = List.of(a)..[2] = a[2].applyTrade(999);
      final change = diffCandles(a, b);
      expect(change.firstChanged, 2);
      expect(change.addedAtEnd, 0);
    });

    test('a different data set is a reset', () {
      expect(
          diffCandles(minutes(0, 5), minutes(0, 5, base: 500)).isReset, isTrue);
      expect(diffCandles(const [], minutes(0, 5)).isReset, isTrue);
      expect(diffCandles(minutes(0, 5), const []).isReset, isTrue);
    });

    test('stays fast with 10,000 candles', () {
      var old = minutes(0, 10000);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        final current = List.of(old)
          ..[old.length - 1] = old.last.applyTrade(100.0 + i);
        expect(diffCandles(old, current).firstChanged, 9999);
        old = current;
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  test('isOrderedByTime', () {
    expect(isOrderedByTime(minutes(0, 5)), isTrue);
    expect(isOrderedByTime(minutes(0, 5).reversed.toList()), isFalse);
    expect(isOrderedByTime(const []), isTrue);
  });
}
