# Regulatory Compliance Patterns

Domain-specific patterns for financial regulatory controls, reporting automation, monitoring, and audit evidence generation.

## Core Patterns

### Pattern: Regulatory Reporting Pipeline with Idempotency

```typescript
// Regulatory reports (MiFID II ARM, CFTC SDR) must be:
// 1. Submitted exactly once (no duplicates)
// 2. Submitted on time (T+1 deadline)
// 3. Resubmittable on rejection without creating duplicates
// 4. Auditable (know what was submitted, when, result)

async function submitRegulatoryReport(
  reportId: string,
  reportType: 'ARM' | 'SDR' | 'CTR' | 'SAR',
  payload: object,
): Promise<ReportSubmissionResult> {
  // Idempotency: check if already submitted
  const existing = await db.regulatoryReport.findUnique({
    where: { reportId },
  });

  if (existing?.status === 'ACCEPTED') {
    return { reportId, status: 'ACCEPTED', idempotent: true };
  }

  // If previously rejected, this is a resubmission - log it
  const isResubmission = existing?.status === 'REJECTED';

  const submission = await db.regulatoryReport.upsert({
    where: { reportId },
    create: {
      reportId, reportType, status: 'PENDING',
      payload: JSON.stringify(payload),
      submittedAt: new Date(),
    },
    update: {
      status: 'PENDING',
      payload: JSON.stringify(payload),
      submittedAt: new Date(),
      resubmissionCount: { increment: isResubmission ? 1 : 0 },
    },
  });

  const response = await reportingGateway.submit(reportType, payload);

  await db.regulatoryReport.update({
    where: { reportId },
    data: {
      status: response.accepted ? 'ACCEPTED' : 'REJECTED',
      regulatorRef: response.referenceNumber,
      rejectionReason: response.rejectionReason,
      acknowledgedAt: new Date(),
    },
  });

  if (!response.accepted) {
    await alertComplianceTeam({ reportId, reportType, rejectionReason: response.rejectionReason });
  }

  return { reportId, status: response.accepted ? 'ACCEPTED' : 'REJECTED' };
}
```

### Pattern: SOX Control Testing Evidence Capture

```typescript
// SOX controls must produce evidence of operation.
// "The control runs every day" is not evidence.
// "Here is the log showing it ran, who approved it, and the population" is evidence.

interface ControlExecutionRecord {
  controlId: string;
  executionDate: Date;
  executedBy: string;
  approvedBy: string | null;
  populationCount: number;
  sampleCount: number;
  exceptions: ControlException[];
  evidenceDocuments: string[];  // Links to screenshots, reports, exports
  conclusion: 'EFFECTIVE' | 'EXCEPTION_NOTED';
}

async function executeAndEvidenceControl(
  controlId: string,
  executor: string,
): Promise<ControlExecutionRecord> {
  // Run the actual control procedure
  const population = await fetchControlPopulation(controlId);
  const sample = selectSample(population, sampleSize(population.length));
  const exceptions = await testSampleItems(controlId, sample);

  // Generate and store evidence artifacts (screenshots, data exports)
  const evidenceDoc = await generateEvidenceDocument(controlId, population, sample, exceptions);
  const docPath = await storeEvidenceDocument(evidenceDoc);  // Immutable storage

  const record: ControlExecutionRecord = {
    controlId,
    executionDate: new Date(),
    executedBy: executor,
    approvedBy: null,  // Must be approved separately (segregation of duties)
    populationCount: population.length,
    sampleCount: sample.length,
    exceptions,
    evidenceDocuments: [docPath],
    conclusion: exceptions.length === 0 ? 'EFFECTIVE' : 'EXCEPTION_NOTED',
  };

  await db.controlExecution.create({ data: record });
  return record;
}

function sampleSize(populationSize: number): number {
  // IIA sampling guidance for key controls
  if (populationSize <= 25) return populationSize;  // Test 100% for small populations
  if (populationSize <= 100) return 25;
  if (populationSize <= 250) return 40;
  return 60;  // Cap at 60 for large populations
}
```

### Pattern: GDPR Data Retention Enforcement

```sql
-- Data retention policies mapped to table/column level
-- Automated deletion runs nightly; retained in audit log

CREATE TABLE data_retention_policies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name  TEXT NOT NULL,
    condition   TEXT,             -- Optional WHERE clause for partial retention
    retention_days  INT NOT NULL,
    legal_basis TEXT NOT NULL,    -- GDPR Article 6 lawful basis or Article 9 exception
    regulation  TEXT NOT NULL,    -- 'GDPR', 'PCI-DSS', 'MiFID2' etc.
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Example policies
INSERT INTO data_retention_policies VALUES
    (gen_random_uuid(), 'users',         'deleted_at IS NOT NULL', 30,   'Art 17 erasure request',   'GDPR'),
    (gen_random_uuid(), 'transactions',  NULL,                      2555, 'Art 6(1)(c) legal obligation (7yr)', 'MiFID2'),
    (gen_random_uuid(), 'kyc_documents', NULL,                      1825, 'Art 6(1)(c) AML legal obligation (5yr)', 'AMLD6'),
    (gen_random_uuid(), 'access_logs',   NULL,                      365,  'Art 5(1)(e) storage limitation',  'GDPR');

-- Automated retention enforcement stored procedure
CREATE OR REPLACE FUNCTION enforce_data_retention() RETURNS INT AS $$
DECLARE
    policy RECORD;
    deleted_count INT := 0;
    batch_count INT;
BEGIN
    FOR policy IN SELECT * FROM data_retention_policies LOOP
        LOOP
            EXECUTE format(
                'WITH to_delete AS (
                    SELECT id FROM %I
                    WHERE created_at < NOW() - INTERVAL ''%s days''
                    %s
                    LIMIT 1000
                )
                DELETE FROM %I WHERE id IN (SELECT id FROM to_delete)',
                policy.table_name,
                policy.retention_days,
                COALESCE('AND ' || policy.condition, ''),
                policy.table_name
            );
            GET DIAGNOSTICS batch_count = ROW_COUNT;
            deleted_count := deleted_count + batch_count;
            EXIT WHEN batch_count < 1000;  -- No more rows to delete
        END LOOP;
    END LOOP;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
```

