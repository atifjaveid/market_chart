import 'package:flutter/foundation.dart';
import 'package:market_chart/market_chart.dart';

/// Where a feed is up to.
enum FeedStatus {
  /// Loading history or connecting.
  loading,

  /// Prices are live.
  live,

  /// The live connection dropped and the feed is trying again.
  reconnecting,

  /// History couldn't be loaded. See [PriceFeed.error].
  failed,
}

/// Candles for the chart: history first, then live updates.
///
/// Listeners are told whenever [candles], [status] or [loadingOlder] change.
abstract class PriceFeed extends ChangeNotifier {
  /// What the prices are for, such as `BTC/USDT`.
  String get name;

  /// The time between candles.
  Duration get interval;

  /// The candles, oldest first. Empty until history has loaded.
  List<Candle> get candles;

  /// Where the feed is up to.
  FeedStatus get status;

  /// What went wrong, when [status] is [FeedStatus.failed].
  Object? get error;

  /// Whether older candles are being loaded.
  bool get loadingOlder;

  /// Loads history, then starts live updates.
  Future<void> start();

  /// Adds older candles to the start of [candles].
  Future<void> loadOlder();
}
