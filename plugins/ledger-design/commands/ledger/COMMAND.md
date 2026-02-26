# /ledger

Double-entry ledger operations: post journal entries, query balances, validate the accounting equation, and close accounting periods.

## Trigger

`/ledger <action> [options]`

## Actions

- `post` - Post a journal entry (debit/credit pairs)
- `query` - Query account balance or transaction history
- `balance` - Get account balance (or trial balance for all accounts)
- `close` - Execute period-close locking procedure

## Options

- `--account <code>` - Account code to operate on
- `--period <YYYY-MM>` - Accounting period
- `--entity <id>` - Legal entity
- `--currency <ISO4217>` - Currency filter
- `--format <json|csv|table>` - Output format

## Process

### Core Schema

```sql
-- Chart of accounts
CREATE TABLE accounts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        TEXT NOT NULL UNIQUE,         -- e.g., '1100'
    name        TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK (account_type IN
                    ('ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE')),
    normal_balance TEXT NOT NULL CHECK (normal_balance IN ('DEBIT', 'CREDIT')),
    parent_id   UUID REFERENCES accounts(id),
    is_control  BOOLEAN DEFAULT FALSE,        -- Control account for sub-ledger
    currency    TEXT,                         -- NULL = multi-currency account
    entity_id   TEXT NOT NULL,
    is_active   BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- Journal entries (header)
CREATE TABLE journal_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_number    TEXT NOT NULL UNIQUE,     -- Human-readable reference
    period          TEXT NOT NULL,            -- 'YYYY-MM'
    entry_date      DATE NOT NULL,
    entity_id       TEXT NOT NULL,
    description     TEXT NOT NULL,
    status          TEXT DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'POSTED', 'REVERSED')),
    source          TEXT NOT NULL,            -- System that created this: 'PAYMENT', 'PAYROLL', etc.
    correlation_id  TEXT,                     -- Links to business event
    posted_by       TEXT,
    posted_at       TIMESTAMPTZ,
    reversed_by     UUID REFERENCES journal_entries(id),
    created_at      TIMESTAMPTZ DEFAULT now(),

    -- Prevent posting to closed periods
    CHECK (status != 'POSTED' OR period_is_open(entity_id, period))
);

-- Journal entry lines (debits and credits)
CREATE TABLE journal_entry_lines (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_entry_id UUID NOT NULL REFERENCES journal_entries(id),
    account_id      UUID NOT NULL REFERENCES accounts(id),
    debit_credit    TEXT NOT NULL CHECK (debit_credit IN ('D', 'C')),
    amount          NUMERIC(38, 10) NOT NULL CHECK (amount > 0),  -- NEVER FLOAT
    currency        TEXT NOT NULL,            -- ISO 4217
    fx_rate         NUMERIC(20, 10),          -- Rate to functional currency (1.0 if same)
    functional_amount NUMERIC(38, 10),        -- Amount in entity's functional currency
    memo            TEXT,
    line_number     INTEGER NOT NULL
);

-- Constraint: every journal entry must balance (debits = credits)
-- Enforced via trigger
CREATE OR REPLACE FUNCTION check_entry_balance()
RETURNS TRIGGER AS $$
DECLARE
    debit_total  NUMERIC;
    credit_total NUMERIC;
BEGIN
    SELECT
        SUM(CASE WHEN debit_credit = 'D' THEN functional_amount ELSE 0 END),
        SUM(CASE WHEN debit_credit = 'C' THEN functional_amount ELSE 0 END)
    INTO debit_total, credit_total
    FROM journal_entry_lines
    WHERE journal_entry_id = NEW.journal_entry_id;

    IF ABS(COALESCE(debit_total, 0) - COALESCE(credit_total, 0)) > 0.000001 THEN
        RAISE EXCEPTION 'Journal entry does not balance: debits=% credits=%',
            debit_total, credit_total;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### post

```typescript
interface JournalEntryLine {
  accountCode: string;
  debitCredit: 'D' | 'C';
  amount: Decimal;    // Always positive; direction is debitCredit
  currency: string;   // ISO 4217
  memo?: string;
}

interface JournalEntryRequest {
  period: string;          // 'YYYY-MM'
  entryDate: Date;
  entityId: string;
  description: string;
  source: string;
  correlationId?: string;  // Link to business event
  lines: JournalEntryLine[];
}

// Example: Record a customer payment receipt
const paymentEntry: JournalEntryRequest = {
  period: '2024-11',
  entryDate: new Date('2024-11-15'),
  entityId: 'ENTITY-001',
  description: 'Customer payment - Invoice INV-2024-1234',
  source: 'PAYMENTS',
  correlationId: 'PAY-001234',
  lines: [
    { accountCode: '1001', debitCredit: 'D', amount: new Decimal('500.00'), currency: 'USD', memo: 'Cash received' },
    { accountCode: '1200', debitCredit: 'C', amount: new Decimal('500.00'), currency: 'USD', memo: 'AR cleared' },
  ],
};
```

### balance

```sql
-- Account balance (calculated from journal entries - no rounding drift)
SELECT
    a.code,
    a.name,
    a.account_type,
    a.normal_balance,
    SUM(CASE WHEN jel.debit_credit = 'D' THEN jel.functional_amount ELSE 0 END) AS total_debits,
    SUM(CASE WHEN jel.debit_credit = 'C' THEN jel.functional_amount ELSE 0 END) AS total_credits,
    CASE a.normal_balance
        WHEN 'DEBIT' THEN
            SUM(CASE WHEN jel.debit_credit = 'D' THEN jel.functional_amount
                     ELSE -jel.functional_amount END)
        ELSE
            SUM(CASE WHEN jel.debit_credit = 'C' THEN jel.functional_amount
                     ELSE -jel.functional_amount END)
    END AS balance
FROM accounts a
JOIN journal_entry_lines jel ON jel.account_id = a.id
JOIN journal_entries je ON je.id = jel.journal_entry_id
WHERE a.entity_id = :entity_id
  AND je.period <= :period
  AND je.status = 'POSTED'
GROUP BY a.id, a.code, a.name, a.account_type, a.normal_balance
ORDER BY a.code;
```

### close

```sql
-- Lock a period: prevent new postings to closed periods
INSERT INTO accounting_periods (entity_id, period, status, closed_by, closed_at)
VALUES (:entity_id, :period, 'CLOSED', :user_id, NOW())
ON CONFLICT (entity_id, period)
DO UPDATE SET status = 'CLOSED', closed_by = :user_id, closed_at = NOW();
```

## Examples

```bash
# Post a journal entry for a customer payment
/ledger post --entity ENTITY-001 --period 2024-11

# Query AR account balance as of November 2024
/ledger balance --account 1200 --entity ENTITY-001 --period 2024-11

# Generate trial balance for period-end review
/ledger balance --entity ENTITY-001 --period 2024-11 --format table

# Close November 2024 period after all reconciliations pass
/ledger close --entity ENTITY-001 --period 2024-11
```
