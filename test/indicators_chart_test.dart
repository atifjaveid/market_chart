import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';
import 'package:market_chart/src/candle_diff.dart';
import 'package:market_chart/src/indicator_views.dart';
import 'package:market_chart/src/scale.dart';

/// 2,000 one-minute candles from a random walk. Slices of it are used as
/// data, so the same index always gives the same candle.
final List<Candle> master = () {
  final random = Random(5);
  var price = 100.0;
  return [
    for (var i = 0; i < 2000; i++)
      () {
        final open = price;
        price += random.nextDouble() - 0.5;
        return Candle(
          time: DateTime.utc(2026).add(Duration(minutes: i)),
          open: open,
          high: max(open, price) + 0.2,
          low: min(open, price) - 0.2,
          close: price,
          volume: 10.0 + i % 7,
        );
      }(),
  ];
}();

const allIndicators = [
  MovingAverage.ema(20),
  MovingAverage.sma(50),
  BollingerBands(),
  Rsi(),
  Macd(),
];

Widget host(
  List<Candle> candles, {
  List<Indicator> indicators = allIndicators,
  MarketChartType type = MarketChartType.candles,
  bool showVolume = true,
  ValueChanged<Candle?>? onCrosshair,
}) =>
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: MarketChart(
            candles: candles,
            indicators: indicators,
            type: type,
            showVolume: showVolume,
            onCrosshairChanged: onCrosshair,
          ),
        ),
      ),
    );

