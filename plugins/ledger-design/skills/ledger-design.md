# Ledger design pattern library

Reference patterns for financial ledger systems.

## Double-entry rules

For every event:

1. At least two entries
2. Sum of debits = sum of credits (per currency)
3. Entries are atomic with the event (single transaction)
4. The invariant is enforced by a database constraint or trigger, not application code

## Account-type rules

| Type | Debit means | Credit means |
|---|---|---|
| Asset | Increase | Decrease |
| Liability | Decrease | Increase |
| Revenue | Decrease | Increase |
| Expense | Increase | Decrease |
| Equity | Decrease | Increase |

(For asset and expense accounts, debit increases. For liability, revenue, and equity, credit increases. Memorize via DEAD-CLIC mnemonic or accept the convention.)

## Event patterns

### Pattern: customer payment splits across accounts

Customer pays $100. Platform takes $5, merchant gets $95.

```
DEBIT  payment_processor_balance  10000 USD
CREDIT merchant_escrow             9500 USD
CREDIT platform_fees_earned         500 USD
```

### Pattern: payout

Platform wires $9500 to merchant.

```
DEBIT  merchant_escrow  9500 USD
CREDIT bank_account     9500 USD
```

### Pattern: refund

Customer gets $100 back; provider charges $5 fee.

```
DEBIT  customer_pending          10000 USD  (we owed customer this)
CREDIT payment_processor_balance 10000 USD  (Stripe returned the money)
DEBIT  refund_provider_fees        500 USD  (we paid fee)
CREDIT bank_account                500 USD
```

### Pattern: FX conversion

Convert $100 USD to €92 EUR.

```
CREDIT fx_holdings_usd 10000 USD
DEBIT  fx_holdings_eur  9200 EUR
```

Note: per-currency balance. USD nets to -10000 within USD; EUR nets to +9200 within EUR. Each currency balances independently.

### Pattern: rounding remainder

A split that doesn't divide evenly: $10 / 3 = $3.33 + $3.33 + $3.34.

```
DEBIT  cash         1000 USD
CREDIT account_a    333 USD
CREDIT account_b    333 USD
CREDIT account_c    334 USD  (gets the extra cent)
```

Or use a `rounding_remainder` account:

```
DEBIT  cash               1000 USD
CREDIT account_a           333 USD
CREDIT account_b           333 USD
CREDIT account_c           333 USD
CREDIT rounding_remainder    1 USD  (absorbs the extra cent)
```

Pick a convention and apply consistently.

## Immutability patterns

### NEVER

- `UPDATE ledger_events SET ...`
- `UPDATE ledger_entries SET ...`
- `DELETE FROM ledger_events ...`
- `DELETE FROM ledger_entries ...`

### ALWAYS (for corrections)

```python
# Original was wrong; create a compensating event
correction_event = create_event(
    event_type='correction',
    metadata={'corrects': original_event_id, 'reason': 'amount misrecorded'},
)

# Reverse the original entries
for original_entry in original_event.entries:
    create_entry(
        event_id=correction_event.id,
        account=original_entry.account,
        amount_minor=original_entry.amount_minor,
        currency=original_entry.currency,
        direction='credit' if original_entry.direction == 'debit' else 'debit',  # reverse
    )

# Add the correct entries
create_entry(event_id=correction_event.id, account='...', amount_minor=...)
```

The audit trail shows the original + correction. Both are immutable.

## Materialization strategies

### Periodic refresh (low throughput)

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY account_balances;
```

Run on cron (e.g., every 5 minutes). Stale balances OK for the refresh interval.

### Trigger-maintained (medium throughput)

```sql
CREATE OR REPLACE FUNCTION update_balance_on_entry()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO account_balances (account_id, currency, balance_minor)
  VALUES (NEW.account_id, NEW.currency,
          CASE NEW.direction WHEN 'debit' THEN NEW.amount_minor ELSE -NEW.amount_minor END)
  ON CONFLICT (account_id, currency) DO UPDATE
    SET balance_minor = account_balances.balance_minor + EXCLUDED.balance_minor;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

Real-time balances, slight write amplification.

### Event-sourcing framework (high throughput)

Kafka + a downstream service that consumes events and maintains balances in a separate read store. Scales horizontally; introduces eventual consistency.

## Multi-currency handling

### Account-level

Every account is single-currency. A "wallet" with USD and EUR is two accounts: `wallet_usd` and `wallet_eur`.

### Conversion events

```
EVENT: fx_conversion
  metadata: { rate: 1.0875, source: 'stripe_treasury_at_2026-05-23T14:00:00Z' }

ENTRIES:
  CREDIT fx_holdings_usd  10000 USD
  DEBIT  fx_holdings_eur   9195 EUR  (rounding to integer cents)
  DEBIT  fx_spread_earned    87 USD  (our markup; could be in fx_rounding instead)
```

Always snapshot the rate. The bank's rate at settlement may differ; reconcile both.

### Rounding accounts

```
fx_rounding_usd
fx_rounding_eur
fx_rounding_jpy
```

When a conversion produces fractional minor units, the rounding lands here. Reconciled monthly against actual FX provider statements.

## Reconciliation cadence

| Source | Recommended cadence |
|---|---|
| Stripe / Adyen / payment processor | Daily |
| Bank statements | Weekly (depends on availability) |
| Internal cash forecasts | Monthly |
| Regulatory reporting | Per filing cadence (varies by jurisdiction) |

## Common mistakes catalog

### "Balance is off by a small amount"

Almost always rounding. Check:

- Float arithmetic anywhere in the math
- FX conversions with no rounding account
- Tax calculations that don't sum correctly
- Promotional discounts that produce fractional cents

Find the rounding-loss accumulator and balance it.

### "Audit can't trace a transaction"

Likely: the event ID is missing or the metadata doesn't link to the originating transaction. Every ledger event should carry the originating transaction ID (Stripe charge ID, bank transfer ID, etc.) in metadata.

### "Balance ≠ external source"

Reconcile. Common causes:

- Missing webhook (event never created)
- Timezone (your day boundary ≠ their day boundary)
- Status mismatch (you recorded `succeeded`, they show `pending`)
- FX rate timing (you recorded at authorization, settlement was at a different rate)

### "Performance degraded over time"

Likely: balance computation is doing a full scan. Solutions:

- Materialized view with incremental refresh
- Periodic snapshot tables (every account, every quarter; deltas in between)
- Partition the events table by time

### "Couldn't undo a mistake"

The mistake is permanent (event immutability). The correction is a compensating event. The "undo" is a new event that reverses the prior. Audit trail intact.

## Cross-references

- [`payment-processing`](../payment-processing/) — events that feed the ledger
- [`reconciliation`](../reconciliation/) — external comparison patterns
- [`financial-reporting`](../financial-reporting/) — analytical layer on top of the ledger
- [`audit-trails`](../audit-trails/) — for regulatory audit requirements
- [`regulatory-compliance`](../regulatory-compliance/) — for compliance-specific ledger requirements
