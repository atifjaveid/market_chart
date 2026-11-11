import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'candle.dart';
import 'candle_diff.dart';
import 'format.dart';
import 'indicator_views.dart';
import 'indicators/indicator.dart';
import 'painter.dart';
import 'scale.dart';
import 'theme.dart';

/// Controls a [MarketChart] from outside: jump back to the latest candle,
/// zoom in and out, and find out whether the latest candle is in view.
///
/// It notifies its listeners when [isAtLatest] changes, so you can show a
/// "back to latest" button only when the user has scrolled away:
///
/// ```dart
/// ListenableBuilder(
///   listenable: controller,
///   builder: (context, _) => controller.isAtLatest
///       ? const SizedBox.shrink()
///       : TextButton(
///           onPressed: controller.jumpToLatest,
///           child: const Text('Latest'),
///         ),
/// )
/// ```
///
/// One controller can be used by one chart at a time. Dispose it when you no
/// longer need it.
class MarketChartController extends ChangeNotifier {
  _MarketChartState? _chart;
  bool _isAtLatest = true;

  /// Whether a chart is using this controller.
  bool get isAttached => _chart != null;

  /// Whether the chart shows the latest candle, so live updates stay in
  /// view. Becomes false when the user scrolls back in time.
  bool get isAtLatest => _isAtLatest;

  /// The current zoom: the width of one candle in pixels, or null when no
  /// chart is attached.
  double? get candleWidth => _chart?._candleWidth;

  /// Scrolls back to the latest candle.
  void jumpToLatest({bool animate = true}) =>
      _chart?._jumpToLatest(animate: animate);

  /// Makes candles wider, showing fewer of them.
  void zoomIn() => _chart?._zoomBy(1.25);

  /// Makes candles narrower, showing more of them.
  void zoomOut() => _chart?._zoomBy(0.8);

  void _attach(_MarketChartState chart) {
    assert(_chart == null || identical(_chart, chart),
        'A MarketChartController can only be used by one MarketChart at a time.');
    _chart = chart;
  }

  void _detach(_MarketChartState chart) {
    if (identical(_chart, chart)) _chart = null;
  }

  void _setAtLatest(bool value) {
    if (value == _isAtLatest) return;
    _isAtLatest = value;
    notifyListeners();
  }
}

/// An interactive trading chart.
///
/// * Drag to scroll back in time; pinch, trackpad-pinch or mouse wheel to zoom.
/// * Long-press (touch) or hover (mouse) to show the crosshair and the values
///   of the candle under it.
/// * For live prices, rebuild the chart with updated [candles]. While the
///   latest candle is in view the chart follows new candles; after the user
///   scrolls back, the view stays where it is.
/// * Use a [MarketChartController] to jump back to the latest candle or zoom
///   from your own buttons, and [onLoadMore] to load older history as the
///   user scrolls back.
///
/// ```dart
/// MarketChart(candles: candles)
/// ```
class MarketChart extends StatefulWidget {
  /// Creates a chart for [candles], oldest first.
  const MarketChart({
    super.key,
    required this.candles,
    this.controller,
    this.type = MarketChartType.candles,
    this.showVolume = true,
    this.indicators = const [],
    this.theme,
    this.pricePrecision,
    this.timeFormatter = defaultTimeFormatter,
    this.initialCandleWidth = 8,
    this.minCandleWidth = 2,
    this.maxCandleWidth = 48,
    this.onCrosshairChanged,
    this.onLoadMore,
    this.loadMoreThreshold = 20,
  })  : assert(minCandleWidth > 0),
        assert(minCandleWidth <= initialCandleWidth),
        assert(initialCandleWidth <= maxCandleWidth),
        assert(loadMoreThreshold >= 0);

  /// The price data, ordered from oldest to newest.
  ///
  /// To update the chart, rebuild it (for example with `setState`). You can
  /// pass a new list or change the same list in place: the chart works out
  /// what changed and keeps the view steady.
  final List<Candle> candles;

  /// Lets you jump to the latest candle and zoom from your own buttons.
  final MarketChartController? controller;

  /// Whether to draw candlesticks, a line or an area.
  final MarketChartType type;

  /// Whether to show volume bars under the prices.
  final bool showVolume;

