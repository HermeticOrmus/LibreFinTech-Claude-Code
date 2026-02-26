# Reconciliation Patterns

Domain-specific patterns for transaction matching, break management, and reconciliation controls in financial systems.

## Core Patterns

### Pattern: Multi-Pass Matching with Confidence Scoring

```python
from decimal import Decimal
from datetime import date

def match_transactions(
    internals: list[dict],
    externals: list[dict],
) -> dict:
    """
    Multiple matching passes with decreasing strictness.
    Score each match; human review required below 0.8 confidence.
    Never auto-approve low-confidence matches for material amounts.
    """
    results = {'matched': [], 'unmatched_internal': [], 'unmatched_external': []}
    used_external_ids = set()

    passes = [
        # (name, confidence, match_function)
        ('EXACT_REF_AMT_DATE', 1.0, _match_exact),
        ('EXACT_REF_AMT', 0.90, _match_ref_amount),
        ('EXACT_REF_TEMPORAL', 0.75, _match_ref_date_window),
        ('AMOUNT_DATE_ONLY', 0.50, _match_amount_date),  # Low confidence - review required
    ]

    unmatched_int = list(internals)

    for pass_name, confidence, match_fn in passes:
        still_unmatched = []
        for internal in unmatched_int:
            match = match_fn(internal, externals, used_external_ids)
            if match:
                results['matched'].append({
                    'internal': internal,
                    'external': match,
                    'pass': pass_name,
                    'confidence': confidence,
                    'requires_review': confidence < 0.80,
                })
                used_external_ids.add(match['id'])
            else:
                still_unmatched.append(internal)
        unmatched_int = still_unmatched

    results['unmatched_internal'] = unmatched_int
    results['unmatched_external'] = [e for e in externals if e['id'] not in used_external_ids]
    return results

def _match_exact(internal, externals, used):
    for ext in externals:
        if ext['id'] in used:
            continue
        if (internal['reference'] == ext['reference']
                and internal['amount'] == ext['amount']
                and internal['value_date'] == ext['value_date']):
            return ext
    return None
```

### Pattern: One-to-Many Matching for Aggregated Settlements

```python
from itertools import combinations
from decimal import Decimal

def find_one_to_many_match(
    stmt_amount: Decimal,
    unmatched_internals: list[dict],
    max_combination_size: int = 5,
) -> list[dict] | None:
    """
    One external settlement entry can correspond to multiple internal records.
    Example: Stripe payout = 100 individual charges netted together.
    Expensive O(n^k) for large sets - limit combination size.
    """
    for size in range(2, max_combination_size + 1):
        for combo in combinations(unmatched_internals, size):
            combo_total = sum(item['amount'] for item in combo)
            if abs(combo_total - stmt_amount) <= Decimal('0.01'):
                return list(combo)
    return None
```

### Pattern: Break Escalation State Machine

```typescript
type BreakStatus = 'NEW' | 'INVESTIGATING' | 'ESCALATED_L1' | 'ESCALATED_L2' | 'RESOLVED' | 'WRITTEN_OFF';

interface BreakEscalationRule {
  ageDays: number;
  minimumAmount: number;
  targetStatus: BreakStatus;
  notifyRole: string;
}

const ESCALATION_RULES: BreakEscalationRule[] = [
  { ageDays: 1,  minimumAmount: 0,       targetStatus: 'NEW',          notifyRole: 'recon_analyst' },
  { ageDays: 3,  minimumAmount: 0,       targetStatus: 'INVESTIGATING', notifyRole: 'recon_analyst' },
  { ageDays: 5,  minimumAmount: 0,       targetStatus: 'ESCALATED_L1', notifyRole: 'ops_manager' },
  { ageDays: 10, minimumAmount: 0,       targetStatus: 'ESCALATED_L2', notifyRole: 'finance_controller' },
  { ageDays: 1,  minimumAmount: 100000,  targetStatus: 'ESCALATED_L1', notifyRole: 'ops_manager' },   // High-value fast-track
  { ageDays: 2,  minimumAmount: 1000000, targetStatus: 'ESCALATED_L2', notifyRole: 'cfo' },            // Material same-day
];

async function applyEscalationRules(breaks: ReconciliationBreak[]): Promise<void> {
  for (const br of breaks) {
    const ageDays = Math.floor((Date.now() - br.identifiedAt.getTime()) / 86400000);

    // Apply most severe matching rule
    const applicableRules = ESCALATION_RULES.filter(
      r => ageDays >= r.ageDays && Math.abs(br.amount) >= r.minimumAmount
    );
    const mostSevere = applicableRules.sort((a, b) => b.ageDays - a.ageDays)[0];

    if (mostSevere && br.status !== mostSevere.targetStatus) {
      await escalateBreak(br.id, mostSevere.targetStatus);
      await notifyByRole(mostSevere.notifyRole, br);
    }
  }
}
```

