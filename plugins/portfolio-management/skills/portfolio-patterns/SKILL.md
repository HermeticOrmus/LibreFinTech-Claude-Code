# Portfolio Management Patterns

Domain-specific patterns for portfolio construction, rebalancing, performance attribution, and GIPS-compliant reporting.

## Core Patterns

### Pattern: Mean-Variance Optimization with Transaction Cost Constraint

```python
import numpy as np
from scipy.optimize import minimize

def mean_variance_optimize(
    expected_returns: np.ndarray,  # annualized expected return per asset
    cov_matrix: np.ndarray,        # annualized covariance matrix
    current_weights: np.ndarray,
    target_risk: float,            # target portfolio volatility
    transaction_cost: float = 0.001,  # 10bps per unit of turnover
) -> np.ndarray:
    n = len(expected_returns)

    def objective(w):
        # Maximize return - transaction costs
        turnover = np.sum(np.abs(w - current_weights))
        return -(w @ expected_returns - transaction_cost * turnover)

    def portfolio_vol(w):
        return np.sqrt(w @ cov_matrix @ w)

    constraints = [
        {'type': 'eq', 'fun': lambda w: np.sum(w) - 1},         # fully invested
        {'type': 'ineq', 'fun': lambda w: target_risk - portfolio_vol(w)},  # vol constraint
    ]
    bounds = [(0, 0.40)] * n  # max 40% per position (concentration limit)

    result = minimize(
        objective,
        x0=current_weights,
        method='SLSQP',
        bounds=bounds,
        constraints=constraints,
    )
    return result.x
```

### Pattern: Threshold-Based Drift Monitoring

```python
from decimal import Decimal

def check_portfolio_drift(
    current_weights: dict[str, Decimal],
    target_weights: dict[str, Decimal],
    threshold: Decimal = Decimal('0.05'),
) -> list[dict]:
    """
    Returns list of assets breaching drift threshold.
    Drift = |current_weight - target_weight|
    Threshold rebalancing is more tax-efficient than calendar rebalancing:
    trades only execute when necessary.
    """
    breaches = []
    for symbol, target in target_weights.items():
        current = current_weights.get(symbol, Decimal('0'))
        drift = abs(current - target)
        if drift > threshold:
            breaches.append({
                'symbol': symbol,
                'current_weight': current,
                'target_weight': target,
                'drift': drift,
                'direction': 'overweight' if current > target else 'underweight',
            })
    # Sort by largest drift first - prioritize most urgent rebalances
    return sorted(breaches, key=lambda x: x['drift'], reverse=True)
```

### Pattern: Tax-Loss Harvesting with Wash Sale Avoidance

```python
from datetime import date, timedelta
from decimal import Decimal

def identify_tax_loss_candidates(
    tax_lots: list[dict],  # {symbol, quantity, cost_basis, purchase_date, current_price}
    harvest_threshold: Decimal = Decimal('-500'),  # minimum loss to harvest
    wash_sale_window: int = 30,                    # IRS 30-day rule
    substantially_identical: dict[str, str] = {},  # {symbol: replacement_symbol}
) -> list[dict]:
    """
    Identify lots suitable for tax-loss harvesting.
    Wash sale rule (IRC Section 1091): cannot claim loss if you purchase
    substantially identical security within 30 days before or after sale.
    """
    today = date.today()
    candidates = []

    for lot in tax_lots:
        unrealized = (Decimal(str(lot['current_price'])) - lot['cost_basis']) * lot['quantity']
        if unrealized >= harvest_threshold:
            continue  # Not enough loss

        # Check wash sale window - must not have purchased same symbol recently
        days_held = (today - lot['purchase_date']).days
        if days_held < wash_sale_window:
            continue  # Purchased within 30 days - wash sale risk on repurchase

        replacement = substantially_identical.get(lot['symbol'])
        if not replacement:
            continue  # No replacement identified (can't immediately repurchase same symbol)

        candidates.append({
            'symbol': lot['symbol'],
            'replacement': replacement,
            'loss': unrealized,
            'lot_date': lot['purchase_date'],
            'holding_period': 'long' if days_held > 365 else 'short',
            'quantity': lot['quantity'],
        })

    return sorted(candidates, key=lambda x: x['loss'])  # Largest losses first
```

### Pattern: HIFO Lot Selection for Selling

```python
def select_lots_to_sell(
    tax_lots: list[dict],       # {symbol, quantity, cost_basis, purchase_date}
    target_quantity: Decimal,
    method: str = 'HIFO',       # HIFO | FIFO | SPECIFIC_ID
) -> list[dict]:
    """
    HIFO (Highest In, First Out): sell highest cost basis lots first.
    Minimizes realized gains. Default for tax-aware selling.
    FIFO is the IRS default if specific ID not declared at time of sale.
    """
    lots = sorted(tax_lots, key=lambda x: {
        'HIFO': -x['cost_basis'],
        'FIFO': x['purchase_date'],
        'SPECIFIC_ID': -x['cost_basis'],  # Handled separately
    }[method])

    selected = []
    remaining = target_quantity

    for lot in lots:
        if remaining <= 0:
            break
        sell_qty = min(lot['quantity'], remaining)
        selected.append({**lot, 'sell_quantity': sell_qty})
        remaining -= sell_qty

    return selected
```

