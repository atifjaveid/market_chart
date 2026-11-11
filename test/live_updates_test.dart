import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';

/// One-minute candles from minute [from]. The same minute always gives an
/// equal candle.
List<Candle> minutes(int from, int count) => [
      for (var i = from; i < from + count; i++)
        Candle(
          time: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          open: 100.0 + i % 17,
          high: 105.0 + i % 17,
          low: 95.0 + i % 17,
          close: 101.0 + i % 17,
          volume: 10,
        ),
    ];

Widget host({
  required List<Candle> candles,
  MarketChartController? controller,
  ValueChanged<Candle?>? onCrosshair,
  FutureOr<void> Function()? onLoadMore,
}) =>
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: MarketChart(
            candles: candles,
            controller: controller,
            onCrosshairChanged: onCrosshair,
            onLoadMore: onLoadMore,
          ),
        ),
      ),
    );

/// Long-presses at [point] and returns the candle the crosshair snapped to.
Future<Candle?> candleAt(
  WidgetTester tester,
  Offset point,
  List<Candle?> reported,
) async {
  final gesture = await tester.startGesture(point);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  final candle = reported.isEmpty ? null : reported.last;
  await gesture.up();
  await tester.pump();
  return candle;
}

void main() {
  group('Live data', () {
    testWidgets('on the latest candle, the view follows new candles',
        (tester) async {
      final reported = <Candle?>[];
      var candles = minutes(0, 300);
      await tester
          .pumpWidget(host(candles: candles, onCrosshair: reported.add));
      final center = tester.getCenter(find.byType(MarketChart));
      final before = (await candleAt(tester, center, reported))!;

      candles = [...candles, ...minutes(300, 1)];
      await tester
          .pumpWidget(host(candles: candles, onCrosshair: reported.add));
      final after = (await candleAt(tester, center, reported))!;
      expect(after.time, before.time.add(const Duration(minutes: 1)));
    });

    testWidgets('after scrolling back, new candles do not move the view',
        (tester) async {
      final reported = <Candle?>[];
      final controller = MarketChartController();
      addTearDown(controller.dispose);
      var candles = minutes(0, 300);
      Widget build() => host(
          candles: candles, controller: controller, onCrosshair: reported.add);

      await tester.pumpWidget(build());
      final chart = find.byType(MarketChart);
      await tester.drag(chart, const Offset(300, 0));
      await tester.pump();
      expect(controller.isAtLatest, isFalse);
      final center = tester.getCenter(chart);
      final before = await candleAt(tester, center, reported);
      expect(before, isNotNull);

      // A new list with one more candle.
      candles = [...candles, ...minutes(300, 1)];
      await tester.pumpWidget(build());
      expect(await candleAt(tester, center, reported), before);

      // The same list changed in place.
      candles.addAll(minutes(301, 2));
      await tester.pumpWidget(build());
      expect(await candleAt(tester, center, reported), before);
      expect(controller.isAtLatest, isFalse);
    });

    testWidgets('adding older history does not move the view', (tester) async {
      final reported = <Candle?>[];
      var candles = minutes(0, 300);
      Widget build() => host(candles: candles, onCrosshair: reported.add);

      await tester.pumpWidget(build());
      final chart = find.byType(MarketChart);
      await tester.drag(chart, const Offset(300, 0));
      await tester.pump();
      final center = tester.getCenter(chart);
      final before = await candleAt(tester, center, reported);

      candles = [...minutes(-100, 100), ...candles];
      await tester.pumpWidget(build());
      expect(await candleAt(tester, center, reported), before);
    });

    testWidgets('a whole new data set starts at the latest candle',
        (tester) async {
      final controller = MarketChartController();
      addTearDown(controller.dispose);
      await tester
          .pumpWidget(host(candles: minutes(0, 300), controller: controller));
      await tester.drag(find.byType(MarketChart), const Offset(300, 0));
      await tester.pump();
      expect(controller.isAtLatest, isFalse);

      await tester.pumpWidget(
          host(candles: minutes(5000, 200), controller: controller));
      expect(controller.isAtLatest, isTrue);
    });

    testWidgets('a live update to the candle under the crosshair is reported',
        (tester) async {
      final reported = <Candle?>[];
      var candles = minutes(0, 300);
      await tester
          .pumpWidget(host(candles: candles, onCrosshair: reported.add));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(MarketChart)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      final under = reported.last!;
      final index = candles.indexOf(under);

      candles = List.of(candles)..[index] = under.applyTrade(under.high + 1);
      await tester
          .pumpWidget(host(candles: candles, onCrosshair: reported.add));
      expect(reported.last, candles[index]);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('handles 10,000 candles with frequent updates', (tester) async {
      var candles = minutes(0, 10000);
      await tester.pumpWidget(host(candles: candles));
      final watch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        candles = [
          ...candles.take(candles.length - 1),
          candles.last.applyTrade(110.0 + i % 5),
        ];
        if (i % 10 == 9) candles = [...candles, ...minutes(candles.length, 1)];
        await tester.pumpWidget(host(candles: candles));
      }
      expect(tester.takeException(), isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });

  group('MarketChartController', () {
    testWidgets('isAtLatest follows scrolling and notifies listeners',
        (tester) async {
      final controller = MarketChartController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      await tester
          .pumpWidget(host(candles: minutes(0, 300), controller: controller));
      expect(controller.isAttached, isTrue);
      expect(controller.isAtLatest, isTrue);

      await tester.drag(find.byType(MarketChart), const Offset(200, 0));
      await tester.pump();
      expect(controller.isAtLatest, isFalse);
      expect(notified, 1);

      controller.jumpToLatest(animate: false);
      await tester.pump();
      expect(controller.isAtLatest, isTrue);
      expect(notified, 2);
    });

    testWidgets('jumpToLatest animates back to the latest candle',
        (tester) async {
      final controller = MarketChartController();
      addTearDown(controller.dispose);
      await tester
          .pumpWidget(host(candles: minutes(0, 300), controller: controller));
      await tester.drag(find.byType(MarketChart), const Offset(300, 0));
      await tester.pump();

      controller.jumpToLatest();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.isAtLatest, isFalse, reason: 'still animating');
      await tester.pumpAndSettle();
      expect(controller.isAtLatest, isTrue);
    });

    testWidgets('zoomIn and zoomOut stay within the limits and on the latest',
        (tester) async {
      final controller = MarketChartController();
      addTearDown(controller.dispose);
      await tester
          .pumpWidget(host(candles: minutes(0, 300), controller: controller));
      expect(controller.candleWidth, 8);

      controller.zoomIn();
      expect(controller.candleWidth, closeTo(10, 1e-9));
      controller.zoomOut();
      expect(controller.candleWidth, closeTo(8, 1e-9));
      expect(controller.isAtLatest, isTrue);

      for (var i = 0; i < 20; i++) {
        controller.zoomIn();
      }
      expect(controller.candleWidth, 48);
      for (var i = 0; i < 40; i++) {
        controller.zoomOut();
      }
      expect(controller.candleWidth, 2);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    test('does nothing without a chart', () {
      final controller = MarketChartController()
        ..jumpToLatest()
        ..zoomIn()
        ..zoomOut();
      expect(controller.isAttached, isFalse);
      expect(controller.candleWidth, isNull);
      controller.dispose();
    });

    testWidgets('moves to a new chart and detaches when the chart goes',
        (tester) async {
      final first = MarketChartController();
      final second = MarketChartController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await tester.pumpWidget(host(candles: minutes(0, 50), controller: first));
      expect(first.isAttached, isTrue);
      await tester
          .pumpWidget(host(candles: minutes(0, 50), controller: second));
      expect(first.isAttached, isFalse);
      expect(second.isAttached, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(second.isAttached, isFalse);
    });
  });

  group('onLoadMore', () {
    testWidgets('is called when the user scrolls to the oldest candle',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(
        candles: minutes(0, 300),
        onLoadMore: () {
          calls++;
        },
      ));
      expect(calls, 0);

      final chart = find.byType(MarketChart);
      await tester.drag(chart, const Offset(5000, 0));
      await tester.pump();
      expect(calls, 1);

      await tester.drag(chart, const Offset(100, 0));
      await tester.pump();
      expect(calls, 1, reason: 'not again until something changes');
    });

    testWidgets('is called again after older candles are added',
        (tester) async {
      var calls = 0;
      var candles = minutes(0, 300);
      Widget build() => host(
            candles: candles,
            onLoadMore: () {
              calls++;
            },
          );

      await tester.pumpWidget(build());
      final chart = find.byType(MarketChart);
      await tester.drag(chart, const Offset(5000, 0));
      await tester.pump();
      expect(calls, 1);

      candles = [...minutes(-200, 200), ...candles];
      await tester.pumpWidget(build());
      expect(calls, 1, reason: 'the oldest candle is now out of reach');

      await tester.drag(chart, const Offset(5000, 0));
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('is not called again while a load is running', (tester) async {
      final completer = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(host(
        candles: minutes(0, 300),
        onLoadMore: () {
          calls++;
          return completer.future;
        },
      ));
      final chart = find.byType(MarketChart);
      await tester.drag(chart, const Offset(5000, 0));
      await tester.pump();
      await tester.drag(chart, const Offset(-3000, 0));
      await tester.pump();
      await tester.drag(chart, const Offset(5000, 0));
      await tester.pump();
      expect(calls, 1);

      // The load finished without adding anything: ask again only after the
      // user scrolls away and back.
      completer.complete();
      await tester.pump();
      expect(calls, 1);
      await tester.drag(chart, const Offset(-3000, 0));
      await tester.pump();
      await tester.drag(chart, const Offset(5000, 0));
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('is called on the first frame when all candles fit',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(
        candles: minutes(0, 10),
        onLoadMore: () {
          calls++;
        },
      ));
      expect(calls, 1);
    });

    testWidgets('reports errors from the returned Future', (tester) async {
      await tester.pumpWidget(host(
        candles: minutes(0, 10),
        onLoadMore: () async => throw StateError('offline'),
      ));
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
    });
  });
}
