import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_chart/market_chart.dart';

/// Reference values from TA-Lib, made by test/fixtures/generate_reference.py.
final Map<String, dynamic> reference =
    jsonDecode(File('test/fixtures/reference.json').readAsStringSync())
        as Map<String, dynamic>;

List<double?> series(Object? json) =>
    [for (final value in json! as List) (value as num?)?.toDouble()];

/// Checks that [actual] has nulls in the same places as [expected], and
/// values within [tolerance] elsewhere (0 means exactly equal).
///
/// Messages are only built for a mismatch: some tests compare millions of
/// values.
void expectSeries(
  List<double?> actual,
  List<double?> expected, {
  double tolerance = 1e-6,
  String reason = '',
}) {
  expect(actual, hasLength(expected.length), reason: reason);
  for (var i = 0; i < expected.length; i++) {
    final want = expected[i];
    final got = actual[i];
    final ok = want == null
        ? got == null
        : got != null && (got - want).abs() <= tolerance;
    if (!ok) fail('$reason at index $i: expected $want, got $got');
  }
}

void main() {
  group('Matches TA-Lib on 150 days of BTC/USDT', () {
    final closes = [for (final v in series(reference['close'])) v!];

    test('SMA 20', () {
      expectSeries(sma(closes, 20), series(reference['sma20']));
    });

    test('EMA 20 and EMA 9', () {
      expectSeries(ema(closes, 20), series(reference['ema20']));
      expectSeries(ema(closes, 9), series(reference['ema9']));
    });

    test('Bollinger Bands 20, 2', () {
      final expected = reference['bollinger20'] as Map<String, dynamic>;
      final bands = bollingerBands(closes);
      expectSeries(bands.upper, series(expected['upper']), reason: 'upper');
      expectSeries(bands.middle, series(expected['middle']), reason: 'middle');
      expectSeries(bands.lower, series(expected['lower']), reason: 'lower');
    });

    test('RSI 14', () {
      expectSeries(rsi(closes), series(reference['rsi14']), tolerance: 1e-9);
    });

    test('MACD 12, 26, 9', () {
      final expected = reference['macd12_26_9'] as Map<String, dynamic>;
      final result = macd(closes);
      expectSeries(result.macd, series(expected['macd']), reason: 'macd');
      expectSeries(result.signal, series(expected['signal']), reason: 'signal');
      expectSeries(result.histogram, series(expected['histogram']),
          reason: 'histogram');
    });
  });

  group('Small cases worked out by hand', () {
    test('SMA', () {
      expect(sma([1, 2, 3, 4, 5], 3), [null, null, 2, 3, 4]);
      expect(sma([1, 2, 3], 1), [1, 2, 3]);
    });

    test('EMA starts with the simple average', () {
      // Period 3: the first EMA is (1 + 2 + 3) / 3 = 2, then each value moves
      // it halfway (2 / (3 + 1)) towards the new value.
      expect(ema([1, 2, 3, 4, 5], 3), [null, null, 2, 3, 4]);
      expect(ema([1, 2, 3], 1), [1, 2, 3]);
    });

    test('Bollinger Bands', () {
      // Average 3, population standard deviation sqrt(2).
      final bands = bollingerBands([1, 2, 3, 4, 5], period: 5);
      expect(bands.middle.last, 3);
      expect(bands.upper.last, closeTo(3 + 2 * sqrt(2), 1e-12));
      expect(bands.lower.last, closeTo(3 - 2 * sqrt(2), 1e-12));

      final flat = bollingerBands([5, 5, 5], period: 3);
      expect([flat.lower.last, flat.middle.last, flat.upper.last], [5, 5, 5]);
    });

    test('RSI', () {
      // Changes +1, +1, +1, +1, -1. With period 3 the first averages are
      // gain 1 and loss 0 (RSI 100). At the last value: gain (1 × 2 + 0) / 3,
      // loss (0 × 2 + 1) / 3, so RSI = 100 × (2/3) / 1.
      final result = rsi([1, 2, 3, 4, 5, 4], period: 3);
      expect(result.take(3), [null, null, null]);
      expect(result[3], 100);
      expect(result[4], 100);
      expect(result[5], closeTo(200 / 3, 1e-12));

      expect(rsi([5, 4, 3, 2], period: 3).last, 0);
      expect(rsi([5, 5, 5, 5], period: 3).last, 50, reason: 'no movement');
    });

    test('MACD of a straight line is constant', () {
      // Fast EMA 2: 1.5, 2.5, 3.5 ...; slow EMA 3: 2, 3, 4 ... so MACD is 0.5.
      final result = macd([1, 2, 3, 4, 5, 6],
          fastPeriod: 2, slowPeriod: 3, signalPeriod: 2);
      expect(result.macd, [null, null, 0.5, 0.5, 0.5, 0.5]);
      expect(result.signal, [null, null, null, 0.5, 0.5, 0.5]);
      expect(result.histogram, [null, null, null, 0, 0, 0]);
    });

    test('too few values gives nulls, no values gives nothing', () {
      expect(sma([1, 2], 5), [null, null]);
      expect(rsi([1, 2, 3]), [null, null, null]);
      expect(macd([1, 2, 3]).signal, [null, null, null]);
      expect(ema(const [], 10), isEmpty);
      expect(bollingerBands(const []).middle, isEmpty);
    });
  });

  group('Updating step by step gives the same results as starting over', () {
    final cases = <String,
        (
      IndicatorCalculator Function(),
      List<List<double?>> Function(IndicatorCalculator)
    )>{
      'SMA 5': (() => SmaCalculator(5), (c) => [(c as SmaCalculator).values]),
      'EMA 7': (() => EmaCalculator(7), (c) => [(c as EmaCalculator).values]),
      'Bollinger 10': (
        () => BollingerBandsCalculator(period: 10),
        (c) {
          final b = c as BollingerBandsCalculator;
          return [b.upper, b.middle, b.lower];
        },
      ),
      'RSI 6': (
        () => RsiCalculator(period: 6),
        (c) => [(c as RsiCalculator).values]
      ),
      'MACD 3, 8, 4': (
        () => MacdCalculator(fastPeriod: 3, slowPeriod: 8, signalPeriod: 4),
        (c) {
          final m = c as MacdCalculator;
          return [m.macd, m.signal, m.histogram];
        },
      ),
    };

    cases.forEach((name, spec) {
      final (create, outputs) = spec;
      test(name, () {
        final random = Random(42);
        // Start with 500 values, so the updates cross index 512 (where the
        // SMA adds its window up from scratch).
        final values = <double>[
          for (var i = 0, p = 100.0; i < 500; i++)
            p += random.nextDouble() - 0.5,
        ];
        final live = create()..update(values);

        for (var step = 0; step < 500; step++) {
          final roll = random.nextDouble();
          int from;
          if (roll < 0.5) {
            // The latest value changes (a live price update).
            values[values.length - 1] += random.nextDouble() - 0.5;
            from = values.length - 1;
          } else if (roll < 0.8) {
            // A new value arrives.
            values.add(values.last + random.nextDouble() - 0.5);
            from = values.length - 1;
          } else if (roll < 0.9) {
            // An older value is corrected.
            final index = random.nextInt(values.length);
            values[index] += 1;
            from = index;
          } else if (values.length > 3) {
            // The latest value is removed.
            values.removeLast();
            from = values.length;
          } else {
            from = 0;
          }

          live.update(values, from: from);
          final fresh = create()..update(values);
          final a = outputs(live);
          final b = outputs(fresh);
          // Exactly the same, not just close.
          for (var k = 0; k < a.length; k++) {
            expectSeries(a[k], b[k], tolerance: 0, reason: '$name step $step');
          }
        }
      });
    });

    test('the SMA stays accurate over long lists of large prices', () {
      final random = Random(3);
      final values = [
        for (var i = 0, p = 1e5; i < 20000; i++) p += random.nextDouble() - 0.5,
      ];
      final result = sma(values, 50);
      for (var i = 49; i < values.length; i += 97) {
        var sum = 0.0;
        for (var j = i - 49; j <= i; j++) {
          sum += values[j];
        }
        expect(result[i], closeTo(sum / 50, 1e-7), reason: 'index $i');
      }
    });

    test('starting after the end of the previous results fills the gap', () {
      final values = [for (var i = 0; i < 40; i++) 100.0 + i % 7];
      final live = EmaCalculator(5)..update(values.sublist(0, 10));
      live.update(values, from: 30);
      expectSeries(live.values, ema(values, 5), tolerance: 0);
    });
  });

  group('Prices of candles', () {
    final candle =
        Candle(time: DateTime(2026), open: 1, high: 4, low: 0, close: 3);

    test('each price source', () {
      expect(PriceSource.open.of(candle), 1);
      expect(PriceSource.high.of(candle), 4);
      expect(PriceSource.low.of(candle), 0);
      expect(PriceSource.close.of(candle), 3);
      expect(PriceSource.hl2.of(candle), 2);
      expect(PriceSource.hlc3.of(candle), 7 / 3);
      expect(PriceSource.ohlc4.of(candle), 2);
    });

    test('lists of prices read the candles without copying', () {
      final candles = [candle, candle.copyWith(close: 2)];
      expect(candles.closes, [3, 2]);
      expect(candles.prices(PriceSource.hl2), [2, 2]);
      expect(() => candles.closes[0] = 5, throwsUnsupportedError);
      expect(() => candles.closes.add(5), throwsUnsupportedError);
      expect(sma(candles.closes, 2), [null, 2.5]);
    });
  });

  test('10,000 values with live updates stay fast', () {
    final random = Random(1);
    var price = 100.0;
    final values = [
      for (var i = 0; i < 10000; i++) price += random.nextDouble() - 0.5,
    ];
    final calculators = <IndicatorCalculator>[
      SmaCalculator(200),
      EmaCalculator(50),
      BollingerBandsCalculator(),
      RsiCalculator(),
      MacdCalculator(),
    ];
    final watch = Stopwatch()..start();
    for (final calculator in calculators) {
      calculator.update(values);
    }
    for (var i = 0; i < 1000; i++) {
      values[values.length - 1] += 0.01;
      for (final calculator in calculators) {
        calculator.update(values, from: values.length - 1);
      }
    }
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
