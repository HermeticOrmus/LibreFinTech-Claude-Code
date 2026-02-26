# Audit Trail Patterns

Domain-specific patterns for immutable financial audit logging, covering schema design, integrity verification, regulatory compliance, and forensic analysis.

## Core Patterns

### Pattern: Append-Only Table with Hash Chaining

Each row's hash covers its own data plus the previous row's hash. This creates a cryptographic chain - tampering with any row invalidates all subsequent hashes.

```sql
-- Trigger function: compute row_hash on insert
CREATE OR REPLACE FUNCTION compute_audit_hash()
RETURNS TRIGGER AS $$
DECLARE
    prev_row_hash CHAR(64);
    raw_content   TEXT;
BEGIN
    -- Get the hash of the most recent row
    SELECT row_hash INTO prev_row_hash
    FROM financial_audit_log
    ORDER BY event_time DESC, id DESC
    LIMIT 1;

    NEW.prev_hash := prev_row_hash;  -- NULL for first row

    -- Concatenate all auditable fields
    raw_content := COALESCE(NEW.id::TEXT, '') ||
                   COALESCE(NEW.event_time::TEXT, '') ||
                   COALESCE(NEW.event_type, '') ||
                   COALESCE(NEW.actor_id, '') ||
                   COALESCE(NEW.entity_id, '') ||
                   COALESCE(NEW.before_state::TEXT, '') ||
                   COALESCE(NEW.after_state::TEXT, '') ||
                   COALESCE(NEW.prev_hash, '');

    NEW.row_hash := encode(digest(raw_content, 'sha256'), 'hex');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_hash_chain
    BEFORE INSERT ON financial_audit_log
    FOR EACH ROW EXECUTE FUNCTION compute_audit_hash();
```

### Pattern: Event Store with Projection Rebuild

Store events, not state. Current account balance is the sum of all credit/debit events, not a stored value. This means the full history is always available and can be audited at any point in time.

```typescript
interface LedgerEvent {
  id: string;
  accountId: string;
  eventType: 'CREDIT' | 'DEBIT' | 'HOLD' | 'RELEASE' | 'FEE' | 'REVERSAL';
  amount: bigint;           // Stored in minor units (cents) to avoid float issues
  currency: string;         // ISO 4217
  correlationId: string;    // Links to originating transaction
  causationId: string;      // Links to event that caused this event
  occurredAt: Date;
  metadata: Record<string, unknown>;
}

// Rebuild balance at any point in time
async function getBalanceAt(accountId: string, asOf: Date): Promise<bigint> {
  const events = await eventStore.query({
    accountId,
    before: asOf,
    types: ['CREDIT', 'DEBIT', 'FEE', 'REVERSAL'],
  });

  return events.reduce((balance, event) => {
    if (['CREDIT'].includes(event.eventType)) return balance + event.amount;
    if (['DEBIT', 'FEE'].includes(event.eventType)) return balance - event.amount;
    if (event.eventType === 'REVERSAL') {
      // Find the original event and reverse it
      return balance; // simplified - real impl looks up original
    }
    return balance;
  }, 0n);
}
```

### Pattern: WORM Storage Offload

Move audit logs to WORM (Write Once Read Many) storage after a cooling period. AWS S3 Object Lock in Compliance mode prevents deletion even by root account.

```typescript
// After 24 hours, offload audit records to WORM storage
async function offloadToWORM(records: AuditRecord[]): Promise<void> {
  const s3 = new S3Client({ region: 'us-east-1' });
  const batch = {
    exportedAt: new Date().toISOString(),
    records,
    manifestHash: computeSHA256(JSON.stringify(records)),
  };

  await s3.send(new PutObjectCommand({
    Bucket: 'financial-audit-worm',
    Key: `audit/${new Date().toISOString().slice(0, 10)}/${records[0].id}.json`,
    Body: JSON.stringify(batch),
    ContentType: 'application/json',
    // Object Lock: Cannot be deleted or modified for 7 years (SOX requirement)
    ObjectLockMode: 'COMPLIANCE',
    ObjectLockRetainUntilDate: addYears(new Date(), 7),
  }));
}
```

