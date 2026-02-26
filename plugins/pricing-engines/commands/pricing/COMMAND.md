# /pricing

Fee calculation, interest computation, derivatives pricing, and premium rating.

## Trigger

`/pricing <action> [options]`

## Actions

- `fee` - Calculate transaction or service fee (tiered, percentage, flat, mixed)
- `interest` - Compute interest accrual with correct day count and compounding
- `option` - Price European or American option using BSM or binomial tree
- `premium` - Calculate insurance premium using loss cost or GLM method

## Options

- `--product <loan|option|insurance|fx|subscription>` - Product type
- `--principal <amount>` - Principal or notional amount
- `--rate <decimal>` - Annual interest rate (e.g., 0.065 for 6.5%)
- `--day-count <ACT/360|ACT/365|30/360|ACT/ACT>` - Day count convention
- `--from <ISO8601>` - Period start date
- `--to <ISO8601>` - Period end date
- `--strike <amount>` - Option strike price
- `--vol <decimal>` - Implied volatility (e.g., 0.20 for 20%)

## Process

### fee

Tiered fee calculation - common for AUM-based advisory fees, interchange, and SaaS:

```python
from decimal import Decimal, ROUND_HALF_EVEN

# Example: AUM-based fee schedule (typical RIA)
FEE_SCHEDULE = [
    (Decimal('1_000_000'),   Decimal('0.0100')),   # 1.00% on first $1M
    (Decimal('5_000_000'),   Decimal('0.0075')),   # 0.75% on $1M-$5M
    (Decimal('10_000_000'),  Decimal('0.0050')),   # 0.50% on $5M-$10M
    (None,                   Decimal('0.0035')),   # 0.35% on balance
]

def calculate_tiered_fee(aum: Decimal) -> Decimal:
    """Marginal tiered fee - each tier's rate applies only to that tier's amount."""
    fee = Decimal('0')
    previous_tier_max = Decimal('0')

    for tier_max, rate in FEE_SCHEDULE:
        if tier_max is None:
            # Final tier - apply to remainder
            tier_amount = aum - previous_tier_max
        else:
            if aum <= previous_tier_max:
                break
            tier_amount = min(aum, tier_max) - previous_tier_max

        fee += tier_amount * rate
        if tier_max:
            previous_tier_max = tier_max

    # Annualized fee - divide by 4 for quarterly billing
    return fee.quantize(Decimal('0.01'), rounding=ROUND_HALF_EVEN)
```

### interest

Interest accrual with correct day count convention:

```python
from decimal import Decimal, ROUND_HALF_EVEN
from datetime import date

def calculate_interest(
    principal: Decimal,
    annual_rate: Decimal,
    start_date: date,
    end_date: date,
    day_count: str = 'ACT/365',
    compounding: str = 'simple',
) -> Decimal:
    """
    Day count conventions:
    - ACT/360: Actual days / 360. Used in: USD money markets, EUR, commercial paper.
    - ACT/365: Actual days / 365. Used in: GBP, AUD, government bonds (some markets).
    - 30/360: Each month assumed 30 days, year 360. Used in: corporate bonds, mortgages.
    - ACT/ACT: Actual days / actual days in year. Used in: US Treasuries, most gov bonds.
    """
    actual_days = (end_date - start_date).days

    if day_count == 'ACT/360':
        day_fraction = Decimal(actual_days) / Decimal('360')
    elif day_count == 'ACT/365':
        day_fraction = Decimal(actual_days) / Decimal('365')
    elif day_count == '30/360':
        d1, m1, y1 = start_date.day, start_date.month, start_date.year
        d2, m2, y2 = end_date.day, end_date.month, end_date.year
        days_30_360 = 360*(y2-y1) + 30*(m2-m1) + (d2-d1)
        day_fraction = Decimal(days_30_360) / Decimal('360')
    elif day_count == 'ACT/ACT':
        days_in_year = Decimal('366') if _is_leap_year(start_date.year) else Decimal('365')
        day_fraction = Decimal(actual_days) / days_in_year

    interest = principal * annual_rate * day_fraction
    return interest.quantize(Decimal('0.0001'), rounding=ROUND_HALF_EVEN)

def _is_leap_year(year: int) -> bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
```

