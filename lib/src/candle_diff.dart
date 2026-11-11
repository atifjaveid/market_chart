import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'candle.dart';

/// How a candle list changed between two updates. Both lists must be ordered
/// oldest first.
///
/// Candles that are in both lists keep their order: the candle at old index
/// `i` is at new index `i + shift`.
@immutable
class CandleChange {
  /// Describes a change from a list of [oldLength] candles to one of
  /// [newLength].
  const CandleChange({
    required this.oldLength,
    required this.newLength,
    this.isReset = false,
    this.shift = 0,
    int? firstChanged,
  }) : firstChanged = firstChanged ?? newLength;

  /// Number of candles before the change.
  final int oldLength;

  /// Number of candles after the change.
  final int newLength;

  /// Whether the two lists have nothing in common, so everything must be
  /// worked out again.
  final bool isReset;

  /// How far the existing candles moved: positive when older candles were
  /// added at the start, negative when candles were removed from the start.
  final int shift;

  /// Index in the new list of the first candle (after any added at the start)
  /// that is new or different. Equal to [newLength] when the end of the list
  /// didn't change.
  final int firstChanged;

  /// Candles added (positive) or removed (negative) at the end.
  int get addedAtEnd => newLength - (oldLength + shift);

  /// Whether anything changed.
  bool get hasChanges =>
      isReset ||
      shift != 0 ||
      firstChanged < newLength ||
      newLength != oldLength;

  @override
  String toString() => 'CandleChange(old: $oldLength, new: $newLength, '
      'reset: $isReset, shift: $shift, firstChanged: $firstChanged)';
}

/// Works out how [current] differs from [old].
///
/// The common cases are found cheaply: the latest candle changed, candles
/// were added at the end, older history was added at the start, or the
/// oldest candles were dropped. Anything else counts as a reset.
CandleChange diffCandles(List<Candle> old, List<Candle> current) {
  final m = old.length;
  final n = current.length;
  if (m == 0 && n == 0) return const CandleChange(oldLength: 0, newLength: 0);
  if (m == 0 || n == 0) {
    return CandleChange(
        oldLength: m, newLength: n, isReset: true, firstChanged: 0);
  }

  // Line the two lists up by their first candles.
  final int shift;
  if (_same(current[0], old[0])) {
    shift = 0;
  } else {
    final inOld = indexOfTime(old, current[0].time);
    final inNew = indexOfTime(current, old[0].time);
    if (inOld > 0 && _same(old[inOld], current[0])) {
      shift = -inOld; // The oldest candles were dropped.
    } else if (inNew > 0 && _same(current[inNew], old[0])) {
      shift = inNew; // Older candles were added at the start.
    } else {
      return CandleChange(
          oldLength: m, newLength: n, isReset: true, firstChanged: 0);
    }
  }

  // Find the first difference where the lists overlap.
  final start = math.max(0, shift);
  final end = math.min(n, m + shift);
  var first = end;
  for (var j = start; j < end; j++) {
    if (!_same(current[j], old[j - shift])) {
      first = j;
      break;
    }
  }
  return CandleChange(
      oldLength: m, newLength: n, shift: shift, firstChanged: first);
}

bool _same(Candle a, Candle b) => identical(a, b) || a == b;

/// Index of the candle at [time] in [candles] (ordered oldest first), or -1.
int indexOfTime(List<Candle> candles, DateTime time) {
  var low = 0;
  var high = candles.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final order = candles[mid].time.compareTo(time);
    if (order == 0) return mid;
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

/// Index where a candle at [time] would go to keep [candles] in order.
int insertionIndexForTime(List<Candle> candles, DateTime time) {
  var low = 0;
  var high = candles.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (candles[mid].time.isBefore(time)) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

/// Whether [candles] are ordered oldest first.
bool isOrderedByTime(List<Candle> candles) {
  for (var i = 1; i < candles.length; i++) {
    if (candles[i].time.isBefore(candles[i - 1].time)) return false;
  }
  return true;
}
