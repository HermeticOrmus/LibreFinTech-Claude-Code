# /fin-security

Manage financial security operations: PCI compliance audits, PAN tokenization, key rotation, and sensitive data scanning.

## Trigger

`/fin-security <action> [options]`

## Actions

- `audit` - Run PCI DSS compliance gap assessment against current architecture
- `tokenize` - Tokenize a PAN or batch of PANs using vault or format-preserving tokenization
- `rotate-keys` - Execute key rotation procedure with re-encryption of existing data
- `scan` - Scan codebase or logs for inadvertent CHD/SAD exposure

## Options

- `--pci-level <1|2|3|4>` - Merchant level (determines SAQ or ROC requirement)
- `--saq-type <a|a-ep|b|b-ip|c|c-vt|d>` - Specific SAQ type
- `--tokenization-method <vault|fpe>` - Tokenization approach
- `--key-type <dek|kek|tmk>` - Key type for rotation (Data Encryption Key, Key Encryption Key, Terminal Master Key)
- `--path <dir>` - Directory to scan for CHD patterns

## Process

### audit

Maps architecture to PCI DSS v4.0 requirements. Generates gap report.

Key requirements checked:
- **Req 3.3.1**: SAD not stored post-auth. Check logs, databases, temp files.
- **Req 3.5.1**: PAN protected anywhere it is stored. Check database columns, files, backups.
- **Req 4.2.1**: Strong cryptography for PAN in transit (TLS 1.2+ only).
- **Req 7**: Access to CHD restricted by need-to-know. Check database access controls.
- **Req 10**: Audit logs for all CHD access. Check log coverage and retention (12 months).
- **Req 11.3**: Penetration testing annually and after significant changes.

### tokenize

Vault tokenization implementation:

```typescript
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

interface TokenVault {
  tokenize(pan: string): Promise<string>;
  detokenize(token: string): Promise<string>;
}

class VaultTokenizer implements TokenVault {
  // Token is a UUID v4 - no mathematical relationship to PAN
  async tokenize(pan: string): Promise<string> {
    if (!isValidLuhn(pan)) throw new Error('Invalid PAN');

    // Check if PAN already has a token (deduplication)
    const panHash = createHash('sha256')
      .update(pan + process.env.PAN_HASH_SALT)
      .digest('hex');

    const existing = await this.vault.findByPanHash(panHash);
    if (existing) return existing.token;

    const token = randomUUID();  // crypto.randomUUID() - no relationship to PAN

    // Encrypt PAN before storing in vault
    const encryptedPan = await kms.encrypt(pan);

    await this.vault.store({
      token,
      panHash,           // For deduplication lookup only
      encryptedPan,      // KMS-encrypted PAN
      lastFourDigits: pan.slice(-4),  // Allowed to store for display
      firstSixDigits: pan.slice(0, 6), // BIN - allowed for routing logic
      createdAt: new Date(),
    });

    return token;
  }

  async detokenize(token: string): Promise<string> {
    const record = await this.vault.findByToken(token);
    if (!record) throw new Error('Token not found');

    // Log every detokenization - this is a high-value audit event
    await auditLog.record({
      event: 'DETOKENIZE',
      token,
      actorId: getCurrentActorId(),
      reason: getCurrentOperationReason(),
    });

    return kms.decrypt(record.encryptedPan);
  }
}
```

Format-Preserving Encryption (FPE) using FF3-1:

```typescript
import { FF3 } from 'ff3'; // NIST SP 800-38G approved algorithm

const fpe = new FF3({
  key: Buffer.from(process.env.FPE_KEY, 'hex'), // 256-bit key from HSM
  tweak: Buffer.from(process.env.FPE_TWEAK, 'hex'),
  alphabet: '0123456789',
  radix: 10,
});

function tokenizeWithFPE(pan: string): string {
  // Preserve length and format; result passes Luhn check if configured
  const token = fpe.encrypt(pan);
  return token; // Same length as original PAN
}
```

### rotate-keys

```typescript
async function rotateDataEncryptionKey(entityId: string): Promise<void> {
  const newKey = await kms.generateDataKey(); // KMS generates new DEK

  // Re-encrypt in batches to avoid locking the database
  const batchSize = 1000;
  let offset = 0;

  while (true) {
    const records = await vault.findBatch({ entityId, offset, limit: batchSize });
    if (records.length === 0) break;

    await db.transaction(async (tx) => {
      for (const record of records) {
        const plaintext = await kms.decrypt(record.encryptedData, { keyId: record.keyId });
        const reEncrypted = await kms.encrypt(plaintext, { keyId: newKey.keyId });

        await tx.vault.update({
          where: { id: record.id },
          data: {
            encryptedData: reEncrypted,
            keyId: newKey.keyId,
            reEncryptedAt: new Date(),
          },
        });
      }
    });

    offset += batchSize;
  }

  await keyRegistry.retire(oldKeyId); // Mark old key as retired (not deleted yet)
}
```

### scan

Scan source code and logs for PAN patterns:

```bash
# PAN regex: 13-19 digits (with optional separators)
# Luhn validation should follow to reduce false positives
grep -rE '\b([0-9]{4}[-\s]?){3}[0-9]{1,4}\b' --include="*.log" ./logs/
grep -rE '\b[0-9]{13,19}\b' --include="*.ts" --include="*.js" ./src/

# CVV/CVV2 patterns (3-4 digits near "cvv" or "cvc")
grep -rEi '(cvv|cvc|csv|security.?code).{0,30}[0-9]{3,4}' --include="*.log" ./logs/
```

## Examples

```bash
# Run PCI DSS gap assessment for a Level 2 merchant
/fin-security audit --pci-level 2 --saq-type d

# Tokenize a batch of PANs from legacy database migration
/fin-security tokenize --tokenization-method vault --path ./migration/pan-export.csv

# Rotate DEKs for the payments vault
/fin-security rotate-keys --key-type dek

# Scan application logs for inadvertent PAN exposure
/fin-security scan --path ./logs/
```
