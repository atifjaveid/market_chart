## 0.2.0

**Indicators**

* Indicators on the chart: `indicators: [MovingAverage.ema(20), BollingerBands(), Rsi(), Macd()]`. Moving averages and Bollinger Bands are drawn over the price (and included in its scale); RSI and MACD get panels with their own scales, axis labels and legends. The crosshair runs through every panel. Only changed values are worked out again, and changing only colours keeps the values.
* `MarketChartTheme.indicatorColors`: colours for moving averages and Bollinger Bands that don't set their own.
* Indicator maths: `sma`, `ema`, `bollingerBands`, `rsi` (Wilder's method) and `macd`, checked against TA-Lib on real prices.
* Indicator calculators (`SmaCalculator`, `EmaCalculator`, `BollingerBandsCalculator`, `RsiCalculator`, `MacdCalculator`) that work out only what changed, for live data.
* `PriceSource`, and `candles.closes` / `candles.prices(...)` to pass candle prices to indicators without copying.

**Live data**

* The chart works out what changed between updates (latest candle updated, candles added at the end, older history added, oldest candles dropped), so live updates stay fast and the view stays steady. Changing the same list in place now works too.
* New `CandleAggregator`: builds candles from trades or prices (`addTrade`), merges candles from a candle feed (`addCandle`) and adds older history (`addHistory`). Options for filling quiet periods, a maximum number of candles, and period alignment.
* New `MarketChartController`: `jumpToLatest()` (animated), `zoomIn()`, `zoomOut()`, and `isAtLatest` for showing a "back to latest" button.
* New `onLoadMore` callback for loading older history as the user scrolls back.
* Zooming while on the latest candle keeps it in view.
* `onCrosshairChanged` also fires when a live update changes the candle under the crosshair.

**Axes and labels**

* Time labels go at round times (14:00, 14:15, a new day, a new month) and stay on the same candles while scrolling, when older history loads and when old candles are dropped. New days are marked even when candles don't start at midnight, such as 4-hour or daily candles outside UTC.
* Time labels show seconds for candles shorter than a minute.
* Prices show as many decimals as the data has (4 for XRP at 2.3405, 5 for DOGE at 0.17891). `detectPricePrecision` works this out for your own labels.
* Price axis steps are never finer than the prices' decimals, so no two labels read the same.
* Time axis labels under the crosshair's time label are hidden.
* Legends have a translucent background so they stay readable over the chart.
* `MarketChartTheme.fontFamily`; by default the chart now uses the app's font.

**Example app**

* Live prices from Binance: history from the REST API, then candles and trades over a WebSocket, with reconnection and older history as you scroll back. When Binance can't be reached, it shows simulated prices.

## 0.1.0

* First version.
* Candlestick, line and area charts.
* Volume bars under the price.
* Drag to scroll; pinch, trackpad-pinch or mouse wheel to zoom.
* Crosshair on long-press or mouse hover, with price, time and an OHLC summary.
* Dashed line and label for the latest price.
* Live updates: rebuild with new data and the view follows the latest candle.
* Light and dark themes.
