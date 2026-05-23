# Beginner — your first fintech feature

You've shipped web apps. Now you're building something that handles money. The mindset shifts matter more than the code.

## The 5 mindset shifts

### 1. Idempotency is mandatory

Web app: a retry is "annoying, refresh the page." Fintech: a retry is "you got charged twice."

Every payment-mutating endpoint MUST be idempotent. Without idempotency, retries cause double-charges.

### 2. The provider's response is not the source of truth

The provider says "succeeded" via API. Then the webhook says "failed" 30 seconds later. Then it says "succeeded" again 60 seconds after that. All within the same transaction.

Build for "eventually consistent" not "API call succeeded therefore done."

### 3. Money math is integer math

Floats accumulate rounding errors. Cents (or smaller for crypto), never dollars-and-cents-as-float.

### 4. Audit means everything is traceable

Every dollar that moved through your system has a paper trail. The ledger is the paper trail. Don't skip the ledger.

### 5. Compliance is structural, not bolt-on

PCI scope, KYC, AML — these inform how the system is shaped. Bolting them on after launch is a 6-month migration.

## Walk the QUICK_START

The 30-minute walkthrough in [QUICK_START.md](../QUICK_START.md) covers:

- Idempotent payment endpoint
- Webhook handler with signature verification
- Double-entry ledger
- Reconciliation

Build it once. The patterns transfer to every fintech project.

## Read deeper

- [`docs/payments-101`](../docs/) — payment processing fundamentals
- [`docs/ledger-fundamentals`](../docs/) — double-entry, event sourcing
- [`docs/regulatory-landscape`](../docs/) — what you need to know about PCI, PSD2, AML

## Common gotchas

1. **Forgetting idempotency on the second mutation endpoint** — every POST that modifies state needs it
2. **Logging full request bodies** — they contain idempotency keys + customer IDs; redact
3. **Storing card data "just for now"** — never. PCI scope is contagious
4. **Skipping webhook signature verification** — anyone can POST fake events
5. **Trusting the dashboard as the source of truth** — build your own ledger from Day 1

## Next: [Intermediate](intermediate.md)

When your first feature is live: chargebacks, fraud attempts, reconciliation, multi-currency.
