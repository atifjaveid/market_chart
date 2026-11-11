import 'package:flutter/foundation.dart';

/// One price bar: the open, high, low and close prices for a period of time,
/// plus the volume traded in it.
@immutable
class Candle {
  /// Creates a candle. [high] must not be below [low].
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  })  : assert(high >= low, 'high must not be below low'),
        assert(volume >= 0, 'volume must not be negative');

  /// A candle where open, high, low and close are all [price], for example
  /// the first trade of a new period.
  const Candle.flat({
    required this.time,
    required double price,
    this.volume = 0,
  })  : open = price,
        high = price,
        low = price,
        close = price;

  /// Start time of the period this candle covers.
  final DateTime time;

  /// First traded price in the period.
  final double open;

  /// Highest traded price in the period.
  final double high;

  /// Lowest traded price in the period.
  final double low;

  /// Last traded price in the period.
  final double close;

  /// Amount traded in the period.
  final double volume;

  /// Whether the price closed at or above where it opened.
  bool get isBullish => close >= open;

  /// Returns this candle updated with a new trade at [price].
  ///
  /// The close becomes [price], the high and low stretch to include it, and
  /// [volume] is added. Use it to update the latest candle from a live feed.
  Candle applyTrade(double price, {double volume = 0}) => Candle(
        time: time,
        open: open,
        high: price > high ? price : high,
        low: price < low ? price : low,
        close: price,
        volume: this.volume + volume,
      );

  /// Returns a copy with the given fields replaced.
  Candle copyWith({
    DateTime? time,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
  }) =>
      Candle(
        time: time ?? this.time,
        open: open ?? this.open,
        high: high ?? this.high,
        low: low ?? this.low,
        close: close ?? this.close,
        volume: volume ?? this.volume,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Candle &&
          other.time == time &&
          other.open == open &&
          other.high == high &&
          other.low == low &&
          other.close == close &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(time, open, high, low, close, volume);

  @override
  String toString() =>
      'Candle($time, O: $open, H: $high, L: $low, C: $close, V: $volume)';
}
