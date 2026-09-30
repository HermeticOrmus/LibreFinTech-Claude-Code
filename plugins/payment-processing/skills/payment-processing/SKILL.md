---
name: payment-processing
description: "Payments library: idempotency-key patterns, a webhook reliability checklist, Stripe, Adyen, and PayPal quirks, a refund and chargeback decision tree, currency handling, PCI scope reduction, the PaymentIntent state machine, and code for idempotent creation, webhook processing, 3DS2 exemptions, and dunning. Use when building or debugging payment flows."
---

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

## Core Patterns

Domain-specific patterns for payment gateway integration, idempotent payment handling, 3DS2, webhook processing, and payment reconciliation.

### Pattern: Idempotent Payment Creation

```typescript
// Every charge creation must have an idempotency key
// Key must be deterministic from the business operation - not random
// Random key = if client retries with new random key, you get two charges

function generatePaymentIdempotencyKey(orderId: string, attempt: number = 0): string {
  // Include order ID (makes it deterministic per order)
  // Include attempt number if you want to allow intentional retries
  return `order-${orderId}-attempt-${attempt}`;
}

// Store idempotency result to handle within-application deduplication
interface IdempotencyRecord {
  key: string;
  requestHash: string;   // Hash of the request body
  responseStatus: number;
  responseBody: string;
  createdAt: Date;
  expiresAt: Date;       // After this, key is no longer valid (Stripe: 24h)
}

async function createPaymentWithIdempotency(
  params: PaymentParams,
  idempotencyKey: string
): Promise<PaymentResult> {
  // Check if we've already processed this key
  const existing = await db.idempotencyRecord.findUnique({ where: { key: idempotencyKey } });
  if (existing) {
    return JSON.parse(existing.responseBody); // Return cached result
  }

  const result = await stripe.paymentIntents.create(params, { idempotencyKey });

  await db.idempotencyRecord.create({
    data: {
      key: idempotencyKey,
      requestHash: hashObject(params),
      responseStatus: 200,
      responseBody: JSON.stringify(result),
      createdAt: new Date(),
      expiresAt: addHours(new Date(), 24),
    },
  });

  return result;
}
```

### Pattern: Webhook Event Processing with Idempotency

```typescript
// Stripe sends webhooks; events can be delivered more than once
app.post('/webhooks/stripe', express.raw({ type: 'application/json' }), async (req, res) => {
  // 1. Verify signature FIRST with raw body (before any parsing)
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(
      req.body,                           // MUST be raw Buffer, not parsed JSON
      req.headers['stripe-signature']!,
      process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  // 2. Acknowledge immediately - don't hold up Stripe's delivery
  res.sendStatus(200);

  // 3. Deduplicate: check if we've already processed this event
  const processed = await db.webhookEvent.findUnique({ where: { stripeEventId: event.id } });
  if (processed) return; // Idempotent - already handled

  // 4. Store event before processing (in case processing crashes)
  await db.webhookEvent.create({
    data: {
      stripeEventId: event.id,
      type: event.type,
      payload: JSON.stringify(event),
      processedAt: null,
    },
  });

  // 5. Process asynchronously via queue (don't process inline)
  await queue.enqueue('process-stripe-event', { eventId: event.id });
});

// Webhook event processor (runs from queue)
async function processStripeEvent(eventId: string): Promise<void> {
  const record = await db.webhookEvent.findUnique({ where: { stripeEventId: eventId } });
  const event = JSON.parse(record.payload) as Stripe.Event;

  switch (event.type) {
    case 'payment_intent.succeeded':
      await fulfillOrder((event.data.object as Stripe.PaymentIntent).metadata.orderId);
      break;

    case 'charge.dispute.created':
      await alertDisputeTeam((event.data.object as Stripe.Dispute).id);
      break;

    case 'invoice.payment_failed':
      await triggerDunning((event.data.object as Stripe.Invoice).subscription as string);
      break;
  }

  await db.webhookEvent.update({
    where: { stripeEventId: eventId },
    data: { processedAt: new Date() },
  });
}
```

### Pattern: 3DS2 with SCA Exemption Handling

