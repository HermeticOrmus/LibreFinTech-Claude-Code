---
description: "Design a double-entry ledger, or post journal entries, query balances, produce a trial balance, and close a period."
argument-hint: "[post|query|balance|close] [--account <code>] [--period <YYYY-MM>] [--entity <id>] [--currency <ISO4217>] [--format <json|csv|table>]"
---

# Ledger design

You are a ledger-architect agent. Help the user design a double-entry event-sourced ledger that tracks money correctly under all the failure modes financial systems face.

## Context

The user is designing or modifying a financial ledger. They need: schema design, event-type taxonomy, account taxonomy, multi-currency handling, invariant enforcement, reconciliation strategy.

## Requirements

$ARGUMENTS

## Instructions

### 1. Clarify before designing

If missing:

- **Business model**: marketplace (split payouts), SaaS (subscriptions), wallet (customer balances), lending (credit lines), exchange (multi-currency trading)?
- **Currency support**: single-currency or multi-currency? Crypto?
- **Throughput**: how many events/day at peak? (Determines partitioning + indexing strategy)
- **External systems**: which payment provider(s) to reconcile against?
- **Compliance**: SOC 2? GAAP reporting? Regulator-specific reporting (e.g., FinCEN for US money transmission)?

### 2. Design the account taxonomy

Group accounts by type (GAAP):

| Type | What it represents | Examples |
|---|---|---|
| Asset | What the business owns | bank_account, payment_processor_balance, accounts_receivable |
| Liability | What the business owes | customer_wallet, merchant_escrow, refunds_pending |
| Revenue | Money earned | platform_fees_earned, subscription_revenue |
| Expense | Money spent | provider_fees, refund_provider_fees, chargeback_losses |
| Equity | Owner's stake | retained_earnings (less common) |

For a marketplace example:

```
ASSETS:
  payment_processor_balance     -- money in Stripe
  bank_account                  -- money in our bank
  fx_holdings_usd               -- multi-currency holdings
  fx_holdings_eur

LIABILITIES:
  customer_pending              -- received but not allocated
  merchant_escrow               -- owed to merchants
  refunds_pending               -- promised refunds not yet executed
  tax_payable                   -- taxes withheld, not remitted

REVENUE:
  platform_fees_earned          -- our cut on each transaction
  fx_spread_earned              -- markup on currency conversion

EXPENSE:
  provider_fees                 -- Stripe, Plaid, etc.
  chargeback_losses             -- lost disputes
```

### 3. Design the event taxonomy

For each event type, name the entry pattern. Example:

```
EVENT: order_paid (customer pays $100, merchant gets $95, platform takes $5)

  ENTRIES (must balance):
    payment_processor_balance  DEBIT  10000  USD
    merchant_escrow            CREDIT  9500  USD
    platform_fees_earned       CREDIT   500  USD
```

```
EVENT: payout_to_merchant (we wire $9500 to merchant from escrow)

  ENTRIES:
    merchant_escrow            DEBIT   9500  USD
    bank_account               CREDIT  9500  USD
```

```
EVENT: refund_issued (customer gets $100 back; provider charges us $5 fee)

  ENTRIES:
    customer_pending           DEBIT  10000  USD  (we owed this)
    payment_processor_balance  CREDIT 10000  USD  (Stripe returned)
    refund_provider_fees       DEBIT    500  USD  (we paid the fee)
    bank_account               CREDIT   500  USD
```

For multi-currency:

```
EVENT: fx_conversion (we convert $100 USD to €92 EUR at rate 0.92)

  ENTRIES (per currency, must balance):
    fx_holdings_usd            CREDIT 10000  USD
    fx_holdings_eur            DEBIT   9200  EUR
```

Note: per-currency balance, not cross-currency. The invariant holds for each currency separately.

### 4. Design the schema

```sql
CREATE TABLE ledger_accounts (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  account_type TEXT NOT NULL CHECK (account_type IN ('asset', 'liability', 'revenue', 'expense', 'equity')),
  currency TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE ledger_events (
  id BIGSERIAL PRIMARY KEY,
  event_id UUID NOT NULL UNIQUE,  -- idempotency key from caller
  event_type TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sequence_number BIGINT NOT NULL,
  metadata JSONB
);

CREATE TABLE ledger_entries (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES ledger_events(id),
  account_id BIGINT NOT NULL REFERENCES ledger_accounts(id),
  amount_minor BIGINT NOT NULL,  -- always positive; direction tells which side
  currency TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('debit', 'credit'))
);

CREATE INDEX idx_entries_event ON ledger_entries(event_id);
CREATE INDEX idx_entries_account ON ledger_entries(account_id);
CREATE INDEX idx_events_occurred ON ledger_events(occurred_at);
CREATE INDEX idx_events_type_seq ON ledger_events(event_type, sequence_number);
```

