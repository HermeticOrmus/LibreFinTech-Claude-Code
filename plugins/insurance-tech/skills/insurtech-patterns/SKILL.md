# InsurTech Patterns

Domain-specific patterns for insurance technology: policy versioning, claims workflow, underwriting engines, reserve calculation, and regulatory compliance.

## Core Patterns

### Pattern: Policy Versioning with Endorsement Trail

A policy is a legal contract. Every change must be documented as an endorsement; original terms must be preserved. Never mutate bound policy terms.

```typescript
// Policy is immutable after bind; all changes via endorsement
async function endorsePolicy(
  policyId: string,
  changes: PolicyChange[],
  endorsementReason: string,
  effectiveDate: Date,
  endorsedBy: string
): Promise<Endorsement> {
  const policy = await db.policy.findUnique({
    where: { id: policyId, status: 'ACTIVE' },
  });
  if (!policy) throw new Error('Policy not found or not active');

  // Calculate pro-rata premium adjustment
  const remainingDays = differenceInDays(policy.expirationDate, effectiveDate);
  const totalDays = differenceInDays(policy.expirationDate, policy.effectiveDate);
  const proRataFactor = remainingDays / totalDays;

  const premiumChange = calculatePremiumChange(changes);
  const premiumAdjustment = premiumChange.mul(proRataFactor);

  const endorsement = await db.endorsement.create({
    data: {
      id: generateId(),
      policyId,
      endorsementNumber: generateEndorsementNumber(policy.policyNumber),
      effectiveDate,
      changes: JSON.stringify(changes),  // Structured diff
      premiumAdjustment,
      endorsedBy,
      reason: endorsementReason,
      createdAt: new Date(),
    },
  });

  // Increment policy version - do NOT modify original fields
  await db.policy.update({
    where: { id: policyId },
    data: { version: { increment: 1 } },
  });

  return endorsement;
}
```

### Pattern: Claims FNOL Workflow with Reserve Adequacy

```typescript
enum ClaimStatus {
  FNOL_RECEIVED    = 'FNOL_RECEIVED',
  COVERAGE_VERIFY  = 'COVERAGE_VERIFY',
  UNDER_INVESTIGATION = 'UNDER_INVESTIGATION',
  SIU_REFERRAL     = 'SIU_REFERRAL',
  SETTLEMENT_OFFER = 'SETTLEMENT_OFFER',
  PENDING_PAYMENT  = 'PENDING_PAYMENT',
  CLOSED_PAID      = 'CLOSED_PAID',
  CLOSED_NO_PAY    = 'CLOSED_NO_PAY',
  CLOSED_SUBROGATED = 'CLOSED_SUBROGATED',
}

interface ReserveRecord {
  claimId: string;
  reserveType: 'CASE_LOSS' | 'CASE_EXPENSE' | 'SUBROGATION_RECOVERY';
  amount: Decimal;
  setBy: string;
  setAt: Date;
  reason: string;
  previousAmount: Decimal;  // For audit trail of reserve changes
}

// Reserve changes are append-only audit records
async function updateReserve(
  claimId: string,
  newAmount: Decimal,
  reason: string,
  setBy: string
): Promise<void> {
  const current = await db.reserveRecord.findFirst({
    where: { claimId, reserveType: 'CASE_LOSS' },
    orderBy: { setAt: 'desc' },
  });

  await db.reserveRecord.create({
    data: {
      claimId,
      reserveType: 'CASE_LOSS',
      amount: newAmount,
      setBy,
      setAt: new Date(),
      reason,
      previousAmount: current?.amount ?? new Decimal(0),
    },
  });
}
```

### Pattern: Underwriting Rule Engine with Regulatory Defensibility

