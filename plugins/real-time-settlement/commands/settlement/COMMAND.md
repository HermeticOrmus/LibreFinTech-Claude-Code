# /settlement

Real-time payment settlement: submit to RTGS, monitor position, reconcile confirmations, and manage payment queues.

## Trigger

`/settlement <action> [options]`

## Actions

- `submit` - Submit a payment instruction to RTGS or instant rail
- `status` - Query payment status and queue position
- `position` - Real-time Nostro/liquidity position by currency
- `reconcile` - Match RTGS confirmations to internal ledger

## Options

- `--rail <fedwire|rtp|fednow|chaps|sepa-instant|fps>` - Settlement rail
- `--payment-id <id>` - Internal payment instruction ID
- `--currency <ISO4217>` - Settlement currency
- `--uetr <uuid>` - Unique End-to-End Transaction Reference (ISO 20022)
- `--priority <urgent|high|normal>` - Queue priority
- `--value-date <ISO8601>` - Settlement value date

## Process

### submit

ISO 20022 pacs.008 credit transfer submission:

```typescript
// pacs.008 - FI Credit Transfer Initiation (used for wire transfers)
interface Pacs008Message {
  grpHdr: {
    msgId: string;          // Unique message ID (35 chars max)
    creDtTm: string;        // ISO 8601 creation timestamp
    nbOfTxs: number;        // Number of transactions in batch
    sttlmInf: {
      sttlmMtd: 'INGA' | 'INDA' | 'COVE' | 'CLRG';  // Settlement method
      sttlmAcct?: { id: string; ccy: string };         // RTGS account
    };
  };
  cdtTrfTxInf: Array<{
    pmtId: {
      instrId: string;    // Instruction ID (internal)
      endToEndId: string; // End-to-end ID (passed to beneficiary)
      uetr: string;       // Unique End-to-End Transaction Reference (UUID v4)
    };
    intrBkSttlmAmt: { ccy: string; value: number };  // Settlement amount
    intrBkSttlmDt: string;    // Value date YYYY-MM-DD
    dbtr: { nm: string; acct: { id: string } };
    dbtrAgt: { finInstnId: { bicfi: string } };     // Sending bank BIC
    cdtr: { nm: string; acct: { id: string } };
    cdtrAgt: { finInstnId: { bicfi: string } };     // Receiving bank BIC
    rmtInf?: { ustrd: string[] };  // Remittance information
  }>;
}

async function submitToRTGS(
  payment: PaymentInstruction,
  rail: 'fedwire' | 'chaps' | 'sepa-instant',
): Promise<SettlementResult> {
  // Generate UETR - required for SWIFT gpi tracking
  const uetr = crypto.randomUUID();

  const msg = buildPacs008(payment, uetr);

  // Validate before submission
  await validatePacs008Schema(msg);
  await screenSanctions(payment.beneficiary);  // OFAC/EU sanctions

  // Check Nostro balance before committing
  const nostroBalance = await getNostroBalance(payment.currency);
  if (nostroBalance < payment.amount) {
    await queuePayment(payment.id, 'PENDING_FUNDS');
    throw new InsufficientLiquidityError(payment.currency, payment.amount, nostroBalance);
  }

  const response = await sendToRailGateway(rail, msg);

  // Update internal state
  await db.payment.update({
    where: { id: payment.id },
    data: {
      uetr,
      status: 'SUBMITTED',
      submittedAt: new Date(),
      railReference: response.msgId,
    },
  });

  return { uetr, msgId: response.msgId, status: 'SUBMITTED' };
}
```

Payment state machine:
```
CREATED → VALIDATED → SCREENED → QUEUED → SUBMITTED → SETTLED
                                                   ↓
                                               RETURNED (pacs.004)
                                               REJECTED (pacs.002 RJCT)
```

### status

Query payment status via pacs.002:

