# /kyc-aml

Identity verification, sanctions screening, AML monitoring, and regulatory filing workflows.

## Trigger

`/kyc-aml <action> [options]`

## Actions

- `verify` - Run KYC verification for a new or existing customer
- `screen` - Screen entity against sanctions, PEP, and adverse media databases
- `monitor` - Evaluate a transaction or pattern for AML indicators
- `file` - Prepare SAR or CTR filing

## Options

- `--customer-id <id>` - Customer to operate on
- `--risk-level <sdd|cdd|edd>` - Specify KYC tier (default: determined by risk engine)
- `--screen-lists <ofac,un,eu,uk,all>` - Screening lists (default: all)
- `--transaction-id <id>` - Transaction for monitoring
- `--filing-type <sar|ctr>` - Regulatory filing type

## Process

### verify

```typescript
interface KYCVerificationRequest {
  customerId: string;
  customerType: 'INDIVIDUAL' | 'ENTITY';

  // Individual
  firstName?: string;
  lastName?: string;
  dateOfBirth?: Date;
  nationality?: string;
  idDocument?: {
    type: 'PASSPORT' | 'DRIVERS_LICENSE' | 'NATIONAL_ID';
    number: string;
    issuingCountry: string;
    expirationDate: Date;
    frontImageUrl: string;
    backImageUrl?: string;
  };
  selfieImageUrl?: string;

  // Entity
  registeredName?: string;
  registrationNumber?: string;
  registrationCountry?: string;
  incorporationDate?: Date;
  businessActivity?: string;
  beneficialOwners?: BeneficialOwner[];
}

interface BeneficialOwner {
  name: string;
  dateOfBirth: Date;
  nationality: string;
  ownershipPercentage: number;  // FinCEN CDD Rule: report all >= 25%
  controlPerson: boolean;       // Significant management control
}

async function runKYCVerification(request: KYCVerificationRequest): Promise<KYCResult> {
  const riskScore = await riskEngine.scoreCustomer(request);
  const tier = determineTier(riskScore); // SDD / CDD / EDD

  // Document verification (Jumio, Onfido, etc.)
  if (request.idDocument) {
    const docVerification = await documentVerifier.verify({
      documentType: request.idDocument.type,
      frontImage: request.idDocument.frontImageUrl,
      backImage: request.idDocument.backImageUrl,
    });
    if (!docVerification.authentic) {
      return { status: 'REJECTED', reason: 'Document authenticity check failed' };
    }
  }

  // Biometric check
  if (request.selfieImageUrl && request.idDocument) {
    const biometricMatch = await faceMatch.compare(
      request.idDocument.frontImageUrl,
      request.selfieImageUrl
    );
    if (biometricMatch.score < 0.85) {
      return { status: 'REJECTED', reason: 'Biometric face match below threshold' };
    }
  }

  // Sanctions + PEP screening
  const screeningResult = await sanctionsScreener.screen({
    name: `${request.firstName} ${request.lastName}`,
    dateOfBirth: request.dateOfBirth,
    nationality: request.nationality,
  });

  if (screeningResult.sanctionsMatch && screeningResult.matchConfidence > 0.9) {
    return { status: 'BLOCKED', reason: 'Sanctions match', matchDetail: screeningResult };
  }

  return {
    status: tier === 'EDD' ? 'PENDING_EDD' : 'APPROVED',
    tier,
    riskScore,
    sanctionsMatch: screeningResult.sanctionsMatch,
    pepStatus: screeningResult.pepMatch,
    verifiedAt: new Date(),
  };
}
```

### screen

```typescript
interface ScreeningRequest {
  name: string;
  aliases?: string[];
  dateOfBirth?: Date;
  nationality?: string;
  entityType: 'INDIVIDUAL' | 'ORGANIZATION';
}

// Fuzzy matching against OFAC SDN list
async function screenAgainstOFAC(request: ScreeningRequest): Promise<ScreeningMatch[]> {
  const matches: ScreeningMatch[] = [];

  for (const sdnEntry of ofacList.entries) {
    // Exact match first
    if (sdnEntry.name.toLowerCase() === request.name.toLowerCase()) {
      matches.push({ entry: sdnEntry, confidence: 1.0, matchType: 'EXACT' });
      continue;
    }

    // Fuzzy match with Jaro-Winkler (better for names than Levenshtein)
    const similarity = jaroWinkler(
      request.name.toLowerCase(),
      sdnEntry.name.toLowerCase()
    );

    if (similarity >= 0.85) {
      matches.push({ entry: sdnEntry, confidence: similarity, matchType: 'FUZZY' });
    }
  }

  // Also check aliases
  for (const alias of request.aliases ?? []) {
    // ... same logic
  }

  return matches.filter(m => m.confidence >= 0.80); // Threshold for human review
}
```

### monitor

```sql
-- Structuring detection: multiple transactions just below $10,000 within a short window
-- (structuring to avoid CTR filing is a federal crime - 31 USC § 5324)
SELECT
    customer_id,
    SUM(amount) AS total_in_24hrs,
    COUNT(*) AS transaction_count,
    MIN(amount) AS min_transaction,
    MAX(amount) AS max_transaction
FROM cash_transactions
WHERE transaction_time > NOW() - INTERVAL '24 hours'
  AND amount BETWEEN 3000 AND 9999  -- Suspiciously below CTR threshold
GROUP BY customer_id
HAVING COUNT(*) >= 2
   AND SUM(amount) >= 10000;  -- Combined would trigger CTR
```

### file (SAR Preparation)

SAR narrative template following FinCEN guidance:

```
SUSPICIOUS ACTIVITY REPORT - SAR NARRATIVE

Filing Institution: [Institution Name / LEI]
Subject: [Customer Name] | Account: [Account Number]
SAR Filing Reason: [Select: Structuring / Money Laundering / Fraud / Other]
Activity Period: [Start Date] to [End Date]
Total Suspicious Amount: USD [Amount]

WHAT: Describe the suspicious activity in detail. Include transaction types, amounts,
dates, and why they are unusual relative to customer's known profile and expected activity.

WHO: Identify all parties involved. Include names, addresses, account numbers,
and relationship to the subject.

WHERE: Financial institutions and geographic locations involved.

WHEN: Timeline of suspicious activity.

HOW: Method used. E.g., "Customer conducted 14 cash deposits of $9,800 each over
30 days through different branches, totaling $137,200. Pattern is consistent with
structuring to avoid CTR reporting requirements."

FILING NOTE: This SAR is filed in compliance with 31 CFR § 1020.320.
Disclosure of this filing to the subject is prohibited under 31 USC § 5318(g)(2).
```

## Examples

```bash
# Run CDD verification for a new individual customer
/kyc-aml verify --customer-id CUST-001 --risk-level cdd

# Screen entity against all sanctions lists
/kyc-aml screen --customer-id ENTITY-001 --screen-lists all

# Run AML monitoring on a transaction pattern
/kyc-aml monitor --customer-id CUST-001 --transaction-id TXN-BATCH-001

# Prepare SAR for filing
/kyc-aml file --filing-type sar --customer-id CUST-001
```
