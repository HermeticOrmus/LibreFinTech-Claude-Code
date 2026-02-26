# /market-data

Subscribe to market data feeds, query historical prices, normalize tick data, and backfill corporate action adjustments.

## Trigger

`/market-data <action> [options]`

## Actions

- `subscribe` - Subscribe to real-time market data for instruments
- `query` - Query historical OHLCV data from the market data store
- `normalize` - Normalize raw feed data to canonical format
- `backfill` - Backfill missing data or re-apply corporate action adjustments

## Options

- `--symbols <comma-separated>` - Instrument symbols (e.g., AAPL,MSFT,SPY)
- `--from <ISO8601>` - Historical data start
- `--to <ISO8601>` - Historical data end
- `--frequency <tick|1s|1m|5m|1h|1d>` - Bar frequency
- `--provider <bloomberg|refinitiv|ice|exchange>` - Data source
- `--adjusted` - Return dividend/split adjusted prices

## Process

### subscribe

Bloomberg B-PIPE subscription for real-time data:

```python
import blpapi
from datetime import datetime

class MarketDataSubscriber:
    def __init__(self, host: str, port: int):
        self.session_options = blpapi.SessionOptions()
        self.session_options.setServerHost(host)
        self.session_options.setServerPort(port)
        self.session = blpapi.Session(self.session_options, self._event_handler)

    def subscribe(self, securities: list[str], fields: list[str] = None):
        if fields is None:
            fields = ['LAST_PRICE', 'BID', 'ASK', 'VOLUME', 'OPEN', 'HIGH', 'LOW']

        subscriptions = blpapi.SubscriptionList()
        for security in securities:
            subscriptions.add(
                topic=f'//blp/mktdata/{security}',
                fields=fields,
                options=['interval=0'],  # Real-time
                correlationId=blpapi.CorrelationId(security)
            )
        self.session.subscribe(subscriptions)

    def _event_handler(self, event, session):
        if event.eventType() == blpapi.Event.SUBSCRIPTION_DATA:
            for msg in event:
                ticker = str(msg.correlationIds()[0].value())
                if msg.hasElement('LAST_PRICE'):
                    price = msg.getElementAsFloat('LAST_PRICE')
                    self._publish_tick(ticker, price, datetime.utcnow())
```

WebSocket subscription (generic exchange or crypto):

```typescript
import WebSocket from 'ws';

interface Tick {
  symbol: string;
  timestamp: Date;  // Always UTC
  bid: Decimal;
  ask: Decimal;
  lastPrice: Decimal;
  volume: Decimal;
  exchange: string;
}

class ExchangeWebSocket {
  private ws: WebSocket;
  private reconnectDelay = 1000;

  connect(url: string, symbols: string[]): void {
    this.ws = new WebSocket(url);

    this.ws.on('open', () => {
      this.reconnectDelay = 1000;  // Reset on successful connect
      this.subscribe(symbols);
    });

    this.ws.on('message', (data: string) => {
      const tick = this.parseTick(JSON.parse(data));
      if (tick) this.onTick(tick);
    });

    this.ws.on('close', () => {
      // Exponential backoff reconnection
      setTimeout(() => this.connect(url, symbols), this.reconnectDelay);
      this.reconnectDelay = Math.min(this.reconnectDelay * 2, 30000);
    });
  }
}
```

### query