### Pattern: Compliance Monitoring Dashboard Feed

```python
from dataclasses import dataclass
from datetime import datetime
from enum import Enum

class ComplianceStatus(Enum):
    GREEN = 'GREEN'    # All checks passing
    AMBER = 'AMBER'   # Warnings; no breach yet
    RED = 'RED'       # Active violation; action required

@dataclass
class ComplianceMetric:
    metric_id: str
    regulation: str
    description: str
    current_value: float
    threshold: float
    status: ComplianceStatus
    last_checked: datetime
    breach_deadline: datetime | None  # When regulatory breach timer expires

def compute_mifid_reporting_rate(from_date, to_date) -> ComplianceMetric:
    total_reportable = count_reportable_trades(from_date, to_date)
    reported_on_time = count_reported_on_time(from_date, to_date)

    rate = (reported_on_time / total_reportable * 100) if total_reportable else 100.0

    return ComplianceMetric(
        metric_id='MIFID2_ARM_TIMELINESS',
        regulation='MiFID II Article 26',
        description='% of trades reported to ARM by T+1',
        current_value=rate,
        threshold=100.0,  # Must be 100%; any missed = breach
        status=ComplianceStatus.GREEN if rate == 100.0
               else ComplianceStatus.AMBER if rate >= 99.0
               else ComplianceStatus.RED,
        last_checked=datetime.utcnow(),
        breach_deadline=None,
    )
```

## Anti-Patterns

### Anti-Pattern: Spreadsheet-Based Compliance Controls

```
WRONG: SOX control = "Finance team manually reviews the report in Excel each month"
- No automated evidence capture
- Human error possible and not detectable
- Reviewer could be the one committing fraud
- Cannot be tested efficiently by external auditor
- No version control on the spreadsheet
- SOX auditors increasingly requiring system-generated evidence

RIGHT: Automated control with evidence
- System generates exception report automatically
- Exceptions sent to reviewer dashboard for approval
- Reviewer approval logged with timestamp and user ID
- Zero-exception runs also logged (proves control ran even when nothing to flag)
- Evidence stored immutably; accessible for PCAOB review
```

### Anti-Pattern: Treating Regulation as Binary Pass/Fail

```python
# WRONG: "We're GDPR compliant" or "We're not"
gdpr_compliant = True  # Set by checkbox in project tracker

# RIGHT: Regulation has dozens of articles, each with multiple sub-requirements
# Track compliance per requirement, not per regulation
gdpr_compliance = {
    'Art_5_1_a_lawfulness': 'IMPLEMENTED',
    'Art_5_1_b_purpose_limitation': 'PARTIAL',   # Gap: analytics use case unclear
    'Art_5_1_e_storage_limitation': 'MISSING',   # No automated retention enforcement
    'Art_17_right_to_erasure': 'IMPLEMENTED',
    'Art_30_records_of_processing': 'PARTIAL',   # RoPA not fully up to date
    'Art_32_security_measures': 'IMPLEMENTED',
}
# Now you have an actionable gap list, not a false binary
```

### Anti-Pattern: Reporting Delay Tolerance

```
WRONG: "We'll fix the MiFID II ARM reporting bug next sprint"
- MiFID II: T+1 deadline - every missed day is a reportable breach
- CFTC SDR: same-day reporting for block trades, T+1 for others
- FinCEN SAR: 30-day window from detection (60 days if no suspect identified)
- CTR: 15 calendar days from transaction date

Regulatory reporting deadlines cannot be treated as flexible sprint commitments.
Every day of delay is an additional violation. Self-report to regulator immediately
if you cannot meet a deadline - regulators treat self-disclosure more favorably than discovery.
```

## References

- **MiFID II / MiFIR (EU)**: https://www.esma.europa.eu/policy-rules/mifid-ii-and-mifir
- **ESMA RTS 22** (MiFID II transaction reporting fields): https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32017R0590
- **CFTC Swap Reporting**: https://www.cftc.gov/PressRoom/PressReleases/8383-21
- **SOX Section 302 and 404**: https://pcaobus.org/Standards/Auditing/Pages/AS2201.aspx
- **GDPR Full Text**: https://gdpr-info.eu/
- **Basel III Standards (BIS)**: https://www.bis.org/bcbs/basel3.htm
- **FinCEN BSA Regulations**: https://www.fincen.gov/resources/statutes-regulations/bank-secrecy-act
- **FATF 40 Recommendations**: https://www.fatf-gafi.org/en/topics/fatf-recommendations.html
