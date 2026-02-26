# Market Data Patterns

Domain-specific patterns for market data ingestion, tick processing, OHLCV normalization, corporate actions adjustment, and time series storage.

## Core Patterns

### Pattern: Split-Adjusted Price Series

```python
import pandas as pd
from decimal import Decimal

def build_adjusted_series(
    raw_prices: pd.DataFrame,  # columns: date, open, high, low, close, volume
    corporate_actions: pd.DataFrame  # columns: ex_date, type, factor
) -> pd.DataFrame:
    """
    Apply corporate action adjustments to build a continuous price series.
    Adjustments are applied backward: new action affects all prior prices.

    Types:
    - SPLIT: factor = split_ratio (e.g., 4.0 for 4:1 split). Divide old prices by factor.
    - DIVIDEND: factor = (1 - dividend/prev_close). Multiply old prices by factor.
    """
    prices = raw_prices.copy().sort_values('date')
    prices = prices.set_index('date')

    # Cumulative factor starts at 1.0; actions are applied in reverse date order
    cumulative_factor = 1.0

    for _, action in corporate_actions.sort_values('ex_date', ascending=False).iterrows():
        ex_date = action['ex_date']
        if action['type'] == 'SPLIT':
            cumulative_factor /= action['factor']  # Divide prices, multiply volume
        elif action['type'] == 'DIVIDEND':
            cumulative_factor *= action['factor']

        # Apply to all rows BEFORE the ex-date
        mask = prices.index < ex_date
        prices.loc[mask, ['open', 'high', 'low', 'close']] *= action['factor']
        if action['type'] == 'SPLIT':
            prices.loc[mask, 'volume'] *= action['factor']  # Volume adjusts inversely

    return prices
```

### Pattern: Time Series Gap Detection

```python
def find_gaps(
    prices: pd.DataFrame,
    symbol: str,
    exchange_calendar: str = 'NYSE'
) -> list[tuple[date, date]]:
    """
    Find gaps in OHLCV data relative to expected trading days.
    Uses exchange calendar to exclude weekends and holidays.
    """
    import pandas_market_calendars as mcal

    cal = mcal.get_calendar(exchange_calendar)
    schedule = cal.schedule(
        start_date=prices.index.min(),
        end_date=prices.index.max()
    )
    expected_trading_days = set(schedule.index.date)
    actual_days = set(prices.index.date)

    missing_days = sorted(expected_trading_days - actual_days)

    # Group consecutive missing days into gap ranges
    gaps = []
    if missing_days:
        gap_start = missing_days[0]
        gap_end = missing_days[0]
        for d in missing_days[1:]:
            if (d - gap_end).days <= 3:  # Allow weekends within a gap
                gap_end = d
            else:
                gaps.append((gap_start, gap_end))
                gap_start = d
                gap_end = d
        gaps.append((gap_start, gap_end))

    return gaps
```

### Pattern: Outlier Detection for Price Validation

```python
def detect_price_outliers(
    prices: pd.DataFrame,
    max_daily_move_pct: float = 0.50  # Flag if price moves >50% in one day
) -> pd.DataFrame:
    """
    Flag potentially erroneous prices.
    Legitimate 50%+ moves are rare; common in data quality issues.
    """
    returns = prices['close'].pct_change().abs()

    # OHLC consistency checks
    ohlc_violations = pd.DataFrame({
        'high_lt_low': prices['high'] < prices['low'],
        'high_lt_open': prices['high'] < prices['open'],
        'high_lt_close': prices['high'] < prices['close'],
        'low_gt_open': prices['low'] > prices['open'],
        'low_gt_close': prices['low'] > prices['close'],
        'price_negative': prices['close'] <= 0,
        'large_return': returns > max_daily_move_pct,
    })

    violations = ohlc_violations[ohlc_violations.any(axis=1)]
    return violations
```

### Pattern: Tick Aggregation to OHLCV Bars

```python
import pandas as pd
from decimal import Decimal

def ticks_to_ohlcv(
    ticks: pd.DataFrame,  # columns: timestamp (UTC), price, volume
    frequency: str = '1min'
) -> pd.DataFrame:
    """
    Aggregate raw ticks to OHLCV bars.
    timestamp must be UTC timezone-aware.
    """
    ticks = ticks.set_index('timestamp').sort_index()

    # Resample to desired frequency
    bars = ticks['price'].resample(frequency).ohlc()
    bars['volume'] = ticks['volume'].resample(frequency).sum()
    bars['tick_count'] = ticks['price'].resample(frequency).count()
    bars['vwap'] = (
        (ticks['price'] * ticks['volume']).resample(frequency).sum() /
        ticks['volume'].resample(frequency).sum()
    )

    # Drop empty bars (no trading activity in that period)
    bars = bars.dropna(subset=['close'])

    return bars
```

## Anti-Patterns

### Anti-Pattern: Double-Counting Dividends

```python
# WRONG: Loading corporate actions twice (e.g., from two sources) without deduplication
corp_actions = load_from_refinitiv(symbol) + load_from_bloomberg(symbol)
apply_adjustments(prices, corp_actions)  # Dividends applied twice!

# RIGHT: Deduplicate by ex_date and action_type before applying
import pandas as pd
corp_actions = pd.concat([
    load_from_refinitiv(symbol),
    load_from_bloomberg(symbol)
]).drop_duplicates(subset=['ex_date', 'action_type'])

apply_adjustments(prices, corp_actions)
```

### Anti-Pattern: Mixing Adjusted and Unadjusted Prices

Never mix adjusted and unadjusted prices in the same calculation. The two series must be stored separately and clearly labeled. Using unadjusted prices for return calculations produces incorrect results. Using adjusted prices for current portfolio valuation produces incorrect NAV.

### Anti-Pattern: No Exchange Calendar for Gap Detection

```python
# WRONG: Flag all missing days including holidays and weekends
all_days = pd.date_range(start='2024-01-01', end='2024-12-31', freq='D')
missing = all_days[~all_days.isin(prices.index)]  # Flags Christmas, weekends = noise

# RIGHT: Use exchange calendar to know expected trading days
import pandas_market_calendars as mcal
nyse = mcal.get_calendar('NYSE')
trading_days = nyse.valid_days(start_date='2024-01-01', end_date='2024-12-31')
missing = trading_days[~trading_days.isin(prices.index)]  # Only real gaps
```

### Anti-Pattern: Storing Timestamps Without Timezone

```python
# WRONG: Naive timestamp - which timezone? Exchange local? UTC?
prices['timestamp'] = pd.to_datetime('2024-11-01 09:30:00')

# RIGHT: Always UTC, always timezone-aware
prices['timestamp'] = pd.to_datetime('2024-11-01 14:30:00', utc=True)
# NYSE opens at 9:30 ET = 14:30 UTC
```

## References

- **Bloomberg BLPAPI**: https://www.bloomberg.com/professional/support/api-library/
- **Refinitiv Data Platform**: https://developers.refinitiv.com/
- **kdb+ Documentation**: https://code.kx.com/q/
- **Arctic (Man Group)**: https://github.com/man-group/arctic
- **pandas-market-calendars**: https://github.com/rsheftel/pandas_market_calendars
- **CUSIP Global Services**: https://www.cusip.com/
- **ISIN Specification**: ISO 6166
- **FIX Protocol**: https://www.fixtrading.org/standards/
