# Ledger Patterns

Domain-specific patterns for double-entry ledger design, journal entry management, balance calculation, multi-currency accounting, and period-close procedures.

## Core Patterns

### Pattern: Immutable Journal Entry Schema

```sql
-- Core ledger schema with proper constraints
-- All amounts in NUMERIC(38,10) - NEVER FLOAT
CREATE TABLE journal_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_number    TEXT NOT NULL UNIQUE,
    period          TEXT NOT NULL,                  -- 'YYYY-MM'
    entry_date      DATE NOT NULL,
    entity_id       TEXT NOT NULL,
    description     TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'DRAFT',
    source          TEXT NOT NULL,
    correlation_id  TEXT,

    -- Immutability enforcement
    CONSTRAINT valid_status CHECK (status IN ('DRAFT', 'POSTED', 'REVERSED')),
    -- Cannot delete posted entries (enforced by policy + trigger)
);

CREATE TABLE journal_entry_lines (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_entry_id  UUID NOT NULL REFERENCES journal_entries(id),
    account_id        UUID NOT NULL REFERENCES accounts(id),
    debit_credit      CHAR(1) NOT NULL CHECK (debit_credit IN ('D', 'C')),
    amount            NUMERIC(38, 10) NOT NULL CHECK (amount > 0),
    currency          CHAR(3) NOT NULL,
    fx_rate           NUMERIC(20, 10) NOT NULL DEFAULT 1,
    functional_amount NUMERIC(38, 10) NOT NULL,   -- = amount * fx_rate
    line_number       SMALLINT NOT NULL
);

-- Prevent modification of posted entries
CREATE RULE no_update_posted AS ON UPDATE TO journal_entries
    WHERE OLD.status = 'POSTED'
    DO INSTEAD NOTHING;

CREATE RULE no_delete_posted AS ON DELETE TO journal_entries
    WHERE OLD.status = 'POSTED'
    DO INSTEAD NOTHING;
```

### Pattern: Compensating Transaction for Corrections

```typescript
// WRONG: Modifying a posted entry
await db.journalEntryLine.update({
  where: { id: errorLineId },
  data: { amount: correctedAmount }
});

// RIGHT: Reverse the original, post a correct replacement
async function correctJournalEntry(
  originalEntryId: string,
  correctionLines: JournalEntryLine[],
  correctionReason: string,
  correctedBy: string
): Promise<{ reversalEntry: JournalEntry; correctionEntry: JournalEntry }> {
  const original = await db.journalEntry.findUnique({
    where: { id: originalEntryId, status: 'POSTED' },
    include: { lines: true },
  });

  // Step 1: Create reversal (all debits/credits flipped)
  const reversalEntry = await db.journalEntry.create({
    data: {
      entryNumber: generateEntryNumber('REV'),
      period: original.period,
      entryDate: new Date(),
      entityId: original.entityId,
      description: `REVERSAL of ${original.entryNumber}: ${correctionReason}`,
      source: 'CORRECTION',
      correlationId: original.correlationId,
      status: 'POSTED',
      postedBy: correctedBy,
      postedAt: new Date(),
      lines: {
        create: original.lines.map(line => ({
          accountId: line.accountId,
          debitCredit: line.debitCredit === 'D' ? 'C' : 'D',  // Flip
          amount: line.amount,
          currency: line.currency,
          functionalAmount: line.functionalAmount,
          lineNumber: line.lineNumber,
          memo: `Reversal of line ${line.lineNumber}`,
        })),
      },
    },
  });

  // Step 2: Post corrected entry
  const correctionEntry = await postJournalEntry({
    description: `CORRECTION replacing ${original.entryNumber}: ${correctionReason}`,
    source: 'CORRECTION',
    lines: correctionLines,
  });

  // Link original to its reversal for audit trail
  await db.journalEntry.update({
    where: { id: originalEntryId },
    data: { reversedById: reversalEntry.id, status: 'REVERSED' },
  });

  return { reversalEntry, correctionEntry };
}
```

### Pattern: Materialized Balance with Optimistic Locking

For high-frequency accounts (e.g., operating accounts with thousands of daily postings), calculating from journal entries for every balance query is too slow. Use materialized balances with optimistic locking.

