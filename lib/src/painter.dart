import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'candle.dart';
import 'drawing.dart';
import 'format.dart';
import 'indicator_views.dart';
import 'scale.dart';
import 'theme.dart';
import 'time_axis.dart';

/// How prices are drawn.
enum MarketChartType {
  /// Japanese candlesticks: a body from open to close and a wick from low to
  /// high.
  candles,

  /// A line through the close prices.
  line,

  /// A line through the close prices with a shaded area under it.
  area,
}

/// Space at the top of each indicator panel for its legend.
const double panelLegendSpace = 20;

/// The fewest decimals that show multiples of [step] exactly: 0 for 200, 1
/// for 2.5, 2 for 0.25.
int _decimalsFor(double step) {
  for (var decimals = 0; decimals < 8; decimals++) {
    final scaled = step * math.pow(10, decimals);
    if ((scaled - scaled.roundToDouble()).abs() <
        1e-9 * math.max(1, scaled.abs())) {
      return decimals;
    }
  }
  return 8;
}

/// Measures how wide the axis on the right must be: wide enough for the
/// largest price, and for the labels of any indicator [panels].
double measureAxisWidth(
  List<Candle> candles,
  int precision,
  TextStyle style, {
  List<PanelView> panels = const [],
}) {
  var largest = 0.0;
  for (final candle in candles) {
    largest = math.max(largest, candle.high.abs());
  }
  var width = textWidth(formatPrice(largest * 1.1, precision), style);
  for (final panel in panels) {
    final label = formatPrice(-panel.largestValue * 1.1, panel.precision);
    width = math.max(width, textWidth(label, style));
  }
  return math.max(48, width + 16);
}

/// Draws the chart: grid, axes, candles or line, volume, indicators, the
/// latest price, the crosshair and the legends.
class MarketChartPainter extends CustomPainter {
  /// Creates a painter. [dataVersion] must change whenever [candles] (and so
  /// the indicator values) change, and [indicatorsVersion] whenever the list
  /// of [indicators] does.
  MarketChartPainter({
    required this.candles,
    required this.dataVersion,
    required this.layout,
    required this.candleWidth,
    required this.scrollOffset,
    required this.type,
    required this.theme,
    required this.precision,
    required this.timeFormatter,
    this.crosshair,
    this.indicators = const [],
    this.indicatorsVersion = 0,
  });

  final List<Candle> candles;
  final int dataVersion;
  final ChartLayout layout;
  final double candleWidth;
  final double scrollOffset;
  final MarketChartType type;
  final MarketChartTheme theme;
  final int precision;
  final MarketChartTimeFormatter timeFormatter;
  final Offset? crosshair;
  final List<IndicatorView> indicators;
  final int indicatorsVersion;

