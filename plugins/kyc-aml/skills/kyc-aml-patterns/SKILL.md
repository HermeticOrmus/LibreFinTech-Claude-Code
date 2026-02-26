# KYC/AML Patterns

Domain-specific patterns for identity verification, sanctions screening, transaction monitoring, UBO resolution, and regulatory filing.

## Core Patterns

### Pattern: Risk-Based KYC Tiering

```typescript
interface CustomerRiskProfile {
  customerId: string;
  riskScore: number;        // 0-100
  riskTier: 'LOW' | 'MEDIUM' | 'HIGH' | 'VERY_HIGH';
  riskFactors: string[];    // What drove the score
  kycTier: 'SDD' | 'CDD' | 'EDD';
  reviewFrequency: 'ANNUAL' | 'BIENNIAL' | 'TRIENNIAL';
  lastReviewDate: Date;
  nextReviewDate: Date;
}

function classifyRisk(customer: CustomerData): CustomerRiskProfile {
  let score = 0;
  const factors: string[] = [];

  // Geography risk
  const countryRisk = fatfCountryRisk[customer.country];
  if (countryRisk === 'HIGH') { score += 30; factors.push(`High-risk jurisdiction: ${customer.country}`); }
  else if (countryRisk === 'MEDIUM') { score += 15; }

  // Industry/business risk
  if (HIGH_RISK_INDUSTRIES.includes(customer.businessType)) {
    score += 20;
    factors.push(`High-risk industry: ${customer.businessType}`);
  }

  // PEP status
  if (customer.isPEP) { score += 30; factors.push('Politically Exposed Person'); }

  // Product/service risk
  if (customer.products.includes('CRYPTO')) { score += 15; factors.push('Crypto transactions'); }
  if (customer.products.includes('CASH_INTENSIVE')) { score += 20; factors.push('Cash-intensive business'); }

  // Transaction volume
  if (customer.expectedMonthlyVolume > 100000) { score += 10; factors.push('High transaction volume'); }

  const tier = score >= 60 ? 'VERY_HIGH' : score >= 40 ? 'HIGH' : score >= 20 ? 'MEDIUM' : 'LOW';
  const kycTier = tier === 'VERY_HIGH' || tier === 'HIGH' ? 'EDD' : tier === 'MEDIUM' ? 'CDD' : 'SDD';

  return {
    customerId: customer.id,
    riskScore: Math.min(score, 100),
    riskTier: tier,
    riskFactors: factors,
    kycTier,
    reviewFrequency: kycTier === 'EDD' ? 'ANNUAL' : kycTier === 'CDD' ? 'BIENNIAL' : 'TRIENNIAL',
    lastReviewDate: new Date(),
    nextReviewDate: addYears(new Date(), kycTier === 'EDD' ? 1 : kycTier === 'CDD' ? 2 : 3),
  };
}
```

### Pattern: UBO Graph Traversal

```typescript
// Find all natural persons (UBOs) at the end of the ownership chain
async function resolveUBOs(
  entityId: string,
  ownershipThreshold: number = 0.25,  // FinCEN CDD Rule: 25%
  visitedEntities: Set<string> = new Set()
): Promise<UBO[]> {
  if (visitedEntities.has(entityId)) {
    throw new Error(`Circular ownership detected at entity ${entityId}`);
  }
  visitedEntities.add(entityId);

  const owners = await db.ownership.findMany({
    where: { ownedEntityId: entityId, ownershipPercentage: { gte: ownershipThreshold } },
    include: { ownerEntity: true },
  });

  const ubos: UBO[] = [];

  for (const ownership of owners) {
    if (ownership.ownerEntity.type === 'INDIVIDUAL') {
      ubos.push({
        individualId: ownership.ownerEntity.id,
        name: ownership.ownerEntity.name,
        ownershipPercentage: ownership.ownershipPercentage,
        ownershipChain: [entityId, ownership.ownerEntity.id],
      });
    } else {
      // Corporate owner: recurse to find natural persons behind it
      // Ownership is cumulative: 60% of 50% = 30% effective ownership
      const childUBOs = await resolveUBOs(
        ownership.ownerEntity.id,
        ownershipThreshold / ownership.ownershipPercentage,
        visitedEntities
      );
      ubos.push(...childUBOs.map(ubo => ({
        ...ubo,
        ownershipPercentage: ubo.ownershipPercentage * ownership.ownershipPercentage,
        ownershipChain: [entityId, ...ubo.ownershipChain],
      })));
    }
  }

  return ubos;
}
```

### Pattern: SAR Filing Automation with Tipping-Off Prevention

