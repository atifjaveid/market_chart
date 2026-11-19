import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';
import 'package:market_chart/src/scale.dart';
import 'package:market_chart/src/time_axis.dart';

List<Candle> at(Iterable<DateTime> times) =>
    [for (final t in times) Candle.flat(time: t, price: 100)];

List<DateTime> every(DateTime start, Duration step, int count) =>
    [for (var i = 0; i < count; i++) start.add(step * i)];

List<DateTime> labelTimes(
        List<Candle> candles, Duration interval, double candlesPerLabel) =>
    [
      for (final l in timeAxisLabels(
          candles, 0, candles.length - 1, interval, candlesPerLabel))
        l.time
    ];

String axisText(TimeAxisLabel label, Duration interval) =>
    defaultTimeFormatter(label.time, interval, TimeLabelKind.axis);

void main() {
  group('time axis labels', () {
    test('go at round times', () {
      // 13:52 to 14:40, a label about every 11 candles: every 15 minutes.
      final candles = at(every(
          DateTime.utc(2026, 3, 2, 13, 52), const Duration(minutes: 1), 49));
      final labels =
          timeAxisLabels(candles, 0, 48, const Duration(minutes: 1), 90 / 8);
      expect(labels.map((l) => l.index), [8, 23, 38]);
      expect(labels.map((l) => axisText(l, const Duration(minutes: 1))),
          ['14:00', '14:15', '14:30']);
      expect(labels.every((l) => l.rank == 0), isTrue);
    });

    test('stay on the same candles when older candles are added', () {
      const interval = Duration(minutes: 1);
      final times = every(DateTime.utc(2026, 3, 2, 13, 52), interval, 49);
      final before = labelTimes(at(times), interval, 11.25);
      final older = every(DateTime.utc(2026, 3, 2, 13, 2), interval, 50);
      final after = labelTimes(at([...older, ...times]), interval, 11.25);
      expect(after, containsAllInOrder(before));
      // Plus 13:15, 13:30 and 13:45.
      expect(after.length, before.length + 3);
    });

    test('only look at the visible candles', () {
      final candles = at(every(
          DateTime.utc(2026, 3, 2, 13, 52), const Duration(minutes: 1), 49));
      final labels =
          timeAxisLabels(candles, 20, 40, const Duration(minutes: 1), 11.25);
      expect(labels.map((l) => l.index), [23, 38]);
    });

    test('show the date when a new day starts', () {
      const interval = Duration(hours: 1);
      final candles =
          at(every(DateTime.utc(2026, 3, 1, 20), interval, 10)); // to 05:00
      final labels = timeAxisLabels(candles, 0, 9, interval, 3);
      expect(labels.map((l) => axisText(l, interval)),
          ['21:00', 'Mar 2', '03:00']);
      expect(labels.map((l) => l.rank), [0, 1, 0]);
      expect(labels[1].time, DateTime.utc(2026, 3, 2));
    });

    test('mark new days even when candles start at 01:00', () {
      // 4-hour candles at 01:00, 05:00, ... as in time zones such as UTC+5.
      const interval = Duration(hours: 4);
      final candles = at(every(DateTime.utc(2026, 3, 1, 1), interval, 18));
      final labels = timeAxisLabels(candles, 0, 17, interval, 4);
      expect(labels.map((l) => l.index), [6, 12]);
      expect(labels.map((l) => axisText(l, interval)), ['Mar 2', 'Mar 3']);
    });

    test('show the year when daily candles start a new year', () {
      const interval = Duration(days: 1);
      final candles = at(every(DateTime.utc(2026, 11, 1), interval, 150));
      final labels = timeAxisLabels(candles, 0, 149, interval, 40);
      expect(labels.map((l) => axisText(l, interval)), ['2027', 'Mar 1']);
      expect(labels.map((l) => l.rank), [3, 2]);
    });

    test('use weeks starting on Monday', () {
      const interval = Duration(days: 1);
      final candles = at(every(DateTime.utc(2026, 3, 1), interval, 40));
      final labels = timeAxisLabels(candles, 0, 39, interval, 6);
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(candles[label.index].time.weekday, DateTime.monday);
      }
    });

    test('handle gaps, such as weekends', () {
      const interval = Duration(days: 1);
      final weekdays = [
        for (final t in every(DateTime.utc(2026, 3, 1), interval, 60))
          if (t.weekday <= DateTime.friday) t
      ];
      final candles = at(weekdays);
      final labels =
          timeAxisLabels(candles, 0, candles.length - 1, interval, 4);
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(candles[label.index].time.weekday, DateTime.monday);
      }
    });

    test('use seconds for short candles', () {
      const interval = Duration(seconds: 5);
      final candles =
          at(every(DateTime.utc(2026, 3, 2, 9, 0, 35), interval, 60));
      final labels = timeAxisLabels(candles, 0, 59, interval, 11.25);
      expect(labels.map((l) => axisText(l, interval)),
          ['09:01:00', '09:02:00', '09:03:00', '09:04:00', '09:05:00']);
    });

    test('work with local times', () {
      const interval = Duration(minutes: 30);
      final candles = at(every(DateTime(2026, 6, 10, 18), interval, 20));
      final labels = timeAxisLabels(candles, 0, 19, interval, 4);
      expect(labels, isNotEmpty);
      final midnight = labels.where((l) => l.rank == 1).single;
      expect(midnight.time, DateTime(2026, 6, 11));
      expect(midnight.time.isUtc, isFalse);
    });

    test('need at least two candles', () {
      final one = at([DateTime.utc(2026)]);
      expect(
          timeAxisLabels(one, 0, 0, const Duration(minutes: 1), 10), isEmpty);
      expect(timeAxisLabels(const [], 0, -1, const Duration(minutes: 1), 10),
          isEmpty);
    });
  });

  group('detectPricePrecision', () {
    List<Candle> prices(List<double> values) => [
          for (var i = 0; i < values.length; i++)
            Candle.flat(time: DateTime.utc(2026, 1, 1, 0, i), price: values[i])
        ];

    test('uses the decimals the prices have', () {
      expect(detectPricePrecision(prices([73720.01, 73721.5, 73719])), 2);
      expect(detectPricePrecision(prices([2.3405, 2.341, 2.3399])), 4);
      expect(detectPricePrecision(prices([0.17891, 0.1789])), 5);
      expect(detectPricePrecision(prices([0.00001234, 0.00001235])), 8);
      expect(detectPricePrecision(prices([1.08345, 1.0835])), 5);
    });

    test('shows at least autoPrecision', () {
      expect(detectPricePrecision(prices([100, 101, 99])), 2);
      expect(detectPricePrecision(prices([1.1 + 2.2])), 2);
      expect(detectPricePrecision(prices([0.05, 0.06])), 5);
      expect(detectPricePrecision(const []), 2);
    });

    test('falls back to autoPrecision for calculated prices', () {
      final random = Random(1);
      final values = [
        for (var i = 0; i < 30; i++) 64000 * (1 + random.nextDouble() / 100)
      ];
      expect(detectPricePrecision(prices(values)), 2);
    });

    test('looks at the latest candles', () {
      expect(
        detectPricePrecision(prices([
          for (var i = 0; i < 60; i++) i < 10 ? 100.123456 : 100.25,
        ])),
        2,
      );
    });
  });

  group('niceTicks with a minimum step', () {
    test('keeps steps whole multiples of it', () {
      final plain = niceTicks(0, 0.11, 5);
      expect(plain.length, 5);
      expect(plain[1], closeTo(0.025, 1e-12));
      final ticks = niceTicks(0, 0.11, 5, minStep: 0.01);
      expect(ticks.length, 6);
      for (var k = 0; k < ticks.length; k++) {
        expect(ticks[k], closeTo(k * 0.02, 1e-12));
      }
    });

    test('is never finer than it', () {
      expect(niceTicks(100, 100.05, 5, minStep: 0.1), [closeTo(100, 1e-9)]);
      expect(niceTicks(100, 100.05, 5).length, greaterThan(3));
    });

    test('leaves coarser steps alone', () {
      expect(niceTicks(0, 100, 5, minStep: 0.01), [0, 20, 40, 60, 80, 100]);
    });
  });

  testWidgets('chart draws real-world shaped data', (tester) async {
    // 4-hour candles at 01:00 with four decimals, like XRP in UTC+5.
    final random = Random(3);
    var price = 2.3405;
    final candles = <Candle>[];
    for (var i = 0; i < 300; i++) {
      final open = price;
      price = ((price * (1 + (random.nextDouble() - 0.5) / 50)) * 1e4)
              .roundToDouble() /
          1e4;
      candles.add(Candle(
        time: DateTime.utc(2026, 1, 1, 1).add(Duration(hours: 4 * i)),
        open: open,
        high: max(open, price) + 0.0012,
        low: min(open, price) - 0.0009,
        close: price,
        volume: 1000 + i.toDouble(),
      ));
    }
    for (final width in [2.0, 8.0, 48.0]) {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 800,
          height: 500,
          child: MarketChart(
            key: ValueKey(width),
            candles: candles,
            initialCandleWidth: width,
            indicators: const [MovingAverage.ema(20), Macd()],
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
