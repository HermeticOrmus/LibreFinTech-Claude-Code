# Intermediate — production fintech without the disasters

Your feature is live. Now you need to handle chargebacks, fraud attempts, reconciliation drift, multi-currency, FX, partial outages, settlement delays.

## The disasters that catch new fintech ops

### Chargeback wave

A customer disputes. Then 10 customers dispute. Then a card scheme threatens to put you on a watchlist (Visa Threshold Monitoring Program kicks in at 0.65% chargeback rate).

**Prevention**: dispute defense pipeline (collect evidence at transaction time, not after). See `/fraud-detect` plugin for the workflow.

**Mitigation when active**: refund proactively before chargeback fires. Customer service team trained on dispute reasons. Stripe Radar rules tightened temporarily.

### Reconciliation drift

The ledger and Stripe disagree by $0.43 cents. Then $1.20. Then $50. Six weeks later it's $2,000 and no one knows where it came from.

**Prevention**: daily reconciliation from Day 1. Don't accept drift. Investigate every penny.

**Common causes**:
- Timezone mismatch in day boundary
- FX rate timing (authorization vs. settlement)
- Provider fees not recorded as ledger events
- Webhook delivery failures (events Stripe sent, you never received)
- Status mismatches (Stripe shows `succeeded`, ledger shows `processing`)

### Multi-currency disaster

A user with USD wallet checks out in EUR. The conversion happens at one rate; the settlement happens at another. The user gets charged a slightly different amount than displayed. They dispute.

**Prevention**: snapshot the FX rate at authorization. Record the source of the rate. Make the rate visible to the user at checkout. Recompute at settlement and book the difference as `fx_spread_earned` or `fx_rounding`.

**Multi-currency design**: every account is single-currency. FX is its own event. Never aggregate.

### Provider outage

Stripe is down for 4 hours. Or Adyen. Or your bank. Or Plaid.

**Prevention**:
- Multiple payment providers (Stripe primary, Adyen fallback)
- Retry queue with exponential backoff for transient failures
- Status page subscription for all critical providers
- Documented runbook for "Stripe is down" scenario

**Mitigation when active**:
- Customer-facing message ("payments temporarily unavailable, please try again in N minutes")
- Don't auto-retry indefinitely (creates a thundering herd when service returns)
- Reconciliation after the outage to catch dropped webhooks

### Settlement delay

Customer pays. Stripe holds the money. Three days later it's supposed to settle to your bank. It doesn't.

**Causes**: payout schedule (Stripe's default is rolling 2-day; can be longer), KYC hold (Stripe ran a re-verification), reserve held against future chargebacks, manual review.

**Investigation**: Stripe Dashboard → Payouts. Each payout has a status; failed payouts have a reason.

## Read deeper

- [`docs/dispute-defense`](../docs/) — chargeback response evidence packaging
- [`docs/reconciliation-patterns`](../docs/) — daily reconciliation workflows
- [`docs/multi-currency-patterns`](../docs/) — FX, snapshots, rounding accounts
- [`docs/incident-response`](../docs/) — playbooks for provider outages, fraud waves

## What's next

You're shipping reliably. Time to think about scale: SOC 2, PCI audit, multi-region settlement, custom risk models.

## Next: [Advanced](advanced.md)

Compliance, scale, ops.
