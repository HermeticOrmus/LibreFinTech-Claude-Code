# /portfolio

Portfolio analysis, rebalancing, performance attribution, and GIPS-compliant reporting.

## Trigger

`/portfolio <action> [options]`

## Actions

- `analyze` - Analyze current portfolio composition, weights, drift, and risk metrics
- `rebalance` - Generate rebalancing trades to restore target allocation
- `attribute` - Run performance attribution (Brinson-Hood-Beebower)
- `report` - Generate performance report (TWR, GIPS-compliant)

## Options

- `--portfolio-id <id>` - Portfolio to operate on
- `--benchmark <id|ticker>` - Benchmark for comparison (e.g., SPY, MSCI_WORLD)
- `--from <ISO8601>` - Performance period start
- `--to <ISO8601>` - Performance period end
- `--tax-aware` - Consider tax lots in rebalancing optimization
- `--threshold <float>` - Drift threshold for rebalancing trigger (e.g., 0.05 for 5%)

## Process

### analyze

```python
import pandas as pd
import numpy as np

def analyze_portfolio(holdings: pd.DataFrame, prices: pd.DataFrame) -> dict:
    """
    holdings: columns = [symbol, quantity, cost_basis, purchase_date]
    prices:   columns = [symbol, price, date]
    """
    current_prices = prices.groupby('symbol')['price'].last()

    holdings['market_value'] = holdings['quantity'] * holdings.apply(
        lambda r: current_prices.get(r['symbol'], 0), axis=1
    )
    total_value = holdings['market_value'].sum()
    holdings['weight'] = holdings['market_value'] / total_value
    holdings['unrealized_gain'] = (
        holdings['market_value'] -
        holdings['quantity'] * holdings['cost_basis']
    )

    # Risk metrics
    returns = prices.pivot(index='date', columns='symbol', values='price').pct_change()
    portfolio_returns = (returns * holdings.set_index('symbol')['weight']).sum(axis=1)

    return {
        'total_value': total_value,
        'holdings': holdings.to_dict('records'),
        'portfolio_return_daily_mean': portfolio_returns.mean(),
        'portfolio_volatility_annual': portfolio_returns.std() * np.sqrt(252),
        'sharpe_ratio': (portfolio_returns.mean() * 252) / (portfolio_returns.std() * np.sqrt(252)),
        'max_drawdown': calculate_max_drawdown(portfolio_returns),
    }

def calculate_max_drawdown(returns: pd.Series) -> float:
    cumulative = (1 + returns).cumprod()
    rolling_max = cumulative.expanding().max()
    drawdowns = (cumulative - rolling_max) / rolling_max
    return drawdowns.min()
```

### rebalance

Tax-aware rebalancing with drift threshold:

```python
def generate_rebalancing_trades(
    current_holdings: pd.DataFrame,  # symbol, quantity, market_value, weight, tax_lots
    target_weights: dict,             # {symbol: target_weight}
    total_portfolio_value: float,
    drift_threshold: float = 0.05,
    tax_aware: bool = True
) -> pd.DataFrame:
    trades = []

    for symbol, target_weight in target_weights.items():
        current = current_holdings[current_holdings['symbol'] == symbol]
        current_weight = current['weight'].sum() if len(current) > 0 else 0

        drift = abs(current_weight - target_weight)
        if drift <= drift_threshold:
            continue  # Within tolerance - no trade needed

        target_value = total_portfolio_value * target_weight
        current_value = current['market_value'].sum() if len(current) > 0 else 0
        trade_value = target_value - current_value

        if tax_aware and trade_value < 0:  # Selling
            # Prefer selling loss lots first (maximize tax loss harvesting)
            lots = current.explode('tax_lots').sort_values('unrealized_gain')
            # Sell lowest-gain lots first
            trade_lots = optimize_lot_selection(lots, abs(trade_value))
        else:
            trade_lots = None

        trades.append({
            'symbol': symbol,
            'action': 'BUY' if trade_value > 0 else 'SELL',
            'trade_value': abs(trade_value),
            'current_weight': current_weight,
            'target_weight': target_weight,
            'drift': drift,
            'tax_lots': trade_lots,
        })

    return pd.DataFrame(trades).sort_values('action')  # Sells first (fund buys)
```

### attribute

Brinson-Hood-Beebower performance attribution:

```python
def brinson_attribution(
    portfolio_weights: pd.Series,   # index: sector, values: weight
    portfolio_returns: pd.Series,   # index: sector, values: return
    benchmark_weights: pd.Series,
    benchmark_returns: pd.Series,
) -> pd.DataFrame:
    """Returns attribution decomposed by sector."""
    total_benchmark_return = (benchmark_weights * benchmark_returns).sum()

    attribution = pd.DataFrame({
        'sector': portfolio_weights.index,
        'port_weight': portfolio_weights.values,
        'port_return': portfolio_returns.values,
        'bench_weight': benchmark_weights.values,
        'bench_return': benchmark_returns.values,
    })

    # Allocation effect: did over/underweighting sectors add value?
    # = (port_weight - bench_weight) * (bench_sector_return - total_bench_return)
    attribution['allocation_effect'] = (
        (attribution['port_weight'] - attribution['bench_weight']) *
        (attribution['bench_return'] - total_benchmark_return)
    )

    # Selection effect: did better stock picks within sectors add value?
    # = bench_weight * (port_sector_return - bench_sector_return)
    attribution['selection_effect'] = (
        attribution['bench_weight'] *
        (attribution['port_return'] - attribution['bench_return'])
    )

    # Interaction effect
    attribution['interaction_effect'] = (
        (attribution['port_weight'] - attribution['bench_weight']) *
        (attribution['port_return'] - attribution['bench_return'])
    )

    attribution['total_active_return'] = (
        attribution['allocation_effect'] +
        attribution['selection_effect'] +
        attribution['interaction_effect']
    )

    return attribution
```

### report (GIPS-Compliant TWR)

```python
def calculate_twr(valuations: list[tuple[date, float, float]]) -> float:
    """
    GIPS-compliant Time-Weighted Return.
    valuations: list of (date, beginning_value, cash_flow)
    Links sub-period returns across each cash flow date.
    """
    sub_period_returns = []

    for i in range(1, len(valuations)):
        prev_date, prev_value, _ = valuations[i-1]
        curr_date, curr_value, cash_flow = valuations[i]

        # Modified Dietz for each sub-period
        # R = (EMV - BMV - CF) / (BMV + (CF * W))
        # W = weight factor based on when in period cash flow occurred
        days_in_period = (curr_date - prev_date).days
        days_remaining = (curr_date - prev_date).days  # Simplified: CF at end
        weight = days_remaining / days_in_period if days_in_period > 0 else 0.5

        sub_return = (curr_value - prev_value - cash_flow) / (prev_value + cash_flow * weight)
        sub_period_returns.append(1 + sub_return)

    # Link sub-period returns (geometric linking)
    twr = 1.0
    for r in sub_period_returns:
        twr *= r
    return twr - 1
```

## Examples

```bash
# Analyze portfolio drift and risk metrics
/portfolio analyze --portfolio-id PORT-001 --benchmark SPY

# Generate tax-aware rebalancing trades with 5% drift threshold
/portfolio rebalance --portfolio-id PORT-001 --threshold 0.05 --tax-aware

# Run Q3 performance attribution vs S&P 500
/portfolio attribute --portfolio-id PORT-001 --benchmark SPY --from 2024-07-01 --to 2024-09-30

# Generate annual GIPS-compliant performance report
/portfolio report --portfolio-id PORT-001 --from 2024-01-01 --to 2024-12-31
```