### Pattern: MT940 / camt.053 Statement Parser

```python
import re
from decimal import Decimal
from datetime import date

def parse_mt940_statement(content: str) -> list[dict]:
    """
    MT940: SWIFT bank statement format.
    Field :61: = Statement line (date, amount, reference)
    Field :86: = Additional information (narrative)
    Still widely used by correspondent banks even as ISO 20022 rollout continues.
    """
    entries = []
    current_entry = {}

    for line in content.split('\n'):
        if line.startswith(':61:'):
            # Format: :61:YYMMDDYYMMDD[D/C][amount]N[reference]
            match = re.match(r':61:(\d{6})(\d{6})?([DC])(\d+,\d+)N(.+)', line)
            if match:
                booking_date = _parse_mt940_date(match.group(1))
                value_date = _parse_mt940_date(match.group(2) or match.group(1))
                direction = match.group(3)  # D = debit, C = credit
                amount_str = match.group(4).replace(',', '.')
                amount = Decimal(amount_str)
                if direction == 'D':
                    amount = -amount

                current_entry = {
                    'booking_date': booking_date,
                    'value_date': value_date,
                    'amount': amount,
                    'reference': match.group(5).strip(),
                }

        elif line.startswith(':86:') and current_entry:
            current_entry['narrative'] = line[4:].strip()
            entries.append(current_entry)
            current_entry = {}

    return entries

def _parse_mt940_date(yymmdd: str) -> date:
    year = int(yymmdd[:2])
    year += 2000 if year < 70 else 1900
    return date(year, int(yymmdd[2:4]), int(yymmdd[4:6]))
```

## Anti-Patterns

### Anti-Pattern: Auto-Resolving Breaks by Writing Them Off

```sql
-- WRONG: Automatically write off small breaks without investigation
UPDATE reconciliation_breaks
SET status = 'WRITTEN_OFF', resolution = 'BELOW_MATERIALITY'
WHERE ABS(amount) < 10
  AND identified_date < CURRENT_DATE - 5;
-- Small breaks can be symptoms of systemic issues (rounding bug in pricing engine)
-- Accumulation of small write-offs can mask fraud

-- RIGHT: Flag for review, never auto-resolve without classification
UPDATE reconciliation_breaks
SET status = 'PENDING_REVIEW', aging_status = 'AUTO_FLAGGED'
WHERE ABS(amount) < 10
  AND identified_date < CURRENT_DATE - 5;
-- A human reviews and classifies each break, even sub-dollar amounts
```

### Anti-Pattern: Matching Across Different Currencies

```python
# WRONG: Match USD 100 internal to GBP 100 external (same number, different currency)
if internal['amount'] == external['amount']:  # Forgot to check currency
    match(internal, external)
# GBP 100 = USD ~126 at current rates - you've just matched a break incorrectly

# RIGHT: Always check currency before amount comparison
if (internal['amount'] == external['amount']
        and internal['currency'] == external['currency']):
    match(internal, external)
```

### Anti-Pattern: Reconciling Against Mutable External Data

```python
# WRONG: Pull live data from Stripe API for reconciliation
transactions = stripe.PaymentIntent.list(created={'gte': start, 'lte': end})
# Stripe data can change: a charge can be refunded or disputed after you fetch it
# Re-running reconciliation fetches different data = different results

# RIGHT: Download and snapshot statement at close of period
# Store immutable copy before reconciling against it
statement = download_stripe_payout_csv(payout_id)
snapshot_id = store_immutable_snapshot(statement, payout_id, date)
# All reconciliation runs use the same immutable snapshot
```

## References

- **SWIFT MT940 User Handbook**: https://www.swift.com/standards/data-standards/mt940
- **ISO 20022 camt.053**: Bank-to-Customer Statement - https://www.iso20022.org/
- **CASS Sourcebook (FCA)**: Client money reconciliation requirements - https://www.handbook.fca.org.uk/handbook/CASS/
- **SOX Section 404**: Management assessment of internal controls
- **Basel III Pillar 1**: Position data accuracy for risk-weighted assets
- **EMIR Regulation (EU 648/2012)**: Portfolio reconciliation for OTC derivatives
- **Stripe Balance Transaction API**: https://stripe.com/docs/api/balance_transactions
