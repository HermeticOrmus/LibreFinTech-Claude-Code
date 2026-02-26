# Risk Management Patterns

Domain-specific patterns for market risk, credit risk, operational risk, and stress testing in financial systems.

## Core Patterns

### Pattern: VaR Backtesting (Basel Traffic Light)

```python
import numpy as np
from scipy.stats import binom

def backtest_var(
    var_estimates: list[float],   # Daily VaR estimates (positive = potential loss)
    actual_pnl: list[float],      # Actual daily P&L (negative = loss)
    confidence: float = 0.99,
) -> dict:
    """
    Basel II/III VaR backtesting: count days where actual loss > VaR estimate.
    These are "exceptions" or "exceedances."
    Traffic light system for 250 trading days:
    - Green zone (0-4 exceptions): VaR model acceptable
    - Yellow zone (5-9 exceptions): Scrutiny required; capital multiplier 3.4-3.75
    - Red zone (10+ exceptions): Model inadequate; capital multiplier 4.0; remediation required

    Note: At 99% confidence, we EXPECT 2-3 exceptions per year (250 * 1% = 2.5).
    Zero exceptions may indicate VaR is too conservative (overstating risk).
    """
    exceptions = sum(1 for var, pnl in zip(var_estimates, actual_pnl)
                     if pnl < -var)  # Actual loss exceeds VaR estimate

    n = len(var_estimates)
    expected_exceptions = n * (1 - confidence)

    # Kupiec test: is exception rate consistent with stated confidence level?
    # H0: exception rate = (1-confidence)
    from scipy.stats import binom_test
    p_value = binom_test(exceptions, n, 1 - confidence, alternative='two-sided')

    zone = 'GREEN' if exceptions <= 4 else 'YELLOW' if exceptions <= 9 else 'RED'
    capital_multiplier = {
        'GREEN': 3.0,
        'YELLOW': 3.4 + (exceptions - 5) * 0.07,  # 3.4 to 3.75
        'RED': 4.0,
    }[zone]

    return {
        'exceptions': exceptions,
        'expected': expected_exceptions,
        'zone': zone,
        'capital_multiplier': min(capital_multiplier, 4.0),
        'kupiec_p_value': p_value,
        'model_adequate': p_value > 0.05 and zone in ('GREEN', 'YELLOW'),
    }
```

### Pattern: Real-Time Risk Limit Monitoring

```typescript
interface RiskLimit {
  limitId: string;
  portfolioId: string;
  riskMetric: 'VAR_1DAY' | 'DELTA_USD' | 'NOTIONAL' | 'CONCENTRATION_PCT';
  hardLimit: number;    // Breach = automatic trading halt
  softLimit: number;    // Breach = alert sent, trading continues
  currentValue: number;
}

async function checkAllLimits(portfolioId: string): Promise<LimitCheckResult[]> {
  const limits = await db.riskLimit.findMany({ where: { portfolioId, active: true } });
  const currentMetrics = await computePortfolioRiskMetrics(portfolioId);
  const results: LimitCheckResult[] = [];

  for (const limit of limits) {
    const current = currentMetrics[limit.riskMetric];
    const utilizationPct = (current / limit.hardLimit) * 100;

    const result: LimitCheckResult = {
      limitId: limit.limitId,
      riskMetric: limit.riskMetric,
      currentValue: current,
      softLimit: limit.softLimit,
      hardLimit: limit.hardLimit,
      utilizationPct,
      status: current >= limit.hardLimit ? 'HARD_BREACH'
              : current >= limit.softLimit ? 'SOFT_BREACH'
              : utilizationPct >= 80 ? 'APPROACHING'
              : 'OK',
    };

    if (result.status === 'HARD_BREACH') {
      await haltTrading(portfolioId, limit.riskMetric, current, limit.hardLimit);
      await alertRiskOfficer(result, 'URGENT');
    } else if (result.status === 'SOFT_BREACH') {
      await alertRiskOfficer(result, 'WARNING');
    }

    results.push(result);
  }

  return results;
}
```

### Pattern: IFRS 9 Stage Migration Tracking

```sql
-- Track stage migrations for IFRS 9 / CECL
-- Stage migration changes ECL from 12-month to lifetime (Stage 1 -> 2)
-- This is a significant P&L event; auditors scrutinize stage transfers

CREATE TABLE credit_stage_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id         UUID NOT NULL,
    previous_stage  SMALLINT NOT NULL CHECK (previous_stage IN (1, 2, 3)),
    new_stage       SMALLINT NOT NULL CHECK (new_stage IN (1, 2, 3)),
    migration_date  DATE NOT NULL,
    trigger_factor  TEXT NOT NULL,   -- 'DPD_30', 'PD_THRESHOLD', 'WATCHLIST', 'CURE'
    previous_ecl    NUMERIC(20, 4),
    new_ecl         NUMERIC(20, 4),
    ecl_impact      NUMERIC(20, 4) GENERATED ALWAYS AS (new_ecl - previous_ecl) STORED,
    recorded_by     TEXT NOT NULL,
    CONSTRAINT no_skip_stage CHECK (
        -- Cannot skip stages (Stage 1 directly to Stage 3 requires explanation)
        ABS(new_stage - previous_stage) = 1
        OR (previous_stage = 1 AND new_stage = 3)  -- Allowed but requires override
    )
);

-- Daily stage migration summary for credit risk reporting
SELECT
    migration_date,
    COUNT(*) FILTER (WHERE previous_stage = 1 AND new_stage = 2) AS s1_to_s2_count,
    COUNT(*) FILTER (WHERE previous_stage = 2 AND new_stage = 3) AS s2_to_s3_count,
    COUNT(*) FILTER (WHERE new_stage < previous_stage) AS cures_count,
    SUM(ecl_impact) FILTER (WHERE new_stage > previous_stage) AS deterioration_ecl_impact,
    SUM(ecl_impact) FILTER (WHERE new_stage < previous_stage) AS cure_ecl_release
FROM credit_stage_history
WHERE migration_date >= CURRENT_DATE - 30
GROUP BY migration_date
ORDER BY migration_date DESC;
```

