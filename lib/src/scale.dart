import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Evenly spaced round values (steps of 1, 2, 2.5 or 5 × 10ⁿ) between [min]
/// and [max], aiming for about [targetCount] steps. Used for price grid lines.
///
/// With a [minStep] (a power of ten, such as 0.01), the step is a whole
/// multiple of it, so labels with that many decimals are exact and never
/// repeat.
List<double> niceTicks(
  double min,
  double max,
  int targetCount, {
  double minStep = 0,
}) {
  if (!(max > min) || targetCount < 1 || !min.isFinite || !max.isFinite) {
    return const [];
  }
  final rawStep = (max - min) / targetCount;
  final magnitude =
      math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final residual = rawStep / magnitude;
  final double nice;
  if (residual <= 1) {
    nice = 1;
  } else if (residual <= 2) {
    nice = 2;
  } else if (residual <= 2.5) {
    nice = 2.5;
  } else if (residual <= 5) {
    nice = 5;
  } else {
    nice = 10;
  }
  var step = nice * magnitude;
  if (minStep > 0) {
    if (step < minStep * (1 - 1e-9)) {
      step = minStep;
    } else if (nice == 2.5 && magnitude < minStep * 1.5) {
      // 2.5 × minStep would need one more decimal.
      step = 2 * magnitude;
    }
  }
  final firstIndex = (min / step).ceil();
  final ticks = <double>[];
  for (var k = firstIndex;; k++) {
    final value = k * step;
    if (value > max + step * 1e-9) break;
    ticks.add(value);
  }
  return ticks;
}

/// Maps candle indexes to x positions, given the zoom ([candleWidth]) and how
/// far the user has scrolled back in time ([scrollOffset], in pixels).
///
/// With a scroll offset of 0 the latest candle sits near the right edge, with
/// [rightPadding] candles of empty space after it.
@immutable
class ChartViewport {
  /// Creates a viewport for [candleCount] candles drawn across [width] pixels.
  const ChartViewport({
    required this.candleCount,
    required this.width,
    required this.candleWidth,
    this.scrollOffset = 0,
    this.rightPadding = 3,
  });

  /// Number of candles in the data.
  final int candleCount;

  /// Width of the drawing area in pixels.
  final double width;

  /// Horizontal space for one candle, including the gap next to it.
  final double candleWidth;

  /// How far the view is scrolled back in time, in pixels.
  final double scrollOffset;

  /// Empty space after the latest candle, in candle widths.
  final double rightPadding;

  /// The x position of the centre of the candle at [index].
  double xForIndex(int index) =>
      width -
      (candleCount - 0.5 - index + rightPadding) * candleWidth +
      scrollOffset;

  /// The (fractional) candle index at [x]. Candle centres are whole numbers.
  double indexAt(double x) =>
      candleCount -
      0.5 +
      rightPadding -
      (width - x + scrollOffset) / candleWidth;

  /// Index of the first candle that is at least partly visible.
  int get firstVisible => math.max(0, indexAt(0).floor());

  /// Index of the last candle that is at least partly visible.
  int get lastVisible => math.min(candleCount - 1, indexAt(width).ceil());

  /// The candle closest to [x], limited to the visible ones, or null if none
  /// are visible.
  int? nearestVisible(double x) {
    final first = firstVisible;
    final last = lastVisible;
    if (first > last) return null;
    return indexAt(x).round().clamp(first, last);
  }

  /// The furthest the user can scroll back: until the first candle reaches
  /// the middle of the chart.
  double get maxScroll => math.max(
        0,
        (candleCount - 0.5 + rightPadding) * candleWidth - width / 2,
      );

  /// [offset] limited to the allowed scroll range.
  double clampScroll(double offset) => offset.clamp(0.0, maxScroll);

  /// The scroll offset that keeps the candle under [focalX] in place when the
  /// candle width changes to [newCandleWidth]. Used for pinch and wheel zoom.
  double scrollForZoom(double newCandleWidth, double focalX) {
    final focusIndex = indexAt(focalX);
    return (candleCount - 0.5 + rightPadding - focusIndex) * newCandleWidth -
        width +
        focalX;
  }
}

/// Maps values to y positions inside [area]: [min] at the bottom, [max] at
/// the top.
@immutable
class ValueScale {
  /// Creates a scale from [min] to [max] over [area].
  const ValueScale(this.area, this.min, this.max);