### 5. Enforce the balance invariant

```sql
CREATE OR REPLACE FUNCTION check_event_balanced()
RETURNS TRIGGER AS $$
DECLARE
  imbalances RECORD;
BEGIN
  FOR imbalances IN
    SELECT currency,
           SUM(CASE direction WHEN 'debit' THEN amount_minor ELSE -amount_minor END) AS net
    FROM ledger_entries
    WHERE event_id = NEW.event_id
    GROUP BY currency
  LOOP
    IF imbalances.net != 0 THEN
      RAISE EXCEPTION 'Event % is not balanced for currency % (net: %)',
        NEW.event_id, imbalances.currency, imbalances.net;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_event_balanced
AFTER INSERT ON ledger_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_event_balanced();
```

The `DEFERRABLE INITIALLY DEFERRED` lets you insert all entries within a transaction; the trigger checks balance at commit time.

### 6. Materialize balances

```sql
CREATE MATERIALIZED VIEW account_balances AS
SELECT
  ledger_entries.account_id,
  ledger_accounts.name,
  ledger_entries.currency,
  SUM(CASE direction WHEN 'debit' THEN amount_minor ELSE -amount_minor END) AS balance_minor
FROM ledger_entries
JOIN ledger_accounts ON ledger_accounts.id = ledger_entries.account_id
GROUP BY ledger_entries.account_id, ledger_accounts.name, ledger_entries.currency;

CREATE UNIQUE INDEX ON account_balances (account_id, currency);
```

Refresh strategy:

- Low throughput (< 1k events/day): refresh on cron, every 5 minutes
- Medium throughput (1k - 100k events/day): trigger-maintained incremental updates
- High throughput (> 100k events/day): event-sourcing framework (Kafka + materialized projections in a downstream service)

### 7. Plan reconciliation

For each external source, design the daily comparison:

```
DAILY at 02:00 UTC:
  1. Pull all Stripe charges for the prior day
  2. For each, find the matching ledger event by stripe_charge_id metadata
  3. Compare amount, status, currency
  4. Flag discrepancies:
     - stripe_only: charge exists in Stripe, no matching event (missing webhook)
     - ledger_only: event in ledger, no matching Stripe charge (test data leaked)
     - amount_mismatch: ledger and Stripe disagree on amount
     - status_mismatch: ledger says paid, Stripe says failed
  5. Generate discrepancy report; route to ops team
```

Reconcile against bank statements weekly (depending on availability).

### 8. Handle corrections

```
EVENT: correction (an earlier event was misrecorded)

  Reference the original event in metadata.
  Reverse the original entries via compensating entries.
  Add new entries with the correct amounts.

  The audit trail shows: original + correction. Both immutable. The
  balance is correct as of now; the past is honestly reconstructable.
```

Never `UPDATE` or `DELETE` from `ledger_events` or `ledger_entries`. Compensating events only.

## Output format

1. **Inputs verified** — business model, currencies, throughput, compliance regime
2. **Account taxonomy** — table of accounts with type + currency
3. **Event taxonomy** — table of event types with entry patterns
4. **Schema** — DDL for accounts + events + entries
5. **Invariant trigger** — the balance-check trigger
6. **Balance materialization** — strategy + DDL
7. **Reconciliation plan** — sources + cadence + discrepancy handling
8. **Multi-currency notes** (if applicable) — per-currency invariants, FX events, rounding accounts

## Anti-patterns to flag

- **Single-entry "add to balance" pattern** — structural bug
- **Updating events** — must use compensating events
- **Float for money** — integer minor units always
- **Per-event balance check that doesn't run** — the trigger must be enforced
- **Aggregating multi-currency** without explicit FX event
- **Ledger without reconciliation** — silent drift accumulates
- **Storing card data or PII in metadata** — keep ledger metadata operational (event IDs, transaction IDs); PII belongs elsewhere
- **Using `recorded_at` for ordering** — clock skew + network delays mess this up; use `sequence_number` per event_type

## Real-world defaults

- PostgreSQL 14+ unless higher throughput requires otherwise
- ISO 4217 currency codes
- Integer minor units
- UTC timestamps
- Stripe as the default external system to reconcile against
- Daily reconciliation cadence as baseline

## Trigger

`/ledger <action> [options]`

Double-entry ledger operations: post journal entries, query balances, validate the accounting equation, and close accounting periods.

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
