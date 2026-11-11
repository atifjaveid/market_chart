import 'dart:collection';

import 'calculator.dart';

/// Relative Strength Index (RSI), from 0 to 100: how strong recent rises are
/// compared with recent falls. Readings above 70 are often read as
/// overbought, below 30 as oversold.
///
/// Uses J. Welles Wilder's method: the first average gain and loss are simple
/// averages of the first [period] changes; after that each new change counts
/// for `1 / period`. RSI = 100 × average gain / (average gain + average
/// loss). When prices didn't move at all, the result is 50.
///
/// ```dart
/// final rsi14 = rsi(candles.closes);
/// ```
///
/// There is one result per value. The first [period] are null (the first
/// change needs two values).
List<double?> rsi(List<double> values, {int period = 14}) =>
    (RsiCalculator(period: period)..update(values)).values;

/// Keeps an RSI up to date. See [rsi] and [IndicatorCalculator].
class RsiCalculator extends IndicatorCalculator {
  /// Creates a calculator for an RSI over [period] changes.
  RsiCalculator({this.period = 14})
      : assert(period >= 1, 'period must be at least 1');

  /// How many changes the averages are based on.
  final int period;

  final List<double?> _values = [];
  final List<double?> _averageGain = [];
  final List<double?> _averageLoss = [];

  /// The RSI, one result per value. The first [period] are null.
  late final List<double?> values = UnmodifiableListView(_values);

  @override
  int get length => _values.length;

  @override
  void update(List<double> values, {int from = 0}) {
    final start = startIndex(from, values.length);
    final n = values.length;
    _values.length = n;
    _averageGain.length = n;
    _averageLoss.length = n;

    for (var i = start; i < n; i++) {
      if (i < period) {
        _values[i] = null;
        _averageGain[i] = null;
        _averageLoss[i] = null;
        continue;
      }
      double gain;
      double loss;
      if (i == period) {
        var gains = 0.0;
        var losses = 0.0;
        for (var j = 1; j <= period; j++) {
          final change = values[j] - values[j - 1];
          if (change > 0) {
            gains += change;
          } else {
            losses -= change;
          }
        }
        gain = gains / period;
        loss = losses / period;
      } else {
        final change = values[i] - values[i - 1];
        gain = _averageGain[i - 1]! * (period - 1);
        loss = _averageLoss[i - 1]! * (period - 1);
        if (change > 0) {
          gain += change;
        } else {
          loss -= change;
        }
        gain /= period;
        loss /= period;
      }
      _averageGain[i] = gain;
      _averageLoss[i] = loss;
      final total = gain + loss;
      _values[i] = total == 0 ? 50 : 100 * (gain / total);
    }
  }
}
