import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'price_source.dart';

/// An indicator to draw on a `MarketChart`, listed in its `indicators`.
///
/// [MovingAverage] and [BollingerBands] are drawn over the prices. [Rsi] and
/// [Macd] each get a panel below them. The values stay up to date as live
/// data arrives, and only what changed is worked out again.
///
/// ```dart
/// MarketChart(
///   candles: candles,
///   indicators: const [
///     MovingAverage.ema(20),
///     BollingerBands(),
///     Rsi(),
///     Macd(),
///   ],
/// )
/// ```
///
/// Indicators are compared by value, so building the same list again in
/// every build is fine: the chart keeps the work it has already done.
@immutable
sealed class Indicator {
  const Indicator();

  /// The name shown in the chart's legend, for example `EMA 20`.
  String get label;

  /// Whether the indicator has a panel of its own below the prices.
  bool get hasPanel;
}

/// Whether a [MovingAverage] is simple or exponential.
enum MovingAverageType {
  /// The plain average of the last values (see `sma`).
  simple,

  /// An average where recent values count for more (see `ema`).
  exponential,
}

/// A moving average, drawn as a line over the prices.
class MovingAverage extends Indicator {
  /// A moving average over [period] candles.
  const MovingAverage(
    this.period, {
    this.type = MovingAverageType.simple,
    this.source = PriceSource.close,
    this.color,
    this.width = 1.5,
  }) : assert(period >= 1, 'period must be at least 1');

  /// A simple moving average (SMA) over [period] candles.
  const MovingAverage.sma(
    this.period, {
    this.source = PriceSource.close,
    this.color,
    this.width = 1.5,
  })  : type = MovingAverageType.simple,
        assert(period >= 1, 'period must be at least 1');

  /// An exponential moving average (EMA) over [period] candles.
  const MovingAverage.ema(
    this.period, {
    this.source = PriceSource.close,
    this.color,
    this.width = 1.5,
  })  : type = MovingAverageType.exponential,
        assert(period >= 1, 'period must be at least 1');

  /// How many candles the average covers.
  final int period;

  /// Simple or exponential.
  final MovingAverageType type;

  /// Which price of each candle is averaged.
  final PriceSource source;

  /// Line colour. When null, the chart uses the next colour from
  /// `MarketChartTheme.indicatorColors`.
  final Color? color;

  /// Line width in pixels.
  final double width;

  @override
  String get label =>
      '${type == MovingAverageType.simple ? 'SMA' : 'EMA'} $period'
      '${_sourceSuffix(source)}';

  @override
  bool get hasPanel => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovingAverage &&
          other.period == period &&
          other.type == type &&
          other.source == source &&
          other.color == color &&
          other.width == width;

  @override
  int get hashCode =>
      Object.hash(MovingAverage, period, type, source, color, width);
}

/// Bollinger Bands, drawn over the prices: a moving average with a band
/// [deviations] standard deviations above and below it.
class BollingerBands extends Indicator {
  /// Bollinger Bands over [period] candles. The defaults (20, 2) are the
  /// usual ones.
  const BollingerBands({
    this.period = 20,
    this.deviations = 2,
    this.source = PriceSource.close,
    this.color,
    this.fillOpacity = 0.08,
    this.width = 1,
  })  : assert(period >= 1, 'period must be at least 1'),
        assert(deviations >= 0, 'deviations must not be negative'),
        assert(fillOpacity >= 0 && fillOpacity <= 1,
            'fillOpacity must be between 0 and 1');

  /// How many candles the average and standard deviation cover.
  final int period;

  /// How far the bands are from the average, in standard deviations.
  final double deviations;

  /// Which price of each candle is used.
  final PriceSource source;

  /// Colour of the bands and the average. When null, the chart uses the next
  /// colour from `MarketChartTheme.indicatorColors`.
  final Color? color;

  /// Opacity of the shading between the bands. 0 turns it off.
  final double fillOpacity;

  /// Line width in pixels.
  final double width;

  @override
  String get label =>
      'BB $period ${_number(deviations)}${_sourceSuffix(source)}';

  @override
  bool get hasPanel => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BollingerBands &&
          other.period == period &&
          other.deviations == deviations &&
          other.source == source &&
          other.color == color &&
          other.fillOpacity == fillOpacity &&
          other.width == width;

  @override
  int get hashCode => Object.hash(
      BollingerBands, period, deviations, source, color, fillOpacity, width);
}

/// The Relative Strength Index (0 to 100), in a panel below the prices, with
/// the [overbought] and [oversold] levels marked.
class Rsi extends Indicator {
  /// An RSI over [period] candles. 14 is the usual period.
  const Rsi({
    this.period = 14,
    this.source = PriceSource.close,
    this.color = const Color(0xFF7E57C2),
    this.overbought = 70,
    this.oversold = 30,
    this.width = 1.5,
  })  : assert(period >= 1, 'period must be at least 1'),
        assert(oversold >= 0 && overbought <= 100 && oversold < overbought,
            'levels must be between 0 and 100, oversold below overbought');

  /// How many candles the averages cover.
  final int period;

  /// Which price of each candle is used.
  final PriceSource source;

  /// Line colour.
  final Color color;

  /// The upper level marked in the panel.
  final double overbought;

  /// The lower level marked in the panel.
  final double oversold;

  /// Line width in pixels.
  final double width;

  @override
  String get label => 'RSI $period${_sourceSuffix(source)}';

  @override
  bool get hasPanel => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Rsi &&
          other.period == period &&
          other.source == source &&
          other.color == color &&
          other.overbought == overbought &&
          other.oversold == oversold &&
          other.width == width;

  @override
  int get hashCode =>
      Object.hash(Rsi, period, source, color, overbought, oversold, width);
}

/// MACD in a panel below the prices: the MACD line, its signal line, and the
/// difference between them as a histogram.
class Macd extends Indicator {
  /// A MACD with the given periods. The defaults (12, 26, 9) are the usual
  /// ones.
  const Macd({
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.signalPeriod = 9,
    this.source = PriceSource.close,
    this.macdColor = const Color(0xFF2962FF),
    this.signalColor = const Color(0xFFFF6D00),
    this.width = 1.5,
  })  : assert(fastPeriod >= 1, 'fastPeriod must be at least 1'),
        assert(slowPeriod >= 1, 'slowPeriod must be at least 1'),
        assert(signalPeriod >= 1, 'signalPeriod must be at least 1');

  /// Period of the fast EMA.
  final int fastPeriod;

  /// Period of the slow EMA.
  final int slowPeriod;

  /// Period of the EMA of the MACD line.
  final int signalPeriod;

  /// Which price of each candle is used.
  final PriceSource source;

  /// Colour of the MACD line.
  final Color macdColor;

  /// Colour of the signal line.
  final Color signalColor;

  /// Line width in pixels.
  final double width;

  @override
  String get label =>
      'MACD $fastPeriod $slowPeriod $signalPeriod${_sourceSuffix(source)}';

  @override
  bool get hasPanel => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Macd &&
          other.fastPeriod == fastPeriod &&
          other.slowPeriod == slowPeriod &&
          other.signalPeriod == signalPeriod &&
          other.source == source &&
          other.macdColor == macdColor &&
          other.signalColor == signalColor &&
          other.width == width;

  @override
  int get hashCode => Object.hash(Macd, fastPeriod, slowPeriod, signalPeriod,
      source, macdColor, signalColor, width);
}

String _sourceSuffix(PriceSource source) =>
    source == PriceSource.close ? '' : ' ${source.name}';

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();
