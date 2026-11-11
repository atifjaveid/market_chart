import 'dart:collection';
import 'dart:math' as math;

import 'candle.dart';
import 'candle_diff.dart';

/// Keeps a list of candles up to date from a live feed.
///
/// * For feeds that send single trades or prices, use [addTrade]: the first
///   trade in a period starts a new candle, later ones move its close and
///   stretch its high and low.
/// * For feeds that send whole candles (such as an exchange's candle stream),
///   use [addCandle].
/// * When the user scrolls back, add older candles with [addHistory].
///
/// ```dart
/// final feed = CandleAggregator(interval: const Duration(minutes: 1));
///
/// prices.listen((trade) {
///   setState(() => feed.addTrade(trade.price, volume: trade.amount));
/// });
///
/// MarketChart(candles: feed.candles)
/// ```
class CandleAggregator {
  /// Creates an aggregator for candles of length [interval].
  ///
  /// [initialCandles] (oldest first) should start on period boundaries, for
  /// example candles fetched from the same exchange.
  CandleAggregator({
    required this.interval,
    Iterable<Candle> initialCandles = const [],
    this.fillGaps = false,
    this.maxCandles,
    DateTime? origin,
    DateTime Function()? clock,
  })  : assert(interval.inMilliseconds > 0, 'interval must be at least 1 ms'),
        assert(maxCandles == null || maxCandles > 0),
        origin = origin ?? DateTime.utc(1970),
        _clock = clock ?? DateTime.now,
        _candles = List.of(initialCandles) {
    assert(isOrderedByTime(_candles), 'initialCandles must be oldest first');
    _trim();
  }

  /// Length of each candle, for example one minute.
  final Duration interval;

  /// Whether to add flat candles (at the last close, with no volume) for
  /// periods without trades, so the time axis has no jumps. When false,
  /// quiet periods are skipped.
  final bool fillGaps;

  /// If set, the oldest candles are dropped when new ones push the count past
  /// this, to save memory in charts that run for a long time.
  ///
  /// Leave it null if you load older history with [addHistory]: otherwise
  /// that history is dropped again as new candles arrive.
  final int? maxCandles;

  /// A moment that periods line up with. The default, the Unix epoch in UTC,
  /// matches exchanges for intervals up to one day. For weekly candles that
  /// start on Monday, use `DateTime.utc(1970, 1, 5)`.
  final DateTime origin;

  final DateTime Function() _clock;
  final List<Candle> _candles;

  /// The candles so far, oldest first. This is a read-only list that updates
  /// as data comes in, so you can pass it straight to `MarketChart`.
  List<Candle> get candles => UnmodifiableListView(_candles);

  /// Start of the period that [time] falls in.
  DateTime periodStart(DateTime time) {
    final step = interval.inMilliseconds;
    final ms = time.millisecondsSinceEpoch;
    final start = ms - (ms - origin.millisecondsSinceEpoch) % step;
    return DateTime.fromMillisecondsSinceEpoch(start, isUtc: _isUtc(time));
  }

  /// Adds a trade (or a price update) at [price], traded at [time], which
  /// defaults to now.
  ///
  /// A trade for an older period that is still in the list stretches that
  /// candle's high, low and volume but keeps its close. A trade for an older
  /// period that isn't in the list is ignored.
  void addTrade(double price, {double volume = 0, DateTime? time}) {
    assert(price.isFinite, 'price must be a finite number');
    assert(volume >= 0, 'volume must not be negative');
    final start = periodStart(time ?? _clock());
    final last = _candles.isEmpty ? null : _candles.last;

    if (last == null || start.isAfter(last.time)) {
      _addNewest(Candle.flat(time: start, price: price, volume: volume));
    } else if (start.isAtSameMomentAs(last.time)) {
      _candles[_candles.length - 1] = last.applyTrade(price, volume: volume);
    } else {
      final index = indexOfTime(_candles, start);
      if (index == -1) return;
      final candle = _candles[index];
      _candles[index] = candle.copyWith(
        high: math.max(candle.high, price),
        low: math.min(candle.low, price),
        volume: candle.volume + volume,
      );
    }
  }

  /// Adds or replaces a whole candle, for feeds that send candles.
  ///
  /// A candle with the same time as one in the list replaces it, a newer one
  /// is added at the end, and an older one is put in its place by time.
  void addCandle(Candle candle) {
    final last = _candles.isEmpty ? null : _candles.last;
    if (last == null || candle.time.isAfter(last.time)) {
      _addNewest(candle);
      return;
    }
    final index = indexOfTime(_candles, candle.time);
    if (index != -1) {
      _candles[index] = candle;
    } else {
      _candles.insert(insertionIndexForTime(_candles, candle.time), candle);
    }
  }

  /// Adds older candles before the first one, for example after the user
  /// scrolls back and you fetch more history. They can be in any order.
  /// Candles that aren't older than the current first candle are skipped, and
  /// if a time appears more than once, the first one is used.
  void addHistory(Iterable<Candle> older) {
    final first = _candles.isEmpty ? null : _candles.first.time;
    final byTime = <int, Candle>{};
    for (final candle in older) {
      if (first == null || candle.time.isBefore(first)) {
        byTime.putIfAbsent(candle.time.microsecondsSinceEpoch, () => candle);
      }
    }
    final sorted = byTime.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    _candles.insertAll(0, sorted);
  }

  /// Removes all candles.
  void clear() => _candles.clear();

  void _addNewest(Candle candle) {
    final last = _candles.isEmpty ? null : _candles.last;
    if (fillGaps && last != null) {
      var time = last.time.add(interval);
      // Gaps longer than maxCandles would be dropped anyway.
      final limit = maxCandles;
      if (limit != null) {
        final earliest = candle.time.subtract(interval * limit);
        if (time.isBefore(earliest)) time = earliest;
      }
      for (; time.isBefore(candle.time); time = time.add(interval)) {
        _candles.add(Candle.flat(time: time, price: last.close));
      }
    }
    _candles.add(candle);
    _trim();
  }

  void _trim() {
    final limit = maxCandles;
    if (limit != null && _candles.length > limit) {
      _candles.removeRange(0, _candles.length - limit);
    }
  }

  // New candles use the same kind of time (UTC or local) as the existing
  // ones, so axis labels stay consistent.
  bool _isUtc(DateTime time) =>
      _candles.isEmpty ? time.isUtc : _candles.last.time.isUtc;
}
