import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';
import 'package:market_chart/src/scale.dart';

List<Candle> sampleCandles(int count) {
  final start = DateTime(2026, 1, 1, 9);
  return List.generate(count, (i) {
    final open = 100.0 + i;
    final close = i.isEven ? open + 2 : open - 2;
    return Candle(
      time: start.add(Duration(minutes: i)),
      open: open,
      high: open + 3,
      low: open - 3,
      close: close,
      volume: 10.0 + i,
    );
  });
}

void main() {
  group('Candle', () {
    test('isBullish', () {
      expect(sampleCandles(2)[0].isBullish, isTrue);
      expect(sampleCandles(2)[1].isBullish, isFalse);
    });

    test('applyTrade updates close, high, low and volume', () {
      final candle = Candle.flat(time: DateTime(2026), price: 10, volume: 1);
      final up = candle.applyTrade(12, volume: 2);
      expect(
        up,
        Candle(
          time: DateTime(2026),
          open: 10,
          high: 12,
          low: 10,
          close: 12,
          volume: 3,
        ),
      );
      final down = up.applyTrade(8);
      expect(down.low, 8);
      expect(down.high, 12);
      expect(down.close, 8);
    });
  });

  group('formatting', () {
    test('formatPrice adds thousands separators', () {
      expect(formatPrice(64250.5, 2), '64,250.50');
      expect(formatPrice(-1234567, 0), '-1,234,567');
      expect(formatPrice(0.05123, 5), '0.05123');
      expect(formatPrice(double.nan, 2), '-');
    });

    test('formatCompact', () {
      expect(formatCompact(950), '950');
      expect(formatCompact(1250), '1.25K');
      expect(formatCompact(3400000), '3.40M');
      expect(formatCompact(2.1e9), '2.10B');
    });

    test('autoPrecision', () {
      expect(autoPrecision(64000), 2);
      expect(autoPrecision(1.5), 2);
      expect(autoPrecision(0.5), 4);
      expect(autoPrecision(0.05123), 5);
      expect(autoPrecision(0), 2);
    });

    test('defaultTimeFormatter', () {
      final t = DateTime(2026, 3, 5, 14, 30);
      const minute = Duration(minutes: 1);
      const day = Duration(days: 1);
      expect(defaultTimeFormatter(t, minute, TimeLabelKind.axis), '14:30');
      expect(defaultTimeFormatter(t, minute, TimeLabelKind.crosshair),
          'Mar 5 14:30');
      expect(defaultTimeFormatter(t, day, TimeLabelKind.axis), 'Mar 5');
      expect(
          defaultTimeFormatter(t, day, TimeLabelKind.crosshair), 'Mar 5, 2026');
    });

    test('defaultTimeFormatter shows seconds for short candles', () {
      final t = DateTime(2026, 3, 5, 14, 30, 5);
      const fiveSeconds = Duration(seconds: 5);
      expect(
          defaultTimeFormatter(t, fiveSeconds, TimeLabelKind.axis), '14:30:05');
      expect(defaultTimeFormatter(t, fiveSeconds, TimeLabelKind.crosshair),
          'Mar 5 14:30:05');
    });
  });

  test('MarketChartTheme fontFamily', () {
    expect(MarketChartTheme.dark.textStyle.fontFamily, isNull);
    final inter = MarketChartTheme.dark.copyWith(fontFamily: 'Inter');
    expect(inter.textStyle.fontFamily, 'Inter');
    expect(inter, isNot(MarketChartTheme.dark));
    expect(inter, MarketChartTheme.dark.copyWith(fontFamily: 'Inter'));
  });

  group('niceTicks', () {
    test('uses round steps', () {
      expect(niceTicks(0, 100, 5), [0, 20, 40, 60, 80, 100]);
      final ticks = niceTicks(63912, 64388, 5);
      expect(ticks.first, 64000);
      expect(ticks[1] - ticks[0], closeTo(100, 1e-9));
    });

    test('returns nothing for an empty range', () {
      expect(niceTicks(5, 5, 4), isEmpty);
      expect(niceTicks(0, double.infinity, 4), isEmpty);
    });
  });

  group('ChartViewport', () {
    const viewport = ChartViewport(
      candleCount: 100,
      width: 400,
      candleWidth: 10,
      scrollOffset: 35,
    );

    test('xForIndex and indexAt are inverses', () {
      for (final i in [0, 42, 99]) {
        expect(viewport.indexAt(viewport.xForIndex(i)), closeTo(i, 1e-9));
      }
    });

    test('the latest candle sits inside the right edge when not scrolled', () {
      const v = ChartViewport(candleCount: 100, width: 400, candleWidth: 10);
      expect(v.xForIndex(99), 400 - 3.5 * 10);
      expect(v.lastVisible, 99);
      expect(v.firstVisible, 62);
    });

    test('zooming keeps the candle under the pointer in place', () {
      final focalIndex = viewport.indexAt(123);
      final scroll = viewport.scrollForZoom(20, 123);
      final zoomed = ChartViewport(
        candleCount: 100,
        width: 400,
        candleWidth: 20,
        scrollOffset: scroll,
      );
      expect(zoomed.indexAt(123), closeTo(focalIndex, 1e-9));
    });

    test('scroll is limited to the data', () {
      expect(viewport.clampScroll(-50), 0);
      expect(viewport.clampScroll(1e9), viewport.maxScroll);
      expect(
        const ChartViewport(candleCount: 5, width: 400, candleWidth: 10)
            .maxScroll,
        0,
      );
    });
  });

  group('MarketChart widget', () {
    Widget host(Widget chart) => MaterialApp(
          home: Center(
            child: SizedBox(width: 400, height: 300, child: chart),
          ),
        );

    testWidgets('draws without errors for every chart type', (tester) async {
      for (final type in MarketChartType.values) {
        await tester.pumpWidget(
            host(MarketChart(candles: sampleCandles(300), type: type)));
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('handles empty and single-candle data', (tester) async {
      await tester.pumpWidget(host(const MarketChart(candles: [])));
      await tester.pumpWidget(host(MarketChart(candles: sampleCandles(1))));
      await tester.pumpWidget(
          host(MarketChart(candles: sampleCandles(1), showVolume: false)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long-press shows the candle under the crosshair',
        (tester) async {
      final reported = <Candle?>[];
      final candles = sampleCandles(300);
      await tester.pumpWidget(host(
          MarketChart(candles: candles, onCrosshairChanged: reported.add)));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(MarketChart)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(reported, hasLength(1));
      expect(candles, contains(reported.single));

      await gesture.up();
      await tester.pump();
      expect(reported.last, isNull);
    });

    testWidgets('dragging and mouse-wheel zoom do not throw', (tester) async {
      await tester.pumpWidget(host(MarketChart(candles: sampleCandles(500))));
      final chart = find.byType(MarketChart);
      await tester.drag(chart, const Offset(200, 0));
      await tester.pump();

      final center = tester.getCenter(chart);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('accepts live updates and new candles', (tester) async {
      var candles = sampleCandles(100);
      await tester.pumpWidget(host(MarketChart(candles: candles)));
      candles = [
        ...candles.take(99),
        candles.last.applyTrade(500, volume: 5),
      ];
      await tester.pumpWidget(host(MarketChart(candles: candles)));
      candles = [
        ...candles,
        Candle.flat(
          time: candles.last.time.add(const Duration(minutes: 1)),
          price: 501,
        ),
      ];
      await tester.pumpWidget(host(MarketChart(candles: candles)));
      expect(tester.takeException(), isNull);
    });
  });
}
