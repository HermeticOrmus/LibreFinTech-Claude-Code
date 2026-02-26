# Lending Patterns

Domain-specific patterns for loan origination, amortization, credit decisioning, collections compliance, and regulatory disclosure.

## Core Patterns

### Pattern: Actuarial Amortization with Interest Accrual

```typescript
import Decimal from 'decimal.js';
Decimal.set({ precision: 20, rounding: Decimal.ROUND_HALF_UP });

// Monthly payment (PMT) using standard annuity formula
function calculateMonthlyPayment(principal: Decimal, annualRate: Decimal, termMonths: number): Decimal {
  if (annualRate.isZero()) {
    return principal.div(termMonths).toDecimalPlaces(2);  // Zero-interest: divide equally
  }
  const monthlyRate = annualRate.div(12);
  const factor = monthlyRate.plus(1).pow(termMonths);
  return principal.mul(monthlyRate).mul(factor).div(factor.minus(1)).toDecimalPlaces(2);
}

// Example: $10,000 at 12% annual rate for 24 months
const pmt = calculateMonthlyPayment(new Decimal('10000'), new Decimal('0.12'), 24);
// pmt = $470.73

// Verify: Total paid = $470.73 * 24 = $11,297.52
// Total interest = $11,297.52 - $10,000 = $1,297.52
```

### Pattern: Daily Interest Accrual (Simple Interest Loans)

For lines of credit and some personal loans, interest accrues daily and is calculated on the actual outstanding principal each day.

```typescript
interface DailyAccrual {
  date: Date;
  principalBalance: Decimal;
  dailyRate: Decimal;
  interestAccrued: Decimal;
}

function calculateDailyAccrual(
  balance: Decimal,
  annualRate: Decimal,
  daysInYear: 365 | 360 = 365
): Decimal {
  return balance.mul(annualRate).div(daysInYear).toDecimalPlaces(10);
}

// Apply a payment to a simple interest loan (interest-first order)
function applyPayment(
  payment: Decimal,
  outstandingInterest: Decimal,
  outstandingPrincipal: Decimal,
  outstandingFees: Decimal
): PaymentAllocation {
  // Standard order: fees first, then interest, then principal
  // (some products vary - must match loan agreement)
  let remaining = payment;

  const feePayment = Decimal.min(remaining, outstandingFees);
  remaining = remaining.minus(feePayment);

  const interestPayment = Decimal.min(remaining, outstandingInterest);
  remaining = remaining.minus(interestPayment);

  const principalPayment = Decimal.min(remaining, outstandingPrincipal);
  remaining = remaining.minus(principalPayment);

  return { feePayment, interestPayment, principalPayment, unapplied: remaining };
}
```

### Pattern: Delinquency Bucket Management with Reserve Provisioning

```sql
-- CECL (Current Expected Credit Loss) - ASC 326 compliant aging analysis
-- Loss rate by DPD bucket used for ALLL/ACL calculation
SELECT
    l.loan_id,
    l.outstanding_principal,
    l.days_past_due,
    CASE
        WHEN l.days_past_due = 0        THEN 'CURRENT'
        WHEN l.days_past_due <= 30      THEN '1-30_DPD'
        WHEN l.days_past_due <= 60      THEN '31-60_DPD'
        WHEN l.days_past_due <= 90      THEN '61-90_DPD'
        ELSE                                 '90_PLUS_DPD'
    END AS bucket,
    -- Apply historical loss rates by bucket (institution-specific)
    CASE
        WHEN l.days_past_due = 0        THEN l.outstanding_principal * 0.005
        WHEN l.days_past_due <= 30      THEN l.outstanding_principal * 0.02
        WHEN l.days_past_due <= 60      THEN l.outstanding_principal * 0.10
        WHEN l.days_past_due <= 90      THEN l.outstanding_principal * 0.35
        ELSE                                 l.outstanding_principal * 0.70
    END AS expected_credit_loss
FROM loans l
WHERE l.status = 'ACTIVE'
  AND l.entity_id = :entity_id;
```

