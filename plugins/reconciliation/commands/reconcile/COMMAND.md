# /reconcile

Transaction reconciliation: match internal records against external statements, classify breaks, and generate exception reports.

## Trigger

`/reconcile <action> [options]`

## Actions

- `run` - Execute reconciliation matching for a given account and date
- `breaks` - List unmatched breaks with aging and classification
- `resolve` - Mark a break as resolved with explanation and journal reference
- `report` - Generate reconciliation summary report for sign-off

## Options

- `--account <id>` - Account or Nostro to reconcile
- `--source <bank|custodian|stripe|adyen|exchange>` - External statement source
- `--date <ISO8601>` - Statement date to reconcile
- `--tolerance <amount>` - Amount tolerance for fuzzy matching (default: 0.01)
- `--window <days>` - Temporal matching window in days (default: 2)
- `--format <mt940|camt053|csv>` - External statement format

## Process

### run

Core matching engine - exact match first, then fuzzy rules:

```python
from decimal import Decimal
from datetime import date, timedelta
from dataclasses import dataclass
from typing import Optional

@dataclass
class LedgerEntry:
    id: str
    amount: Decimal
    currency: str
    value_date: date
    reference: str
    description: str

@dataclass
class StatementEntry:
    amount: Decimal
    currency: str
    booking_date: date
    value_date: date
    reference: str   # SWIFT field 61 reference or camt.053 EndToEndId

@dataclass
class ReconciliationMatch:
    ledger_entry: LedgerEntry
    statement_entry: StatementEntry
    match_type: str   # 'EXACT' | 'FUZZY_AMOUNT' | 'TEMPORAL' | 'ONE_TO_MANY'
    confidence: float  # 0.0-1.0

def run_reconciliation(
    ledger: list[LedgerEntry],
    statement: list[StatementEntry],
    amount_tolerance: Decimal = Decimal('0.01'),
    date_window: int = 2,
) -> tuple[list[ReconciliationMatch], list[LedgerEntry], list[StatementEntry]]:
    """
    Returns: (matches, unmatched_ledger, unmatched_statement)
    Unmatched items become breaks requiring investigation.
    """
    matches = []
    unmatched_ledger = list(ledger)
    unmatched_stmt = list(statement)
    matched_stmt_ids = set()

    # Pass 1: Exact match (reference + amount + date)
    for le in list(unmatched_ledger):
        for se in unmatched_stmt:
            if se.reference in matched_stmt_ids:
                continue
            if (le.reference == se.reference
                    and le.amount == se.amount
                    and le.value_date == se.value_date):
                matches.append(ReconciliationMatch(le, se, 'EXACT', 1.0))
                unmatched_ledger.remove(le)
                matched_stmt_ids.add(se.reference)
                break

    # Pass 2: Fuzzy amount match (same reference, amount within tolerance)
    for le in list(unmatched_ledger):
        for se in unmatched_stmt:
            if se.reference in matched_stmt_ids:
                continue
            amount_diff = abs(le.amount - se.amount)
            if le.reference == se.reference and amount_diff <= amount_tolerance:
                matches.append(ReconciliationMatch(le, se, 'FUZZY_AMOUNT', 0.9))
                unmatched_ledger.remove(le)
                matched_stmt_ids.add(se.reference)
                break

    # Pass 3: Temporal window match (same amount, reference, different date)
    for le in list(unmatched_ledger):
        for se in unmatched_stmt:
            if se.reference in matched_stmt_ids:
                continue
            date_diff = abs((le.value_date - se.value_date).days)
            if (le.reference == se.reference
                    and le.amount == se.amount
                    and date_diff <= date_window):
                matches.append(ReconciliationMatch(le, se, 'TEMPORAL', 0.75))
                unmatched_ledger.remove(le)
                matched_stmt_ids.add(se.reference)
                break

    unmatched_stmt = [s for s in unmatched_stmt if s.reference not in matched_stmt_ids]
    return matches, unmatched_ledger, unmatched_stmt
```

### breaks