### option

Black-Scholes-Merton European option pricing:

```python
import math
from decimal import Decimal

def black_scholes(
    S: float,     # Current spot price
    K: float,     # Strike price
    T: float,     # Time to expiry in years (e.g., 90/365)
    r: float,     # Risk-free rate (annual, continuous compounding)
    sigma: float, # Implied volatility (annual)
    option_type: str = 'call',
) -> dict:
    """
    BSM assumes: log-normal returns, no dividends, constant vol, no early exercise.
    For American options use binomial tree (handles early exercise premium).
    For dividends: adjust S = S * exp(-q * T) where q = continuous dividend yield.
    """
    from scipy.stats import norm

    d1 = (math.log(S / K) + (r + 0.5 * sigma**2) * T) / (sigma * math.sqrt(T))
    d2 = d1 - sigma * math.sqrt(T)

    if option_type == 'call':
        price = S * norm.cdf(d1) - K * math.exp(-r * T) * norm.cdf(d2)
        delta = norm.cdf(d1)
    else:  # put
        price = K * math.exp(-r * T) * norm.cdf(-d2) - S * norm.cdf(-d1)
        delta = norm.cdf(d1) - 1

    gamma = norm.pdf(d1) / (S * sigma * math.sqrt(T))
    vega = S * norm.pdf(d1) * math.sqrt(T) / 100  # per 1% vol move
    theta = (-(S * norm.pdf(d1) * sigma) / (2 * math.sqrt(T))
             - r * K * math.exp(-r * T) * norm.cdf(d2 if option_type=='call' else -d2)) / 365

    return {'price': price, 'delta': delta, 'gamma': gamma, 'vega': vega, 'theta': theta}
```

### premium

Insurance pure premium calculation:

```python
from decimal import Decimal, ROUND_HALF_EVEN

def calculate_insurance_premium(
    expected_loss_cost: Decimal,   # Pure premium per exposure unit
    exposure_units: Decimal,        # E.g., $100k of property value = 1 unit
    fixed_expense: Decimal,         # Fixed costs per policy
    variable_expense_pct: Decimal,  # Commission + variable admin as % of premium
    profit_loading_pct: Decimal,    # Target underwriting profit margin
    schedule_mod: Decimal = Decimal('1.0'),  # -25% to +25% schedule rating
) -> dict:
    """
    Rate adequacy = pure premium must cover all expected losses.
    Rate equity = each risk pays its actuarially fair share.
    Rate regulation = most states require filed rates (prior approval or file-and-use).
    """
    pure_premium = expected_loss_cost * exposure_units
    loading_divisor = Decimal('1') - variable_expense_pct - profit_loading_pct

    if loading_divisor <= 0:
        raise ValueError("Variable expense + profit loading must be < 100%")

    base_premium = (pure_premium + fixed_expense) / loading_divisor
    final_premium = (base_premium * schedule_mod).quantize(
        Decimal('0.01'), rounding=ROUND_HALF_EVEN
    )

    return {
        'pure_premium': pure_premium,
        'base_premium': base_premium,
        'final_premium': final_premium,
        'loss_ratio_at_target': pure_premium / final_premium,
        'schedule_mod_applied': schedule_mod,
    }
```

## Examples

```bash
# Calculate quarterly AUM fee for $2.5M portfolio
/pricing fee --product subscription --principal 2500000

# Compute 90-day ACT/360 interest on $500k at 5.25%
/pricing interest --principal 500000 --rate 0.0525 --day-count ACT/360 --from 2024-01-15 --to 2024-04-15

# Price a call option: SPY $480, 45 DTE, 18% IV, 5.25% risk-free
/pricing option --product option --principal 480 --strike 480 --vol 0.18 --from 2024-01-01 --to 2024-02-15

# Calculate commercial property insurance premium
/pricing premium --product insurance --principal 1000000 --rate 0.003
```
