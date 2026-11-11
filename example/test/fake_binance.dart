import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_chart_example/binance_feed.dart';
import 'package:stream_channel/stream_channel.dart';

const minute = 60000;

/// 10:00 UTC on 11 November 2026, in milliseconds.
final t0 = DateTime.utc(2026, 11, 11, 10).millisecondsSinceEpoch;

/// A candle as Binance's REST API sends it.
List<Object> row(int time, double price, {double volume = 1}) => [
      time,
      '$price',
      '${price + 1}',
      '${price - 1}',
      '$price',
      '$volume',
      time + minute - 1,
      '0',
      1,
      '0',
      '0',
      '0',
    ];

/// A candle-stream message: candle [time] as it was at [event].
String kline(int time, double close, {required int event, double volume = 1}) =>
    jsonEncode({
      'stream': 'btcusdt@kline_1m',
      'data': {
        'e': 'kline',
        'E': event,
        's': 'BTCUSDT',
        'k': {
          't': time,
          'T': time + minute - 1,
          'i': '1m',
          'o': '100.0',
          'h': '${max(close, 101.0)}',
          'l': '99.0',
          'c': '$close',
          'v': '$volume',
          'x': false,
        },
      },
    });

/// A trade-stream message.
String trade(double price, int time) => jsonEncode({
      'stream': 'btcusdt@aggTrade',
      'data': {
        'e': 'aggTrade',
        'E': time,
        's': 'BTCUSDT',
        'p': '$price',
        'q': '0.5',
        'T': time,
        'm': false,
      },
    });

/// Lets queued messages and HTTP responses arrive.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A pretend Binance. The REST API answers from [history]; each WebSocket is
/// a channel the test can send messages on or close.
class FakeBinance {
  FakeBinance(this.history);

  /// Every candle the server has, oldest first.
  final List<List<Object>> history;

  /// HTTP status for REST requests.
  var statusCode = 200;

  /// Whether WebSocket connections fail.
  var refuseSockets = false;

  final requests = <Uri>[];
  final socketUrls = <Uri>[];
  final sockets = <StreamChannelController<dynamic>>[];

  late final client = MockClient((request) async {
    requests.add(request.url);
    if (statusCode != 200) return http.Response('{"msg":"no"}', statusCode);
    final query = request.url.queryParameters;
    final limit = int.parse(query['limit']!);
    final start = int.tryParse(query['startTime'] ?? '');
    final end = int.tryParse(query['endTime'] ?? '');
    var rows = [
      for (final r in history)
        if ((start == null || (r[0] as int) >= start) &&
            (end == null || (r[0] as int) <= end))
          r
    ];
    if (rows.length > limit) {
      // From startTime forwards, or else the latest ones.
      rows = start != null
          ? rows.sublist(0, limit)
          : rows.sublist(rows.length - limit);
    }
    return http.Response(jsonEncode(rows), 200);
  });

  Future<StreamChannel<dynamic>> connect(Uri url) async {
    socketUrls.add(url);
    if (refuseSockets) throw http.ClientException('Connection refused');
    final socket = StreamChannelController<dynamic>();
    sockets.add(socket);
    return socket.local;
  }

  /// Sends [message] from the server on the newest socket.
  void send(String message) => sockets.last.foreign.sink.add(message);

  /// A feed connected to this server. It's disposed after the test.
  BinanceFeed feed({
    String symbol = 'BTCUSDT',
    Timeframe timeframe = Timeframe.m1,
    Duration silenceTimeout = const Duration(seconds: 10),
  }) {
    final feed = BinanceFeed(
      symbol: symbol,
      timeframe: timeframe,
      client: client,
      connect: connect,
      retryDelay: (_) => Duration.zero,
      silenceTimeout: silenceTimeout,
    );
    addTearDown(feed.dispose);
    return feed;
  }
}
