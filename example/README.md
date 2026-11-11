# market_chart example

A trading screen with live prices from [Binance](https://www.binance.com)'s public market data. No account or API key is needed. If Binance can't be reached (offline, or in a country where Binance isn't available), it shows simulated prices instead.

- Pick a market (BTC, ETH, SOL, XRP or DOGE against USDT) and a timeframe from 1 minute to 1 day.
- Switch indicators, chart type and volume on and off.
- Drag to scroll back: older history loads as you go. Tap **Latest** to come back.
- Hover or long-press for the crosshair; pinch or use the mouse wheel to zoom.

```sh
cd example
flutter run
```

## How it's put together

| File | What it does |
|---|---|
| [lib/main.dart](lib/main.dart) | The screen: the chart and its controls. |
| [lib/binance_feed.dart](lib/binance_feed.dart) | History from Binance's REST API, then live candles and trades over a WebSocket. Reconnects (and fetches missed candles) when the connection drops. |
| [lib/simulated_feed.dart](lib/simulated_feed.dart) | Made-up prices for when Binance can't be reached. |
| [lib/price_feed.dart](lib/price_feed.dart) | What the screen needs from a feed. |

## The chart part

Everything the chart needs fits in one widget. `feed.candles` comes from a `CandleAggregator`, which the feeds keep up to date:

```dart
MarketChart(
  candles: feed.candles,
  controller: controller, // for the zoom and "Latest" buttons
  type: MarketChartType.candles,
  indicators: const [MovingAverage.ema(20), Rsi()],
  onCrosshairChanged: (candle) => setState(() => selected = candle),
  onLoadMore: feed.loadOlder, // older history as the user scrolls back
)
```

The networking packages ([http](https://pub.dev/packages/http) and [web_socket_channel](https://pub.dev/packages/web_socket_channel)) are only used by this example; `market_chart` itself depends on nothing but Flutter.
