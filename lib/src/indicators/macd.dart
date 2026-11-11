import 'dart:collection';
import 'dart:math' as math;

import 'calculator.dart';
import 'ema_helper.dart';
import 'moving_average.dart';

/// Moving Average Convergence Divergence (MACD): how a fast and a slow
/// moving average pull apart or come together.
///
/// * `macd`: fast EMA minus slow EMA (each worked out like [ema]).
/// * `signal`: an EMA of the MACD line over [signalPeriod] values.
/// * `histogram`: MACD minus signal.
///
/// ```dart
/// final result = macd(candles.closes);
/// print(result.histogram.last);
/// ```
///
/// Each list has one result per value. The MACD line starts at index
/// `max(fastPeriod, slowPeriod) - 1`, the signal and histogram
/// `signalPeriod - 1` values later.
///
/// This is the common definition (fast and slow EMAs worked out
/// independently). TA-Lib's own MACD function starts its fast average later,
/// so its first few dozen values differ slightly.
({List<double?> macd, List<double?> signal, List<double?> histogram}) macd(
  List<double> values, {
  int fastPeriod = 12,
  int slowPeriod = 26,
  int signalPeriod = 9,
}) {
  final calculator = MacdCalculator(
    fastPeriod: fastPeriod,
    slowPeriod: slowPeriod,
    signalPeriod: signalPeriod,
  )..update(values);
  return (
    macd: calculator.macd,
    signal: calculator.signal,
    histogram: calculator.histogram,
  );
}

/// Keeps a MACD up to date. See [macd] and [IndicatorCalculator].
class MacdCalculator extends IndicatorCalculator {
  /// Creates a calculator with the given periods. The defaults (12, 26, 9)
  /// are the usual ones.
  MacdCalculator({
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.signalPeriod = 9,
  })  : assert(fastPeriod >= 1, 'fastPeriod must be at least 1'),
        assert(slowPeriod >= 1, 'slowPeriod must be at least 1'),
        assert(signalPeriod >= 1, 'signalPeriod must be at least 1');

  /// Period of the fast EMA.
  final int fastPeriod;

  /// Period of the slow EMA.
  final int slowPeriod;

  /// Period of the EMA of the MACD line.
  final int signalPeriod;

  late final EmaCalculator _fast = EmaCalculator(fastPeriod);
  late final EmaCalculator _slow = EmaCalculator(slowPeriod);
  final List<double?> _macd = [];
  final List<double?> _signal = [];
  final List<double?> _histogram = [];

  /// The MACD line (fast EMA minus slow EMA), one result per value.
  late final List<double?> macd = UnmodifiableListView(_macd);

  /// The signal line (EMA of the MACD line), one result per value.
  late final List<double?> signal = UnmodifiableListView(_signal);

  /// MACD minus signal, one result per value.
  late final List<double?> histogram = UnmodifiableListView(_histogram);

  @override
  int get length => _macd.length;

  @override
  void update(List<double> values, {int from = 0}) {
    final start = startIndex(from, values.length);
    final n = values.length;
    _fast.update(values, from: start);
    _slow.update(values, from: start);
    _macd.length = n;
    _signal.length = n;
    _histogram.length = n;

    for (var i = start; i < n; i++) {
      final fast = _fast.values[i];
      final slow = _slow.values[i];
      _macd[i] = fast == null || slow == null ? null : fast - slow;
    }

    final firstMacd = math.max(fastPeriod, slowPeriod) - 1;
    emaInto(_signal, (i) => _macd[i]!, n, signalPeriod, start, firstMacd);

    for (var i = start; i < n; i++) {
      final line = _macd[i];
      final signal = _signal[i];
      _histogram[i] = line == null || signal == null ? null : line - signal;
    }
  }
}
