import 'dart:collection';

import 'calculator.dart';
import 'ema_helper.dart';

/// Simple moving average (SMA): the average of the last [period] values.
///
/// ```dart
/// final sma20 = sma(candles.closes, 20);
/// ```
///
/// There is one result per value. The first `period - 1` are null.
List<double?> sma(List<double> values, int period) =>
    (SmaCalculator(period)..update(values)).values;

/// Exponential moving average (EMA) over [period] values. It reacts faster
/// than a simple average because recent values count for more.
///
/// The first result (at index `period - 1`) is the simple average of the
/// first [period] values; after that each value moves the average by
/// `2 / (period + 1)` of the difference. This is the standard method (used by
/// TA-Lib, among others). Platforms that start the average differently agree
/// after the first few dozen values.
///
/// ```dart
/// final ema20 = ema(candles.closes, 20);
/// ```
List<double?> ema(List<double> values, int period) =>
    (EmaCalculator(period)..update(values)).values;

/// Keeps a simple moving average up to date. See [sma] and
/// [IndicatorCalculator].
class SmaCalculator extends IndicatorCalculator {
  /// Creates a calculator for the average of the last [period] values.
  SmaCalculator(this.period) : assert(period >= 1, 'period must be at least 1');

  /// How many values each average covers.
  final int period;

  final List<double?> _values = [];

  // The sum of the window ending at each index. Keeping it means an update
  // continues exactly where the previous one left off.
  final List<double?> _sums = [];

  /// The averages, one per value. The first `period - 1` are null.
  late final List<double?> values = UnmodifiableListView(_values);

  @override
  int get length => _values.length;

  @override
  void update(List<double> values, {int from = 0}) {
    final start = startIndex(from, values.length);
    _values.length = values.length;
    _sums.length = values.length;
    for (var i = start; i < values.length; i++) {
      if (i < period - 1) {
        _values[i] = null;
        _sums[i] = null;
        continue;
      }
      double sum;
      // Normally: add the new value and drop the oldest one. At the first
      // window, and every 512 values so rounding errors can't build up, add
      // the window up from scratch.
      if (i == period - 1 || i % 512 == 0) {
        sum = 0;
        for (var j = i - period + 1; j <= i; j++) {
          sum += values[j];
        }
      } else {
        sum = _sums[i - 1]! + values[i] - values[i - period];
      }
      _sums[i] = sum;
      _values[i] = sum / period;
    }
  }
}

/// Keeps an exponential moving average up to date. See [ema] and
/// [IndicatorCalculator].
class EmaCalculator extends IndicatorCalculator {
  /// Creates a calculator for an EMA over [period] values.
  EmaCalculator(this.period) : assert(period >= 1, 'period must be at least 1');

  /// The number of values the average is based on.
  final int period;

  final List<double?> _values = [];

  /// The averages, one per value. The first `period - 1` are null.
  late final List<double?> values = UnmodifiableListView(_values);

  @override
  int get length => _values.length;

  @override
  void update(List<double> values, {int from = 0}) {
    final start = startIndex(from, values.length);
    _values.length = values.length;
    emaInto(_values, (i) => values[i], values.length, period, start, 0);
  }
}
