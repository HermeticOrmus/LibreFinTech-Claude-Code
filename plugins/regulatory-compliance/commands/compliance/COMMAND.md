# /compliance

Regulatory compliance workflows: gap analysis, control evidence, regulatory reporting, and breach monitoring.

## Trigger

`/compliance <action> [options]`

## Actions

- `gap-analysis` - Map regulatory requirements to existing controls; identify gaps
- `report` - Generate regulatory submission (MiFID II ARM, CFTC SDR, CTR/SAR)
- `monitor` - Run continuous compliance checks against configured rules
- `evidence` - Generate SOX/audit evidence package for a control

## Options

- `--regulation <mifid2|dodd-frank|sox|gdpr|bsa|pci-dss|basel3>` - Target regulation
- `--entity-id <id>` - Legal entity (LEI preferred)
- `--from <ISO8601>` - Reporting period start
- `--to <ISO8601>` - Reporting period end
- `--report-type <arm|sdr|ctr|sar|ccar>` - Report type for regulatory submissions
- `--control-id <id>` - Specific control for evidence generation

## Process

### gap-analysis

Map regulation articles to implemented controls:

```python
from dataclasses import dataclass
from enum import Enum

class ControlStatus(Enum):
    IMPLEMENTED = 'IMPLEMENTED'
    PARTIAL = 'PARTIAL'
    MISSING = 'MISSING'
    NOT_APPLICABLE = 'NOT_APPLICABLE'

@dataclass
class RequirementMapping:
    regulation: str
    article: str
    requirement_description: str
    control_id: str | None
    control_description: str | None
    status: ControlStatus
    evidence_location: str | None
    gap_description: str | None
    remediation_owner: str | None
    remediation_due: str | None  # ISO 8601 date

def run_gap_analysis(regulation: str, entity_profile: dict) -> list[RequirementMapping]:
    """
    Load regulation requirements matrix; test each control against evidence store.
    Output drives remediation roadmap and board-level compliance reporting.
    """
    requirements = load_regulation_matrix(regulation)  # YAML/DB of all articles
    controls = load_control_inventory(entity_profile['entity_id'])
    mappings = []

    for req in requirements:
        mapped_control = controls.get(req.control_mapping_tag)
        if not mapped_control:
            mappings.append(RequirementMapping(
                regulation=regulation,
                article=req.article,
                requirement_description=req.description,
                control_id=None,
                control_description=None,
                status=ControlStatus.MISSING,
                evidence_location=None,
                gap_description=f"No control mapped for {req.article}",
                remediation_owner=None,
                remediation_due=None,
            ))
        else:
            evidence_ok = verify_control_evidence(mapped_control, req)
            mappings.append(RequirementMapping(
                regulation=regulation,
                article=req.article,
                requirement_description=req.description,
                control_id=mapped_control.id,
                control_description=mapped_control.description,
                status=ControlStatus.IMPLEMENTED if evidence_ok else ControlStatus.PARTIAL,
                evidence_location=mapped_control.evidence_path,
                gap_description=None if evidence_ok else 'Evidence incomplete or stale',
                remediation_owner=mapped_control.owner,
                remediation_due=None,
            ))

    return mappings
```

### report (MiFID II transaction report)

```python
# MiFID II / MiFIR Article 26: Transaction reporting to NCA (or ARM)
# Each trade must be reported by T+1 (next business day)
# 65 mandatory fields in ESMA's technical standard (RTS 22)

def build_mifid_transaction_report(trade: Trade, firm: FirmProfile) -> dict:
    return {
        # Field 1: Transaction reference number (unique per report)
        'transaction_reference_number': f"{firm.lei}-{trade.id}",
        # Field 4: Trading day - ISO 8601 date
        'trading_day': trade.executed_at.date().isoformat(),
        # Field 5: Trading time - ISO 8601 timestamp to microsecond precision
        'trading_time': trade.executed_at.strftime('%Y-%m-%dT%H:%M:%S.%fZ'),
        # Field 6: Financial instrument identification (ISIN)
        'instrument_identification_code': trade.isin,
        # Field 14: Quantity
        'quantity': str(trade.quantity),
        # Field 15: Quantity currency (for bonds/derivatives)
        'quantity_currency': trade.currency,
        # Field 16: Price
        'price': str(trade.price),
        # Field 17: Price currency
        'price_currency': trade.price_currency,
        # Field 19: Net amount (price * quantity * contract size)
        'net_amount': str(trade.notional_value),
        # Field 26: Venue - MIC code (e.g., XLON for LSE, XNAS for Nasdaq)
        'trading_venue': trade.venue_mic,
        # Fields 27-31: Counterparty (buy side)
        'buyer_identification_code': trade.buyer_lei,  # LEI preferred
        # Fields 32-36: Counterparty (sell side)
        'seller_identification_code': trade.seller_lei,
        # Field 37: Investment decision within firm - trader ID
        'investment_decision_within_firm': trade.trader_id,
        # Fields 59-64: Transmission of order details (if applicable)
    }
```

