# Financial Reporting Patterns

Domain-specific patterns for financial statement generation, period-end close, regulatory reporting, multi-currency consolidation, and XBRL compliance.

## Core Patterns

### Pattern: Double-Entry Verification in Reports

Every trial balance query must verify the accounting equation holds. This should run as a gate before any report is generated.

```sql
-- A healthy trial balance: debits = credits for all posted entries
SELECT
    SUM(CASE WHEN debit_credit = 'D' THEN amount ELSE 0 END) AS total_debits,
    SUM(CASE WHEN debit_credit = 'C' THEN amount ELSE 0 END) AS total_credits,
    SUM(CASE WHEN debit_credit = 'D' THEN amount ELSE 0 END) -
    SUM(CASE WHEN debit_credit = 'C' THEN amount ELSE 0 END) AS imbalance
FROM journal_entry_lines jel
JOIN journal_entries je ON je.id = jel.journal_entry_id
WHERE je.period = :period
  AND je.status = 'POSTED';
-- imbalance must be exactly 0. Any deviation = bug in journal entry logic.
```

### Pattern: Period-End Close Sequence

Close operations must happen in strict order. Running consolidation before sub-ledgers are closed produces incorrect intercompany eliminations.

```typescript
const closeSequence = [
  { step: 'AR_CLOSE',         description: 'Accounts Receivable sub-ledger close' },
  { step: 'AP_CLOSE',         description: 'Accounts Payable sub-ledger close' },
  { step: 'PAYROLL_CLOSE',    description: 'Payroll accruals posted' },
  { step: 'INVENTORY_CLOSE',  description: 'Inventory count reconciled and posted' },
  { step: 'FIXED_ASSETS',     description: 'Depreciation runs completed' },
  { step: 'ACCRUALS',         description: 'Month-end accruals and prepayments posted' },
  { step: 'INTERCOMPANY',     description: 'Intercompany invoices matched and confirmed' },
  { step: 'FX_REVALUATION',   description: 'Foreign currency monetary items revalued at closing rate' },
  { step: 'GL_CLOSE',         description: 'General Ledger period locked against new postings' },
  { step: 'IC_ELIMINATION',   description: 'Intercompany balances eliminated in consolidation' },
  { step: 'CONSOLIDATION',    description: 'Group financial statements generated' },
  { step: 'REPORTING',        description: 'Reports distributed / filed' },
];

async function runClose(period: string, entityId: string): Promise<void> {
  for (const step of closeSequence) {
    const result = await executeCloseStep(step.step, period, entityId);
    if (!result.success) {
      throw new Error(`Close halted at ${step.step}: ${result.error}`);
      // Do NOT continue - downstream steps will produce wrong results
    }
    await auditLog.record({ step: step.step, period, entityId, completedAt: new Date() });
  }
}
```

### Pattern: Multi-Currency FX Translation (IAS 21)

```typescript
interface FXTranslation {
  entityCurrency: string;         // Functional currency
  presentationCurrency: string;   // Currency of consolidated statements
  closingRate: Decimal;           // Balance sheet rate (closing spot)
  averageRate: Decimal;           // Income statement rate (period average)
  historicalEquityRate: Decimal;  // Rate when equity was contributed
}

function translateBalanceSheet(
  balances: AccountBalance[],
  translation: FXTranslation
): TranslatedBalance[] {
  return balances.map(balance => {
    let translatedAmount: Decimal;
    let translationDifference: Decimal;

    if (balance.accountType === 'EQUITY' && balance.subType === 'SHARE_CAPITAL') {
      // Equity items at historical rate
      translatedAmount = balance.amount.mul(translation.historicalEquityRate);
    } else {
      // All other balance sheet items at closing rate
      translatedAmount = balance.amount.mul(translation.closingRate);
    }

    return { ...balance, translatedAmount, translationRate: translation.closingRate };
  });
}

// Translation difference = plug to make the consolidated balance sheet balance
// Goes to OCI (Other Comprehensive Income), not P&L
function calculateTranslationDifference(
  openingNetAssets: Decimal,
  closingNetAssets: Decimal,
  periodProfit: Decimal,
  translation: FXTranslation
): Decimal {
  const openingTranslated = openingNetAssets.mul(translation.closingRate);
  const profitTranslated = periodProfit.mul(translation.averageRate);
  const theoretical = openingTranslated.add(profitTranslated);
  return closingNetAssets.sub(theoretical); // Residual = translation difference
}
```

