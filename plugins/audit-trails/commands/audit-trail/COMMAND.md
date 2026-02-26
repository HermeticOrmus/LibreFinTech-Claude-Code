# /audit-trail

Manage immutable audit logging for financial systems: generate schemas, verify chain integrity, query audit history, and export for regulatory review.

## Trigger

`/audit-trail <action> [options]`

## Actions

- `generate` - Generate append-only audit table schema with hash chaining
- `verify` - Verify hash chain integrity across an audit log table
- `query` - Query audit history for a specific entity or time range
- `export` - Export audit records in regulator-ready format (CSV, JSON-LD)

## Options

- `--table <name>` - Target audit table name
- `--entity-id <id>` - Filter by specific entity (account, transaction, user)
- `--from <ISO8601>` - Start of time range
- `--to <ISO8601>` - End of time range
- `--format <csv|jsonld|splunk>` - Export format
- `--regulation <sox|pci|gdpr|all>` - Compliance regime to validate against

## Process

### generate

Produces a PostgreSQL audit table schema with hash chaining. The schema enforces:
- `id` is a UUID generated server-side
- `event_time` uses `clock_timestamp()`, not `now()` (transaction-safe precision)
- `prev_hash` references the SHA-256 of the previous row
- `row_hash` is computed over all fields including `prev_hash`
- No UPDATE or DELETE permissions granted on the table

```sql
CREATE TABLE financial_audit_log (
    id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    event_time      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    event_type      TEXT NOT NULL,          -- 'PAYMENT_INITIATED', 'ACCOUNT_MODIFIED', etc.
    actor_id        TEXT NOT NULL,          -- User or service that performed the action
    actor_ip        INET,
    session_id      TEXT,
    entity_type     TEXT NOT NULL,          -- 'account', 'transaction', 'user'
    entity_id       TEXT NOT NULL,
    before_state    JSONB,                  -- Snapshot before change (null for creates)
    after_state     JSONB,                  -- Snapshot after change (null for deletes)
    correlation_id  TEXT,                   -- W3C TraceContext traceparent value
    metadata        JSONB,
    prev_hash       CHAR(64),               -- SHA-256 of previous row (null for first row)
    row_hash        CHAR(64) NOT NULL       -- SHA-256(id||event_time||...||prev_hash)
);

-- Revoke mutability
REVOKE UPDATE, DELETE, TRUNCATE ON financial_audit_log FROM PUBLIC;
REVOKE UPDATE, DELETE, TRUNCATE ON financial_audit_log FROM app_user;

-- Partition by month for query performance and retention enforcement
CREATE TABLE financial_audit_log_2024_01
    PARTITION OF financial_audit_log
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### verify

Recomputes hash chain from oldest to newest record. Reports first broken link if found.

```sql
WITH ordered_log AS (
    SELECT
        id, row_hash, prev_hash,
        LAG(row_hash) OVER (ORDER BY event_time, id) AS expected_prev_hash
    FROM financial_audit_log
    WHERE event_time BETWEEN :from AND :to
),
chain_check AS (
    SELECT
        id,
        row_hash,
        prev_hash,
        expected_prev_hash,
        (prev_hash IS NULL AND expected_prev_hash IS NULL)
            OR prev_hash = expected_prev_hash AS chain_valid
    FROM ordered_log
)
SELECT id, prev_hash, expected_prev_hash
FROM chain_check
WHERE NOT chain_valid;
-- Zero rows = chain intact. Any row = tampering detected at that record.
```

### query

```sql
-- All events for a specific account in the last 30 days
SELECT
    event_time,
    event_type,
    actor_id,
    actor_ip,
    before_state,
    after_state,
    correlation_id
FROM financial_audit_log
WHERE entity_type = 'account'
  AND entity_id = :account_id
  AND event_time > NOW() - INTERVAL '30 days'
ORDER BY event_time DESC;

-- Who changed a specific transaction record?
SELECT actor_id, event_time, before_state->>'status' AS old_status,
       after_state->>'status' AS new_status
FROM financial_audit_log
WHERE entity_type = 'transaction'
  AND entity_id = :tx_id
  AND event_type = 'STATUS_CHANGED';
```

### export

SOX export for external auditor review. Produces signed JSON-LD with hash manifest.

```bash
/audit-trail export \
  --table financial_audit_log \
  --from 2024-01-01T00:00:00Z \
  --to 2024-03-31T23:59:59Z \
  --format jsonld \
  --regulation sox
```

Output includes: records file, SHA-256 manifest, chain verification report, and signing certificate chain for non-repudiation.

## Examples

```bash
# Generate audit schema for a payments service
/audit-trail generate --table payment_audit_log --regulation pci

# Verify integrity of Q1 audit log before SOX submission
/audit-trail verify --table financial_audit_log --from 2024-01-01 --to 2024-03-31

# Query all actions on account ACC-001234 this week
/audit-trail query --entity-id ACC-001234 --from 2024-11-01 --format csv

# Export PCI DSS audit records for QSA review
/audit-trail export --regulation pci --from 2024-10-01 --to 2024-10-31 --format csv
```
