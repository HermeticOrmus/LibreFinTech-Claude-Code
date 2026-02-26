# Settlement Patterns

Domain-specific patterns for real-time payment settlement, RTGS integration, instant rails, and liquidity management.

## Core Patterns

### Pattern: Idempotent Payment Submission with UETR

```typescript
// UETR (Unique End-to-End Transaction Reference) is the ISO 20022 universal payment ID
// Must be UUID v4. Carried end-to-end. Used for tracking in gpi, correspondent chains.

async function submitPaymentIdempotent(
  paymentId: string,
  instruction: PaymentInstruction,
): Promise<SettlementSubmissionResult> {
  // Check if already submitted (idempotency guard)
  const existing = await db.paymentSubmission.findUnique({
    where: { paymentId },
  });

  if (existing) {
    // Return cached result - do NOT resubmit to RTGS
    // Resubmitting to Fedwire with same content = second wire transfer
    return { uetr: existing.uetr, status: existing.status, idempotent: true };
  }

  // Allocate UETR exactly once per payment
  const uetr = crypto.randomUUID();

  // Persist before submitting to RTGS
  // If submission succeeds but we crash before saving, we'd never know it settled
  await db.paymentSubmission.create({
    data: { paymentId, uetr, status: 'PENDING', submittedAt: new Date() },
  });

  const result = await rtgsGateway.submit(buildPacs008(instruction, uetr));

  await db.paymentSubmission.update({
    where: { paymentId },
    data: { status: 'SUBMITTED', rtgsReference: result.msgId },
  });

  return { uetr, status: 'SUBMITTED' };
}
```

### Pattern: Nostro Reservation with Rollback

```typescript
// Reserve Nostro balance before committing to submission
// Prevents overdraft if multiple payments submit simultaneously

async function reserveAndSubmit(payment: PaymentInstruction): Promise<void> {
  // Optimistic locking on Nostro balance
  const reservation = await db.$transaction(async (tx) => {
    const nostro = await tx.nostroAccount.findFirst({
      where: { currency: payment.currency, valueDate: payment.valueDate },
      // Lock the row for update
    });

    if (!nostro || nostro.availableBalance < payment.amount) {
      throw new InsufficientFundsError(payment.currency, nostro?.availableBalance ?? 0);
    }

    // Reserve the amount
    await tx.nostroAccount.update({
      where: { id: nostro.id },
      data: { availableBalance: { decrement: payment.amount } },
    });

    return await tx.nostroReservation.create({
      data: { paymentId: payment.id, amount: payment.amount, currency: payment.currency },
    });
  });

  try {
    await rtgsGateway.submit(payment);
  } catch (err) {
    // Roll back reservation - payment did not submit
    await db.nostroReservation.delete({ where: { id: reservation.id } });
    await db.nostroAccount.update({
      where: { currency: payment.currency },
      data: { availableBalance: { increment: payment.amount } },
    });
    throw err;
  }
}
```

### Pattern: Payment Queue with Priority Processing

```typescript
// Large-value payment systems queue payments when funds insufficient
// Process queue when: new funds received, batch settlement clears, or gridlock algo runs

enum PaymentPriority {
  URGENT = 1,    // Time-critical (e.g., securities settlement DvP)
  HIGH = 2,      // Same-day deadline
  NORMAL = 3,    // Standard processing
}

async function processPaymentQueue(currency: string): Promise<void> {
  const queuedPayments = await db.payment.findMany({
    where: { status: 'QUEUED', currency },
    orderBy: [
      { priority: 'asc' },          // Priority first
      { valueDate: 'asc' },          // Earliest value date
      { amount: 'desc' },            // Larger amounts (to clear faster)
    ],
  });

  const nostroBalance = await getCurrentNostroBalance(currency);
  let remaining = nostroBalance;

  for (const payment of queuedPayments) {
    if (remaining < payment.amount) {
      // Check if bilateral offset possible with incoming payments
      const offset = await findBilateralOffset(payment);
      if (!offset) continue;  // Skip and try next payment
    }

    await submitPaymentIdempotent(payment.id, payment);
    remaining -= payment.amount;
  }
}
```

### Pattern: Settlement Finality State Machine

