# Quick start

Thirty minutes from clone to "idempotent payment endpoint with proper Stripe integration."

## What you'll build

A minimal payment endpoint that:
- Accepts payment intents from a marketplace frontend
- Generates idempotency keys per attempt
- Handles 3DS challenge flow
- Persists state to a ledger on success
- Survives webhook out-of-order delivery
- Reconciles against Stripe at end-of-day

This is the smallest end-to-end payment flow that wouldn't embarrass you in production. We're not building a full marketplace; we're proving the core patterns.

## Prerequisites

- A Stripe test account (free at stripe.com)
- Node.js 18+ or Python 3.11+ (examples below in TypeScript; Python equivalent in `examples/python/`)
- PostgreSQL 14+ for the ledger
- Claude Code installed
- LibreFinTech plugins installed (see below)

## 1. Install plugins

```bash
git clone https://github.com/HermeticOrmus/LibreFinTech-Claude-Code.git ~/projects/LibreFinTech-Claude-Code
cd ~/projects/LibreFinTech-Claude-Code
./setup.sh
```

Restart Claude Code so it picks up the plugins.

## 2. Open Claude Code at your project root

```bash
mkdir ~/projects/payments-demo && cd ~/projects/payments-demo
git init
```

## 3. Design the payment flow

```
/payments design an idempotent payment endpoint. POST /pay with {amount, currency, customerId, idempotencyKey}. Creates Stripe PaymentIntent. Returns clientSecret. Webhook persists status to local ledger. Survives webhook out-of-order delivery.
```

Expected response includes:

- An idempotency key strategy (UUIDv4 from client OR (customerId, intent, idempotencyKey) tuple)
- Stripe PaymentIntent creation with the idempotency-key header
- The webhook design with signature verification + idempotency on incoming events
- The ledger schema (events table, immutable, append-only)
- The reconciliation pattern (event ordering)
- An explicit note that the system handles webhook out-of-order delivery via versioned events, not by trusting webhook timestamps

If the response doesn't mention idempotency-key headers or out-of-order webhook handling, the plugin isn't installed correctly.

## 4. Design the ledger schema

```
/ledger design a double-entry ledger to support the payment endpoint. Events: payment_initiated, payment_authorized, payment_captured, payment_failed, payment_refunded. Show the balance invariant and how it's enforced.
```

Expected response includes:

- An `events` table (immutable, append-only)
- A `balances` view (derived from events; the materialized version)
- The double-entry invariant: every event is a pair (debit one account, credit another)
- The accounts: customer_pending, customer_authorized, processor_holding, merchant_settled, refunds_pending
- A test that the sum of all debits equals the sum of all credits (the integrity check)

## 5. Build the API

```
/payments write the Express + TypeScript implementation. Use Stripe SDK. Persist events to Postgres via the ledger design from step 4. Include the webhook handler.
```

You should get:

- `POST /pay` endpoint with idempotency-key header support
- Webhook endpoint with Stripe signature verification
- Event persistence using the ledger schema
- A `GET /balance/:customerId` endpoint reading from the materialized balances view

Implement, run locally with Stripe CLI for webhooks:

```bash
stripe listen --forward-to localhost:3000/webhooks/stripe
```

## 6. Test the failure modes

This is where fintech systems usually fail. Test:

**6.1. Idempotency**

```bash
# Call /pay twice with the same idempotencyKey
curl -X POST localhost:3000/pay -d '{"amount": 1000, "currency": "usd", "customerId": "c_1", "idempotencyKey": "key_1"}'
curl -X POST localhost:3000/pay -d '{"amount": 1000, "currency": "usd", "customerId": "c_1", "idempotencyKey": "key_1"}'
```

Both should return the same PaymentIntent (Stripe enforces this via the idempotency-key header). The ledger should have exactly ONE `payment_initiated` event for that key.

**6.2. Webhook delivered twice**

Stripe sometimes retries webhooks. Simulate by manually re-sending the webhook event from Stripe Dashboard. The ledger should not double-record.

**6.3. Webhook arrives out of order**

If `payment_captured` arrives before `payment_authorized`, the system should handle it. Test by replaying webhook events in reverse order.

```
/fraud-detect what fraud signals should the payment endpoint check before creating the PaymentIntent? List 5 with the rationale + the implementation.
```

Expected: velocity check, device fingerprint, geolocation mismatch, BIN check, payment method age. Each with a specific implementation approach (Stripe Radar pre-built, or custom rule layer).

## 7. Reconcile at end-of-day

```
/reconcile design end-of-day reconciliation. Pull Stripe's `charges` list for the day. Compare to ledger events. Flag discrepancies.
```

Expected:
- Fetch all Stripe charges for the day via the API
- For each, find the matching ledger event by `charge_id`
- Report: matched, ledger-only (something the API call lost), Stripe-only (webhook never arrived)
- Don't auto-resolve discrepancies; flag for human review

## 8. What you've built in 30 minutes

You have:
- An idempotent payment endpoint
- A webhook handler that survives retries + out-of-order delivery
- A double-entry ledger that tracks money correctly
- A reconciliation report

This is the minimum-viable payment system. It's not feature-complete — refunds, partial refunds, chargebacks, multi-currency, FX, escrow are all separate plugins (see `/refund`, `/chargeback`, `/pricing`).

## What's next

- **[Beginner path](learning-paths/beginner.md)** — foundational mindset shifts for fintech
- **[Intermediate path](learning-paths/intermediate.md)** — chargebacks, reconciliation, multi-currency
- **[Advanced path](learning-paths/advanced.md)** — SOC 2, PCI DSS, multi-region, live-ops

## Common gotchas

1. **Webhook signature not verified** — Stripe webhook signatures must be checked; without verification, anyone can POST fake events
2. **Idempotency key reused for different intents** — same key + different amount = Stripe returns the original; this is intentional but surprising
3. **Storing card data** — never store raw PAN, CVV, full card number; use Stripe's PaymentMethod tokens
4. **Time zones in reconciliation** — Stripe's "day" boundary != yours; agree on a UTC convention
5. **Rounding** — use integer minor units (cents), never floats; multi-currency adds complexity (zero-decimal currencies like JPY)