### Pattern: Cash Drag Management

```python
from decimal import Decimal

def generate_cash_deployment_trades(
    cash_balance: Decimal,
    target_weights: dict[str, Decimal],
    current_holdings: dict[str, Decimal],  # {symbol: market_value}
    total_portfolio_value: Decimal,
    min_trade_value: Decimal = Decimal('500'),
) -> list[dict]:
    """
    Cash drag: uninvested cash earns less than the portfolio target return.
    For a 10% target return, $10k in cash costs ~$1k/year in opportunity cost.
    Deploy cash proportionally to current underweights to reduce drift.
    """
    trades = []
    new_total = total_portfolio_value  # Cash already included in total

    for symbol, target_weight in target_weights.items():
        target_value = new_total * target_weight
        current_value = current_holdings.get(symbol, Decimal('0'))
        gap = target_value - current_value

        # Only buy into underweights; cap purchase at available cash
        if gap > min_trade_value:
            buy_value = min(gap, cash_balance)
            if buy_value >= min_trade_value:
                trades.append({'symbol': symbol, 'action': 'BUY', 'value': buy_value})
                cash_balance -= buy_value

        if cash_balance < min_trade_value:
            break

    return trades
```

## Anti-Patterns

### Anti-Pattern: Ignoring Transaction Costs in Rebalancing

```python
# WRONG: Rebalance to exact target weights every day
def naive_rebalance(current_weights, target_weights, prices):
    for symbol, target in target_weights.items():
        drift = abs(current_weights[symbol] - target)
        if drift > 0:  # Any drift triggers trade
            execute_trade(symbol, target - current_weights[symbol])
# Result: Daily turnover of 5-15%, transaction costs consume all alpha

# RIGHT: Only trade when drift exceeds threshold AND TCA justifies it
THRESHOLD = 0.05  # 5% drift
def threshold_rebalance(current_weights, target_weights):
    for symbol, target in target_weights.items():
        drift = abs(current_weights[symbol] - target)
        if drift > THRESHOLD:
            execute_trade(symbol, target - current_weights[symbol])
```

### Anti-Pattern: Confusing TWR and MWR

```
TWR (Time-Weighted Return):
- Eliminates effect of cash flow timing
- Use for: comparing manager performance, GIPS composite reporting
- Never influenced by when clients deposit/withdraw money

MWR / IRR (Money-Weighted Return):
- Reflects actual investor wealth impact
- Use for: reporting actual client account performance
- Hurt by bad timing (client deposited peak, withdrew trough)

WRONG: Using MWR to compare manager performance
- Manager who happened to receive deposits before a rally looks great
- This reflects client timing, not manager skill

RIGHT: TWR for benchmarking managers, MWR for client statements
```

### Anti-Pattern: Backtesting with Look-Ahead Bias

```python
# WRONG: Using full history to calculate covariance matrix
cov = returns.cov()  # Uses future data
weights = optimize(expected_returns, cov)
backtest_returns = (returns * weights).sum()
# This overstates backtest performance by 100-300bps/year typically

# RIGHT: Rolling/expanding window - only use data available at each point
def walk_forward_backtest(returns: pd.DataFrame, window: int = 252):
    portfolio_returns = []
    for i in range(window, len(returns)):
        hist = returns.iloc[i-window:i]    # Only past data
        cov = hist.cov()
        mu = hist.mean()
        w = optimize(mu, cov)
        next_return = (returns.iloc[i] * w).sum()  # Apply to future period
        portfolio_returns.append(next_return)
    return pd.Series(portfolio_returns)
```

### Anti-Pattern: GIPS Non-Compliance in Composite Construction

```
WRONG: Cherry-pick accounts for composite
- Include only top-performing accounts in "Growth Composite"
- Exclude accounts with client-imposed restrictions that hurt returns
- Start composite on a date when performance was strong

RIGHT (GIPS 2020 requirements):
- Include ALL discretionary, fee-paying accounts that meet composite definition
- Define composite before adding accounts
- Composite definition must be documented in IPS
- Minimum 5-year (or since inception) history required
- Cannot retroactively change composite definition
```

## References

- **GIPS 2020 Standards**: https://www.cfainstitute.org/en/ethics-standards/gips
- **Markowitz (1952)**: "Portfolio Selection" - Journal of Finance
- **Brinson, Hood, Beebower (1986)**: "Determinants of Portfolio Performance" - FAJ
- **IRS Publication 550**: Wash sale rules (IRC Section 1091)
- **HIFO/FIFO/Specific ID**: IRS Publication 550, Chapter 4 (basis of investment)
- **Active Share**: Cremers & Petajisto (2009) - "How Active Is Your Fund Manager?"
- **Risk Parity**: Qian (2005) - "Risk Parity Portfolios"
- **QuantLib**: https://www.quantlib.org/ (C++ library for quantitative finance)
- **PyPortfolioOpt**: https://github.com/robertmartin8/PyPortfolioOpt