### Pattern: Operational Risk Event Capture

```typescript
// Basel III operational risk: capture all loss events >$10k threshold
// External loss data (ORX) supplements internal data for tail estimation

interface OperationalLossEvent {
  eventId: string;
  eventDate: Date;
  discoveryDate: Date;         // May be later than event date
  category: BaselOpRiskCategory;  // Seven Basel II business line / event type categories
  grossLoss: Decimal;
  recovery: Decimal;           // Insurance recovery, litigation recovery
  netLoss: Decimal;            // grossLoss - recovery
  businessLine: string;
  description: string;
  rootCause: string;
  controlFailure: string;      // Which control failed to prevent this event?
  remediationAction: string;
  approvedBy: string;          // Senior management sign-off required for large events
}

enum BaselOpRiskCategory {
  INTERNAL_FRAUD = 'INTERNAL_FRAUD',
  EXTERNAL_FRAUD = 'EXTERNAL_FRAUD',
  EMPLOYMENT_PRACTICES = 'EMPLOYMENT_PRACTICES',
  CLIENTS_PRODUCTS = 'CLIENTS_PRODUCTS',
  PHYSICAL_ASSETS = 'PHYSICAL_ASSETS',
  BUSINESS_DISRUPTION = 'BUSINESS_DISRUPTION',
  EXECUTION_DELIVERY = 'EXECUTION_DELIVERY',
}
```

## Anti-Patterns

### Anti-Pattern: Relying on VaR as Maximum Loss

```
WRONG: "Our 99% VaR is $5M, so our maximum loss is $5M"
99% VaR means: losses will EXCEED $5M on 1% of trading days.
That's about 2.5 days per year where losses are larger than $5M.
In the 2008 crisis, daily losses exceeded 99% VaR many times consecutively.

RIGHT: Use Expected Shortfall (ES) alongside VaR
ES = average loss on the days VaR is exceeded
If 99% VaR = $5M and 99% ES = $12M:
- You will exceed $5M about 2.5 days/year
- When you do exceed $5M, average loss is $12M
Basel III FRTB replaced VaR with 97.5% ES precisely because ES captures the tail better.
```

### Anti-Pattern: Ignoring Model Risk

```python
# WRONG: Deploy VaR model without validation or backtesting
var = parametric_var(positions, returns)  # Ship it

# RIGHT: Validate model before relying on it
# 1. Backtest: compare VaR estimates to actual P&L over 250+ days
# 2. Kupiec test: verify exception rate is statistically consistent with confidence level
# 3. Christoffersen test: verify exceptions are not clustered (autocorrelation)
# 4. Document model assumptions and known limitations
# 5. Set model risk limit: what is the uncertainty in the VaR estimate itself?
# 6. Obtain independent model validation sign-off (MRM team, separate from developers)
```

### Anti-Pattern: Measuring Credit Risk at Origination Only

```
WRONG: Assign PD once at loan origination; never update
- A borrower with PD 0.5% at origination may be PD 15% after job loss
- Provisions will be dramatically understated
- Regulatory requirement (IFRS 9, CECL): forward-looking, dynamic ECL

RIGHT: pKYC-style ongoing credit monitoring
- Update PD monthly for retail; quarterly for commercial
- Trigger Stage 2 migration on: 30+ DPD, significant PD increase, watchlist addition
- Use macroeconomic overlays: GDP forecasts, unemployment rates affect portfolio-level PD
- Vintage analysis: cohorts originated in adverse conditions have higher through-cycle losses
```

## References

- **Basel III: Market Risk (FRTB)**: https://www.bis.org/bcbs/publ/d457.htm
- **Basel III: Credit Risk**: https://www.bis.org/bcbs/publ/d424.htm
- **IFRS 9 Financial Instruments**: https://www.ifrs.org/issued-standards/list-of-standards/ifrs-9-financial-instruments/
- **CECL (ASC 326)**: https://www.fasb.org/page/PageContent?pageId=/reference-library/superseded-standards/summary-of-statement-no-133.html
- **Kupiec (1995)**: "Techniques for Verifying the Accuracy of Risk Measurement Models" - Journal of Derivatives
- **Jorion, "Value at Risk"**: Standard reference text for risk practitioners
- **ORX (Operational Risk Exchange)**: https://orx.org/ - Industry loss data consortium
- **DFAST Scenarios**: https://www.federalreserve.gov/publications/stress-test-scenarios.htm
- **RiskMetrics (J.P. Morgan)**: Original VaR methodology publication