### Pattern: Distributed Trace Correlation

In microservices, a single payment spans multiple services. The W3C TraceContext `traceparent` header links all audit events from a single business operation.

```typescript
// Middleware: propagate trace context to audit log
function auditMiddleware(req: Request, res: Response, next: NextFunction) {
  const traceParent = req.headers['traceparent'] as string
    ?? generateTraceParent(); // If no upstream trace, create one

  // Attach to AsyncLocalStorage so all audit writes in this request use it
  auditContext.run({ correlationId: traceParent }, () => next());
}

// In any service, get correlation ID without threading it through every function
function writeAuditRecord(event: AuditEvent): void {
  const { correlationId } = auditContext.getStore() ?? {};
  db.insert('financial_audit_log', {
    ...event,
    correlation_id: correlationId,
  });
}
```

### Pattern: Splunk/ELK Financial Audit Search

For operational audit queries, SIEM platforms offer faster search than raw SQL over years of data.

```splunk
-- Splunk SPL: Find all privileged account modifications in the last 7 days
index=financial_audit source=payment-service
  event_type="ACCOUNT_MODIFIED"
  actor_id IN [admin_*, svc_*]
  earliest=-7d
| table event_time, actor_id, actor_ip, entity_id, before_state.status, after_state.status
| sort -event_time

-- Detect access pattern anomaly: user accessing accounts outside normal hours
index=financial_audit
| eval hour=strftime(_time, "%H")
| where hour < 6 OR hour > 22
| stats count by actor_id, entity_id
| where count > 5
```

## Anti-Patterns

### Anti-Pattern: Mutable Audit Fields

```sql
-- WRONG: Allows audit record modification
UPDATE financial_audit_log
SET event_type = 'LEGITIMATE_ACCESS'
WHERE event_type = 'UNAUTHORIZED_ACCESS';
-- This destroys the audit trail and is itself a compliance violation.

-- RIGHT: Append a compensating record if correction is needed
INSERT INTO financial_audit_log (event_type, entity_id, metadata, ...)
VALUES (
  'AUDIT_CORRECTION',
  :entity_id,
  jsonb_build_object(
    'corrects_record', :original_record_id,
    'reason', 'Incorrect event_type classification',
    'approved_by', :compliance_officer_id
  ),
  ...
);
```

### Anti-Pattern: Audit Logs in Operational Database

Storing audit logs in the same database as operational data means a SQL injection in your app layer exposes both. A compromised audit table undermines all compliance claims. Use a separate database instance, ideally with no application-layer DELETE privileges at all.

### Anti-Pattern: No Log Integrity Verification

A hash chain only protects you if you verify it. Schedule daily hash chain verification and alert on any broken link. Without automated verification, your "tamper-evident" logs are just tamper-evident in theory.

```typescript
// Schedule this as a daily job
async function dailyIntegrityCheck(): Promise<void> {
  const brokenLinks = await verifyHashChain({
    from: startOfYesterday(),
    to: endOfYesterday(),
  });

  if (brokenLinks.length > 0) {
    await alertSecurityTeam({
      severity: 'CRITICAL',
      message: `Audit log integrity violation detected`,
      affectedRecords: brokenLinks,
    });
    // This is a potential SOX material weakness - escalate immediately
  }
}
```

### Anti-Pattern: Logging PII or Secrets in Audit Fields

Before-state and after-state snapshots should never include raw card numbers, SSNs, or passwords. Tokenize sensitive fields before they reach the audit layer. Audit logs often have longer retention than operational data, creating a compliance landmine.

## References

- **SOX Compliance**: PCAOB AS 2201 (internal control over financial reporting)
- **PCI DSS**: Requirement 10 - Track and monitor all access to network resources and cardholder data
- **NIST SP 800-92**: Guide to Computer Security Log Management
- **OWASP Logging Cheat Sheet**: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html
- **W3C TraceContext**: https://www.w3.org/TR/trace-context/
- **Event Sourcing**: Martin Fowler - https://martinfowler.com/eaaDev/EventSourcing.html
- **AWS S3 Object Lock**: https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html