```sql
CREATE TABLE account_balances (
    account_id    UUID REFERENCES accounts(id),
    period        TEXT NOT NULL,         -- 'YYYY-MM'
    currency      CHAR(3) NOT NULL,
    balance       NUMERIC(38, 10) NOT NULL DEFAULT 0,
    version       INTEGER NOT NULL DEFAULT 0,  -- For optimistic locking
    last_posted_entry_id UUID,
    updated_at    TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (account_id, period, currency)
);

-- Atomic balance update using version check (optimistic locking)
UPDATE account_balances
SET
    balance = balance + :delta,
    version = version + 1,
    last_posted_entry_id = :entry_id,
    updated_at = now()
WHERE account_id = :account_id
  AND period = :period
  AND currency = :currency
  AND version = :expected_version;
-- If 0 rows updated: concurrent modification detected, retry
```

### Pattern: Multi-Currency Journal Entry

```typescript
// Every journal line carries its native currency and the FX rate to functional currency
async function postMultiCurrencyEntry(
  functionalCurrency: string,
  lines: Array<{
    accountCode: string;
    debitCredit: 'D' | 'C';
    amount: Decimal;
    currency: string;
    fxRateDate: Date;
  }>
): Promise<JournalEntry> {
  const linesWithFX = await Promise.all(lines.map(async line => {
    const fxRate = line.currency === functionalCurrency
      ? new Decimal(1)
      : await fxRateService.getRate({
          from: line.currency,
          to: functionalCurrency,
          date: line.fxRateDate,
          rateType: 'CLOSING',
        });

    return {
      ...line,
      fxRate,
      functionalAmount: line.amount.mul(fxRate),
    };
  }));

  // Validate that functional currency amounts balance
  const debitTotal = linesWithFX
    .filter(l => l.debitCredit === 'D')
    .reduce((sum, l) => sum.plus(l.functionalAmount), new Decimal(0));
  const creditTotal = linesWithFX
    .filter(l => l.debitCredit === 'C')
    .reduce((sum, l) => sum.plus(l.functionalAmount), new Decimal(0));

  if (!debitTotal.eq(creditTotal)) {
    throw new Error(`Entry does not balance in functional currency: D=${debitTotal} C=${creditTotal}`);
  }

  return db.journalEntry.create({ data: { lines: { create: linesWithFX } } });
}
```

## Anti-Patterns

### Anti-Pattern: Using FLOAT for Monetary Amounts

```sql
-- WRONG: FLOAT causes binary floating-point rounding errors
CREATE TABLE account_balances (
    balance FLOAT NOT NULL  -- 0.1 + 0.2 = 0.30000000000000004
);

-- RIGHT: NUMERIC preserves exact decimal arithmetic
CREATE TABLE account_balances (
    balance NUMERIC(38, 10) NOT NULL  -- Exact; no rounding error
);
```

### Anti-Pattern: Storing Balance Without Journal (No Audit Trail)

```typescript
// WRONG: Just update the balance field
await db.account.update({
  where: { id: accountId },
  data: { balance: newBalance },  // Where did the change come from? Why?
});

// RIGHT: Post journal entry; balance is always derivable from entries
await postJournalEntry({
  description: reason,
  lines: [
    { accountCode: accountCode, debitCredit: 'D', amount, currency },
    { accountCode: offsetAccountCode, debitCredit: 'C', amount, currency },
  ],
});
```

### Anti-Pattern: Mutable Posted Transactions

No UPDATE or DELETE on posted journal entries. Ever. If this means you can't use an ORM that auto-applies updates, restrict the database user's permissions directly at the database level.

### Anti-Pattern: Mixing Business Logic and Period Control in Application Code

Period locking (preventing posting to closed periods) must be enforced at the database level. Application-level checks can be bypassed by direct database access, background jobs, or migration scripts. Use database constraints or triggers.

## References

- **FASB COA Guidance**: https://asc.fasb.org/
- **Double-Entry Bookkeeping (Pacioli)**: Original description in Summa de Arithmetica (1494)
- **Martin Fowler - Accounting Patterns**: https://martinfowler.com/apsupp/accounting.pdf
- **ISO 4217 Currency Codes**: https://www.iso.org/iso-4217-currency-codes.html
- **Decimal.js (JS arbitrary precision)**: https://mikemcl.github.io/decimal.js/
- **PostgreSQL NUMERIC type**: https://www.postgresql.org/docs/current/datatype-numeric.html