```python
import pandas as pd
from sqlalchemy import create_engine, text

def get_ohlcv(
    symbols: list[str],
    start: str,
    end: str,
    frequency: str = '1d',
    adjusted: bool = True
) -> pd.DataFrame:
    engine = create_engine(DATABASE_URL)

    query = text("""
        SELECT
            symbol,
            bar_time AT TIME ZONE 'UTC' AS timestamp,
            CASE WHEN :adjusted THEN open_adj ELSE open END AS open,
            CASE WHEN :adjusted THEN high_adj ELSE high END AS high,
            CASE WHEN :adjusted THEN low_adj  ELSE low  END AS low,
            CASE WHEN :adjusted THEN close_adj ELSE close END AS close,
            CASE WHEN :adjusted THEN volume / adj_factor ELSE volume END AS volume
        FROM market_data_bars
        WHERE symbol = ANY(:symbols)
          AND bar_time BETWEEN :start AND :end
          AND frequency = :frequency
        ORDER BY symbol, bar_time
    """)

    df = pd.read_sql(query, engine, params={
        'symbols': symbols,
        'start': start,
        'end': end,
        'frequency': frequency,
        'adjusted': adjusted,
    })

    # Validate: no negative prices, OHLC relationship valid
    assert (df['low'] <= df['close']).all(), "Low > Close detected"
    assert (df['high'] >= df['close']).all(), "High < Close detected"

    return df.pivot_table(index='timestamp', columns='symbol', values='close')
```

### normalize

Canonical tick normalization:

```python
def normalize_tick(raw_tick: dict, source: str) -> NormalizedTick:
    """
    Normalize ticks from different vendors into canonical format.
    All prices in Decimal, all timestamps in UTC, all symbols in normalized form.
    """
    normalizers = {
        'bloomberg': normalize_bloomberg_tick,
        'refinitiv': normalize_refinitiv_tick,
        'binance': normalize_binance_tick,
        'coinbase': normalize_coinbase_tick,
    }

    return normalizers[source](raw_tick)

def normalize_bloomberg_tick(raw: dict) -> NormalizedTick:
    return NormalizedTick(
        symbol=raw['SECURITY'],           # e.g., 'AAPL US Equity'
        exchange='US',
        timestamp=datetime.utcnow(),      # Bloomberg doesn't always include timestamp
        bid=Decimal(str(raw.get('BID', 0))),
        ask=Decimal(str(raw.get('ASK', 0))),
        last=Decimal(str(raw.get('LAST_PRICE', 0))),
        volume=Decimal(str(raw.get('VOLUME', 0))),
        currency='USD',
        source='bloomberg',
    )
```

### backfill

```python
# Re-apply corporate action adjustments after new actions are loaded
def recalculate_adjusted_prices(symbol: str, as_of_date: date) -> None:
    """
    When a new corporate action is loaded (e.g., dividend just declared),
    recalculate all adjusted prices from the oldest affected date.
    """
    actions = db.get_corporate_actions(symbol, before=as_of_date)

    # Start from oldest raw price
    raw_prices = db.get_raw_ohlcv(symbol)
    adj_factor = Decimal('1.0')  # Cumulative adjustment factor

    # Apply actions in reverse chronological order (oldest to newest)
    for action in sorted(actions, key=lambda a: a.ex_date, reverse=True):
        if action.type == 'DIVIDEND':
            # Proportional adjustment: all prices before ex-date multiplied by factor
            factor = Decimal(1) - (action.dividend_amount / action.price_day_before)
            adj_factor *= factor
        elif action.type == 'SPLIT':
            adj_factor *= Decimal(action.split_ratio)

        raw_prices.loc[:action.ex_date - timedelta(days=1)] *= adj_factor

    db.save_adjusted_prices(symbol, raw_prices)
```

## Examples

```bash
# Subscribe to real-time quotes for S&P 500 ETF via Bloomberg
/market-data subscribe --symbols SPY,QQQ,IWM --provider bloomberg

# Get 5 years of daily OHLCV for Apple, adjusted for corporate actions
/market-data query --symbols AAPL --from 2020-01-01 --to 2024-12-31 --frequency 1d --adjusted

# Normalize a raw feed file from Refinitiv
/market-data normalize --provider refinitiv --path ./raw-ticks/refinitiv-2024-11-01.csv

# Backfill Apple after loading new dividend data
/market-data backfill --symbols AAPL --from 2020-01-01
```