Classify and age breaks:

```sql
-- Break aging report with classification
-- Run daily; breaks not resolving by age threshold trigger escalation
SELECT
    b.break_id,
    b.break_type,
    b.amount,
    b.currency,
    b.external_reference,
    b.internal_reference,
    b.identified_date,
    CURRENT_DATE - b.identified_date AS age_days,
    CASE
        WHEN CURRENT_DATE - b.identified_date <= 2  THEN 'NEW'
        WHEN CURRENT_DATE - b.identified_date <= 5  THEN 'IN_PROGRESS'
        WHEN CURRENT_DATE - b.identified_date <= 10 THEN 'ESCALATED'
        ELSE 'CRITICAL'
    END AS aging_status,
    b.assigned_to,
    b.investigation_notes,
    -- Flag if break exceeds materiality threshold ($10k)
    ABS(b.amount) > 10000 AS is_material
FROM reconciliation_breaks b
WHERE b.status = 'OPEN'
  AND b.account_id = $1
  AND b.statement_date = $2
ORDER BY ABS(b.amount) DESC, age_days DESC;
```

### resolve

Mark break resolved with audit trail:

```typescript
interface BreakResolution {
  breakId: string;
  resolution: 'TIMING_DIFFERENCE' | 'WRITE_OFF' | 'JOURNAL_POSTED' | 'COUNTERPARTY_CONFIRMED' | 'DUPLICATE_REMOVED';
  journalEntryId?: string;    // If a correcting journal was posted
  approvedBy: string;          // Required for SOX compliance
  notes: string;
  resolvedAt: Date;
}

async function resolveBreak(resolution: BreakResolution): Promise<void> {
  if (resolution.resolution === 'WRITE_OFF') {
    // Write-offs require additional approval
    const breakRecord = await db.reconciliationBreak.findUnique({
      where: { id: resolution.breakId },
    });
    if (Math.abs(breakRecord.amount) > 1000) {
      throw new ApprovalRequiredError('Write-offs over $1,000 require controller approval');
    }
  }

  await db.reconciliationBreak.update({
    where: { id: resolution.breakId },
    data: {
      status: 'RESOLVED',
      resolution: resolution.resolution,
      journalEntryId: resolution.journalEntryId,
      approvedBy: resolution.approvedBy,
      notes: resolution.notes,
      resolvedAt: resolution.resolvedAt,
    },
  });

  // Immutable audit record - never update, always insert
  await db.reconciliationBreakHistory.create({
    data: { breakId: resolution.breakId, ...resolution, action: 'RESOLVED' },
  });
}
```

### report

Reconciliation sign-off report:

```typescript
async function generateReconReport(account: string, date: string): Promise<ReconReport> {
  const stats = await db.$queryRaw`
    SELECT
      COUNT(*) FILTER (WHERE status = 'MATCHED') AS matched_count,
      COUNT(*) FILTER (WHERE status = 'OPEN') AS open_breaks,
      SUM(ABS(amount)) FILTER (WHERE status = 'OPEN') AS open_break_amount,
      COUNT(*) FILTER (WHERE status = 'OPEN' AND ABS(amount) > 10000) AS material_breaks
    FROM reconciliation_entries
    WHERE account_id = ${account} AND statement_date = ${date}
  `;
  return {
    account, date, ...stats[0],
    certifiedBy: null,  // Populated on sign-off
    status: stats[0].open_breaks === 0 ? 'CLEAN' : 'BREAKS_OUTSTANDING',
  };
}
```

## Examples

```bash
# Reconcile USD Nostro account against SWIFT MT940 for today
/reconcile run --account NOSTRO-USD-001 --source bank --date 2024-11-01 --format mt940

# List all open breaks older than 3 days
/reconcile breaks --account NOSTRO-USD-001 --date 2024-11-01

# Resolve a timing difference break
/reconcile resolve --account NOSTRO-USD-001 --date 2024-11-01

# Generate sign-off report for controller
/reconcile report --account NOSTRO-USD-001 --date 2024-11-01
```
