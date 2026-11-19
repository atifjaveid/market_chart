import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'candle.dart';
import 'candle_diff.dart';
import 'drawing.dart';
import 'format.dart';
import 'indicators/bollinger_bands.dart';
import 'indicators/calculator.dart';
import 'indicators/indicator.dart';
import 'indicators/macd.dart';
import 'indicators/moving_average.dart';
import 'indicators/price_source.dart';
import 'indicators/rsi.dart';
import 'scale.dart';
import 'theme.dart';

/// Where indicators must start updating after [change]: from the start after
/// a reset or a change at the start of the list (which affects every value),
/// otherwise from the first changed candle.
int indicatorUpdateStart(CandleChange change) =>
    change.isReset || change.shift != 0 ? 0 : change.firstChanged;

/// What an indicator's values depend on. Indicators with the same key give
/// the same values; colours and widths don't count.
Object calculationKey(Indicator indicator) => switch (indicator) {
      MovingAverage(:final period, :final type, :final source) => (
          MovingAverage,
          period,
          type,
          source,
        ),
      BollingerBands(:final period, :final deviations, :final source) => (
          BollingerBands,
          period,
          deviations,
          source,
        ),
      Rsi(:final period, :final source) => (Rsi, period, source),
      Macd(
        :final fastPeriod,
        :final slowPeriod,
        :final signalPeriod,
        :final source,
      ) =>
        (Macd, fastPeriod, slowPeriod, signalPeriod, source),
    };

/// Draws indicator values into an area of the chart.
class IndicatorCanvas {
  /// Creates a canvas for candles [first] to [last], with values placed by
  /// [scale].
  IndicatorCanvas({
    required this.canvas,
    required this.viewport,
    required this.first,
    required this.last,
    required this.scale,
    required this.theme,
    required this.candleWidth,
  });

  final Canvas canvas;
  final ChartViewport viewport;
  final int first;
  final int last;
  final ValueScale scale;
  final MarketChartTheme theme;
  final double candleWidth;

  // One candle past each edge, so lines run off the sides.
  int get _from => math.max(0, first - 1);
  int _to(List<Object?> values) => math.min(values.length - 1, last + 1);

