# /payments

Payment processing workflows: charge creation, refunds, dispute management, and payment reporting.

## Trigger

`/payments <action> [options]`

## Actions

- `charge` - Create a new payment charge or payment intent
- `refund` - Process a full or partial refund
- `dispute` - Manage chargeback dispute with evidence submission
- `report` - Generate payment reconciliation report

## Options

- `--provider <stripe|adyen|braintree>` - Payment provider
- `--payment-id <id>` - Existing payment/intent to operate on
- `--amount <integer>` - Amount in minor units (cents, pence)
- `--currency <ISO4217>` - Currency code
- `--idempotency-key <key>` - Idempotency key for safe retry
- `--capture-method <automatic|manual>` - Auto or manual capture

## Process

### charge

Stripe PaymentIntent flow with 3DS2 and SCA:

```typescript
import Stripe from 'stripe';
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

// Step 1: Create PaymentIntent on your server
async function createPaymentIntent(
  amount: number,          // In cents
  currency: string,        // 'usd', 'gbp', etc.
  customerId: string,
  idempotencyKey: string   // REQUIRED - prevents double charge on retry
): Promise<Stripe.PaymentIntent> {
  return stripe.paymentIntents.create({
    amount,
    currency,
    customer: customerId,
    payment_method_types: ['card'],
    capture_method: 'automatic',

    // 3DS2 / SCA configuration
    // Stripe handles SCA natively with PaymentIntents
    // Use PaymentElement on frontend for best SCA handling

    // Metadata for reconciliation
    metadata: {
      orderId: generateOrderId(),
      customerId,
    },

    // For EU/UK: provide shipping data to improve 3DS2 exemption rate
    shipping: {
      name: customerName,
      address: { country: 'GB', postal_code: 'SW1A 1AA', /* ... */ },
    },
  }, {
    idempotencyKey,  // Stripe uses this header to deduplicate
  });
}

// Step 2: Client-side - Stripe PaymentElement handles 3DS2 challenge if needed
// stripe.confirmPayment({ elements, confirmParams: { return_url: '...' } })

// Step 3: Handle webhook for async confirmation
// Don't rely on frontend redirect for order fulfillment - use webhook
```

Payment state machine:
```
PaymentIntent created (requires_payment_method)
         |
         | Customer provides payment method
         v
requires_action (3DS2 challenge needed)
  OR     |
confirmed (frictionless / no SCA)
         |
         v
succeeded → Trigger fulfillment (via webhook, not redirect)
   OR
requires_capture (manual capture mode)
   OR
canceled
```

### refund

```typescript
// Full refund
const refund = await stripe.refunds.create({
  payment_intent: paymentIntentId,
  // amount: omitted = full refund
  reason: 'requested_by_customer',
  metadata: { refundRequestId, agentId },
}, { idempotencyKey: `refund-${paymentIntentId}-${refundRequestId}` });

// Partial refund
const partialRefund = await stripe.refunds.create({
  payment_intent: paymentIntentId,
  amount: 500,  // Refund $5.00 of a larger charge
  reason: 'fraudulent',
});
```

### dispute

Chargeback evidence submission:

```typescript
// Respond to a dispute with evidence
// Stripe evidence object varies by reason code
const disputeEvidence: Stripe.DisputeUpdateParams = {
  evidence: {
    // For 'credit_not_processed' disputes:
    refund_policy: 'https://example.com/returns',
    refund_policy_disclosure: 'Customer agreed to no-refund policy at checkout',
    refund_refusal_explanation: 'Service was delivered per contract terms',

    // General evidence:
    customer_name: 'John Smith',
    customer_email_address: 'john@example.com',
    customer_ip_address: '1.2.3.4',
    customer_signature: signedTermsFileId,  // Uploaded file ID
    receipt: receiptFileId,                  // Proof of delivery/service

    // Billing descriptor match
    billing_address: '123 Main St, New York, NY 10001',
    service_date: '2024-11-01',
    service_documentation: serviceLogFileId,
  },
  submit: true,  // Submit immediately (set to false to save draft first)
};

await stripe.disputes.update(disputeId, disputeEvidence);
// IMPORTANT: You typically have 7-20 days to respond depending on network/reason code
```

### report

Payment reconciliation - match Stripe payouts to your ledger:

```typescript
// Fetch all Stripe balance transactions for the payout period
async function fetchPayoutTransactions(payoutId: string): Promise<Stripe.BalanceTransaction[]> {
  const transactions: Stripe.BalanceTransaction[] = [];

  for await (const transaction of stripe.balanceTransactions.list({
    payout: payoutId,
    limit: 100,
  })) {
    transactions.push(transaction);
  }

  return transactions;
}

// Each balance transaction has:
// - type: 'charge', 'refund', 'dispute', 'dispute_reversal', 'stripe_fee'
// - amount: in minor units
// - fee: Stripe's processing fee
// - net: amount - fee (what actually hits your bank account)
// - description: human-readable
// - source: ID of the underlying charge/refund

// Match against your internal orders/ledger
async function reconcilePayoutTransactions(transactions: Stripe.BalanceTransaction[]): Promise<void> {
  for (const tx of transactions) {
    const internalRecord = await db.payment.findByStripeId(tx.source as string);
    if (!internalRecord) {
      await reportMismatch({ stripeId: tx.source, reason: 'No matching internal record' });
      continue;
    }
    if (internalRecord.amount !== tx.amount) {
      await reportMismatch({ stripeId: tx.source, reason: `Amount mismatch: internal=${internalRecord.amount} stripe=${tx.amount}` });
    }
  }
}
```

## Examples

```bash
# Create a $99.00 charge with automatic capture
/payments charge --provider stripe --amount 9900 --currency usd

# Process full refund on a payment
/payments refund --provider stripe --payment-id pi_xxx

# Submit chargeback dispute evidence
/payments dispute --provider stripe --payment-id pi_xxx

# Generate monthly payment reconciliation report
/payments report --provider stripe
```
