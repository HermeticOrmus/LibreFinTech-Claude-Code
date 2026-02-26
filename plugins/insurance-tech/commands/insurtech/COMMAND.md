# /insurtech

Insurance technology workflows: quote generation, policy binding, claims processing, and regulatory reporting.

## Trigger

`/insurtech <action> [options]`

## Actions

- `quote` - Generate an insurance quote based on risk submission data
- `bind` - Bind a quoted policy and initiate coverage
- `claim` - Process a First Notice of Loss (FNOL) and manage claim lifecycle
- `report` - Generate regulatory reports (loss runs, bordereau, IFRS 17)

## Options

- `--policy-id <id>` - Existing policy to operate on
- `--claim-id <id>` - Existing claim to operate on
- `--line-of-business <auto|property|liability|health>` - Insurance line
- `--state <two-letter-state-code>` - Jurisdiction for rate/rule application
- `--format <pdf|acord|xml>` - Output format

## Process

### quote

```typescript
interface RiskSubmission {
  applicantId: string;
  lineOfBusiness: 'PERSONAL_AUTO' | 'HOMEOWNERS' | 'COMMERCIAL_PROPERTY';
  effectiveDate: Date;
  ratingFactors: Record<string, string | number | boolean>;
  coverageRequests: CoverageRequest[];
  stateCode: string;
}

interface QuoteResult {
  quoteId: string;
  quoteNumber: string;
  annualPremium: Decimal;
  coverages: Coverage[];
  ratingDetails: RatingStep[];  // Full audit trail of rate calculation
  eligibilityDecision: 'ACCEPT' | 'REFER' | 'DECLINE';
  declineReasons?: string[];    // Required by most states if declined
  expiresAt: Date;              // Quotes typically valid 30 days
}

async function generateQuote(submission: RiskSubmission): Promise<QuoteResult> {
  // Step 1: Eligibility check
  const eligibility = await underwritingEngine.checkEligibility(submission);
  if (eligibility.decision === 'DECLINE') {
    return buildDeclinedQuote(submission, eligibility.reasons);
  }

  // Step 2: Rate calculation with full audit trail
  const ratingSteps: RatingStep[] = [];

  // Base rate by territory (state-filed)
  const baseRate = await rateTable.getBaseRate({
    lob: submission.lineOfBusiness,
    state: submission.stateCode,
    effectiveDate: submission.effectiveDate,
  });
  ratingSteps.push({ step: 'BASE_RATE', value: baseRate, factor: baseRate });

  // Apply rating factors multiplicatively
  for (const [factor, value] of Object.entries(submission.ratingFactors)) {
    const relativty = await rateTable.getFactor({
      factor, value, state: submission.stateCode, lob: submission.lineOfBusiness,
    });
    ratingSteps.push({ step: `FACTOR_${factor}`, value, relativty });
  }

  const annualPremium = ratingSteps.reduce((premium, step) =>
    step.relativty ? premium.mul(step.relativty) : premium, baseRate);

  return {
    quoteId: generateId(),
    quoteNumber: generateQuoteNumber(),
    annualPremium,
    coverages: buildCoverages(submission.coverageRequests),
    ratingDetails: ratingSteps,  // Every factor documented for regulatory examination
    eligibilityDecision: eligibility.decision,
    expiresAt: addDays(new Date(), 30),
  };
}
```

### bind

```typescript
// Policy schema - designed for endorsement versioning
interface Policy {
  id: string;
  policyNumber: string;
  version: number;           // Increments with each endorsement
  status: 'QUOTED' | 'ACTIVE' | 'ENDORSED' | 'EXPIRED' | 'CANCELLED';
  effectiveDate: Date;
  expirationDate: Date;
  insuredId: string;
  lineOfBusiness: string;
  stateCode: string;
  coverages: Coverage[];
  premiums: PremiumInstallment[];
  endorsements: Endorsement[];  // All mid-term changes
  cancelledAt?: Date;
  cancelledBy?: 'INSURED' | 'CARRIER';
  cancelReason?: string;
  unearnedPremium?: Decimal;   // Must be returned on cancellation
}

// Post-bind endorsement - never modify bound policy terms directly
interface Endorsement {
  id: string;
  policyId: string;
  endorsementNumber: string;
  effectiveDate: Date;
  changes: PolicyChange[];     // Structured diff of what changed
  premiumAdjustment: Decimal;  // Pro-rata or short-rate as applicable
  endorsedBy: string;          // Underwriter or automated system
  reason: string;
}
```

### claim

FNOL intake and claim lifecycle:

```typescript
interface FirstNoticeOfLoss {
  claimId: string;
  claimNumber: string;
  policyId: string;
  dateOfLoss: Date;           // When did the loss event occur?
  dateReported: Date;         // When did the insured report it? (late reporting is a flag)
  lossDescription: string;
  lossType: string;           // Peril: 'COLLISION', 'THEFT', 'WATER_DAMAGE', etc.
  estimatedLoss: Decimal;
  claimantInfo: ClaimantInfo;
  involvedParties: Party[];   // For liability claims: third-party information
  witnessInfo?: WitnessInfo[];
  policeReport?: string;      // Report number if applicable
  initialReserve: Decimal;    // Set at FNOL; updated as investigation proceeds
}

// Coverage verification before any payments
async function verifyCoverage(claim: FirstNoticeOfLoss): Promise<CoverageVerification> {
  const policy = await db.policy.findUnique({ where: { id: claim.policyId } });

  return {
    policyInForce: claim.dateOfLoss >= policy.effectiveDate &&
                   claim.dateOfLoss <= policy.expirationDate,
    premiumPaid: await checkPremiumStatus(policy.id, claim.dateOfLoss),
    perilCovered: await checkPerilCoverage(policy, claim.lossType),
    exclusionsApplicable: await checkExclusions(policy, claim),
    applicableDeductible: await getApplicableDeductible(policy, claim.lossType),
    applicableLimit: await getApplicableLimit(policy, claim.lossType),
  };
}
```

### report

Loss run report (required by reinsurers and for new coverage applications):

```sql
SELECT
    p.policy_number,
    c.claim_number,
    c.date_of_loss,
    c.loss_type,
    c.paid_loss,
    c.paid_expense,
    c.reserve_loss,
    c.reserve_expense,
    (c.paid_loss + c.paid_expense + c.reserve_loss + c.reserve_expense) AS total_incurred,
    c.status
FROM claims c
JOIN policies p ON p.id = c.policy_id
WHERE p.state_code = :state
  AND c.date_of_loss BETWEEN :from_date AND :to_date
ORDER BY c.date_of_loss;
```

## Examples

```bash
# Generate auto insurance quote for Texas applicant
/insurtech quote --line-of-business auto --state TX

# Bind quoted policy after acceptance
/insurtech bind --policy-id Q-2024-001234

# Open new claim for property damage
/insurtech claim --policy-id POL-2024-001234 --line-of-business property

# Generate 5-year loss run for reinsurance renewal
/insurtech report --line-of-business property --format pdf
```