  /// Indicators to draw: [MovingAverage] and [BollingerBands] over the
  /// prices, [Rsi] and [Macd] in panels below them (in the order listed).
  ///
  /// The values stay up to date as [candles] change, and only what changed is
  /// worked out again. Changing an indicator's colours keeps its values.
  final List<Indicator> indicators;

  /// Colours and text size. Defaults to [MarketChartTheme.dark] or
  /// [MarketChartTheme.light] to match the app's brightness.
  final MarketChartTheme? theme;

  /// Decimals shown in prices. By default this is worked out from the prices:
  /// as many decimals as they have (see [detectPricePrecision]).
  final int? pricePrecision;

  /// Turns candle times into axis and crosshair labels.
  final MarketChartTimeFormatter timeFormatter;

  /// Starting width of one candle in pixels, including the gap next to it.
  final double initialCandleWidth;

  /// Narrowest a candle can get when zooming out.
  final double minCandleWidth;

  /// Widest a candle can get when zooming in.
  final double maxCandleWidth;

  /// Called with the candle under the crosshair when it changes (including
  /// when a live update changes that candle), and with null when the
  /// crosshair goes away.
  final ValueChanged<Candle?>? onCrosshairChanged;

  /// Called when the user scrolls near the oldest candle, so you can fetch
  /// older history and add it to the start of [candles].
  ///
  /// If it returns a Future, it isn't called again until that Future
  /// completes. After that it's called again once older candles have been
  /// added, or when the user scrolls away from the oldest candle and back.
  final FutureOr<void> Function()? onLoadMore;

  /// How close to the oldest candle (in candles) the view must get before
  /// [onLoadMore] is called.
  final int loadMoreThreshold;

  @override
  State<MarketChart> createState() => _MarketChartState();
}