```typescript
interface UnderwritingRule {
  id: string;
  name: string;
  description: string;       // Must be explainable to applicant and regulator
  stateApplicability: string[]; // Which states this rule applies in
  lob: string;
  effectiveDate: Date;
  expirationDate?: Date;
  evaluate: (submission: RiskSubmission) => EligibilityResult;
}

interface EligibilityResult {
  passed: boolean;
  reason?: string;  // Required for declines in most jurisdictions
  referReason?: string;  // For underwriter review
}

// Example: Personal auto rule - DUI within 3 years
const duiRule: UnderwritingRule = {
  id: 'AUTO-ELIGIBILITY-DUI-3YR',
  name: 'DUI within 3 years - ineligible',
  description: 'Applicant or any listed driver with DUI conviction within past 3 years',
  stateApplicability: ['CA', 'NY', 'TX'], // Other states may have different thresholds
  lob: 'PERSONAL_AUTO',
  effectiveDate: new Date('2024-01-01'),
  evaluate(submission) {
    const drivers = submission.ratingFactors.drivers as Driver[];
    const cutoffDate = subYears(new Date(), 3);
    const hasDUI = drivers.some(d =>
      d.violations?.some(v => v.type === 'DUI' && v.date > cutoffDate)
    );
    return {
      passed: !hasDUI,
      reason: hasDUI ? 'DUI conviction within past 36 months - ineligible per underwriting guidelines' : undefined,
    };
  },
};
```

### Pattern: Reinsurance Cession Tracking

```typescript
// Facultative reinsurance: each cession is negotiated individually
interface FacultativeCession {
  cedingPolicyId: string;
  reinsurerId: string;
  certificateNumber: string;
  cededLimit: Decimal;         // How much risk is transferred
  retainedLimit: Decimal;      // How much carrier keeps
  cededPremium: Decimal;       // Premium paid to reinsurer
  effectiveDate: Date;
  expirationDate: Date;
  perilsReinsured: string[];
}

// Treaty reinsurance: automatic cession per treaty terms
interface TreatyCession {
  treatyId: string;
  policyId: string;
  cessionPercentage: Decimal;  // % of each risk ceded automatically
  cededPremium: Decimal;
  cededLoss?: Decimal;         // Populated when loss occurs
  accountingPeriod: string;    // Typically quarterly
}
```

## Anti-Patterns

### Anti-Pattern: Mutable Policy Terms

```typescript
// WRONG: Directly modifying bound policy terms
await db.policy.update({
  where: { id: policyId },
  data: { coverageLimit: newLimit },  // Destroys original contract terms
});

// RIGHT: Endorsement adds the change as a versioned record
await endorsePolicy(policyId, [
  { field: 'coverageLimit', oldValue: oldLimit, newValue: newLimit }
], 'Insured requested limit increase', new Date(), requestedBy);
```

### Anti-Pattern: No Claims Audit Trail

Every claims decision must be documented with who made it, when, and why. "We don't pay this because it looks fraudulent" is not a legally defensible denial. The denial letter must cite the specific policy exclusion or condition that applies.

### Anti-Pattern: Hardcoded Premium Tables

Premium rates are state-filed. When a rate filing is approved and effective, all new business must use the new rates. When a rate filing is rejected, existing rates continue. Hardcoded rates make this impossible to manage.

```typescript
// WRONG: Hardcoded base rate
const baseRate = 450; // Where did this come from? When was it last updated?

// RIGHT: Rate table with effective date lookup
const baseRate = await rateTable.getBaseRate({
  lob: 'PERSONAL_AUTO',
  state: 'CA',
  effectiveDate: policyEffectiveDate,
  rateVersion: await rateFilingService.getApprovedVersion('CA', policyEffectiveDate),
});
```

## References

- **ACORD Standards**: https://www.acord.org/standards-architecture/acord-standards (Insurance data exchange)
- **ISO (Verisk Analytics)**: Advisory loss costs and policy forms widely used as rating basis
- **NAIC Model Regulations**: https://content.naic.org/model-laws
- **Solvency II**: https://eiopa.europa.eu/regulation-supervision/insurance/solvency-ii
- **IFRS 17**: https://www.ifrs.org/issued-standards/list-of-standards/ifrs-17-insurance-contracts/
- **Lloyd's of London**: https://www.lloyds.com/conducting-business/underwriting
- **Society of Actuaries**: https://www.soa.org/ (Actuarial standards and methods)
