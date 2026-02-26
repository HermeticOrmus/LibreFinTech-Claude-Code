# Pricing Engine Patterns

Domain-specific patterns for financial product pricing: fee calculation, interest computation, options pricing, and insurance premium rating.

## Core Patterns

### Pattern: Compound Interest with Correct Day Count

```python
from decimal import Decimal, ROUND_HALF_EVEN
from datetime import date

# ACT/360 is standard for USD commercial loans and money market instruments
# Using wrong day count can cause 1-2bps error per day - material over a year

def accrue_daily_interest(
    balance: Decimal,
    annual_rate: Decimal,
    accrual_date: date,
    day_count: str = 'ACT/360',
) -> Decimal:
    """Daily interest accrual. Accumulate to ledger every night."""
    denominator = Decimal('360') if day_count in ('ACT/360', '30/360') else Decimal('365')
    daily_rate = annual_rate / denominator
    interest = balance * daily_rate
    # Round to 4 decimal places for accrual; round to 2 for payment
    return interest.quantize(Decimal('0.0001'), rounding=ROUND_HALF_EVEN)

# For compound interest (e.g., savings accounts, daily compounding)
def compound_balance(
    principal: Decimal,
    annual_rate: Decimal,
    days: int,
    day_count: str = 'ACT/365',
) -> Decimal:
    """
    Daily compounding: balance grows by rate/365 each day.
    Effective annual rate = (1 + APR/365)^365 - 1
    """
    denominator = Decimal('360') if day_count == 'ACT/360' else Decimal('365')
    daily_rate = annual_rate / denominator
    # Use Python's Decimal power for precision
    factor = (Decimal('1') + daily_rate) ** days
    return (principal * factor).quantize(Decimal('0.01'), rounding=ROUND_HALF_EVEN)
```

### Pattern: Implied Volatility Surface Interpolation

```python
import numpy as np
from scipy.interpolate import RectBivariateSpline

class VolatilitySurface:
    """
    Market quotes implied vol for specific strikes and expiries.
    Must interpolate for strikes/expiries not directly quoted.
    Never use flat vol - the vol smile is real and material.
    OTM puts trade at 5-10 vol points higher than ATM (skew).
    """
    def __init__(
        self,
        strikes: np.ndarray,      # Array of quoted strikes
        expiries: np.ndarray,     # Array of expiry times in years
        vols: np.ndarray,         # 2D array [strike_index, expiry_index]
    ):
        self._interpolator = RectBivariateSpline(strikes, expiries, vols)

    def get_vol(self, strike: float, expiry_years: float) -> float:
        """Bicubic spline interpolation of the vol surface."""
        vol = float(self._interpolator(strike, expiry_years))
        # Sanity bounds: vol should be between 1% and 300%
        return max(0.01, min(3.0, vol))

    def get_atm_vol(self, spot: float, expiry_years: float) -> float:
        """ATM vol: strike = forward price."""
        return self.get_vol(spot, expiry_years)
```

### Pattern: Fee Audit Trail

```python
from decimal import Decimal
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

@dataclass
class FeeCalculationAudit:
    """
    Every fee calculation must be reproducible.
    Regulators (CFPB, FCA) may require explanation of any fee charged.
    Store full calculation lineage, not just the final amount.
    """
    fee_type: str
    final_amount: Decimal
    inputs: dict[str, Any]
    calculation_steps: list[dict] = field(default_factory=list)
    applied_schedule_version: str = ''
    calculated_at: datetime = field(default_factory=datetime.utcnow)
    regulatory_disclosure: str = ''  # Required text for TILA, etc.

    def add_step(self, name: str, value: Decimal, description: str):
        self.calculation_steps.append({
            'step': name,
            'value': str(value),  # Decimal serialized as string
            'description': description,
        })

def calculate_loan_fee_with_audit(
    principal: Decimal,
    fee_schedule: dict,
) -> FeeCalculationAudit:
    audit = FeeCalculationAudit(
        fee_type='origination_fee',
        final_amount=Decimal('0'),
        inputs={'principal': str(principal), 'schedule': fee_schedule},
    )

    pct_fee = principal * Decimal(str(fee_schedule['percentage']))
    audit.add_step('percentage_fee', pct_fee, f"{fee_schedule['percentage']*100}% of principal")

    flat_fee = Decimal(str(fee_schedule['flat']))
    audit.add_step('flat_fee', flat_fee, 'Fixed origination fee')

    total = pct_fee + flat_fee
    audit.add_step('total_fee', total, 'Percentage fee + flat fee')

    audit.final_amount = total
    audit.regulatory_disclosure = (
        f"Origination fee of ${total:.2f} is included in the APR calculation."
    )
    return audit
```

### Pattern: Black-Scholes Greeks for Risk Management