### Pattern: TILA-Compliant APR Disclosure

```typescript
// Regulation Z APR: the rate that equates PV of all payments to amount financed
// Amount financed = loan amount - prepaid finance charges (fees, points)
// Finance charge = total of payments - amount financed

interface TILADisclosure {
  annualPercentageRate: string;  // "5.99%" - formatted to nearest 0.125% (Reg Z)
  financeCharge: Decimal;        // Total interest + all fees
  amountFinanced: Decimal;       // Loan amount less prepaid finance charges
  totalOfPayments: Decimal;      // Sum of all scheduled payments
  paymentSchedule: PaymentScheduleEntry[];
}

function formatAPRForDisclosure(apr: Decimal): string {
  // Regulation Z: round to nearest 0.125% (1/8%)
  const roundedToEighths = apr.mul(800).round().div(800);
  return `${roundedToEighths.mul(100).toFixed(3)}%`;
}
```

## Anti-Patterns

### Anti-Pattern: Compound vs Simple Interest Confusion

```typescript
// WRONG: Using compound interest formula when loan contract specifies simple interest
// (common in BNPL and personal loan products)
function wrongInterestCalculation(balance: Decimal, rate: Decimal, months: number): Decimal {
  return balance.mul(rate.div(12).plus(1).pow(months)).minus(balance);
  // This compounds monthly - overstates interest for simple interest loans
}

// RIGHT: Simple interest for the stated period
function correctSimpleInterest(balance: Decimal, annualRate: Decimal, days: number): Decimal {
  return balance.mul(annualRate).mul(days).div(365);
}
```

### Anti-Pattern: Missing TILA Disclosures

Any consumer loan must provide Reg Z disclosures before consummation (binding). Failure is strict liability - the borrower can rescind the loan and/or sue for statutory damages even without showing actual harm. The APR, finance charge, amount financed, and total of payments must be disclosed conspicuously before signing.

### Anti-Pattern: Treating Prepayment Without Recalculation

```typescript
// WRONG: Apply prepayment but keep original schedule
await db.payment.create({ data: { amount: extraPayment } });
// Balance reduced but schedule not updated - interest calculations will be wrong

// RIGHT: Recalculate remaining schedule after any balance-affecting event
async function processExtraPayment(loanId: string, amount: Decimal): Promise<void> {
  await applyPayment(loanId, amount);
  const newBalance = await getCurrentBalance(loanId);
  const remainingTerm = await getRemainingTerm(loanId);
  const newSchedule = generateAmortizationSchedule({
    principal: newBalance,
    termMonths: remainingTerm,
    // ... other terms
  });
  await db.amortizationSchedule.replaceFor(loanId, newSchedule);
}
```

### Anti-Pattern: Ignoring FDCPA Time Restrictions

```typescript
// WRONG: Call at any time
await dialerSystem.call(borrowerPhone);

// RIGHT: FDCPA § 805(a)(1) prohibits calls before 8am or after 9pm local time
function canContactNow(borrowerTimezone: string): boolean {
  const localTime = DateTime.now().setZone(borrowerTimezone);
  return localTime.hour >= 8 && localTime.hour < 21;
}
```

## References

- **Regulation Z / TILA**: https://www.consumerfinance.gov/rules-policy/regulations/1026/
- **ECOA / Regulation B**: https://www.consumerfinance.gov/rules-policy/regulations/1002/
- **FDCPA**: https://www.ftc.gov/legal-library/browse/rules/fair-debt-collection-practices-act-text
- **CECL (ASC 326)**: https://www.fasb.org/page/PageContent?pageId=/standards/accounting-standards-updates/2016-13.html
- **HMDA**: https://www.consumerfinance.gov/data-research/hmda/
- **FICO Score Overview**: https://www.myfico.com/credit-education/whats-in-your-credit-score
- **Decimal.js**: https://mikemcl.github.io/decimal.js/
