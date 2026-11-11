import 'dart:collection';

import '../candle.dart';

/// Which price of each candle an indicator uses.
enum PriceSource {
  /// The open.
  open,

  /// The high.
  high,

  /// The low.
  low,

  /// The close. Most indicators use this.
  close,

  /// The average of high and low.
  hl2,

  /// The average of high, low and close (the "typical price").
  hlc3,

  /// The average of open, high, low and close.
  ohlc4;

  /// This price for [candle].
  double of(Candle candle) => switch (this) {
        PriceSource.open => candle.open,
        PriceSource.high => candle.high,
        PriceSource.low => candle.low,
        PriceSource.close => candle.close,
        PriceSource.hl2 => (candle.high + candle.low) / 2,
        PriceSource.hlc3 => (candle.high + candle.low + candle.close) / 3,
        PriceSource.ohlc4 =>
          (candle.open + candle.high + candle.low + candle.close) / 4,
      };
}

/// Prices of a list of candles, for passing to indicators.
///
/// ```dart
/// final ema20 = ema(candles.closes, 20);
/// final typical = sma(candles.prices(PriceSource.hlc3), 20);
/// ```
extension CandlePrices on List<Candle> {
  /// The [source] price of each candle. This is a read-only list that reads
  /// the candles as needed, so nothing is copied.
  List<double> prices(PriceSource source) => _PriceList(this, source);

  /// The close of each candle. See [prices].
  List<double> get closes => _PriceList(this, PriceSource.close);
}

class _PriceList extends ListBase<double> {
  _PriceList(this._candles, this._source);

  final List<Candle> _candles;
  final PriceSource _source;

  @override
  int get length => _candles.length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Prices of candles cannot be changed');

  @override
  double operator [](int index) => _source.of(_candles[index]);

  @override
  void operator []=(int index, double value) =>
      throw UnsupportedError('Prices of candles cannot be changed');
}
