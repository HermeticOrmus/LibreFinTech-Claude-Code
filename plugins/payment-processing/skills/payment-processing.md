# Payment processing pattern library

Reference patterns for payment integrations.

## Idempotency-key patterns

| Pattern | When to use |
|---|---|
| Client-generated UUIDv4 per attempt | Default for most APIs |
| Server-derived (customerId, intent-id, timestamp-bucket) | When client can't generate unique keys |
| Deterministic from request payload hash | Risky — if any field changes, key changes; not idempotent across retries |

Persist the key client-side so retries reuse it. Without persistence, retries generate new keys and bypass idempotency.

## Webhook reliability checklist

- Signature verification BEFORE parsing payload
- Dedupe by event ID, not event type
- Process inside a DB transaction
- Return 2xx only after persistence commits
- Return 5xx on transient failures (provider retries with backoff)
- Don't trust arrival order (use event sequence / version)
- Cap processing time (Stripe times out at 30s; queue async if longer)

## Stripe-specific quirks

- Idempotency-Key header is finite-lifetime (24h). Past that, retries with same key may create new intents.
- Webhook signatures use timestamped HMAC; replay attacks need both signature + recent timestamp
- `charge.succeeded` and `payment_intent.succeeded` are different — for PaymentIntents flow, use the latter
- `requires_action` status often means 3DS challenge needed (not always — bank can require auth without 3DS)
- Refund metadata is separate from charge metadata; set it explicitly on the refund

## Adyen-specific quirks

- Notifications (webhooks) require HMAC signature verification with a different algorithm than Stripe
- Adyen uses `paymentMethod` (with a stored token) where Stripe uses `payment_method`
- Adyen's `Authorisation` event is the equivalent of Stripe's `payment_intent.succeeded`
- 3DS is handled differently — Adyen's `redirectUrl` flow vs. Stripe's `client_secret`

## PayPal-specific quirks

- Webhook events are PayPal-Verification-Status header + IPN (legacy) or Webhook signatures (modern); pick one
- PayPal uses BillingAgreement for recurring; not directly comparable to Stripe Subscriptions
- Disputes go through PayPal's Resolution Center, not the bank chargeback flow

## Refund + chargeback decision tree

```
Customer wants money back. Did they reach you, or their bank?

Reached you → REFUND
  Initiated by merchant via API. Money returns to the customer's
  payment method. Fast (1-3 business days). Merchant chooses
  full vs. partial.

Reached their bank → CHARGEBACK
  Initiated by issuer. Merchant must respond with evidence.
  Money is held during dispute. Merchant can win (chargeback
  reversed) or lose (money goes back to customer + provider fee).
  Slow (15-90 days).
```

For minor issues, offer refund proactively. Chargebacks have fee + reputation cost.

## Currency handling

| Rule | Why |
|---|---|
| Integer minor units always | Floats accumulate rounding error |
| Zero-decimal currencies (JPY, KRW, VND, IDR) are just integers | The API expects raw integer, not divided |
| Provider amounts are in the smallest unit | Stripe's "amount: 100" = $1.00 (US) or ¥100 (JP) |
| Snapshot FX rates at authorization time | The bank may settle at a different rate; ledger must record both |
| Multi-currency requires per-currency balance tracking | Don't aggregate $100 + 100€ |

## PCI scope minimization

| Pattern | PCI scope |
|---|---|
| Stripe Elements client-side, server only sees PaymentMethod tokens | SAQ-A (lightest) |
| Server proxies card data to provider | SAQ-D (full audit) |
| Server stores raw PAN | Full PCI scope (very expensive audit) |
| Server stores CVV/CVC | Forbidden (PCI DSS Requirement 3.2) |

The cleanest design: never let raw card data touch your servers.

## State machine: PaymentIntent (Stripe)

```
requires_payment_method
    ↓ (attach payment method)
requires_confirmation
    ↓ (confirm)
requires_action (3DS challenge)  ←→  requires_payment_method (failed)
    ↓ (challenge complete)
processing
    ↓ (settled)
succeeded                          ←   processing (failure)
                                        ↓
                                   requires_payment_method
```

Webhook events fire at each transition. Persist the state in your ledger.

## Common mistakes catalog

### "Customer charged twice"

Almost always idempotency. Three sub-causes:

1. Client-side: retried without preserving idempotency key
2. Server-side: idempotency check happens AFTER provider call (race window)
3. Webhook-side: same event ID processed twice (no dedupe)

### "Webhook never arrives"

- Webhook URL misconfigured in provider dashboard
- Endpoint returns 5xx → provider gives up after retry-tail
- Signature verification rejects valid webhooks (wrong secret)
- Webhook handler is asynchronous and crashes before returning 200

### "Refund didn't go through"

- Refund window expired (Stripe: 180 days from charge)
- Refund amount > original charge amount
- Original charge wasn't fully captured (auth-only)
- Payment method is invalid (bank closed account)

### "Chargeback lost"

- Dispute response not filed within window (varies: 7-21 days)
- Evidence package incomplete (Stripe expects specific evidence per dispute reason)
- The customer's reason was "fraudulent" — these are hard to win

### "Multi-currency settlement is off"

- FX rate at authorization differs from settlement (banks set their own conversion timing)
- Fees not accounted for (Stripe takes fees in the settlement currency, not source)
- Rounding differences accumulate across many transactions

## Cross-references

- [`ledger-design`](../ledger-design/) — for persisting payment events
- [`fraud-detection`](../fraud-detection/) — for pre-payment screening
- [`reconciliation`](../reconciliation/) — for daily balance verification
- [`regulatory-compliance`](../regulatory-compliance/) — for PCI DSS, PSD2, SCA
- [`financial-security`](../financial-security/) — for PCI scope + encryption