```python
import math
from scipy.stats import norm

def full_greeks(S, K, T, r, sigma, option_type='call') -> dict:
    """
    Greeks measure option sensitivity. Required for:
    - Delta hedging: maintain delta-neutral book
    - Gamma risk: delta changes as price moves
    - Vega risk: P&L from vol changes (most important for options desks)
    - Theta: time decay (options lose value as expiry approaches)

    For a market-making book, sum of greeks across all positions = net exposure.
    """
    d1 = (math.log(S/K) + (r + 0.5*sigma**2)*T) / (sigma*math.sqrt(T))
    d2 = d1 - sigma*math.sqrt(T)
    sign = 1 if option_type == 'call' else -1

    delta = sign * norm.cdf(sign * d1)
    gamma = norm.pdf(d1) / (S * sigma * math.sqrt(T))
    # Vega: per 1% change in vol (divide by 100)
    vega = S * norm.pdf(d1) * math.sqrt(T) / 100
    # Theta: per calendar day (divide by 365)
    theta = (-(S * norm.pdf(d1) * sigma) / (2 * math.sqrt(T))
             - sign * r * K * math.exp(-r*T) * norm.cdf(sign * d2)) / 365
    # Rho: per 1% change in risk-free rate
    rho = sign * K * T * math.exp(-r*T) * norm.cdf(sign * d2) / 100

    return {'delta': delta, 'gamma': gamma, 'vega': vega, 'theta': theta, 'rho': rho}
```

## Anti-Patterns

### Anti-Pattern: Float for Financial Calculations

```python
# WRONG: Float arithmetic introduces rounding errors
interest = 1000000.0 * 0.05 * (91 / 365)
# Result: 12465.753424657534 (may have floating point error)

# For a $1B loan, this error is significant
amount = 1_000_000_000.0 * 0.05 * (91 / 365)
# Floating point errors compound with multiple operations

# RIGHT: Decimal throughout
from decimal import Decimal, getcontext
getcontext().prec = 28  # 28 significant digits

interest = Decimal('1000000') * Decimal('0.05') * (Decimal('91') / Decimal('365'))
# Result: Decimal('12465.7534246575342465753424')
# Round at the final step only
final = interest.quantize(Decimal('0.01'))  # -> Decimal('12465.75')
```

### Anti-Pattern: Static Volatility Assumption

```python
# WRONG: Use same vol for all strikes and expiries
vol = 0.20  # "20% vol for everything"
price = black_scholes(S=100, K=90, T=0.25, r=0.05, sigma=vol)
# Underprices OTM puts - those have 25-30% implied vol in practice
# This is how traders lose money on tail events

# RIGHT: Use implied vol surface
surface = VolatilitySurface(strikes, expiries, market_vols)
vol = surface.get_vol(strike=90, expiry_years=0.25)  # Will be ~25% for OTM put
price = black_scholes(S=100, K=90, T=0.25, r=0.05, sigma=vol)
```

### Anti-Pattern: Not Adjusting for Day Count in Rate Comparison

```python
# WRONG: Compare rates without normalizing day count
loan_a_rate = 0.065  # ACT/365 day count
loan_b_rate = 0.064  # ACT/360 day count
# Loan B appears cheaper but effective ACT/365 equivalent is:
# 0.064 * (365/360) = 0.06489 -- actually almost the same

# RIGHT: Normalize to same basis before comparison
def normalize_to_act365(rate: Decimal, from_day_count: str) -> Decimal:
    if from_day_count == 'ACT/360':
        return rate * Decimal('365') / Decimal('360')
    return rate  # Already ACT/365
```

### Anti-Pattern: Pricing Without Regulatory Validation

```python
# WRONG: Display fee without checking usury limits or disclosure requirements
fee = calculate_fee(principal, rate)
return {'fee': fee}

# RIGHT: Validate against state usury laws and include required disclosures
def price_loan(principal, rate, state):
    usury_limit = USURY_LIMITS.get(state)
    apr = calculate_apr(principal, rate, fees)
    if usury_limit and apr > usury_limit:
        raise PricingError(f"APR {apr:.2%} exceeds {state} usury limit {usury_limit:.2%}")

    return {
        'fee': fee,
        'apr': apr,
        'tila_disclosure': format_tila_disclosure(apr, principal, term),
    }
```

## References

- **Black-Scholes-Merton (1973)**: "The Pricing of Options and Corporate Liabilities" - JPE
- **ISDA 2006 Definitions**: Day count fraction conventions for derivatives
- **ARRC SOFR Transition**: https://www.newyorkfed.org/arrc
- **TILA Regulation Z (12 CFR 1026)**: APR calculation, Appendix J
- **NAIC Rate Regulation**: https://content.naic.org/cipr-topics/rate-regulation
- **QuantLib**: Open-source library for quantitative finance: https://www.quantlib.org/
- **py_vollib**: Python Black-Scholes library with Greeks: https://github.com/vollib/py_vollib
- **scipy.stats.norm**: Used for N(d1), N(d2) in BSM: https://docs.scipy.org/doc/scipy/