  /// A line through [values], with gaps where they're null.
  void line(List<double?> values, Color color, double width) {
    final path = Path();
    var open = false;
    for (var i = _from; i <= _to(values); i++) {
      final value = values[i];
      if (value == null) {
        open = false;
        continue;
      }
      final x = viewport.xForIndex(i);
      final y = scale.y(value);
      if (open) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        open = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Shading between [top] and [bottom], where both have values.
  void fillBetween(List<double?> top, List<double?> bottom, Color color) {
    final path = Path();
    final to = math.min(_to(top), _to(bottom));
    var i = _from;
    while (i <= to) {
      while (i <= to && (top[i] == null || bottom[i] == null)) {
        i++;
      }
      final start = i;
      while (i <= to && top[i] != null && bottom[i] != null) {
        i++;
      }
      final end = i - 1;
      if (end < start) continue;
      path.moveTo(viewport.xForIndex(start), scale.y(top[start]!));
      for (var k = start + 1; k <= end; k++) {
        path.lineTo(viewport.xForIndex(k), scale.y(top[k]!));
      }
      for (var k = end; k >= start; k--) {
        path.lineTo(viewport.xForIndex(k), scale.y(bottom[k]!));
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  /// Bars from zero to each value. Bars are stronger while they grow away
  /// from zero and paler while they shrink back towards it.
  void histogram(List<double?> values,
      {required Color up, required Color down}) {
    final zero = scale.y(0);
    final width = math.max(1.0, candleWidth * 0.6);
    final paths = [Path(), Path(), Path(), Path()];
    for (var i = first; i <= last && i < values.length; i++) {
      final value = values[i];
      if (value == null) continue;
      final previous = i > 0 ? values[i - 1] : null;
      final growing = previous == null ||
          (value >= 0 ? value >= previous : value <= previous);
      final x = viewport.xForIndex(i);
      final y = scale.y(value);
      paths[(value >= 0 ? 0 : 2) + (growing ? 0 : 1)].addRect(Rect.fromLTRB(
          x - width / 2, math.min(y, zero), x + width / 2, math.max(y, zero)));
    }
    final colors = [
      up,
      up.withValues(alpha: 0.45),
      down,
      down.withValues(alpha: 0.45),
    ];
    for (var k = 0; k < 4; k++) {
      canvas.drawPath(paths[k], Paint()..color = colors[k]);
    }
  }

  /// A dashed line across the area at [value].
  void level(double value, Color color) {
    final y = scale.y(value);
    dashedLine(
      canvas,
      Offset(scale.area.left, y),
      Offset(scale.area.right, y),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }
}

/// The lowest and highest non-null value in [series] for indexes [first] to
/// [last], or null if there are none.
(double, double)? rangeOf(List<List<double?>> series, int first, int last) {
  var low = double.infinity;
  var high = double.negativeInfinity;
  for (final values in series) {
    for (var i = math.max(0, first); i <= last && i < values.length; i++) {
      final value = values[i];
      if (value == null) continue;
      if (value < low) low = value;
      if (value > high) high = value;
    }
  }
  return low > high ? null : (low, high);
}

String _valueAt(List<double?> values, int index, int precision) {
  final value = index >= 0 && index < values.length ? values[index] : null;
  return value == null ? '–' : formatPrice(value, precision);
}

Color _paletteColor(MarketChartTheme theme, int next) {
  final palette = theme.indicatorColors;
  return palette.isEmpty ? theme.lineColor : palette[next % palette.length];
}

/// Connects an [Indicator] to its calculator, and knows how to draw it.
abstract class IndicatorView {
  IndicatorView(this.config);

  /// A view for [indicator].
  factory IndicatorView.of(Indicator indicator) => switch (indicator) {
        MovingAverage ma => MovingAverageView(ma),
        BollingerBands bands => BollingerBandsView(bands),
        Rsi rsi => RsiView(rsi),
        Macd macd => MacdView(macd),
      };

  /// The indicator's settings. Replaced when only its colours or widths
  /// change, so the values can be kept.
  Indicator config;

  /// Works the values out again from candle [from] on.
  void update(List<Candle> candles, int from);

  /// Every series of values the indicator draws, one value per candle.
  List<List<double?>> get series;

  /// How many palette colours this indicator uses.
  int get paletteSlots => 0;

  /// The colours to draw with. [next] is the first unused palette colour.
  List<Color> colors(MarketChartTheme theme, int next);

  /// The lowest and highest value drawn for candles [first] to [last], for
  /// fitting the price scale. Null when there are none (or for panels).
  (double, double)? range(int first, int last) => null;

  /// Draws the values.
  void paint(IndicatorCanvas canvas, List<Color> colors);

  /// The legend text for the candle at [index].
  List<InlineSpan> legend(
      int index, TextStyle style, int precision, List<Color> colors);
}

/// An indicator with a panel of its own.
abstract class PanelView extends IndicatorView {
  PanelView(super.config);

  /// The values the panel shows for candles [first] to [last].
  (double, double) panelRange(int first, int last);

  /// Whether [panelRange] is used as it is (like RSI's 0 to 100), rather
  /// than with a margin.
  bool get fixedRange => false;

  /// Values to label on the axis.
  List<double> axisValues(ValueScale scale);

  /// Decimals for axis labels.
  int get axisPrecision => precision;

  /// Decimals for values in the legend and under the crosshair.
  int get precision;

  /// The largest value (ignoring sign), for sizing the axis.
  double get largestValue;

  /// Marks drawn behind the values, such as RSI's levels.
  void paintGuides(IndicatorCanvas canvas, List<Color> colors) {}
}

class MovingAverageView extends IndicatorView {
  MovingAverageView(MovingAverage config) : super(config) {
    if (config.type == MovingAverageType.simple) {
      final calculator = SmaCalculator(config.period);
      _calculator = calculator;
      values = calculator.values;
    } else {
      final calculator = EmaCalculator(config.period);
      _calculator = calculator;
      values = calculator.values;
    }
  }

  late final IndicatorCalculator _calculator;
  late final List<double?> values;

  MovingAverage get indicator => config as MovingAverage;

  @override
  void update(List<Candle> candles, int from) =>
      _calculator.update(candles.prices(indicator.source), from: from);

  @override
  List<List<double?>> get series => [values];

  @override
  int get paletteSlots => indicator.color == null ? 1 : 0;

  @override
  List<Color> colors(MarketChartTheme theme, int next) =>
      [indicator.color ?? _paletteColor(theme, next)];

  @override
  (double, double)? range(int first, int last) =>
      rangeOf([values], first, last);

  @override
  void paint(IndicatorCanvas canvas, List<Color> colors) =>
      canvas.line(values, colors[0], indicator.width);

  @override
  List<InlineSpan> legend(
          int index, TextStyle style, int precision, List<Color> colors) =>
      [
        TextSpan(text: '${indicator.label} '),
        TextSpan(
          text: _valueAt(values, index, precision),
          style: style.copyWith(color: colors[0]),
        ),
      ];
}

class BollingerBandsView extends IndicatorView {
  BollingerBandsView(BollingerBands super.config)
      : _calculator = BollingerBandsCalculator(
            period: config.period, deviations: config.deviations);

  final BollingerBandsCalculator _calculator;

  BollingerBands get indicator => config as BollingerBands;

  @override
  void update(List<Candle> candles, int from) =>
      _calculator.update(candles.prices(indicator.source), from: from);

  @override
  List<List<double?>> get series =>
      [_calculator.upper, _calculator.middle, _calculator.lower];

  @override
  int get paletteSlots => indicator.color == null ? 1 : 0;

  @override
  List<Color> colors(MarketChartTheme theme, int next) =>
      [indicator.color ?? _paletteColor(theme, next)];

  @override
  (double, double)? range(int first, int last) =>
      rangeOf([_calculator.upper, _calculator.lower], first, last);

  @override
  void paint(IndicatorCanvas canvas, List<Color> colors) {
    final color = colors[0];
    if (indicator.fillOpacity > 0) {
      canvas.fillBetween(_calculator.upper, _calculator.lower,
          color.withValues(alpha: indicator.fillOpacity));
    }
    canvas.line(_calculator.upper, color, indicator.width);
    canvas.line(_calculator.lower, color, indicator.width);
    canvas.line(
        _calculator.middle, color.withValues(alpha: 0.7), indicator.width);
  }

  @override
  List<InlineSpan> legend(
      int index, TextStyle style, int precision, List<Color> colors) {
    final value = style.copyWith(color: colors[0]);
    return [
      TextSpan(text: '${indicator.label} '),
      TextSpan(
        text: '${_valueAt(_calculator.upper, index, precision)} '
            '${_valueAt(_calculator.middle, index, precision)} '
            '${_valueAt(_calculator.lower, index, precision)}',
        style: value,
      ),
    ];
  }
}

class RsiView extends PanelView {
  RsiView(Rsi super.config)
      : _calculator = RsiCalculator(period: config.period);

  final RsiCalculator _calculator;

  Rsi get indicator => config as Rsi;

  @override
  void update(List<Candle> candles, int from) =>
      _calculator.update(candles.prices(indicator.source), from: from);

  @override
  List<List<double?>> get series => [_calculator.values];

  @override
  List<Color> colors(MarketChartTheme theme, int next) => [indicator.color];

  @override
  (double, double) panelRange(int first, int last) => (0, 100);

  @override
  bool get fixedRange => true;

  @override
  List<double> axisValues(ValueScale scale) =>
      [indicator.oversold, indicator.overbought];

  @override
  int get axisPrecision => 0;

  @override
  int get precision => 2;

  @override
  double get largestValue => 100;

  @override
  void paintGuides(IndicatorCanvas canvas, List<Color> colors) {
    final scale = canvas.scale;
    canvas.canvas.drawRect(
      Rect.fromLTRB(scale.area.left, scale.y(indicator.overbought),
          scale.area.right, scale.y(indicator.oversold)),
      Paint()..color = colors[0].withValues(alpha: 0.07),
    );
    final levelColor = canvas.theme.crosshairColor.withValues(alpha: 0.5);
    canvas.level(indicator.overbought, levelColor);
    canvas.level(indicator.oversold, levelColor);
  }

  @override
  void paint(IndicatorCanvas canvas, List<Color> colors) =>
      canvas.line(_calculator.values, colors[0], indicator.width);

  @override
  List<InlineSpan> legend(
          int index, TextStyle style, int precision, List<Color> colors) =>
      [
        TextSpan(text: '${indicator.label} '),
        TextSpan(
          text: _valueAt(_calculator.values, index, this.precision),
          style: style.copyWith(color: colors[0]),
        ),
      ];
}

class MacdView extends PanelView {
  MacdView(Macd super.config)
      : _calculator = MacdCalculator(
          fastPeriod: config.fastPeriod,
          slowPeriod: config.slowPeriod,
          signalPeriod: config.signalPeriod,
        );

  final MacdCalculator _calculator;
  double _largest = 0;

  Macd get indicator => config as Macd;

  @override
  void update(List<Candle> candles, int from) {
    final start = math.max(0, math.min(from, _calculator.length));
    _calculator.update(candles.prices(indicator.source), from: from);
    // The largest value only grows between full updates. That's fine for
    // sizing the axis.
    if (start == 0) _largest = 0;
    for (final values in [
      _calculator.macd,
      _calculator.signal,
      _calculator.histogram,
    ]) {
      for (var i = start; i < values.length; i++) {
        final value = values[i];
        if (value != null && value.abs() > _largest) _largest = value.abs();
      }
    }
  }

  @override
  List<List<double?>> get series =>
      [_calculator.macd, _calculator.signal, _calculator.histogram];

  @override
  List<Color> colors(MarketChartTheme theme, int next) => [
        indicator.macdColor,
        indicator.signalColor,
        theme.bullColor,
        theme.bearColor,
      ];

  @override
  (double, double) panelRange(int first, int last) {
    final range = rangeOf(
      [_calculator.macd, _calculator.signal, _calculator.histogram],
      first,
      last,
    );
    if (range == null) return (-1, 1);
    // Always show the zero line.
    return (math.min(range.$1, 0), math.max(range.$2, 0));
  }

  @override
  List<double> axisValues(ValueScale scale) {
    final count = math.max(2, scale.area.height ~/ 32);
    final ticks = niceTicks(scale.min, scale.max, count);
    // Round steps can leave a single tick; two or more show the scale.
    return ticks.length >= 2
        ? ticks
        : niceTicks(scale.min, scale.max, count * 2);
  }

  @override
  int get precision => autoPrecision(_largest);

  @override
  double get largestValue => _largest;

  @override
  void paintGuides(IndicatorCanvas canvas, List<Color> colors) =>
      canvas.level(0, canvas.theme.crosshairColor.withValues(alpha: 0.5));

  @override
  void paint(IndicatorCanvas canvas, List<Color> colors) {
    canvas.histogram(_calculator.histogram, up: colors[2], down: colors[3]);
    canvas.line(_calculator.macd, colors[0], indicator.width);
    canvas.line(_calculator.signal, colors[1], indicator.width);
  }

  @override
  List<InlineSpan> legend(
      int index, TextStyle style, int precision, List<Color> colors) {
    final histogram = index >= 0 && index < _calculator.histogram.length
        ? _calculator.histogram[index]
        : null;
    final histogramColor =
        histogram != null && histogram < 0 ? colors[3] : colors[2];
    return [
      TextSpan(text: '${indicator.label} '),
      TextSpan(
        text: _valueAt(_calculator.macd, index, this.precision),
        style: style.copyWith(color: colors[0]),
      ),
      const TextSpan(text: ' '),
      TextSpan(
        text: _valueAt(_calculator.signal, index, this.precision),
        style: style.copyWith(color: colors[1]),
      ),
      const TextSpan(text: ' '),
      TextSpan(
        text: _valueAt(_calculator.histogram, index, this.precision),
        style: style.copyWith(color: histogramColor),
      ),
    ];
  }
}