```typescript
// Settlement finality is a legal concept, not just a status flag
// Once ACSC (Accepted Settlement Completed) is received from RTGS,
// the payment is IRREVOCABLE. No cancellation possible.

type PaymentStatus =
  | 'CREATED'      // Instruction received
  | 'VALIDATED'    // Schema, sanctions, format checks passed
  | 'QUEUED'       // Awaiting funds or processing window
  | 'SUBMITTED'    // Sent to RTGS, awaiting confirmation
  | 'SETTLED'      // pacs.002 ACSC received - FINAL, irrevocable
  | 'RETURNED'     // pacs.004 received - funds returned after initial settlement
  | 'REJECTED';    // pacs.002 RJCT - not settled

const ALLOWED_TRANSITIONS: Record<PaymentStatus, PaymentStatus[]> = {
  CREATED: ['VALIDATED', 'REJECTED'],
  VALIDATED: ['QUEUED', 'SUBMITTED', 'REJECTED'],
  QUEUED: ['SUBMITTED', 'REJECTED'],
  SUBMITTED: ['SETTLED', 'REJECTED'],
  SETTLED: ['RETURNED'],        // Returns are possible but unusual post-finality
  RETURNED: [],                  // Terminal state
  REJECTED: [],                  // Terminal state
};

function validateTransition(from: PaymentStatus, to: PaymentStatus): void {
  if (!ALLOWED_TRANSITIONS[from].includes(to)) {
    throw new InvalidStateTransitionError(from, to);
  }
}
```

## Anti-Patterns

### Anti-Pattern: Treating Submission as Settlement

```typescript
// WRONG: Mark payment settled when submitted to RTGS
const result = await rtgsGateway.submit(payment);
if (result.accepted) {
  await db.payment.update({ where: { id }, data: { status: 'SETTLED' } });
  await creditBeneficiary(payment);
}
// RTGS can still reject after accepting the submission
// You've credited the beneficiary for a payment that hasn't settled

// RIGHT: Wait for pacs.002 ACSC confirmation
await rtgsGateway.submit(payment);
await db.payment.update({ where: { id }, data: { status: 'SUBMITTED' } });
// Settlement update happens only in the pacs.002 handler
// Beneficiary credited only after ACSC received
```

### Anti-Pattern: Missing Duplicate Detection

```typescript
// WRONG: No idempotency - same payment instruction resubmitted
// Upstream systems retry on timeout; RTGS systems will execute both
app.post('/payments', async (req, res) => {
  const payment = req.body;
  const result = await submitToRTGS(payment);  // No duplicate check
  res.json(result);
});
// Each POST creates a new wire transfer even if payment already submitted

// RIGHT: Check UETR/internal ID before submission
app.post('/payments', async (req, res) => {
  const { paymentId } = req.body;
  const existing = await db.payment.findUnique({ where: { id: paymentId } });
  if (existing?.status === 'SUBMITTED' || existing?.status === 'SETTLED') {
    return res.json({ uetr: existing.uetr, status: existing.status, idempotent: true });
  }
  // Proceed with new submission
});
```

### Anti-Pattern: Synchronous Nostro Reconciliation

```
WRONG: Reconcile Nostro at end of day from a single batch file
- You won't know about intraday liquidity issues until it's too late
- Fedwire/CHAPS can reject payments for insufficient funds in real-time

RIGHT: Real-time Nostro monitoring
- Subscribe to camt.054 (Debit/Credit Notification) from correspondent bank
- Maintain live intraday balance position
- Alert operations when position falls below minimum threshold
- Front-load large payments early in the day (TARGET2 50% by noon guideline)
```

## References

- **Fedwire Funds Service**: https://www.federalreserve.gov/paymentsystems/fedfunds_about.htm
- **FedNow Service**: https://www.frbservices.org/financial-services/fednow
- **RTP (The Clearing House)**: https://www.theclearinghouse.org/payment-systems/rtp
- **SEPA Instant Credit Transfer**: https://www.europeanpaymentscouncil.eu/what-we-do/scf-schemes/sepa-instant-credit-transfer
- **CLS (Continuous Linked Settlement)**: https://www.cls-group.com/
- **ISO 20022 message catalogue**: https://www.iso20022.org/iso-20022-message-definitions
- **SWIFT gpi (Global Payments Innovation)**: https://www.swift.com/our-solutions/swift-gpi
- **BIS CPMI: Payment system design**: https://www.bis.org/cpmi/
- **Herstatt Risk (BIS)**: https://www.bis.org/cpmi/publ/d27.pdf
