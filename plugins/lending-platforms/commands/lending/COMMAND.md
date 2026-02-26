# /lending

Loan origination, amortization calculation, credit scoring, and collections workflow management.

## Trigger

`/lending <action> [options]`

## Actions

- `originate` - Process a loan application through credit decisioning
- `amortize` - Generate a full amortization schedule for a loan
- `score` - Run credit scoring model against applicant data
- `collect` - Manage delinquent loan collections workflow

## Options

- `--loan-id <id>` - Existing loan to operate on
- `--product-type <personal|auto|mortgage|bnpl|loc>` - Loan product
- `--amount <decimal>` - Principal amount
- `--rate <decimal>` - Annual interest rate (e.g., 0.0599 for 5.99%)
- `--term <months>` - Loan term in months
- `--day-count <actual360|actual365|30-360>` - Day count convention
- `--state <two-letter-code>` - State for regulatory compliance

## Process

### amortize

Actuarial amortization with exact decimal arithmetic:

```typescript
import Decimal from 'decimal.js';

interface LoanTerms {
  principal: Decimal;
  annualRate: Decimal;      // e.g., new Decimal('0.0599')
  termMonths: number;
  originationDate: Date;
  firstPaymentDate: Date;
  dayCountConvention: 'ACTUAL_365' | 'ACTUAL_360' | '30_360';
}

interface AmortizationLine {
  paymentNumber: number;
  paymentDate: Date;
  scheduledPayment: Decimal;
  principalPayment: Decimal;
  interestPayment: Decimal;
  beginningBalance: Decimal;
  endingBalance: Decimal;
  totalInterestToDate: Decimal;
}

function generateAmortizationSchedule(loan: LoanTerms): AmortizationLine[] {
  // Monthly rate from annual rate
  const monthlyRate = loan.annualRate.div(12);

  // Standard amortization payment formula: PMT = P * r / (1 - (1+r)^-n)
  const monthlyPayment = loan.principal
    .mul(monthlyRate)
    .div(new Decimal(1).minus(
      monthlyRate.plus(1).pow(-loan.termMonths)
    ));

  const schedule: AmortizationLine[] = [];
  let balance = loan.principal;
  let totalInterest = new Decimal(0);

  for (let i = 1; i <= loan.termMonths; i++) {
    const beginningBalance = balance;
    const interestPayment = balance.mul(monthlyRate).toDecimalPlaces(2);
    const principalPayment = (i === loan.termMonths)
      ? balance  // Final payment: pay off remaining balance exactly
      : monthlyPayment.minus(interestPayment).toDecimalPlaces(2);

    balance = balance.minus(principalPayment);
    totalInterest = totalInterest.plus(interestPayment);

    schedule.push({
      paymentNumber: i,
      paymentDate: addMonths(loan.firstPaymentDate, i - 1),
      scheduledPayment: principalPayment.plus(interestPayment),
      principalPayment,
      interestPayment,
      beginningBalance,
      endingBalance: balance,
      totalInterestToDate: totalInterest,
    });
  }

  return schedule;
}

// APR calculation per Regulation Z (Appendix J method)
// For equal monthly payments, APR ≈ rate that makes NPV of payments = loan amount
function calculateAPR(
  loanAmount: Decimal,
  schedule: AmortizationLine[],
  fees: Decimal  // Origination fees, points, etc. included in finance charge
): Decimal {
  // Newton-Raphson method to solve for monthly rate
  const netProceed = loanAmount.minus(fees);
  let monthlyRate = loanAmount.minus(fees).div(loanAmount).toDecimalPlaces(10);

  for (let iteration = 0; iteration < 100; iteration++) {
    let npv = new Decimal(0);
    let dnpv = new Decimal(0);

    schedule.forEach((line, idx) => {
      const payment = line.scheduledPayment;
      const t = idx + 1;
      const discount = monthlyRate.plus(1).pow(-t);
      npv = npv.plus(payment.mul(discount));
      dnpv = dnpv.minus(payment.mul(t).mul(discount).div(monthlyRate.plus(1)));
    });

    const delta = npv.minus(netProceed).div(dnpv);
    monthlyRate = monthlyRate.minus(delta);
    if (delta.abs().lt('0.0000001')) break;
  }

  return monthlyRate.mul(12);  // Annualized APR
}
```

### originate

Credit decision with adverse action compliance:

```typescript
interface CreditDecision {
  applicationId: string;
  decision: 'APPROVE' | 'CONDITIONAL' | 'DECLINE';
  approvedAmount?: Decimal;
  approvedRate?: Decimal;
  declineReasons?: AdverseActionReason[];  // ECOA requires specific reasons
  conditions?: string[];
  creditScore: number;
  scoreSource: 'FICO8' | 'VANTAGE4' | 'CUSTOM';
  scoreRange: [number, number];  // Required in adverse action notice
  keyScoreFactors?: string[];    // Top 4 factors driving the score
}

// ECOA Adverse Action Reason Codes (must use specific language)
const ADVERSE_ACTION_REASONS = {
  TOO_MANY_DELINQUENCIES: 'Delinquent past or present credit obligations',
  HIGH_UTILIZATION: 'Proportion of balances to credit limits too high',
  TOO_MANY_INQUIRIES: 'Too many inquiries in last 12 months',
  SHORT_HISTORY: 'Length of credit history',
  INSUFFICIENT_INCOME: 'Insufficient income for requested obligation',
  HIGH_DTI: 'Obligations in relation to income',
  INSUFFICIENT_COLLATERAL: 'Collateral does not protect amount of credit requested',
} as const;
```

### collect

```typescript
enum DelinquencyBucket {
  CURRENT      = 'CURRENT',       // 0 DPD
  EARLY        = '1-30',          // 1-30 DPD - soft touch
  LATE         = '31-60',         // 31-60 DPD - automated outreach
  SERIOUS      = '61-90',         // 61-90 DPD - collections team
  DEFAULT      = '90+',           // 90+ DPD - charge-off candidate
}

// FDCPA compliance: initial communication must include Mini-Miranda
const MINI_MIRANDA = `
This communication is from a debt collector. This is an attempt to collect a debt.
Any information obtained will be used for that purpose.
`;

// Cease and desist tracking - must honor within 5 business days
interface CeaseDesistRecord {
  borrowerId: string;
  requestedAt: Date;
  honoredAt?: Date;
  channel: 'WRITTEN' | 'VERBAL';
  // After C&D: may only contact to confirm no further contact, or notify of legal action
}
```

## Examples

```bash
# Generate full amortization schedule for a 5-year personal loan
/lending amortize --amount 25000 --rate 0.0799 --term 60 --day-count actual365

# Process new loan application through credit decisioning
/lending originate --product-type personal --amount 15000 --state CA

# Score applicant for BNPL product
/lending score --product-type bnpl

# Trigger collections workflow for 31-60 DPD bucket
/lending collect --loan-id LOAN-001234
```
