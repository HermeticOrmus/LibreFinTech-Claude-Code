# Financial Security Patterns

Domain-specific patterns for PCI DSS compliance, payment data protection, key management, and financial system security architecture.

## Core Patterns

### Pattern: PCI Scope Reduction via Hosted Payment Page

The most impactful security architecture decision: if your server never touches the PAN, it's out of scope.

```
[Browser] → [Stripe/Adyen JS] → [Processor] → [Token/PaymentIntentId]
                                                        ↓
[Your Server] ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←[Token only]
```

With Stripe Elements or Adyen Drop-in, the PAN is typed directly into an iframe hosted by the processor. Your JavaScript never sees it. Your server receives only a payment method token. Your servers are SAQ A eligible.

```typescript
// Stripe integration - server never sees PAN
const stripe = Stripe(publishableKey);
const elements = stripe.elements();
const cardElement = elements.create('card');
cardElement.mount('#card-element');

// On form submit - PAN goes directly to Stripe, not your server
const { paymentMethod, error } = await stripe.createPaymentMethod({
  type: 'card',
  card: cardElement,
});

// Send only paymentMethod.id to your server
await fetch('/api/charge', {
  method: 'POST',
  body: JSON.stringify({ paymentMethodId: paymentMethod.id, amount: 1000 }),
});
```

### Pattern: Field-Level Encryption with KMS Key Hierarchy

```typescript
// Two-tier key hierarchy: KMS manages KEK (Key Encryption Key),
// DEK (Data Encryption Key) encrypts actual data

interface EncryptedField {
  ciphertext: string;     // base64 encrypted data
  iv: string;             // base64 initialization vector
  keyId: string;          // Which DEK was used (for rotation tracking)
  algorithm: string;      // 'AES-256-GCM'
}

async function encryptSensitiveField(plaintext: string): Promise<EncryptedField> {
  // Generate a random DEK for this field (envelope encryption)
  const { plaintext: dek, ciphertext: encryptedDek, keyId } =
    await kmsClient.generateDataKey({ keyId: 'alias/payments-dek', keySpec: 'AES_256' });

  const iv = randomBytes(12); // 96-bit IV for GCM
  const cipher = createCipheriv('aes-256-gcm', dek, iv);

  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag(); // GCM auth tag - must be stored with ciphertext

  // Wipe DEK from memory immediately
  dek.fill(0);

  return {
    ciphertext: Buffer.concat([encrypted, authTag]).toString('base64'),
    iv: iv.toString('base64'),
    keyId,
    algorithm: 'AES-256-GCM',
  };
}
```

### Pattern: TLS Configuration Hardening for Financial APIs

```nginx
# nginx TLS configuration for PCI-compliant financial API
ssl_protocols TLSv1.2 TLSv1.3;   # NO TLS 1.0 or 1.1 per PCI DSS Req 4.2.1

# TLS 1.3 only ciphers (negotiated automatically by openssl)
# TLS 1.2 strong ciphers only - no RC4, no export ciphers, no NULL
ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
ssl_prefer_server_ciphers on;

# HSTS - 2 years, include subdomains
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

# Disable compression (CRIME/BREACH attack mitigation)
ssl_comp_level 0;

# Session resumption - reduce handshake overhead
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;  # Forward secrecy - disable session tickets

# OCSP stapling
ssl_stapling on;
ssl_stapling_verify on;
```

### Pattern: HSM-Backed Key Ceremony Documentation

```
KEY CEREMONY RECORD
Date: [DATE]
Purpose: Generate new Zone Master Key (ZMK) for ATM network
Location: [SECURE FACILITY NAME]
Participants: [NAME/ROLE for each of 5 custodians]

DUAL CONTROL REQUIREMENTS:
- M-of-N scheme: 3-of-5 key custodians required
- No single custodian has knowledge of full key
- External auditor present

PROCEDURE:
1. Verify HSM tamper seals (custodian 1 + 2 witness)
2. Initialize HSM in FIPS mode
3. Each of 5 custodians loads 1 key component via smartcard
4. HSM combines components - no individual sees full key
5. Generate key check value (KCV) - verify matches expected
6. Key stored in HSM - components destroyed
7. All custodians sign ceremony log
```

## Anti-Patterns

### Anti-Pattern: Storing Raw PANs or SAD

```typescript
// CATASTROPHICALLY WRONG: Storing full PAN in logs
logger.info(`Payment failed for card ${cardNumber} with error ${errorCode}`);

// CATASTROPHICALLY WRONG: Storing CVV anywhere post-authorization
await db.paymentAttempt.create({
  data: { pan: cardNumber, cvv: cvvCode, amount: 100 },  // CVV must NEVER be stored
});

// CORRECT: Mask in logs, never store CVV
logger.info(`Payment failed for card ${maskPan(cardNumber)} with error ${errorCode}`);
// maskPan: show only first 6 + last 4, mask middle digits with *

// CORRECT: Tokenize PAN before storage, never store CVV
const token = await tokenizer.tokenize(cardNumber);
await db.paymentAttempt.create({
  data: { panToken: token, amount: 100 },  // No CVV, no raw PAN
});
```

### Anti-Pattern: Weak Key Derivation

```typescript
// WRONG: MD5 or SHA1 for key derivation - computationally reversible
const key = createHash('md5').update(password).digest();

// WRONG: Single iteration - brute-forceable
const key = pbkdf2Sync(password, salt, 1, 32, 'sha256');

// RIGHT: PBKDF2 with 600,000+ iterations (OWASP 2023 recommendation) or Argon2id
import { hash, verify } from 'argon2';
const keyMaterial = await hash(password, {
  type: argon2id,
  memoryCost: 65536,  // 64 MB
  timeCost: 3,
  parallelism: 4,
});

// For actual AES key derivation (not password hashing), use HKDF
import { hkdf } from 'crypto';
const derivedKey = await hkdfPromise('sha256', inputKeyMaterial, salt, info, 32);
```

### Anti-Pattern: Shared Encryption Keys Across Tenants

In multi-tenant financial applications, each tenant's data must be encrypted with a unique key. A single shared key means a single breach exposes all tenant data. Use per-tenant key IDs in AWS KMS or HashiCorp Vault with separate key policies.

## References

- **PCI DSS v4.0**: https://www.pcisecuritystandards.org/document_library/
- **PCI DSS SAQ Guidance**: https://www.pcisecuritystandards.org/document_library/#results
- **NIST SP 800-57**: Key Management Recommendation - https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final
- **NIST SP 800-38G**: FF3 AES Mode (Format-Preserving Encryption) - https://csrc.nist.gov/publications/detail/sp/800-38g/rev-1/final
- **AWS Key Management**: https://docs.aws.amazon.com/kms/latest/developerguide/
- **OWASP Cryptographic Storage**: https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html
- **Stripe Elements (PCI scope reduction)**: https://stripe.com/docs/security/guide