```typescript
// pacs.002 - FI To FI Payment Status Report
// Received from RTGS when payment settles, rejects, or returns

async function handlePacs002(msg: Pacs002Message): Promise<void> {
  const txSts = msg.txInfAndSts[0];
  const internalId = await db.payment.findByUetr(msg.grpHdr.orgnlMsgId);

  switch (txSts.txSts) {
    case 'ACSC':  // Accepted Settlement Completed - FINAL
      await db.payment.update({
        where: { id: internalId },
        data: { status: 'SETTLED', settledAt: new Date(), finalityAchieved: true },
      });
      await updateNostroLedger(internalId, 'DEBIT');
      await notifyOriginator(internalId, 'SETTLED');
      break;

    case 'RJCT':  // Rejected
      await db.payment.update({
        where: { id: internalId },
        data: {
          status: 'REJECTED',
          rejectCode: txSts.stsRsnInf?.[0]?.rsn?.cd,
          rejectReason: txSts.stsRsnInf?.[0]?.addtlInf,
        },
      });
      await reverseNostroReservation(internalId);
      await notifyOriginator(internalId, 'REJECTED');
      break;
  }
}
```

### position

Real-time Nostro/liquidity monitoring:

```sql
-- Real-time intraday Nostro position by currency
-- Combines opening balance + settled credits - settled debits + queued items
SELECT
    currency,
    opening_balance,
    SUM(CASE WHEN direction = 'CREDIT' AND status = 'SETTLED' THEN amount ELSE 0 END) AS settled_credits,
    SUM(CASE WHEN direction = 'DEBIT' AND status = 'SETTLED' THEN amount ELSE 0 END) AS settled_debits,
    SUM(CASE WHEN direction = 'DEBIT' AND status IN ('SUBMITTED', 'QUEUED') THEN amount ELSE 0 END) AS pending_debits,
    -- Available balance = what you can settle right now
    opening_balance
        + SUM(CASE WHEN direction = 'CREDIT' AND status = 'SETTLED' THEN amount ELSE 0 END)
        - SUM(CASE WHEN direction = 'DEBIT' AND status = 'SETTLED' THEN amount ELSE 0 END) AS current_balance,
    -- Expected closing balance including queued
    opening_balance
        + SUM(CASE WHEN direction = 'CREDIT' AND status = 'SETTLED' THEN amount ELSE 0 END)
        - SUM(CASE WHEN direction = 'DEBIT' AND status IN ('SETTLED', 'SUBMITTED', 'QUEUED') THEN amount ELSE 0 END) AS projected_balance
FROM nostro_positions
WHERE value_date = CURRENT_DATE
GROUP BY currency, opening_balance
ORDER BY currency;
```

### reconcile

Match RTGS confirmations to internal payment records:

```typescript
async function reconcileSettlementDay(
  valueDate: string,
  currency: string,
): Promise<ReconciliationResult> {
  // Fetch RTGS statement (camt.053 - Bank To Customer Statement)
  const rtgsStatement = await fetchCamt053(valueDate, currency);

  const breaks: ReconciliationBreak[] = [];

  for (const rtgsTx of rtgsStatement.entries) {
    const internalPayment = await db.payment.findByUetr(rtgsTx.refs.uetr);

    if (!internalPayment) {
      breaks.push({ type: 'MISSING_INTERNAL', rtgsRef: rtgsTx.refs.uetr, amount: rtgsTx.amt });
      continue;
    }

    if (Math.abs(internalPayment.amount - rtgsTx.amt) > 0.01) {
      breaks.push({
        type: 'AMOUNT_MISMATCH',
        paymentId: internalPayment.id,
        internalAmount: internalPayment.amount,
        rtgsAmount: rtgsTx.amt,
      });
    }

    if (internalPayment.status !== 'SETTLED') {
      // Payment settled in RTGS but we didn't get the pacs.002 - fix our ledger
      await markAsSettled(internalPayment.id, rtgsTx.bookedAt);
      breaks.push({ type: 'STATUS_LAG_FIXED', paymentId: internalPayment.id });
    }
  }

  return { valueDate, currency, breakCount: breaks.length, breaks };
}
```

## Examples

```bash
# Submit urgent USD wire via Fedwire
/settlement submit --rail fedwire --currency USD --priority urgent

# Check status of a specific payment by UETR
/settlement status --uetr 550e8400-e29b-41d4-a716-446655440000

# View real-time USD Nostro position
/settlement position --currency USD

# Reconcile yesterday's EUR settlements via SEPA
/settlement reconcile --rail sepa-instant --currency EUR --value-date 2024-11-01
```
