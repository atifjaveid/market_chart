import 'dart:collection';
import 'dart:math' as math;

import 'calculator.dart';

/// Bollinger Bands: a simple moving average over [period] values (`middle`),
/// with bands [deviations] standard deviations above (`upper`) and below
/// (`lower`) it. The bands widen when prices swing more.
///
/// The standard deviation is taken over the same [period] values, dividing by
/// [period] (as John Bollinger defines it, and as TA-Lib and TradingView do).
///
/// ```dart
/// final bands = bollingerBands(candles.closes);
/// print(bands.upper.last);
/// ```
///
/// Each list has one result per value. The first `period - 1` are null.
({List<double?> upper, List<double?> middle, List<double?> lower})
    bollingerBands(
  List<double> values, {
  int period = 20,
  double deviations = 2,
}) {
  final calculator =
      BollingerBandsCalculator(period: period, deviations: deviations)
        ..update(values);
  return (
    upper: calculator.upper,
    middle: calculator.middle,
    lower: calculator.lower,
  );
}

/// Keeps Bollinger Bands up to date. See [bollingerBands] and
/// [IndicatorCalculator].
class BollingerBandsCalculator extends IndicatorCalculator {
  /// Creates a calculator for bands over [period] values, [deviations]
  /// standard deviations from the average.
  BollingerBandsCalculator({this.period = 20, this.deviations = 2})
      : assert(period >= 1, 'period must be at least 1'),
        assert(deviations >= 0, 'deviations must not be negative');

  /// How many values the average and standard deviation cover.
  final int period;

  /// How many standard deviations the bands are from the average.
  final double deviations;

  final List<double?> _upper = [];
  final List<double?> _middle = [];
  final List<double?> _lower = [];

  /// The upper band, one result per value.
  late final List<double?> upper = UnmodifiableListView(_upper);

  /// The simple moving average, one result per value.
  late final List<double?> middle = UnmodifiableListView(_middle);

  /// The lower band, one result per value.
  late final List<double?> lower = UnmodifiableListView(_lower);

  @override
  int get length => _middle.length;

  @override
  void update(List<double> values, {int from = 0}) {
    final start = startIndex(from, values.length);
    final n = values.length;
    _upper.length = n;
    _middle.length = n;
    _lower.length = n;
    for (var i = start; i < n; i++) {
      if (i < period - 1) {
        _upper[i] = null;
        _middle[i] = null;
        _lower[i] = null;
        continue;
      }
      // Two passes over the window (average, then spread around it), which
      // stays accurate for large prices.
      var sum = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        sum += values[j];
      }
      final mean = sum / period;
      var squares = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        final difference = values[j] - mean;
        squares += difference * difference;
      }
      final width = deviations * math.sqrt(squares / period);
      _middle[i] = mean;
      _upper[i] = mean + width;
      _lower[i] = mean - width;
    }
  }
}
