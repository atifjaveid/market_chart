import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Works out an indicator for a list of values (for example closing prices)
/// and keeps it up to date as the values change.
///
/// After each change, call [update] with the whole list and say where the
/// change starts with `from`. Only the results from there on are worked out
/// again, so updating the latest value stays quick even with thousands of
/// values.
///
/// ```dart
/// final ema = EmaCalculator(20);
/// ema.update(closes); // Everything.
///
/// closes[closes.length - 1] = latestPrice; // The latest value changed:
/// ema.update(closes, from: closes.length - 1); // only it is worked out again.
/// ```
///
/// Results are null until there are enough values: for example the first 19
/// results of a 20-period average.
abstract class IndicatorCalculator {
  /// How many values the results cover: the length of the list passed to the
  /// last [update].
  int get length;

  /// Works the results out again for [values], starting at index [from].
  ///
  /// Values before [from] must be the same as in the previous call. After any
  /// other kind of change (for example older values added at the start), use
  /// `from: 0`, which is the default. If the list got shorter, results past
  /// its end are removed.
  void update(List<double> values, {int from = 0});

  /// Where an update must start: at [from], but no later than the end of the
  /// previous results (anything not worked out yet must be), and within
  /// [newLength].
  @protected
  int startIndex(int from, int newLength) =>
      math.max(0, math.min(math.min(from, length), newLength));
}