  double get _labelHeight => theme.fontSize * 1.2 + 8;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.backgroundColor);
    final plot = layout.plot;
    if (plot.width <= 0 || plot.height <= 0) return;

    if (candles.isEmpty) {
      drawText(canvas, 'No data', plot.center, theme.textStyle,
          align: Alignment.center);
      return;
    }

    final viewport = ChartViewport(
      candleCount: candles.length,
      width: plot.width,
      candleWidth: candleWidth,
      scrollOffset: scrollOffset,
    );
    final first = viewport.firstVisible;
    final last = viewport.lastVisible;
    if (first > last) return;

    // Colours: indicators without their own take the next palette colour.
    final colors = <IndicatorView, List<Color>>{};
    var next = 0;
    for (final view in indicators) {
      colors[view] = view.colors(theme, next);
      next += view.paletteSlots;
    }
    final overlays = [
      for (final view in indicators)
        if (view is! PanelView) view,
    ];
    final panels = [
      for (final view in indicators)
        if (view is PanelView) view,
    ];

    // Fit the visible candles and overlays.
    var low = double.infinity;
    var high = double.negativeInfinity;
    var maxVolume = 0.0;
    for (var i = first; i <= last; i++) {
      final c = candles[i];
      if (type == MarketChartType.candles) {
        low = math.min(low, c.low);
        high = math.max(high, c.high);
      } else {
        low = math.min(low, c.close);
        high = math.max(high, c.close);
      }
      maxVolume = math.max(maxVolume, c.volume);
    }
    for (final view in overlays) {
      final range = view.range(first, last);
      if (range != null) {
        low = math.min(low, range.$1);
        high = math.max(high, range.$2);
      }
    }
    final priceScale = ValueScale.fit(layout.pricePane, low, high);

    final latest = candles.last;
    final latestColor = latest.isBullish ? theme.bullColor : theme.bearColor;
    final latestY = priceScale.y(latest.close);
    final showLatest =
        latestY >= layout.pricePane.top && latestY <= layout.pricePane.bottom;
    final point = crosshair;
    final crosshairIndex = point != null && plot.contains(point)
        ? viewport.nearestVisible(point.dx)
        : null;
    final selected = crosshairIndex ?? candles.length - 1;
    // Axis labels that would sit under another label are skipped.
    double? reservedIn(Rect pane) =>
        crosshairIndex != null && pane.contains(point!) ? point.dy : null;

    // The crosshair's time label, worked out first so that axis labels under
    // it can be skipped.
    String? timeLabel;
    Rect? timeBox;
    if (crosshairIndex != null) {
      timeLabel = timeFormatter(
          candles[crosshairIndex].time, _interval, TimeLabelKind.crosshair);
      final width = textWidth(timeLabel, theme.textStyle) + 12;
      final left = (viewport.xForIndex(crosshairIndex) - width / 2)
          .clamp(plot.left, math.max(plot.left, plot.right - width))
          .toDouble();
      timeBox = Rect.fromLTWH(
          left, layout.timeAxis.top, width, layout.timeAxis.height);
    }

    _drawPriceGrid(canvas, priceScale, [
      if (showLatest) latestY,
      if (reservedIn(layout.pricePane) case final y?) y,
    ]);
    _drawTimeGrid(canvas, viewport, first, last, timeBox);

    // Prices, volume and the indicators drawn over them.
    canvas.save();
    canvas.clipRect(layout.mainArea);
    _drawVolume(canvas, viewport, first, last, maxVolume);
    if (type == MarketChartType.candles) {
      _drawCandles(canvas, viewport, first, last, priceScale);
    } else {
      _drawLine(canvas, viewport, first, last, priceScale);
    }
    final overlayCanvas = IndicatorCanvas(
      canvas: canvas,
      viewport: viewport,
      first: first,
      last: last,
      scale: priceScale,
      theme: theme,
      candleWidth: candleWidth,
    );
    for (final view in overlays) {
      view.paint(overlayCanvas, colors[view]!);
    }
    if (showLatest) {
      dashedLine(
        canvas,
        Offset(plot.left, latestY),
        Offset(plot.right, latestY),
        Paint()
          ..color = latestColor
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
    if (showLatest) {
      _axisLabel(canvas, latestY, formatPrice(latest.close, precision),
          latestColor, theme.labelTextColor, layout.pricePane);
    }

    // Indicator panels.
    final panelScales = <ValueScale>[];
    for (var k = 0; k < panels.length && k < layout.panels.length; k++) {
      panelScales.add(_drawPanel(canvas, panels[k], layout.panels[k], viewport,
          first, last, colors[panels[k]]!, reservedIn(layout.panels[k])));
    }

    if (crosshairIndex != null) {
      _drawCrosshair(canvas, viewport, crosshairIndex, point!, priceScale,
          maxVolume, panels, panelScales, timeLabel!, timeBox!);
    }

    // Legends go on top of everything.
    _drawPriceLegend(canvas, selected, overlays, colors);
    for (var k = 0; k < panelScales.length; k++) {
      final panel = layout.panels[k];
      _paintLegend(
        canvas,
        TextSpan(
          style: theme.textStyle,
          children: panels[k]
              .legend(selected, theme.textStyle, precision, colors[panels[k]]!),
        ),
        Offset(panel.left + 8, panel.top + 4),
      );
    }
  }

  void _drawPriceGrid(
    Canvas canvas,
    ValueScale scale,
    List<double> reservedYs,
  ) {
    final pane = layout.pricePane;
    final grid = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1;
    final count = math.max(2, (pane.height / 44).round());
    // Never finer than the prices' decimals, so no two labels read the same.
    final minStep = math.pow(10, -precision).toDouble();
    for (final value
        in niceTicks(scale.min, scale.max, count, minStep: minStep)) {
      final y = scale.y(value);
      if (y < pane.top || y > pane.bottom) continue;
      canvas.drawLine(
          Offset(layout.plot.left, y), Offset(layout.plot.right, y), grid);
      if (reservedYs.any((r) => (r - y).abs() < _labelHeight)) continue;
      drawText(canvas, formatPrice(value, precision),
          Offset(layout.priceAxis.left + 8, y), theme.textStyle,
          align: Alignment.centerLeft);
    }
  }

  /// Vertical grid lines with time labels at round times (see
  /// [timeAxisLabels]). Labels that would overlap [reserved] (the crosshair's
  /// time label) are skipped.
  void _drawTimeGrid(
    Canvas canvas,
    ChartViewport viewport,
    int first,
    int last,
    Rect? reserved,
  ) {
    final plot = layout.plot;
    final grid = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1;
    final interval = _interval;
    // Aim for labels about 90 px apart.
    final labels =
        timeAxisLabels(candles, first, last, interval, 90 / candleWidth);
    // Where labels would overlap, keep new years, months and days first.
    labels
        .sort((a, b) => a.rank != b.rank ? b.rank - a.rank : a.index - b.index);
    final placed = <(double, double, String)>[]; // (x, width, text)
    for (final label in labels) {
      final x = viewport.xForIndex(label.index);
      final text = timeFormatter(label.time, interval, TimeLabelKind.axis);
      final width = textWidth(text, theme.textStyle);
      if (placed.any((p) => (p.$1 - x).abs() < (p.$2 + width) / 2 + 12)) {
        continue;
      }
      placed.add((x, width, text));
    }
    for (final (x, width, text) in placed) {
      if (x < plot.left || x > plot.right) continue;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      if (x - width / 2 < plot.left || x + width / 2 > plot.right) continue;
      if (reserved != null &&
          x + width / 2 + 4 > reserved.left &&
          x - width / 2 - 4 < reserved.right) {
        continue;
      }
      drawText(
          canvas, text, Offset(x, layout.timeAxis.center.dy), theme.textStyle,
          align: Alignment.center);
    }
  }

  void _drawVolume(
    Canvas canvas,
    ChartViewport viewport,
    int first,
    int last,
    double maxVolume,
  ) {
    final pane = layout.volumePane;
    if (pane == null || maxVolume <= 0) return;
    final up = Path();
    final down = Path();
    final barWidth = math.max(1.0, candleWidth * 0.7);
    for (var i = first; i <= last; i++) {
      final c = candles[i];
      final height = c.volume / maxVolume * pane.height;
      if (height <= 0) continue;
      final x = viewport.xForIndex(i);
      (c.isBullish ? up : down).addRect(Rect.fromLTRB(x - barWidth / 2,
          pane.bottom - height, x + barWidth / 2, pane.bottom));
    }
    final opacity = theme.volumeOpacity.clamp(0.0, 1.0);
    canvas.drawPath(
        up, Paint()..color = theme.bullColor.withValues(alpha: opacity));
    canvas.drawPath(
        down, Paint()..color = theme.bearColor.withValues(alpha: opacity));
  }

  void _drawCandles(
    Canvas canvas,
    ChartViewport viewport,
    int first,
    int last,
    ValueScale scale,
  ) {
    final up = Path();
    final down = Path();
    final bodyWidth = math.max(1.0, candleWidth * 0.7);
    final wickWidth = candleWidth >= 12 ? 1.5 : 1.0;
    for (var i = first; i <= last; i++) {
      final c = candles[i];
      final x = viewport.xForIndex(i);
      final path = c.isBullish ? up : down;
      path.addRect(Rect.fromLTRB(x - wickWidth / 2, scale.y(c.high),
          x + wickWidth / 2, scale.y(c.low)));
      final top = scale.y(math.max(c.open, c.close));
      final bottom = math.max(top + 1, scale.y(math.min(c.open, c.close)));
      path.addRect(
          Rect.fromLTRB(x - bodyWidth / 2, top, x + bodyWidth / 2, bottom));
    }
    canvas.drawPath(up, Paint()..color = theme.bullColor);
    canvas.drawPath(down, Paint()..color = theme.bearColor);
  }

  void _drawLine(
    Canvas canvas,
    ChartViewport viewport,
    int first,
    int last,
    ValueScale scale,
  ) {
    // One candle past each edge, so the line runs off the sides.
    final from = math.max(0, first - 1);
    final to = math.min(candles.length - 1, last + 1);
    final line = Path();
    for (var i = from; i <= to; i++) {
      final point = Offset(viewport.xForIndex(i), scale.y(candles[i].close));
      i == from
          ? line.moveTo(point.dx, point.dy)
          : line.lineTo(point.dx, point.dy);
    }

    if (type == MarketChartType.area) {
      final pane = layout.pricePane;
      final area = Path.from(line)
        ..lineTo(viewport.xForIndex(to), pane.bottom)
        ..lineTo(viewport.xForIndex(from), pane.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.lineColor.withValues(alpha: 0.35),
              theme.lineColor.withValues(alpha: 0),
            ],
          ).createShader(pane),
      );
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = theme.lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Draws one indicator panel and returns the scale its values use.
  ValueScale _drawPanel(
    Canvas canvas,
    PanelView view,
    Rect panel,
    ChartViewport viewport,
    int first,
    int last,
    List<Color> colors,
    double? reservedY,
  ) {
    final grid = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1;
    // A divider between this panel and the one above, across the axis too.
    canvas.drawLine(Offset(panel.left, panel.top),
        Offset(layout.priceAxis.right, panel.top), grid);

    final area = Rect.fromLTRB(panel.left, panel.top + panelLegendSpace,
        panel.right, panel.bottom - 4);
    if (area.height < 8) return ValueScale(area, 0, 1);
    final (low, high) = view.panelRange(first, last);
    final scale = view.fixedRange
        ? ValueScale(area, low, high)
        : ValueScale.fit(area, low, high, margin: 0.1);

    final axisValues = view.axisValues(scale);
    // Round ticks (like 200 or 2.5) get only the decimals they need.
    final decimals = view.fixedRange
        ? view.axisPrecision
        : _decimalsFor(axisValues.length >= 2
            ? axisValues[1] - axisValues[0]
            : axisValues.firstOrNull ?? 0);
    for (final value in axisValues) {
      final y = scale.y(value);
      if (y < area.top || y > area.bottom) continue;
      if (!view.fixedRange) {
        canvas.drawLine(Offset(panel.left, y), Offset(panel.right, y), grid);
      }
      if (reservedY != null && (reservedY - y).abs() < _labelHeight) continue;
      drawText(canvas, formatPrice(value, decimals),
          Offset(layout.priceAxis.left + 8, y), theme.textStyle,
          align: Alignment.centerLeft);
    }

    canvas.save();
    canvas.clipRect(
        Rect.fromLTRB(panel.left, panel.top + 1, panel.right, panel.bottom));
    final indicatorCanvas = IndicatorCanvas(
      canvas: canvas,
      viewport: viewport,
      first: first,
      last: last,
      scale: scale,
      theme: theme,
      candleWidth: candleWidth,
    );
    view.paintGuides(indicatorCanvas, colors);
    view.paint(indicatorCanvas, colors);
    canvas.restore();
    return scale;
  }

  void _drawCrosshair(
    Canvas canvas,
    ChartViewport viewport,
    int index,
    Offset point,
    ValueScale priceScale,
    double maxVolume,
    List<PanelView> panels,
    List<ValueScale> panelScales,
    String timeLabel,
    Rect timeBox,
  ) {
    final plot = layout.plot;
    final x = viewport.xForIndex(index);
    final paint = Paint()
      ..color = theme.crosshairColor
      ..strokeWidth = 1;
    dashedLine(canvas, Offset(x, plot.top), Offset(x, plot.bottom), paint);
    dashedLine(canvas, Offset(plot.left, point.dy),
        Offset(plot.right, point.dy), paint);

    // The value under the pointer, in whichever pane it's in.
    final volumePane = layout.volumePane;
    String? label;
    Rect? bounds;
    if (layout.pricePane.contains(point)) {
      label = formatPrice(priceScale.valueAt(point.dy), precision);
      bounds = layout.pricePane;
    } else if (volumePane != null && volumePane.contains(point)) {
      label = formatCompact(
          (volumePane.bottom - point.dy) / volumePane.height * maxVolume);
      bounds = volumePane;
    } else {
      for (var k = 0; k < panelScales.length; k++) {
        if (layout.panels[k].contains(point)) {
          label = formatPrice(
              panelScales[k].valueAt(point.dy), panels[k].precision);
          bounds = layout.panels[k];
        }
      }
    }
    if (label != null && bounds != null) {
      _axisLabel(canvas, point.dy, label, theme.labelBackgroundColor,
          theme.labelTextColor, bounds);
    }

    final style = theme.textStyle.copyWith(color: theme.labelTextColor);
    canvas.drawRRect(RRect.fromRectAndRadius(timeBox, const Radius.circular(2)),
        Paint()..color = theme.labelBackgroundColor);
    drawText(canvas, timeLabel, timeBox.center, style, align: Alignment.center);
  }

  void _drawPriceLegend(
    Canvas canvas,
    int index,
    List<IndicatorView> overlays,
    Map<IndicatorView, List<Color>> colors,
  ) {
    final c = candles[index];
    final color = c.isBullish ? theme.bullColor : theme.bearColor;
    final label = theme.textStyle;
    final value = label.copyWith(color: color);
    final change = c.open == 0 ? 0.0 : (c.close - c.open) / c.open * 100;
    final sign = change >= 0 ? '+' : '';
    final volume =
        layout.volumePane == null ? '' : '  Vol ${formatCompact(c.volume)}';
    final children = <InlineSpan>[
      const TextSpan(text: 'O '),
      TextSpan(text: formatPrice(c.open, precision), style: value),
      const TextSpan(text: '  H '),
      TextSpan(text: formatPrice(c.high, precision), style: value),
      const TextSpan(text: '  L '),
      TextSpan(text: formatPrice(c.low, precision), style: value),
      const TextSpan(text: '  C '),
      TextSpan(text: formatPrice(c.close, precision), style: value),
      TextSpan(text: '  $sign${change.toStringAsFixed(2)}%', style: value),
      TextSpan(text: volume),
    ];
    for (var k = 0; k < overlays.length; k++) {
      children.add(TextSpan(text: k == 0 ? '\n' : '   '));
      children.addAll(
          overlays[k].legend(index, label, precision, colors[overlays[k]]!));
    }
    _paintLegend(canvas, TextSpan(style: label, children: children),
        Offset(layout.plot.left + 8, layout.plot.top + 6));
  }

  /// Paints legend text at [at], on a translucent background so it stays
  /// readable over the chart.
  void _paintLegend(Canvas canvas, InlineSpan text, Offset at) {
    final painter = TextPainter(text: text, textDirection: TextDirection.ltr)
      ..layout(maxWidth: math.max(0, layout.plot.width - 16));
    final box = (at & painter.size).inflate(3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      Paint()..color = theme.backgroundColor.withValues(alpha: 0.75),
    );
    painter.paint(canvas, at);
    painter.dispose();
  }

  /// A filled label on the axis, centred on [y] but kept within [bounds].
  void _axisLabel(Canvas canvas, double y, String text, Color background,
      Color foreground, Rect bounds) {
    final axis = layout.priceAxis;
    final style = theme.textStyle.copyWith(color: foreground);
    final height = _labelHeight;
    final top = (y - height / 2)
        .clamp(bounds.top, math.max(bounds.top, bounds.bottom - height))
        .toDouble();
    final box = Rect.fromLTWH(axis.left, top, axis.width, height);
    canvas.drawRect(box, Paint()..color = background);
    drawText(canvas, text, Offset(axis.left + 8, box.center.dy), style,
        align: Alignment.centerLeft);
  }

  /// The usual time between candles: the smallest gap among the latest few,
  /// so a quiet period in the data doesn't count.
  Duration get _interval {
    var best = Duration.zero;
    final n = candles.length;
    for (var i = n - 1; i > 0 && i >= n - 10; i--) {
      final gap = candles[i].time.difference(candles[i - 1].time).abs();
      if (gap > Duration.zero && (best == Duration.zero || gap < best)) {
        best = gap;
      }
    }
    return best == Duration.zero ? const Duration(minutes: 1) : best;
  }

  @override
  bool shouldRepaint(MarketChartPainter old) =>
      !identical(old.candles, candles) ||
      old.dataVersion != dataVersion ||
      old.indicatorsVersion != indicatorsVersion ||
      old.candleWidth != candleWidth ||
      old.scrollOffset != scrollOffset ||
      old.type != type ||
      old.theme != theme ||
      old.precision != precision ||
      old.timeFormatter != timeFormatter ||
      old.crosshair != crosshair ||
      old.layout != layout;
}