### Pattern: XBRL Taxonomy Mapping

Map internal COA codes to XBRL taxonomy concepts. Mapping must be versioned - GAAP and IFRS taxonomies change annually.

```typescript
interface XBRLMapping {
  coaCode: string;
  taxonomy: 'us-gaap' | 'ifrs-full';
  taxonomyVersion: string;   // e.g., '2024'
  elementName: string;       // e.g., 'RevenueFromContractWithCustomerExcludingAssessedTax'
  balance: 'credit' | 'debit';
  periodType: 'instant' | 'duration';
}

// Example mappings
const mappings: XBRLMapping[] = [
  {
    coaCode: '4000',
    taxonomy: 'us-gaap',
    taxonomyVersion: '2024',
    elementName: 'RevenueFromContractWithCustomerExcludingAssessedTax',
    balance: 'credit',
    periodType: 'duration',
  },
  {
    coaCode: '5000',
    taxonomy: 'us-gaap',
    taxonomyVersion: '2024',
    elementName: 'CostOfGoodsAndServicesSold',
    balance: 'debit',
    periodType: 'duration',
  },
];
```

## Anti-Patterns

### Anti-Pattern: Point-in-Time Snapshots Without Audit Trail

Storing only the final reported numbers without the source journal entries makes restatements impossible and fails audit. Every reported figure must be traceable to posted journal entries.

### Anti-Pattern: Mixing GAAP and IFRS Without Documentation

Some companies apply different standards to different entities in the same group. This is legitimate but must be explicitly documented. Undocumented mixed-framework consolidations produce reports that appear to be one standard but contain elements of another.

### Anti-Pattern: Hardcoded FX Rates

```typescript
// WRONG: Hardcoded rate - when was this valid? By whom was it approved?
const usdToEur = 0.92;
const eurAmount = usdAmount * usdToEur;

// RIGHT: Rates from auditable source with effective date
const rate = await fxRateService.getRate({
  fromCurrency: 'USD',
  toCurrency: 'EUR',
  rateDate: reportingDate,
  rateType: 'CLOSING',  // or 'AVERAGE' for income statement
  source: 'ECB',        // European Central Bank reference rates
});
const eurAmount = usdAmount.mul(rate.rate);
```

### Anti-Pattern: Silent Rounding in Financial Calculations

Financial statements require exact decimal precision. JavaScript's `number` type introduces floating-point errors.

```typescript
// WRONG: Floating point error accumulates over many calculations
let total = 0;
transactions.forEach(t => total += t.amount); // 0.1 + 0.2 = 0.30000000000000004

// RIGHT: Use Decimal.js or similar arbitrary-precision library
import Decimal from 'decimal.js';
Decimal.set({ precision: 20, rounding: Decimal.ROUND_HALF_UP });

let total = new Decimal(0);
transactions.forEach(t => total = total.plus(new Decimal(t.amount)));
```

## References

- **FASB ASC**: https://asc.fasb.org/ (US GAAP codification)
- **IFRS Standards**: https://www.ifrs.org/issued-standards/
- **US-GAAP XBRL Taxonomy**: https://xbrl.fasb.org/
- **IFRS XBRL Taxonomy**: https://www.ifrs.org/news-and-events/news/2024/01/ifrs-foundation-publishes-2024-xbrl-taxonomy/
- **SEC EDGAR iXBRL Guidance**: https://www.sec.gov/structureddata/
- **IAS 21 - FX Effects**: https://www.ifrs.org/issued-standards/list-of-standards/ias-21-the-effects-of-changes-in-foreign-exchange-rates/
- **Decimal.js**: https://mikemcl.github.io/decimal.js/
