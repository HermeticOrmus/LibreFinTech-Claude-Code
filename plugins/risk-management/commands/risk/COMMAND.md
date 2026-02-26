# /risk

Financial risk management: VaR calculation, credit risk metrics, stress testing, and limit monitoring.

## Trigger

`/risk <action> [options]`

## Actions

- `var` - Calculate Value at Risk for a portfolio (historical, parametric, or Monte Carlo)
- `credit` - Compute expected loss (PD/LGD/EAD) for a credit portfolio
- `stress` - Run stress scenario or reverse stress test
- `limits` - Check current risk positions against limits framework

## Options

- `--portfolio-id <id>` - Portfolio to analyze
- `--method <historical|parametric|montecarlo>` - VaR calculation method
- `--confidence <float>` - Confidence level (e.g., 0.99 for 99%)
- `--horizon <days>` - Risk horizon in days (default: 10 for VaR)
- `--scenario <id|adverse|severely-adverse>` - Stress scenario to apply
- `--from <ISO8601>` - Historical window start (for historical simulation)

## Process

### var

Historical simulation VaR:

```python
import numpy as np
import pandas as pd
from decimal import Decimal

def historical_var(
    positions: pd.DataFrame,        # columns: [symbol, quantity, price]
    returns_history: pd.DataFrame,  # columns: [date, symbol, return]
    confidence: float = 0.99,
    horizon_days: int = 10,
) -> dict:
    """
    Historical simulation VaR:
    1. Take portfolio weights from current positions
    2. Apply each historical return scenario to current portfolio
    3. Sort resulting P&L distribution
    4. VaR = loss at (1-confidence) percentile

    Advantage: no distributional assumption; captures historical fat tails.
    Disadvantage: limited by history length; slow to update to new volatility regime.
    """
    total_value = (positions['quantity'] * positions['price']).sum()
    positions['weight'] = positions['quantity'] * positions['price'] / total_value

    # Pivot returns into wide format: index=date, columns=symbol
    ret_wide = returns_history.pivot(index='date', columns='symbol', values='return')

    # For each historical day, what would portfolio have returned?
    weights = positions.set_index('symbol')['weight']
    portfolio_returns = ret_wide[weights.index] @ weights  # Matrix multiply

    # Scale 1-day returns to horizon using square-root of time rule
    # (Assumes i.i.d. daily returns - a simplification)
    scaled_returns = portfolio_returns * np.sqrt(horizon_days)

    # VaR = loss at (1-confidence) percentile
    var_return = np.percentile(scaled_returns, (1 - confidence) * 100)
    expected_shortfall = scaled_returns[scaled_returns <= var_return].mean()

    return {
        'var_1pct_10day': abs(var_return) * total_value,
        'expected_shortfall': abs(expected_shortfall) * total_value,
        'confidence': confidence,
        'horizon_days': horizon_days,
        'total_portfolio_value': total_value,
        'history_length_days': len(portfolio_returns),
    }
```

Parametric VaR (delta-normal):

```python
def parametric_var(
    positions: pd.DataFrame,
    returns_history: pd.DataFrame,
    confidence: float = 0.99,
    horizon_days: int = 10,
) -> dict:
    """
    Assumes returns are normally distributed.
    Faster than historical simulation; underestimates tail risk.
    Use for initial estimates or where full history not available.
    """
    from scipy.stats import norm

    ret_wide = returns_history.pivot(index='date', columns='symbol', values='return')
    weights = (positions.set_index('symbol')['quantity'] * positions.set_index('symbol')['price'])
    weights = weights / weights.sum()

    # Covariance matrix from returns history
    cov_matrix = ret_wide[weights.index].cov()
    portfolio_variance = weights @ cov_matrix @ weights
    portfolio_vol_daily = np.sqrt(portfolio_variance)

    # Scale to horizon
    portfolio_vol = portfolio_vol_daily * np.sqrt(horizon_days)
    total_value = (positions['quantity'] * positions['price']).sum()

    # 99% VaR = 2.326 * daily sigma * sqrt(horizon) * portfolio value
    z_score = norm.ppf(confidence)
    var = z_score * portfolio_vol * total_value

    return {'var': var, 'portfolio_vol_annualized': portfolio_vol_daily * np.sqrt(252)}
```

