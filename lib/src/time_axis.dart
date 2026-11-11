import 'dart:math' as math;

import 'candle.dart';

/// A label on the time axis.
class TimeAxisLabel {
  /// Creates a label for the candle at [index].
  const TimeAxisLabel({
    required this.index,
    required this.time,
    required this.rank,
  });

  /// The candle the label goes under.
  final int index;

  /// The time to show. A label that starts a new day gets that day's
  /// midnight, and with daily (or longer) candles a label that starts a new
  /// year gets January 1, so a formatter can show a date or year there.
  final DateTime time;

  /// Which labels to keep when two would overlap: 3 for a new year, 2 for a
  /// new month, 1 for a new day and 0 for the rest.
  final int rank;

  @override
  String toString() => 'TimeAxisLabel($index, $time, rank $rank)';
}

/// A label step: a candle gets a label when its bucket differs from the
/// previous candle's.
class _Step {
  const _Step(this.length, this.bucket);

  /// The length of one step, roughly (months and years vary).
  final Duration length;

  final int Function(_Parts parts) bucket;
}

/// The calendar fields of a candle time, in its own time zone.
class _Parts {
  _Parts(DateTime time)
      : year = time.year,
        month = time.month,
        day = _daysFromCivil(time.year, time.month, time.day),
        second = time.hour * 3600 + time.minute * 60 + time.second;

  final int year;
  final int month;

  /// Days since 1970-01-01.
  final int day;

  /// Seconds since midnight.
  final int second;
}

int _floorDiv(int a, int b) => (a - a % b) ~/ b;

/// Days from 1970-01-01 to the given date (Howard Hinnant's algorithm), so
/// that days can be counted without creating DateTime objects.
int _daysFromCivil(int year, int month, int day) {
  final y = month <= 2 ? year - 1 : year;
  final era = _floorDiv(y, 400);
  final yearOfEra = y - era * 400;
  final dayOfYear =
      (153 * (month > 2 ? month - 3 : month + 9) + 2) ~/ 5 + day - 1;
  final dayOfEra =
      yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
  return era * 146097 + dayOfEra - 719468;
}

_Step _withinDay(Duration length) {
  final seconds = length.inSeconds;
  final perDay = Duration.secondsPerDay ~/ seconds;
  return _Step(length, (p) => p.day * perDay + p.second ~/ seconds);
}

_Step _days(int n) => _Step(Duration(days: n), (p) => _floorDiv(p.day, n));

// Weeks start on Monday. 1970-01-01 was a Thursday, so day 4 is a Monday.
_Step _weeks(int n) =>
    _Step(Duration(days: 7 * n), (p) => _floorDiv(_floorDiv(p.day + 3, 7), n));

_Step _months(int n) => _Step(
      Duration(hours: (730.5 * n).round()),
      (p) => _floorDiv(p.year * 12 + p.month - 1, n),
    );

_Step _years(int n) => _Step(
      Duration(hours: (8766 * n).round()),
      (p) => _floorDiv(p.year, n),
    );

/// The label steps, shortest first. Steps shorter than a day divide a day
/// exactly, so their labels start again at midnight.
final List<_Step> _steps = [
  for (final s in const [1, 2, 5, 10, 15, 30]) _withinDay(Duration(seconds: s)),
  for (final m in const [1, 2, 5, 10, 15, 30]) _withinDay(Duration(minutes: m)),
  for (final h in const [1, 2, 3, 4, 6, 12]) _withinDay(Duration(hours: h)),
  _days(1),
  _days(2),
  _weeks(1),
  _weeks(2),
  for (final n in const [1, 2, 3, 6]) _months(n),
  for (final n in const [1, 2, 5, 10, 20, 50, 100]) _years(n),
];

/// Picks the candles from [first] to [last] to label on the time axis.
///
/// Labels go at round times (14:00, 14:15, 14:30, a new day, a new month...)
/// chosen so that they are about [candlesPerLabel] candles apart. Because the
/// choice depends only on candle times, labels stay on the same candles while
/// scrolling, when older candles are added and when the oldest are dropped.
/// Candles that don't line up with round times (4-hour candles starting at
/// 01:00, say) still get labels: the first candle of each period gets one.
///
/// Labels may still be too close together where the data has gaps; give
/// priority to higher [TimeAxisLabel.rank]s when placing them.
List<TimeAxisLabel> timeAxisLabels(
  List<Candle> candles,
  int first,
  int last,
  Duration interval,
  double candlesPerLabel,
) {
  if (candles.length < 2 || last < first) return [];
  final wanted = interval * math.max(candlesPerLabel, 1.5);
  final step = _steps.firstWhere(
    (s) => s.length >= wanted,
    orElse: () => _steps.last,
  );
  final daily = interval >= const Duration(days: 1);

  final start = math.max(1, first);
  final end = math.min(last, candles.length - 1);
  if (start > end) return [];
  final labels = <TimeAxisLabel>[];
  var previous = _Parts(candles[start - 1].time);
  for (var i = start; i <= end; i++) {
    final time = candles[i].time;
    final parts = _Parts(time);
    if (step.bucket(parts) != step.bucket(previous)) {
      final rank = parts.year != previous.year
          ? 3
          : parts.month != previous.month
              ? 2
              : parts.day != previous.day
                  ? 1
                  : 0;
      final DateTime shown;
      if (rank == 3 && daily) {
        shown = time.isUtc ? DateTime.utc(time.year) : DateTime(time.year);
      } else if (rank > 0) {
        shown = time.isUtc
            ? DateTime.utc(time.year, time.month, time.day)
            : DateTime(time.year, time.month, time.day);
      } else {
        shown = time;
      }
      labels.add(TimeAxisLabel(index: i, time: shown, rank: rank));
    }
    previous = parts;
  }
  return labels;
}
