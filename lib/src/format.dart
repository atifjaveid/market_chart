import 'dart:math' as math;

import 'candle.dart';

/// Where a time label is shown.
enum TimeLabelKind {
  /// The labels along the bottom axis. Keep these short.
  axis,

  /// The label under the crosshair. This can be more detailed.
  crosshair,
}

/// Turns a candle time into a label.
///
/// [interval] is the time between candles, so a formatter can show hours for
/// intraday data and dates for daily data.
///
/// Axis labels go at round times. An axis label that starts a new day is
/// passed that day's midnight (even if the candle starts at 01:00), and with
/// daily or longer candles one that starts a new year is passed January 1, so
/// a formatter can show the date or year there.
typedef MarketChartTimeFormatter = String Function(
  DateTime time,
  Duration interval,
  TimeLabelKind kind,
);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// The default time labels: `14:30` or `Mar 5` on the axis, and
/// `Mar 5 14:30` or `Mar 5, 2026` under the crosshair. Candles shorter than a
/// minute also show seconds (`14:30:05`).
String defaultTimeFormatter(
  DateTime time,
  Duration interval,
  TimeLabelKind kind,
) {
  final date = '${_months[time.month - 1]} ${time.day}';
  final withSeconds = interval < const Duration(minutes: 1);
  final clock = withSeconds
      ? '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}'
      : '${_two(time.hour)}:${_two(time.minute)}';
  final intraday = interval < const Duration(days: 1);

  if (kind == TimeLabelKind.crosshair) {
    return intraday ? '$date $clock' : '$date, ${time.year}';
  }
  if (intraday) {
    final midnight = time.hour == 0 && time.minute == 0 && time.second == 0;
    return midnight ? date : clock;
  }
  return time.month == 1 && time.day == 1 ? '${time.year}' : date;
}

/// Formats a price with [precision] decimals and comma thousands separators,
/// for example `64,250.50`.
String formatPrice(double value, int precision) {
  if (!value.isFinite) return '-';
  final fixed = value.abs().toStringAsFixed(precision);
  final dot = fixed.indexOf('.');
  final whole = dot == -1 ? fixed : fixed.substring(0, dot);
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  if (dot != -1) buffer.write(fixed.substring(dot));
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// Formats a large number briefly, for example `1.25K`, `3.40M` or `2.10B`.
String formatCompact(double value) {
  if (!value.isFinite) return '-';
  final size = value.abs();
  if (size >= 1e9) return '${(value / 1e9).toStringAsFixed(2)}B';
  if (size >= 1e6) return '${(value / 1e6).toStringAsFixed(2)}M';
  if (size >= 1e3) return '${(value / 1e3).toStringAsFixed(2)}K';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

/// Picks how many decimals to show for prices around [price]: 2 for prices of
/// 1 or more, and enough to show about four significant digits below that
/// (so `0.05123`, not `0.05`).
int autoPrecision(double price) {
  final size = price.abs();
  if (size == 0 || size >= 1 || !size.isFinite) return 2;
  final leadingZeros = -(math.log(size) / math.ln10).floor();
  return math.min(8, leadingZeros + 3);
}

/// Works out how many decimals to show for [candles], as the chart does when
/// `pricePrecision` isn't set: as many as the recent prices have (`2.3405`
/// has 4, `73720.01` has 2), and at least [autoPrecision] of the latest
/// close. Prices that don't end within 8 decimals, such as calculated ones,
/// get [autoPrecision].
int detectPricePrecision(List<Candle> candles) {
  if (candles.isEmpty) return 2;
  final base = autoPrecision(candles.last.close);
  var decimals = base;
  for (var i = math.max(0, candles.length - 50); i < candles.length; i++) {
    final c = candles[i];
    for (final value in [c.open, c.high, c.low, c.close]) {
      if (!value.isFinite) continue;
      final exact = _exactDecimals(value);
      if (exact == null) return base;
      decimals = math.max(decimals, exact);
    }
  }
  return decimals;
}

/// The fewest decimals (up to 8) that write [value] exactly, allowing for
/// floating-point rounding, or null if it needs more.
int? _exactDecimals(double value) {
  final size = value.abs();
  for (var decimals = 0; decimals <= 8; decimals++) {
    final scaled = size * math.pow(10, decimals);
    if ((scaled - scaled.roundToDouble()).abs() <= scaled * 1e-14 + 1e-9) {
      return decimals;
    }
  }
  return null;
}