### credit

Expected credit loss calculation:

```python
from decimal import Decimal

def calculate_portfolio_ecl(
    loans: list[dict],  # {loan_id, pd, lgd, ead, stage, remaining_term_months}
) -> dict:
    """
    CECL (ASC 326) / IFRS 9 expected credit loss.
    Stage 1: 12-month ECL. Stage 2/3: lifetime ECL.
    EL = PD * LGD * EAD
    """
    stage_totals = {1: Decimal('0'), 2: Decimal('0'), 3: Decimal('0')}
    total_ead = Decimal('0')
    total_ecl = Decimal('0')

    for loan in loans:
        ead = Decimal(str(loan['ead']))
        pd_val = Decimal(str(loan['pd']))
        lgd = Decimal(str(loan['lgd']))
        stage = loan['stage']

        if stage == 1:
            # 12-month PD only
            pd_12m = pd_val  # Assumed to be annual; use 1-year PD
            ecl = pd_12m * lgd * ead
        else:
            # Lifetime ECL: sum expected loss over remaining term
            monthly_pd = Decimal('1') - (Decimal('1') - pd_val) ** Decimal('1/12')
            months = loan['remaining_term_months']
            survival = Decimal('1')
            ecl = Decimal('0')
            for m in range(months):
                ecl += monthly_pd * survival * lgd * ead
                survival *= (Decimal('1') - monthly_pd)

        stage_totals[stage] += ecl
        total_ead += ead
        total_ecl += ecl

    return {
        'total_ead': total_ead,
        'total_ecl': total_ecl,
        'ecl_rate': total_ecl / total_ead if total_ead else Decimal('0'),
        'stage_1_ecl': stage_totals[1],
        'stage_2_ecl': stage_totals[2],
        'stage_3_ecl': stage_totals[3],
    }
```

### stress

Apply adverse scenario to portfolio:

```python
STRESS_SCENARIOS = {
    'adverse': {
        'equity_shock': -0.30,          # -30% equity markets
        'credit_spread_shock': 0.0200,  # +200bps credit spreads
        'fx_shock': 0.15,               # 15% adverse FX move
        'rate_shock': 0.0150,           # +150bps rates (developed)
        'pd_multiplier': 2.5,           # PDs 2.5x baseline
    },
    'severely_adverse': {
        'equity_shock': -0.55,
        'credit_spread_shock': 0.0550,
        'fx_shock': 0.30,
        'rate_shock': 0.0300,
        'pd_multiplier': 4.0,
    },
}

def apply_stress_scenario(
    portfolio: dict,
    scenario_name: str,
) -> dict:
    scenario = STRESS_SCENARIOS[scenario_name]
    stressed_value = portfolio['market_value'] * (1 + scenario['equity_shock'])
    stressed_ecl = portfolio['ecl'] * scenario['pd_multiplier']
    stressed_cet1 = (portfolio['cet1_capital'] - stressed_ecl
                     + stressed_value - portfolio['market_value'])

    return {
        'scenario': scenario_name,
        'pre_stress_cet1_ratio': portfolio['cet1_ratio'],
        'post_stress_cet1_ratio': stressed_cet1 / portfolio['rwa'],
        'stressed_loss': portfolio['ecl'] * (scenario['pd_multiplier'] - 1),
        'passes_minimum': stressed_cet1 / portfolio['rwa'] >= 0.045,  # 4.5% CET1 minimum
    }
```

## Examples

```bash
# Calculate 99% 10-day VaR using historical simulation
/risk var --portfolio-id PORT-001 --method historical --confidence 0.99 --horizon 10

# Compute CECL expected credit loss for loan portfolio
/risk credit --portfolio-id LOAN-BOOK-001

# Run DFAST severely adverse stress scenario
/risk stress --portfolio-id BANK-001 --scenario severely-adverse

# Check all risk limits for trading desk
/risk limits --portfolio-id EQUITY-DESK-001
```