```typescript
// SAR filing workflow - must NOT notify the subject
async function createSARCase(
  customerId: string,
  transactionIds: string[],
  suspiciousActivity: string,
  totalAmount: Decimal
): Promise<SARCase> {
  // Create SAR case in a separate, access-controlled database
  // AML ops should not have access to customer-facing systems and vice versa
  const sarCase = await amlDb.sarCase.create({
    data: {
      caseId: generateId(),
      status: 'DRAFT',
      customerId,
      transactionIds,
      suspiciousActivity,
      totalAmount,
      activityStartDate: await getEarliestTransactionDate(transactionIds),
      activityEndDate: new Date(),
      filingDeadline: addDays(new Date(), 30), // 30-day FinCEN deadline
      assignedTo: null,  // Pending assignment to AML investigator
      createdAt: new Date(),
    },
  });

  // CRITICAL: Do not alert the customer in any way
  // Do not freeze account (this would tip off)
  // Do not send communication that references investigation

  // Internal alert to AML team only
  await internalAlert.send({
    to: 'aml-team@institution.com',
    subject: `SAR Case Created - ${sarCase.caseId}`,
    priority: 'HIGH',
    caseId: sarCase.caseId,
  });

  return sarCase;
}
```

### Pattern: pKYC (Perpetual KYC) Event Triggers

```typescript
// Events that should trigger immediate KYC re-review
const pKYCTriggers = [
  {
    event: 'ADVERSE_MEDIA_HIT',
    description: 'New adverse media result for customer name',
    action: 'ESCALATE_TO_EDD',
    urgency: 'HIGH',
  },
  {
    event: 'SANCTIONS_MATCH',
    description: 'Customer name appears in updated sanctions list',
    action: 'FREEZE_AND_REVIEW',
    urgency: 'CRITICAL',
  },
  {
    event: 'TRANSACTION_PROFILE_DEVIATION',
    description: 'Transaction amounts/volumes significantly outside established profile',
    action: 'TRIGGER_REVIEW',
    urgency: 'MEDIUM',
  },
  {
    event: 'COUNTRY_RISK_CHANGE',
    description: 'Customer country added to FATF grey/black list',
    action: 'ESCALATE_TO_EDD',
    urgency: 'HIGH',
  },
  {
    event: 'PEP_STATUS_CHANGE',
    description: 'Customer identified as PEP in screening update',
    action: 'ESCALATE_TO_EDD',
    urgency: 'HIGH',
  },
];
```

## Anti-Patterns

### Anti-Pattern: One-Time KYC Without Refresh

KYC done once at onboarding goes stale. A customer who was clean at onboarding can become a sanctions target, be arrested for fraud, or be identified as a PEP. Without periodic re-screening and trigger-based review, your institution has no ongoing AML controls - this is a regulatory examination finding.

### Anti-Pattern: Binary Pass/Fail Without Risk Scoring

```typescript
// WRONG: Binary decision
if (sanctionsMatch) {
  customer.status = 'BLOCKED';
} else {
  customer.status = 'APPROVED';
}

// RIGHT: Risk-scored decision with human review for borderline cases
if (sanctionsMatch.confidence > 0.95) {
  customer.status = 'BLOCKED';  // High-confidence match: hard block
} else if (sanctionsMatch.confidence > 0.75) {
  customer.status = 'PENDING_REVIEW';  // Borderline: human review
  await createReviewCase(customer.id, sanctionsMatch);
} else {
  customer.status = 'APPROVED';  // Low-confidence: likely false positive
}
```

### Anti-Pattern: No Adverse Media Screening

Sanctions lists are reactive - they name people after they've been designated. Adverse media (news articles about fraud, corruption, money laundering) often surfaces months before a formal designation. Not screening adverse media is a significant AML gap.

## References

- **FinCEN CDD Rule**: https://www.fincen.gov/resources/statutes-and-regulations/cdd-final-rule
- **FATF 40 Recommendations**: https://www.fatf-gafi.org/recommendations.html
- **OFAC SDN List**: https://sanctionssearch.ofac.treas.gov/
- **BSA/AML Examination Manual (FFIEC)**: https://bsaaml.ffiec.gov/manual
- **EU 6AMLD**: Sixth Anti-Money Laundering Directive
- **Wolfsberg Group Principles**: https://www.wolfsberg-principles.com/
- **FinCEN SAR Filing Instructions**: https://www.fincen.gov/sites/default/files/shared/SARFIN.pdf
- **Jumio eKYC**: https://www.jumio.com/
- **Onfido**: https://onfido.com/
