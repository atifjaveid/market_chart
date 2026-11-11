import 'dart:async';

import 'package:flutter/material.dart';
import 'package:market_chart/market_chart.dart';

import 'binance_feed.dart';
import 'price_feed.dart';
import 'simulated_feed.dart';

void main() => runApp(const ExampleApp());

/// Creates the feed for a market. Tests pass their own.
typedef FeedBuilder = PriceFeed Function(String symbol, Timeframe timeframe);

/// Live prices from Binance.
PriceFeed binanceFeed(String symbol, Timeframe timeframe) =>
    BinanceFeed(symbol: symbol, timeframe: timeframe);

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.feedBuilder = binanceFeed});

  final FeedBuilder feedBuilder;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  var _mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'market_chart example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      themeMode: _mode,
      home: ChartPage(
        feedBuilder: widget.feedBuilder,
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: () => setState(() {
          _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        }),
      ),
    );
  }
}

class ChartPage extends StatefulWidget {
  const ChartPage({
    super.key,
    required this.feedBuilder,
    required this.isDark,
    required this.onToggleTheme,
  });

  final FeedBuilder feedBuilder;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  static const _markets = [
    'BTCUSDT',
    'ETHUSDT',
    'SOLUSDT',
    'XRPUSDT',
    'DOGEUSDT',
  ];

  // The indicators you can switch on, in the order they're drawn.
  static const _available = <Indicator>[
    MovingAverage.ema(20),
    MovingAverage.sma(50),
    BollingerBands(),
    Rsi(),
    Macd(),
  ];

  final _enabled = <Indicator>{const MovingAverage.ema(20), const Rsi()};
  final _controller = MarketChartController();
  var _symbol = _markets.first;
  var _timeframe = Timeframe.m1;
  var _type = MarketChartType.candles;
  var _showVolume = true;
  late PriceFeed _feed;

  /// Made-up prices, shown if [_feed] can't load.
  PriceFeed? _fallback;
  Candle? _selected;

  PriceFeed get _shown => _fallback ?? _feed;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _close();
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    _feed = widget.feedBuilder(_symbol, _timeframe)..addListener(_onFeed);
    unawaited(_feed.start());
  }

  void _close() {
    _feed
      ..removeListener(_onFeed)
      ..dispose();
    _fallback
      ?..removeListener(_onFeed)
      ..dispose();
    _fallback = null;
  }

  /// Loads the chosen market and timeframe (or tries again after a failure).
  void _reopen() {
    setState(() {
      _close();
      _selected = null;
      _open();
    });
  }

  void _onFeed() {
    if (_feed.status == FeedStatus.failed && _fallback == null) {
      // The exchange can't be reached: show made-up prices instead.
      _fallback = SimulatedFeed()..addListener(_onFeed);
      unawaited(_fallback!.start());
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final feed = _shown;
    final candles = feed.candles;

    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          tooltip: 'Market',
          initialValue: _symbol,
          onSelected: (symbol) {
            _symbol = symbol;
            _reopen();
          },
          itemBuilder: (context) => [
            for (final symbol in _markets)
              PopupMenuItem(
                value: symbol,
                child: Text('${symbol.substring(0, symbol.length - 4)}/USDT'),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(feed.name, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.zoom_out),
            onPressed: _controller.zoomOut,
          ),
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.zoom_in),
            onPressed: _controller.zoomIn,
          ),
          IconButton(
            tooltip: widget.isDark ? 'Light theme' : 'Dark theme',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Shows while older candles are loading.
            SizedBox(
              height: 2,
              child: feed.loadingOlder ? const LinearProgressIndicator() : null,
            ),
            if (_fallback != null)
              _FallbackBanner(
                reason: describeFeedError(_feed.error),
                onRetry: _reopen,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<Timeframe>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      for (final t in Timeframe.values)
                        ButtonSegment(value: t, label: Text(t.code)),
                    ],
                    selected: {_timeframe},
                    onSelectionChanged: (s) {
                      _timeframe = s.first;
                      _reopen();
                    },
                  ),
                  SegmentedButton<MarketChartType>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: MarketChartType.candles,
                        icon: Icon(Icons.candlestick_chart),
                        tooltip: 'Candles',
                      ),
                      ButtonSegment(
                        value: MarketChartType.line,
                        icon: Icon(Icons.show_chart),
                        tooltip: 'Line',
                      ),
                      ButtonSegment(
                        value: MarketChartType.area,
                        icon: Icon(Icons.area_chart),
                        tooltip: 'Area',
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  FilterChip(
                    label: const Text('Volume'),
                    selected: _showVolume,
                    onSelected: (v) => setState(() => _showVolume = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final indicator in _available)
                    FilterChip(
                      label: Text(indicator.label),
                      selected: _enabled.contains(indicator),
                      onSelected: (on) => setState(() => on
                          ? _enabled.add(indicator)
                          : _enabled.remove(indicator)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _InfoLine(
                feed: feed,
                simulated: _fallback != null,
                selected: _selected,
              ),
            ),
            Expanded(
              child: candles.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: MarketChart(
                            candles: candles,
                            controller: _controller,
                            type: _type,
                            showVolume: _showVolume,
                            indicators: [
                              for (final indicator in _available)
                                if (_enabled.contains(indicator)) indicator,
                            ],
                            onCrosshairChanged: (c) =>
                                setState(() => _selected = c),
                            onLoadMore: feed.loadOlder,
                          ),
                        ),
                        // "Latest" appears only after the user scrolls back.
                        Positioned(
                          right: 88,
                          bottom: 36,
                          child: ListenableBuilder(
                            listenable: _controller,
                            builder: (context, _) => _controller.isAtLatest
                                ? const SizedBox.shrink()
                                : FilledButton.tonalIcon(
                                    onPressed: _controller.jumpToLatest,
                                    icon: const Icon(
                                        Icons.keyboard_double_arrow_right),
                                    label: const Text('Latest'),
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says where the prices come from, or shows the candle under the crosshair.
class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.feed,
    required this.simulated,
    required this.selected,
  });

  final PriceFeed feed;
  final bool simulated;
  final Candle? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final candle = selected;
    if (candle != null) {
      final decimals = detectPricePrecision(feed.candles);
      String price(double value) => formatPrice(value, decimals);
      return Text(
        '${defaultTimeFormatter(candle.time, feed.interval, TimeLabelKind.crosshair)}'
        '   O ${price(candle.open)}   H ${price(candle.high)}'
        '   L ${price(candle.low)}   C ${price(candle.close)}',
        style: style,
      );
    }

    final (color, text) = switch (feed.status) {
      _ when simulated => (theme.disabledColor, 'Simulated prices'),
      FeedStatus.live => (Colors.green, 'Live from Binance'),
      FeedStatus.reconnecting => (Colors.orange, 'Reconnecting…'),
      FeedStatus.loading || FeedStatus.failed => (
          theme.disabledColor,
          'Connecting to Binance…'
        ),
    };
    return Text.rich(
      TextSpan(children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        TextSpan(text: text),
        // On wider screens, a reminder of what the chart can do.
        if (MediaQuery.sizeOf(context).width >= 600)
          const TextSpan(
            text: '   ·   Drag to scroll back, pinch or scroll to zoom, '
                'long-press or hover for details',
          ),
      ]),
      style: style,
    );
  }
}

class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner({required this.reason, required this.onRetry});

  final String reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$reason. Showing simulated prices.',
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