class _MarketChartState extends State<MarketChart>
    with SingleTickerProviderStateMixin {
  late double _candleWidth = widget.initialCandleWidth;
  double _scroll = 0;
  double _scaleStartWidth = 0;
  Offset? _crosshair;
  Candle? _reported;
  ChartLayout? _layout;

  // A copy of the data as last seen. Comparing against it finds changes even
  // when the caller changed the same list in place.
  List<Candle> _data = const [];
  int _dataVersion = 0;

  // One view per indicator, holding its calculator.
  List<IndicatorView> _views = const [];
  int _indicatorsVersion = 0;

  AnimationController? _scrollAnimation;
  double _animationFrom = 0;

  bool _loadMoreArmed = true;
  bool _loadingMore = false;
  bool _afterFrameScheduled = false;

  double _axisWidth = 48;
  Object? _axisWidthKey;
  int _precision = 2;
  int _precisionVersion = -1;

  bool get _isAtLatest => _scroll == 0;

  ChartViewport get _viewport => ChartViewport(
        candleCount: _data.length,
        width: _layout?.plot.width ?? 0,
        candleWidth: _candleWidth,
        scrollOffset: _scroll,
      );

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _syncData();
    _syncIndicators(from: 0);
  }

  @override
  void didUpdateWidget(MarketChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    _candleWidth = _candleWidth
        .clamp(widget.minCandleWidth, widget.maxCandleWidth)
        .toDouble();
    final change = _syncData();
    _syncIndicators(
        from: change == null ? _data.length : indicatorUpdateStart(change));
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _scrollAnimation?.dispose();
    super.dispose();
  }

  /// Picks up changes to [MarketChart.candles], and returns what changed (or
  /// null if nothing did).
  CandleChange? _syncData() {
    final change = diffCandles(_data, widget.candles);
    if (!change.hasChanges) return null;
    _data = List.unmodifiable(widget.candles);
    _dataVersion++;

    if (change.isReset) {
      assert(isOrderedByTime(_data),
          'MarketChart.candles must be ordered from oldest to newest.');
      // New data set: start at the latest candle.
      _scrollAnimation?.stop();
      _scroll = 0;
    } else if (change.addedAtEnd != 0 && !_isAtLatest) {
      // The user has scrolled back: keep the candles they're looking at in
      // place. (Candles added or removed at the start never move the view.)
      final delta = change.addedAtEnd * _candleWidth;
      _scroll += delta;
      _animationFrom += delta;
    }
    if (change.isReset || change.shift != 0) _loadMoreArmed = true;
    return change;
  }

  /// Picks up changes to [MarketChart.indicators], and brings every
  /// indicator's values up to date from candle [from] on.
  ///
  /// An indicator whose maths didn't change keeps its calculator, even if its
  /// colours did; a new one is worked out from scratch.
  void _syncIndicators({required int from}) {
    final unused = List.of(_views);
    final next = <IndicatorView>[];
    var changed = widget.indicators.length != _views.length;
    for (var k = 0; k < widget.indicators.length; k++) {
      final indicator = widget.indicators[k];
      final key = calculationKey(indicator);
      final match = unused.indexWhere((v) => calculationKey(v.config) == key);
      if (match == -1) {
        next.add(IndicatorView.of(indicator)..update(_data, 0));
        changed = true;
        continue;
      }
      final view = unused.removeAt(match);
      if (view.config != indicator ||
          k >= _views.length ||
          !identical(_views[k], view)) {
        changed = true;
      }
      view.config = indicator;
      view.update(_data, from);
      next.add(view);
    }
    _views = next;
    if (changed) _indicatorsVersion++;
  }

  void _zoomTo(double width, double focalX) {
    final target =
        width.clamp(widget.minCandleWidth, widget.maxCandleWidth).toDouble();
    if (target == _candleWidth) return;
    if (_isAtLatest) {
      // Zoom around the latest candle, so live updates stay in view.
      _candleWidth = target;
      return;
    }
    final scroll = _viewport.scrollForZoom(target, focalX);
    _candleWidth = target;
    _scroll = _viewport.clampScroll(scroll);
  }

  void _zoomBy(double factor) {
    final layout = _layout;
    if (layout == null) return;
    _scrollAnimation?.stop();
    setState(() => _zoomTo(_candleWidth * factor, layout.plot.center.dx));
    _afterViewChange();
  }

  void _jumpToLatest({required bool animate}) {
    if (_isAtLatest) return;
    if (!animate) {
      _scrollAnimation?.stop();
      setState(() => _scroll = 0);
      _afterViewChange();
      return;
    }
    final animation = _scrollAnimation ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_onScrollAnimation);
    _animationFrom = _scroll;
    animation.forward(from: 0);
  }

  void _onScrollAnimation() {
    final animation = _scrollAnimation!;
    setState(() {
      final progress = Curves.easeOutCubic.transform(animation.value);
      _scroll = animation.isCompleted ? 0 : _animationFrom * (1 - progress);
    });
    _afterViewChange();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scrollAnimation?.stop();
    _scaleStartWidth = _candleWidth;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      final pinching = details.scale != 1.0;
      // A pinch on the latest candle zooms without scrolling away from it.
      if (!(pinching && _isAtLatest)) {
        _scroll = _viewport.clampScroll(_scroll + details.focalPointDelta.dx);
      }
      if (pinching) {
        _zoomTo(_scaleStartWidth * details.scale, details.localFocalPoint.dx);
      }
    });
    _afterViewChange();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final delta = scroll.scrollDelta;
      _scrollAnimation?.stop();
      setState(() {
        if (delta.dx.abs() > delta.dy.abs()) {
          _scroll = _viewport.clampScroll(_scroll - delta.dx);
        } else if (delta.dy != 0) {
          _zoomTo(_candleWidth * (delta.dy > 0 ? 0.9 : 1.1),
              scroll.localPosition.dx);
        }
      });
      _afterViewChange();
    });
  }

  void _setCrosshair(Offset? point) {
    if (point == _crosshair) return;
    setState(() => _crosshair = point);
    _afterViewChange();
  }

  /// Runs [_afterViewChange] once the current frame is done, for changes made
  /// during build (callbacks must not run while the tree is building).
  void _scheduleAfterFrame() {
    if (_afterFrameScheduled) return;
    _afterFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _afterFrameScheduled = false;
      if (mounted) _afterViewChange();
    });
  }

  /// Tells the controller and callbacks about changes to the view.
  void _afterViewChange() {
    widget.controller?._setAtLatest(_isAtLatest);
    _reportCrosshair();
    _checkLoadMore();
  }

  void _reportCrosshair() {
    final callback = widget.onCrosshairChanged;
    if (callback == null) return;
    Candle? candle;
    final point = _crosshair;
    final layout = _layout;
    if (point != null && layout != null && layout.plot.contains(point)) {
      final index = _viewport.nearestVisible(point.dx);
      if (index != null) candle = _data[index];
    }
    if (candle != _reported) {
      _reported = candle;
      callback(candle);
    }
  }

  void _checkLoadMore() {
    final callback = widget.onLoadMore;
    if (callback == null || _loadingMore || _data.isEmpty || _layout == null) {
      return;
    }
    final nearOldest = _viewport.firstVisible <= widget.loadMoreThreshold;
    if (!nearOldest) {
      _loadMoreArmed = true;
      return;
    }
    if (!_loadMoreArmed) return;
    _loadMoreArmed = false;

    final result = callback();
    if (result is Future) {
      _loadingMore = true;
      result.then<void>(
        (_) => _onLoadMoreDone(),
        onError: (Object error, StackTrace stack) {
          _onLoadMoreDone();
          FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'market_chart',
            context: ErrorDescription('while loading more candles'),
          ));
        },
      );
    }
  }

  void _onLoadMoreDone() {
    _loadingMore = false;
    // If older candles arrived while loading, the view may still be near the
    // start and need more.
    if (mounted) _checkLoadMore();
  }

  int _detectedPrecision() {
    if (_precisionVersion != _dataVersion) {
      _precision = detectPricePrecision(_data);
      _precisionVersion = _dataVersion;
    }
    return _precision;
  }

  double _axisWidthFor(int precision, TextStyle style) {
    final key = (_dataVersion, _indicatorsVersion, precision, style);
    if (key != _axisWidthKey) {
      _axisWidth = measureAxisWidth(_data, precision, style, panels: [
        for (final view in _views)
          if (view is PanelView) view,
      ]);
      _axisWidthKey = key;
    }
    return _axisWidth;
  }

  @override
  Widget build(BuildContext context) {
    var theme = widget.theme ??
        (Theme.of(context).brightness == Brightness.dark
            ? MarketChartTheme.dark
            : MarketChartTheme.light);
    if (theme.fontFamily == null) {
      // Match the app's font.
      final appFont = DefaultTextStyle.of(context).style.fontFamily;
      if (appFont != null) theme = theme.copyWith(fontFamily: appFont);
    }
    final data = _data;
    final precision = widget.pricePrecision ?? _detectedPrecision();
    final axisWidth = _axisWidthFor(precision, theme.textStyle);

    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : 400,
        constraints.maxHeight.isFinite ? constraints.maxHeight : 320,
      );
      final panelCount = _views.whereType<PanelView>().length;
      final hasOverlays = _views.length > panelCount;
      final layout = ChartLayout.compute(
        size,
        axisWidth: axisWidth,
        showVolume: widget.showVolume,
        panelCount: panelCount,
        // Room for a second legend line with the overlays' values.
        topPadding: hasOverlays ? 40 : 24,
      );
      _layout = layout;
      // Keep the scroll valid after a resize or a data change.
      _scroll = _viewport.clampScroll(_scroll);
      _scheduleAfterFrame();

      return Semantics(
        label: 'Price chart',
        value: data.isEmpty
            ? 'No data'
            : 'Latest price ${formatPrice(data.last.close, precision)}',
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (event) => _setCrosshair(event.localPosition),
            onExit: (_) => _setCrosshair(null),
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onLongPressStart: (d) => _setCrosshair(d.localPosition),
              onLongPressMoveUpdate: (d) => _setCrosshair(d.localPosition),
              onLongPressEnd: (_) => _setCrosshair(null),
              onLongPressCancel: () => _setCrosshair(null),
              child: CustomPaint(
                size: size,
                painter: MarketChartPainter(
                  candles: data,
                  dataVersion: _dataVersion,
                  layout: layout,
                  candleWidth: _candleWidth,
                  scrollOffset: _scroll,
                  type: widget.type,
                  theme: theme,
                  precision: precision,
                  timeFormatter: widget.timeFormatter,
                  crosshair: _crosshair,
                  indicators: _views,
                  indicatorsVersion: _indicatorsVersion,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