```typescript
// Stripe PaymentIntents handles 3DS2 automatically when you use PaymentElement
// For recurring charges (MIT), pass prior transaction reference

// Initial subscription charge (SCA required)
const setupIntent = await stripe.setupIntents.create({
  customer: customerId,
  payment_method_types: ['card'],
  usage: 'off_session',  // Signals this will be used for MIT
  metadata: { subscriptionId },
});

// After user confirms setup intent and card is verified...
// Store: setupIntent.payment_method

// Subsequent MIT charges (no user present)
const recurringPayment = await stripe.paymentIntents.create({
  amount: subscriptionAmount,
  currency: 'usd',
  customer: customerId,
  payment_method: storedPaymentMethodId,
  off_session: true,   // MIT - no user present
  confirm: true,
  // Stripe includes the MIT exemption and network transaction reference automatically
}, { idempotencyKey: `sub-${subscriptionId}-${billingPeriod}` });
```

### Pattern: Dunning for Failed Recurring Charges

```typescript
const DUNNING_SCHEDULE_DAYS = [1, 3, 7, 14]; // Days to retry after initial failure

async function handleFailedRecurringCharge(subscriptionId: string): Promise<void> {
  const subscription = await db.subscription.findUnique({
    where: { id: subscriptionId },
    include: { dunningState: true },
  });

  const attemptNumber = subscription.dunningState?.attemptCount ?? 0;

  if (attemptNumber >= DUNNING_SCHEDULE_DAYS.length) {
    // Exhausted all retries - cancel subscription
    await cancelSubscriptionForNonPayment(subscriptionId);
    await sendFinalCancellationEmail(subscription.userId);
    return;
  }

  const retryDate = addDays(new Date(), DUNNING_SCHEDULE_DAYS[attemptNumber]);

  await db.dunningState.upsert({
    where: { subscriptionId },
    create: { subscriptionId, attemptCount: 1, nextRetryAt: retryDate },
    update: { attemptCount: { increment: 1 }, nextRetryAt: retryDate },
  });

  await sendPaymentFailedEmail(subscription.userId, { retryDate, attemptNumber });
  await scheduleJob('retry-payment', { subscriptionId }, { runAt: retryDate });
}
```

## Anti-Patterns

### Anti-Pattern: Fulfilling Order from Frontend Redirect

```typescript
// WRONG: Rely on frontend redirect to fulfill order
// The user can close the browser before the redirect completes
// Or the redirect URL can be manipulated
app.get('/payment/success', async (req, res) => {
  const { payment_intent } = req.query;
  await fulfillOrder(payment_intent); // Unreliable! Can be missed or forged
});

// RIGHT: Fulfill from webhook only
// The frontend redirect just shows success UI
// Fulfillment happens when 'payment_intent.succeeded' webhook is received
app.get('/payment/success', async (req, res) => {
  res.json({ status: 'pending', message: 'Order will be confirmed shortly' });
  // Actual fulfillment happens via webhook
});
```

### Anti-Pattern: No Webhook Signature Verification

```typescript
// WRONG: Trust webhook payload without signature verification
app.post('/webhooks/stripe', async (req, res) => {
  const event = req.body; // Anyone can POST fake events to this endpoint
  await fulfillOrder(event.data.object.metadata.orderId);
});
```

### Anti-Pattern: Synchronous Payment Processing in Request Handler

Long-running payment operations (settlement, complex routing) should not run synchronously in a web request handler. Use a job queue. This prevents timeouts, allows retries, and enables observability.

## References

- **Stripe PaymentIntents**: https://stripe.com/docs/payments/payment-intents
- **Stripe Webhooks**: https://stripe.com/docs/webhooks
- **Adyen API Reference**: https://docs.adyen.com/api-explorer/
- **EMVCo 3DS2**: https://www.emvco.com/emv-technologies/3-d-secure/
- **PCI DSS**: https://www.pcisecuritystandards.org/
- **SCA Exemptions (RTS Article 10-18)**: https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=OJ:L:2018:069:FULL
- **Stripe Radar (Fraud)**: https://stripe.com/radar

---

## Cross-references

- [`ledger-design`](../ledger-design/) — for persisting payment events
- [`fraud-detection`](../fraud-detection/) — for pre-payment screening
- [`reconciliation`](../reconciliation/) — for daily balance verification
- [`regulatory-compliance`](../regulatory-compliance/) — for PCI DSS, PSD2, SCA
- [`financial-security`](../financial-security/) — for PCI scope + encryption
