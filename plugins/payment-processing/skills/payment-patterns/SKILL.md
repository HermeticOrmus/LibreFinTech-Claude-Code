# Payment Processing Patterns

Domain-specific patterns for payment gateway integration, idempotent payment handling, 3DS2, webhook processing, and payment reconciliation.

## Core Patterns

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