### monitor

Continuous compliance monitoring rules:

```typescript
interface ComplianceRule {
  id: string;
  regulation: string;
  description: string;
  check: (context: ComplianceContext) => Promise<ComplianceViolation | null>;
  severity: 'INFO' | 'WARNING' | 'VIOLATION' | 'BREACH';
}

const COMPLIANCE_RULES: ComplianceRule[] = [
  {
    id: 'MIFID2-TRANSACTION-REPORT-TIMELINESS',
    regulation: 'MiFID II Article 26',
    description: 'All trades must be reported to ARM by T+1 close',
    severity: 'BREACH',
    check: async (ctx) => {
      const unreported = await db.trade.findMany({
        where: {
          executedAt: { gte: ctx.previousBusinessDay, lt: ctx.businessDayEnd },
          armReportedAt: null,
          reportingRequired: true,
        },
      });
      if (unreported.length > 0) {
        return {
          ruleId: 'MIFID2-TRANSACTION-REPORT-TIMELINESS',
          affectedCount: unreported.length,
          tradeIds: unreported.map(t => t.id),
          message: `${unreported.length} trades not reported to ARM by T+1 deadline`,
        };
      }
      return null;
    },
  },
  {
    id: 'GDPR-DATA-RETENTION',
    regulation: 'GDPR Article 5(1)(e)',
    description: 'Personal data not retained beyond defined retention period',
    severity: 'VIOLATION',
    check: async (ctx) => {
      const expired = await db.personalDataRecord.count({
        where: { retentionExpiry: { lt: new Date() }, deletedAt: null },
      });
      if (expired > 0) {
        return { ruleId: 'GDPR-DATA-RETENTION', affectedCount: expired,
                 message: `${expired} records exceed GDPR retention period` };
      }
      return null;
    },
  },
];
```

### evidence

SOX control evidence package:

```typescript
interface SOXEvidencePackage {
  controlId: string;
  controlObjective: string;
  testingPeriod: { from: Date; to: Date };
  populationSize: number;
  sampleSize: number;           // IIA sampling guidance: 25-60 for key controls
  exceptions: number;
  exceptionRate: number;
  operatingEffectiveness: 'EFFECTIVE' | 'INEFFECTIVE' | 'SIGNIFICANT_DEFICIENCY' | 'MATERIAL_WEAKNESS';
  evidenceArtifacts: string[];  // S3 paths, document IDs
  testedBy: string;
  approvedBy: string;
  testDate: Date;
}

// Material weakness threshold (PCAOB AS 2201.69):
// More than remote likelihood that a material misstatement won't be prevented/detected
// Significant deficiency: less severe but warrants attention of audit committee
```

## Examples

```bash
# Run MiFID II gap analysis for EU investment firm
/compliance gap-analysis --regulation mifid2 --entity-id ENTITY-001

# Generate T+1 transaction reports for ARM submission
/compliance report --regulation mifid2 --report-type arm --from 2024-11-01 --to 2024-11-01

# Run daily compliance monitoring checks
/compliance monitor --regulation mifid2 --entity-id ENTITY-001

# Generate SOX evidence package for user access review control
/compliance evidence --regulation sox --control-id UAR-001 --from 2024-07-01 --to 2024-09-30
```
