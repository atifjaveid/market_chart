"""Generates reference.json: indicator values computed with TA-Lib, used by
test/indicators_test.dart to check the Dart indicator maths.

Requires Python with the TA-Lib package (pip install TA-Lib). Run from the
package root:

    python test/fixtures/generate_reference.py

Data: daily BTC/USDT closes from Binance's public market data API.
"""

import json
import math
import urllib.request

import numpy as np
import talib

START_MS = 1735689600000  # 2025-01-01 00:00 UTC
URL = (
    "https://data-api.binance.vision/api/v3/klines"
    f"?symbol=BTCUSDT&interval=1d&startTime={START_MS}&limit=150"
)

def clean(values):
    """NaN becomes None (null in JSON)."""
    return [None if math.isnan(v) else float(v) for v in values]


def main():
    with urllib.request.urlopen(URL, timeout=30) as response:
        klines = json.load(response)
    close = np.array([float(k[4]) for k in klines], dtype=float)

    upper, middle, lower = talib.BBANDS(
        close, timeperiod=20, nbdevup=2, nbdevdn=2, matype=0
    )

    # MACD from two independent EMAs (each seeded with a simple average),
    # and the signal line as a 9-period EMA of the MACD line.
    macd_line = talib.EMA(close, 12) - talib.EMA(close, 26)
    signal = talib.EMA(macd_line, 9)
    histogram = macd_line - signal

    reference = {
        "about": (
            "Daily BTC/USDT closes from Binance, 2025-01-01 onwards. "
            f"Indicator values from TA-Lib {talib.__version__}."
        ),
        "close": clean(close),
        "sma20": clean(talib.SMA(close, 20)),
        "ema20": clean(talib.EMA(close, 20)),
        "ema9": clean(talib.EMA(close, 9)),
        "bollinger20": {
            "upper": clean(upper),
            "middle": clean(middle),
            "lower": clean(lower),
        },
        "rsi14": clean(talib.RSI(close, 14)),
        "macd12_26_9": {
            "macd": clean(macd_line),
            "signal": clean(signal),
            "histogram": clean(histogram),
        },
    }

    with open("test/fixtures/reference.json", "w", encoding="utf-8") as f:
        json.dump(reference, f, indent=1)
    print(f"Wrote {len(close)} closes.")


if __name__ == "__main__":
    main()