void main() {
  group('Indicator settings', () {
    test('labels', () {
      expect(const MovingAverage.ema(20).label, 'EMA 20');
      expect(const MovingAverage.sma(50, source: PriceSource.hl2).label,
          'SMA 50 hl2');
      expect(const BollingerBands().label, 'BB 20 2');
      expect(const BollingerBands(deviations: 2.5).label, 'BB 20 2.5');
      expect(const Rsi().label, 'RSI 14');
      expect(const Macd().label, 'MACD 12 26 9');
    });

    test('equal settings are equal', () {
      expect(const MovingAverage.ema(20),
          const MovingAverage(20, type: MovingAverageType.exponential));
      expect(
          const MovingAverage.ema(20).hashCode,
          const MovingAverage(20, type: MovingAverageType.exponential)
              .hashCode);
      expect(const MovingAverage.ema(20), isNot(const MovingAverage.sma(20)));
      expect(const Rsi(), isNot(const Rsi(color: Colors.red)));
      expect(const Macd(), const Macd());
    });

    test('which ones get a panel', () {
      expect(allIndicators.map((i) => i.hasPanel),
          [false, false, false, true, true]);
    });

    test('colours and widths do not change the calculation', () {
      expect(calculationKey(const MovingAverage.ema(20, color: Colors.red)),
          calculationKey(const MovingAverage.ema(20, width: 3)));
      expect(calculationKey(const Rsi(color: Colors.red, overbought: 80)),
          calculationKey(const Rsi()));
      expect(calculationKey(const MovingAverage.ema(20)),
          isNot(calculationKey(const MovingAverage.sma(20))));
      expect(calculationKey(const BollingerBands()),
          isNot(calculationKey(const BollingerBands(deviations: 3))));
    });
  });

  group('Layout with panels', () {
    test('panels sit at the bottom, one above the other', () {
      final layout = ChartLayout.compute(const Size(400, 624),
          axisWidth: 60, showVolume: true, panelCount: 2);
      expect(layout.panels, hasLength(2));
      expect(layout.panels.last.bottom, 600);
      expect(layout.panels.first.bottom, layout.panels.last.top);
      expect(layout.panels.first.height, closeTo(600 * 0.22, 1e-9));
      expect(layout.mainArea.bottom, layout.panels.first.top);
      expect(layout.volumePane!.bottom, layout.mainArea.bottom);
      expect(layout.pricePane.bottom, lessThan(layout.volumePane!.top));
    });

    test('panels never take more than 60% of the height', () {
      final layout = ChartLayout.compute(const Size(400, 624),
          axisWidth: 60, showVolume: false, panelCount: 4);
      final panelsHeight =
          layout.panels.fold<double>(0, (sum, panel) => sum + panel.height);
      expect(panelsHeight, closeTo(600 * 0.6, 1e-9));
      expect(layout.mainArea.height, closeTo(600 * 0.4, 1e-9));
    });

    test('tiny sizes give no negative areas', () {
      final layout = ChartLayout.compute(const Size(30, 20),
          axisWidth: 60, showVolume: true, panelCount: 3);
      for (final rect in [
        layout.plot,
        layout.pricePane,
        layout.volumePane!,
        ...layout.panels,
      ]) {
        expect(rect.width, greaterThanOrEqualTo(0));
        expect(rect.height, greaterThanOrEqualTo(0));
      }
    });
  });

  group('Indicators keep up with live data', () {
    test('where updates start', () {
      final a = master.sublist(100, 200);
      expect(
          indicatorUpdateStart(diffCandles(a, master.sublist(100, 201))), 100);
      expect(
          indicatorUpdateStart(diffCandles(a, [
            ...a.take(99),
            a.last.applyTrade(1),
          ])),
          99);
      expect(indicatorUpdateStart(diffCandles(a, master.sublist(50, 200))), 0,
          reason: 'older history added');
      expect(indicatorUpdateStart(diffCandles(a, master.sublist(101, 201))), 0,
          reason: 'oldest candle dropped');
    });

    for (final indicator in const <Indicator>[
      MovingAverage.sma(10),
      MovingAverage.ema(10),
      BollingerBands(period: 10),
      Rsi(period: 7),
      Macd(fastPeriod: 4, slowPeriod: 9, signalPeriod: 3),
    ]) {
      test('${indicator.label}: the same as starting over', () {
        final random = Random(9);
        var start = 600;
        var data = master.sublist(start, start + 200);
        final live = IndicatorView.of(indicator)..update(data, 0);

        for (var step = 0; step < 300; step++) {
          final old = data;
          final roll = random.nextDouble();
          if (roll < 0.5) {
            // The latest candle moves.
            data = [
              ...data.take(data.length - 1),
              data.last.applyTrade(data.last.close + random.nextDouble() - 0.5),
            ];
          } else if (roll < 0.8 && start + data.length < master.length) {
            // A new candle.
            data = [...data, master[start + data.length]];
          } else if (roll < 0.9 && start >= 20) {
            // Older history is loaded.
            start -= 20;
            data = [...master.sublist(start, start + 20), ...data];
          } else {
            // The oldest candle is dropped (a rolling window).
            start += 1;
            data = data.sublist(1);
          }

          live.update(data, indicatorUpdateStart(diffCandles(old, data)));
          final fresh = IndicatorView.of(indicator)..update(data, 0);
          for (var k = 0; k < fresh.series.length; k++) {
            final a = live.series[k];
            final b = fresh.series[k];
            expect(a.length, b.length, reason: 'step $step');
            for (var i = 0; i < b.length; i++) {
              if (a[i] != b[i]) {
                fail('step $step, series $k, index $i: ${a[i]} != ${b[i]}');
              }
            }
          }
        }
      });
    }
  });

  group('Drawing indicators', () {
    testWidgets('every chart type, with and without volume', (tester) async {
      final candles = master.sublist(0, 300);
      for (final type in MarketChartType.values) {
        for (final showVolume in [true, false]) {
          await tester
              .pumpWidget(host(candles, type: type, showVolume: showVolume));
          expect(tester.takeException(), isNull, reason: '$type $showVolume');
        }
      }
    });

    testWidgets('too few candles, or none', (tester) async {
      await tester.pumpWidget(host(master.sublist(0, 5)));
      await tester.pumpWidget(host(master.sublist(0, 1)));
      await tester.pumpWidget(host(const []));
      expect(tester.takeException(), isNull);
    });

    testWidgets('indicators can be added, removed, reordered and recoloured',
        (tester) async {
      final candles = master.sublist(0, 300);
      for (final indicators in [
        const <Indicator>[],
        const [MovingAverage.ema(20)],
        const [Rsi(), MovingAverage.ema(20)],
        const [
          Rsi(color: Colors.red),
          MovingAverage.ema(20, color: Colors.blue)
        ],
        allIndicators,
        allIndicators.reversed.toList(),
        const [Macd()],
        const <Indicator>[],
      ]) {
        await tester.pumpWidget(host(candles, indicators: indicators));
        expect(tester.takeException(), isNull, reason: '$indicators');
      }
    });

    testWidgets('the crosshair works in the indicator panels', (tester) async {
      final reported = <Candle?>[];
      await tester
          .pumpWidget(host(master.sublist(0, 300), onCrosshair: reported.add));
      final chart = tester.getRect(find.byType(MarketChart));
      // 600 px tall: the plot is 576 px, each panel 22% of it.
      const panel = 576 * 0.22;
      for (final y in [576 - panel * 1.5, 576 - panel * 0.5]) {
        final gesture =
            await tester.startGesture(Offset(chart.left + 150, chart.top + y));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        expect(reported.last, isNotNull, reason: 'y $y');
        await gesture.up();
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('10,000 candles with all indicators and live updates',
        (tester) async {
      var candles = master.sublist(0, 1000);
      // Repeat the walk to get 10,000 candles.
      candles = [
        for (var i = 0; i < 10000; i++)
          master[i % 1000]
              .copyWith(time: DateTime.utc(2026).add(Duration(minutes: i))),
      ];
      await tester.pumpWidget(host(candles));
      final watch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        candles = [
          ...candles.take(candles.length - 1),
          candles.last.applyTrade(candles.last.close + 0.01),
        ];
        await tester.pumpWidget(host(candles));
      }
      expect(tester.takeException(), isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });
}
