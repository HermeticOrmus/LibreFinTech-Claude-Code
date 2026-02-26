# Open Banking Patterns

Domain-specific patterns for Open Banking integrations, FAPI security, consent lifecycle management, and TPP infrastructure.

## Core Patterns

### Pattern: FAPI 1.0 Advanced Authorization Flow

```
Client                    AS (ASPSP)               Resource Server
  |                          |                           |
  |-- (1) POST /par -------->|                           |
  |    {request_jwt (signed)}|                           |
  |<-- {request_uri} --------|                           |
  |                          |                           |
  |-- (2) GET /authorize?request_uri=... + client_id --> |
  |   [User authenticates + authorises]                  |
  |<-- redirect with code + id_token (signed, JARM) -----|
  |                          |                           |
  |-- (3) POST /token ------->|                           |
  |    {code, code_verifier} |                           |
  |<-- {access_token (mTLS bound), refresh_token} -------|
  |                          |                           |
  |-- (4) GET /accounts ------------------------------------>
  |   Authorization: Bearer {access_token}               |
  |   [mTLS cert presented at TLS layer]                 |
  |<-- {account data} --------------------------------------|
```

### Pattern: Consent Persistence and Renewal

```typescript
interface ConsentRecord {
  id: string;
  consentId: string;          // ASPSP-assigned consent ID
  aspspId: string;
  userId: string;
  consentType: 'AIS' | 'PIS' | 'CBPII';
  status: 'AwaitingAuthorisation' | 'Authorised' | 'Rejected' | 'Revoked' | 'Expired';
  permissions: string[];
  expirationDateTime: Date | null;
  accessToken: string | null;    // Encrypted with KMS
  refreshToken: string | null;   // Encrypted with KMS
  tokenExpiresAt: Date | null;
  standard: 'UK_OB' | 'NEXTGENPSD2' | 'STET';
  createdAt: Date;
  updatedAt: Date;
}

// Before each API call, ensure token is valid
async function getValidToken(consentId: string): Promise<string> {
  const consent = await db.consent.findUnique({ where: { id: consentId } });

  if (consent.status !== 'Authorised') {
    throw new Error(`Consent ${consentId} is ${consent.status} - re-authorization required`);
  }

  if (consent.tokenExpiresAt && consent.tokenExpiresAt < new Date()) {
    // Token expired - use refresh token
    if (!consent.refreshToken) {
      throw new Error('No refresh token available - full re-consent required');
    }
    return refreshAccessToken(consent);
  }

  return decrypt(consent.accessToken!);
}

// Proactively refresh token before expiry (schedule this)
async function proactiveTokenRefresh(): Promise<void> {
  const expiringConsents = await db.consent.findMany({
    where: {
      status: 'Authorised',
      tokenExpiresAt: {
        gt: new Date(),
        lt: addMinutes(new Date(), 10),  // Refresh if expiring within 10 minutes
      },
    },
  });

  for (const consent of expiringConsents) {
    try {
      await refreshAccessToken(consent);
    } catch (error) {
      // If refresh fails, mark consent and notify user
      await db.consent.update({
        where: { id: consent.id },
        data: { status: 'Expired' },
      });
      await notifyUserReconsentRequired(consent.userId);
    }
  }
}
```

### Pattern: Webhook Handler for Consent Events

```typescript
// ASPSPs push consent state changes as webhooks
// Must be idempotent - webhooks can be delivered more than once
app.post('/webhooks/open-banking/:aspspId', async (req, res) => {
  // 1. Verify webhook signature (UK OB uses JOSE-signed payloads)
  const detachedJWS = req.headers['x-jws-signature'] as string;
  const isValid = await verifyJWSSignature(req.body, detachedJWS, aspspPublicKey);
  if (!isValid) {
    return res.status(401).json({ error: 'Invalid signature' });
  }

  // 2. Acknowledge immediately (ASPSP will retry if no 2xx within timeout)
  res.sendStatus(200);

  // 3. Process asynchronously
  const event = req.body;
  await processConsentEvent(event);
});

async function processConsentEvent(event: OBWebhookEvent): Promise<void> {
  if (event.Data?.OBEventNotification1?.urn_openbanking_events_consent_revoked) {
    const consentId = event.Data.OBEventNotification1.urn_openbanking_events_consent_revoked.ConsentId;
    await db.consent.update({
      where: { externalConsentId: consentId },
      data: { status: 'Revoked', updatedAt: new Date() },
    });
    await notifyUserConsent(consentId, 'REVOKED');
  }
}
```

## Anti-Patterns

### Anti-Pattern: Reusing Consent for Different Purposes

A consent object has specific permissions. A consent with `ReadAccountsBasic` cannot be used for `ReadTransactionsDetail` even if you think the user "would have agreed." Create a new consent with the correct permissions. Misuse of consent is a PSD2 violation.

### Anti-Pattern: No Consent Revocation Handling

If you don't handle revocation webhooks, your system will continue trying to use revoked access tokens (403 errors), won't notify users, and won't prompt re-consent. Users will see mysterious errors. Revocation handling is mandatory for production.

### Anti-Pattern: Storing Access Tokens in Plaintext

```typescript
// WRONG: Plaintext in database
await db.consent.update({ data: { accessToken: accessToken } });

// RIGHT: Encrypt with KMS before storage
const encryptedToken = await kms.encrypt(Buffer.from(accessToken));
await db.consent.update({ data: { accessToken: encryptedToken.toString('base64') } });
```

### Anti-Pattern: Skipping FAPI for Payments

FAPI 1.0 Advanced is mandatory for payment initiation in UK Open Banking. Using plain OAuth 2.0 without PAR, signed request objects, and JARM is non-compliant. ASPSPs will reject non-FAPI payment initiation requests.

## References

- **UK Open Banking Standards**: https://standards.openbanking.org.uk/api-specifications/
- **Berlin Group NextGenPSD2**: https://www.berlin-group.org/nextgenpsd2-downloads
- **FAPI 1.0 Advanced**: https://openid.net/specs/openid-financial-api-part-2-1_0.html
- **RFC 9126 (PAR)**: https://www.rfc-editor.org/rfc/rfc9126
- **JARM**: https://openid.net/specs/oauth-v2-jarm.html
- **RFC 7591 (DCR)**: https://www.rfc-editor.org/rfc/rfc7591
- **eIDAS Regulation**: https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32014R0910