  /// A scale that fits [low] to [high], with [margin] (a fraction of the
  /// range) added above and below. An empty range is widened a little.
  factory ValueScale.fit(
    Rect area,
    double low,
    double high, {
    double margin = 0.08,
  }) {
    if (!(high - low > 1e-12)) {
      final pad = high.abs() * 0.01;
      low -= pad == 0 ? 1 : pad;
      high += pad == 0 ? 1 : pad;
    }
    final extra = (high - low) * margin;
    return ValueScale(area, low - extra, high + extra);
  }

  /// The area the values are drawn in.
  final Rect area;

  /// The value at the bottom of [area].
  final double min;

  /// The value at the top of [area].
  final double max;

  /// The y position of [value].
  double y(double value) =>
      area.bottom - (value - min) / (max - min) * area.height;

  /// The value at the y position [y].
  double valueAt(double y) =>
      min + (area.bottom - y) / area.height * (max - min);
}

/// Where each part of the chart goes inside the widget.
@immutable
class ChartLayout {
  const ChartLayout._({
    required this.plot,
    required this.mainArea,
    required this.pricePane,
    required this.volumePane,
    required this.panels,
    required this.priceAxis,
    required this.timeAxis,
  });

  /// Splits [size] into the drawing area, the axis on the right and the time
  /// axis at the bottom.
  ///
  /// From top to bottom the drawing area holds the prices, the volume (with
  /// [showVolume]) and [panelCount] indicator panels. Each panel takes
  /// [panelFraction] of the height, but together they never take more than
  /// 60%, so the prices always keep room.
  factory ChartLayout.compute(
    Size size, {
    required double axisWidth,
    required bool showVolume,
    int panelCount = 0,
    double timeAxisHeight = 24,
    double volumeFraction = 0.2,
    double panelFraction = 0.22,
    double paneGap = 8,
    double topPadding = 24,
  }) {
    final plotWidth = math.max(0.0, size.width - axisWidth);
    final plotHeight = math.max(0.0, size.height - timeAxisHeight);
    final plot = Rect.fromLTWH(0, 0, plotWidth, plotHeight);

    var panelHeight = plotHeight * panelFraction;
    if (panelCount > 0 && panelHeight * panelCount > plotHeight * 0.6) {
      panelHeight = plotHeight * 0.6 / panelCount;
    }
    final mainBottom = plotHeight - panelHeight * panelCount;
    final panels = [
      for (var k = 0; k < panelCount; k++)
        Rect.fromLTWH(0, mainBottom + panelHeight * k, plotWidth, panelHeight),
    ];

    final top = math.min(topPadding, mainBottom);
    Rect? volume;
    var priceBottom = mainBottom;
    if (showVolume) {
      final volumeHeight = mainBottom * volumeFraction;
      volume =
          Rect.fromLTRB(0, mainBottom - volumeHeight, plotWidth, mainBottom);
      priceBottom = math.max(top, volume.top - paneGap);
    }

    return ChartLayout._(
      plot: plot,
      mainArea: Rect.fromLTRB(0, 0, plotWidth, mainBottom),
      pricePane: Rect.fromLTRB(0, top, plotWidth, priceBottom),
      volumePane: volume,
      panels: panels,
      priceAxis: Rect.fromLTWH(plotWidth, 0, axisWidth, plotHeight),
      timeAxis: Rect.fromLTWH(0, plotHeight, plotWidth, timeAxisHeight),
    );
  }

  /// Everything left of the axis and above the time axis: prices, volume and
  /// indicator panels.
  final Rect plot;

  /// The top part of [plot], with the prices and volume (everything but the
  /// indicator panels).
  final Rect mainArea;

  /// The part of [plot] used for prices.
  final Rect pricePane;

  /// The part of [plot] used for volume bars, if shown.
  final Rect? volumePane;

  /// The indicator panels, top to bottom.
  final List<Rect> panels;

  /// The labels on the right, next to the whole of [plot].
  final Rect priceAxis;

  /// The time labels at the bottom.
  final Rect timeAxis;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartLayout &&
          other.plot == plot &&
          other.mainArea == mainArea &&
          other.pricePane == pricePane &&
          other.volumePane == volumePane &&
          listEquals(other.panels, panels) &&
          other.priceAxis == priceAxis &&
          other.timeAxis == timeAxis;

  @override
  int get hashCode => Object.hash(plot, mainArea, pricePane, volumePane,
      Object.hashAll(panels), priceAxis, timeAxis);
}
