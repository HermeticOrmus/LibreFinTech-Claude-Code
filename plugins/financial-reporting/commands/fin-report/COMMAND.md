# /fin-report

Generate, validate, and export financial statements. Covers P&L, balance sheet, cash flow, XBRL export, and period-close reconciliation.

## Trigger

`/fin-report <action> [options]`

## Actions

- `generate` - Generate financial statements from trial balance data
- `reconcile` - Run period-end reconciliation checks
- `export` - Export statements in regulatory format (XBRL, iXBRL, CSV)
- `validate` - Validate statements for mathematical accuracy and standard compliance

## Options

- `--period <YYYY-MM>` - Reporting period
- `--entity <id>` - Legal entity identifier
- `--framework <gaap|ifrs>` - Accounting framework
- `--currency <ISO4217>` - Presentation currency
- `--comparative` - Include prior period comparative figures
- `--format <xbrl|ixbrl|csv|pdf>` - Export format

## Process

### generate

Pulls from the chart of accounts mapping and trial balance to produce financial statements.

```sql
-- P&L generation from trial balance
-- Assumes COA has report_line mapping to standard P&L structure
WITH trial_balance AS (
    SELECT
        a.account_code,
        a.account_name,
        a.account_type,
        a.report_line,     -- Maps to P&L line: 'revenue', 'cogs', 'opex', etc.
        a.report_order,
        SUM(
            CASE
                WHEN je.debit_credit = 'D' THEN je.amount
                ELSE -je.amount
            END
        ) AS net_balance
    FROM accounts a
    JOIN journal_entry_lines jel ON jel.account_id = a.id
    JOIN journal_entries je ON je.id = jel.journal_entry_id
    WHERE je.period = :period
      AND je.entity_id = :entity_id
      AND je.status = 'POSTED'
    GROUP BY a.account_code, a.account_name, a.account_type, a.report_line, a.report_order
),
pl_lines AS (
    SELECT
        report_line,
        report_order,
        SUM(net_balance) AS line_total
    FROM trial_balance
    WHERE account_type IN ('REVENUE', 'EXPENSE', 'COGS')
    GROUP BY report_line, report_order
)
SELECT
    report_line,
    line_total,
    SUM(line_total) OVER (ORDER BY report_order ROWS UNBOUNDED PRECEDING) AS cumulative
FROM pl_lines
ORDER BY report_order;

-- Balance sheet validation: Assets must equal Liabilities + Equity
SELECT
    SUM(CASE WHEN account_type = 'ASSET' THEN net_balance ELSE 0 END) AS total_assets,
    SUM(CASE WHEN account_type IN ('LIABILITY', 'EQUITY') THEN net_balance ELSE 0 END) AS total_liabilities_equity,
    SUM(CASE WHEN account_type = 'ASSET' THEN net_balance ELSE 0 END) -
    SUM(CASE WHEN account_type IN ('LIABILITY', 'EQUITY') THEN net_balance ELSE 0 END) AS out_of_balance
FROM trial_balance;
-- out_of_balance must be 0.00. Any non-zero value = data integrity error.
```

### reconcile

```sql
-- Check all sub-ledger totals match GL control accounts
-- Accounts Receivable reconciliation
SELECT
    'AR_RECON' AS check_name,
    gl.gl_balance,
    ar.subledger_balance,
    gl.gl_balance - ar.subledger_balance AS difference
FROM (
    SELECT SUM(net_balance) AS gl_balance
    FROM trial_balance
    WHERE account_code = '1200'  -- AR control account
) gl,
(
    SELECT SUM(outstanding_amount) AS subledger_balance
    FROM ar_invoices
    WHERE status NOT IN ('PAID', 'VOIDED')
      AND entity_id = :entity_id
) ar;
-- difference must be 0. Non-zero = unposted AR transactions or data mismatch.

-- FX rate validation: ensure all transactions in foreign currencies
-- have rates that match the official rate source for the period
SELECT
    transaction_date,
    currency_pair,
    applied_rate,
    official_rate,
    ABS(applied_rate - official_rate) / official_rate * 100 AS variance_pct
FROM fx_rate_audit
WHERE period = :period
  AND ABS(applied_rate - official_rate) / official_rate > 0.001  -- >0.1% variance
ORDER BY variance_pct DESC;
```

### export (XBRL)

```xml
<!-- Sample iXBRL fragment for US-GAAP 10-K revenue disclosure -->
<ix:nonFraction
  name="us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax"
  contextRef="FY2024"
  unitRef="USD"
  decimals="-3"
  format="ixt:num-dot-decimal">
    125,450
</ix:nonFraction>

<!-- Context definition for annual period -->
<xbrli:context id="FY2024">
  <xbrli:entity>
    <xbrli:identifier scheme="http://www.sec.gov/CIK">0001234567</xbrli:identifier>
  </xbrli:entity>
  <xbrli:period>
    <xbrli:startDate>2024-01-01</xbrli:startDate>
    <xbrli:endDate>2024-12-31</xbrli:endDate>
  </xbrli:period>
</xbrli:context>
```

### validate

Automated validation checks before submission:

- Balance sheet balances (Assets = L + E, tolerance: 0)
- Cash flow reconciliation (closing cash = opening + net cash flows, tolerance: 0)
- Prior period comparative figures match prior year filing
- All mandatory XBRL elements present for the filing type
- No negative revenue (unless credit note scenario)
- Retained earnings roll matches: Opening + Net Income - Dividends = Closing

## Examples

```bash
# Generate Q3 2024 P&L for entity E001 in USD (GAAP)
/fin-report generate --period 2024-09 --entity E001 --framework gaap --currency USD

# Run period-close reconciliation checks before close
/fin-report reconcile --period 2024-12 --entity E001

# Export full-year 10-K in iXBRL for SEC EDGAR submission
/fin-report export --period 2024-12 --entity E001 --format ixbrl --framework gaap

# Validate balance sheet integrity
/fin-report validate --period 2024-09 --entity E001 --comparative
```
