import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';
import 'package:market_chart_example/binance_feed.dart';
import 'package:market_chart_example/main.dart';
import 'package:market_chart_example/simulated_feed.dart';

import 'fake_binance.dart';

void main() {
  late FakeBinance binance;

  setUp(() {
    binance = FakeBinance([
      for (var i = 0; i < 600; i++) row(t0 + i * minute, 100.0 + i),
    ]);
  });

  Widget appWithFakeBinance() => ExampleApp(
        feedBuilder: (symbol, timeframe) => BinanceFeed(
          symbol: symbol,
          timeframe: timeframe,
          client: binance.client,
          connect: binance.connect,
        ),
      );

  MarketChart chart(WidgetTester tester) =>
      tester.widget<MarketChart>(find.byType(MarketChart));

  testWidgets('shows live prices from Binance', (tester) async {
    await tester.pumpWidget(appWithFakeBinance());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(find.text('BTC/USDT'), findsOneWidget);
    expect(find.textContaining('Live from Binance'), findsOneWidget);
    expect(chart(tester).candles, hasLength(500));

    final last = t0 + 599 * minute;
    binance.send(kline(last, 702.25, event: last + 1000, volume: 5));
    await tester.pump();
    expect(chart(tester).candles.last.close, 702.25);

    // Another timeframe loads again.
    await tester.tap(find.text('5m'));
    await tester.pump();
    await tester.pump();
    expect(binance.requests.last.queryParameters['interval'], '5m');
    expect(binance.sockets, hasLength(2));

    // Another market too.
    await tester.tap(find.text('BTC/USDT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ETH/USDT').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(binance.requests.last.queryParameters['symbol'], 'ETHUSDT');
    expect(find.text('ETH/USDT'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('falls back to simulated prices', (tester) async {
    binance.statusCode = 451;
    await tester.pumpWidget(appWithFakeBinance());
    await tester.pump();
    await tester.pump();
    expect(
        find.text("Binance isn't available in this location. "
            'Showing simulated prices.'),
        findsOneWidget);
    expect(find.text('BTC/USD (simulated)'), findsOneWidget);
    expect(chart(tester).candles, isNotEmpty);

    // Retry once Binance is back.
    binance.statusCode = 200;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('BTC/USDT'), findsOneWidget);
    expect(find.textContaining('Showing simulated prices'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chart controls work', (tester) async {
    await tester
        .pumpWidget(ExampleApp(feedBuilder: (_, __) => SimulatedFeed()));
    expect(find.byType(MarketChart), findsOneWidget);
    expect(find.text('Latest'), findsNothing);

    // Let some simulated trades happen.
    await tester.pump(const Duration(seconds: 2));

    // Scrolling back shows the "Latest" button, which brings the view back.
    await tester.drag(find.byType(MarketChart), const Offset(300, 0));
    await tester.pump();
    expect(find.text('Latest'), findsOneWidget);
    await tester.tap(find.text('Latest'));
    // The first frame starts the scroll animation, the next one finishes it,
    // and the last one rebuilds the button.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Latest'), findsNothing);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Line'));
    await tester.pump();
    expect(chart(tester).type, MarketChartType.line);

    // Indicators can be switched on and off.
    await tester.tap(find.text('MACD 12 26 9'));
    await tester.tap(find.text('BB 20 2'));
    await tester.tap(find.text('RSI 14'));
    await tester.pump();
    expect(chart(tester).indicators,
        [const MovingAverage.ema(20), const BollingerBands(), const Macd()]);
    expect(tester.takeException(), isNull);

    // Remove the app so its timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  test('simulated history ends where the next candle opens', () {
    final next = Candle.flat(time: DateTime(2026, 1, 1, 12), price: 100);
    final history =
        simulateCandlesBefore(next, 50, const Duration(seconds: 5), Random(1));
    expect(history, hasLength(50));
    expect(history.last.close, next.open);
    expect(history.last.time, DateTime(2026, 1, 1, 11, 59, 55));
    for (var i = 1; i < history.length; i++) {
      expect(history[i].open, history[i - 1].close);
    }
  });
}
