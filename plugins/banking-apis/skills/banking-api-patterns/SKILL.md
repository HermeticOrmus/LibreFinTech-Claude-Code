# Banking API Patterns

Domain-specific patterns for Open Banking integrations, PSD2 compliance, and bank API security. Covers OAuth flows, consent management, SCA, and aggregation platform integration.

## Core Patterns

### Pattern: PSD2 Strong Customer Authentication (SCA)

SCA requires at least two of: something you know (PIN/password), something you have (phone/card), something you are (biometric). The exemptions matter as much as the requirements.

SCA exemptions under PSD2 RTS Article 10-18:
- **Low-value transactions**: Contactless < EUR 50, cumulative < EUR 150
- **TRA (Transaction Risk Analysis)**: ML-based exemption for low-risk transactions based on fraud rate thresholds
- **Recurring transactions**: Same amount, same payee - first payment needs SCA, subsequent use MIT (merchant-initiated transaction) exemption
- **Trusted beneficiaries**: User has whitelisted the payee with their bank

```typescript
// When requesting a payment, indicate your preferred exemption
const paymentRequest = {
  Data: {
    Initiation: { /* payment details */ },
    SCAChallengePreference: 'NoPreference',  // or 'NoChallengeRequested' for TRA
  },
  Risk: {
    PaymentContextCode: 'EcommerceGoods',
    MerchantCategoryCode: '5411',
    MerchantCustomerIdentification: customerId,
    // Including these fields improves TRA exemption approval rate
    DeliveryAddress: { /* ... */ },
  },
};
```

### Pattern: FAPI 1.0 Advanced Security Profile

FAPI (Financial-grade API) adds constraints on top of OAuth 2.0 to prevent attacks specific to financial APIs (authorization code interception, CSRF, token leakage in redirects).

Key requirements:
1. **PAR (Pushed Authorization Requests)**: Send authorization parameters directly to AS endpoint, get back a `request_uri`. Prevents parameter tampering in redirect.
2. **JARM (JWT Secured Authorization Response Mode)**: Authorization response is a signed JWT. Prevents response tampering.
3. **Signed request objects**: Authorization request parameters in a signed JWT, not URL params.
4. **Holder-of-key tokens**: mTLS certificate bound access tokens - even if stolen, useless without the client certificate.

### Pattern: Consent State Machine

Track consent state transitions server-side. Never rely on the user being redirected back to assume consent was granted.

```
AwaitingAuthorisation
        |
        ├─── User authorises ──→ Authorised
        |                              |
        └─── User rejects  ──→ Rejected    ├─── Consent expires ──→ Expired
                                            └─── User revokes  ──→ Revoked
```

```typescript
// Store consent state; update via webhook or polling
interface ConsentRecord {
  consentId: string;
  aspspId: string;
  userId: string;
  status: 'AwaitingAuthorisation' | 'Authorised' | 'Rejected' | 'Revoked' | 'Expired';
  permissions: string[];
  expirationDateTime: Date | null;
  accessToken: string | null;      // Encrypted at rest
  refreshToken: string | null;     // Encrypted at rest
  tokenExpiresAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

// Handle revocation webhook from ASPSP
app.post('/webhooks/consent-revoked', async (req, res) => {
  // Verify webhook signature first
  await verifyWebhookSignature(req);

  const { ConsentId, Status } = req.body.Data;
  await db.consent.update({
    where: { consentId: ConsentId },
    data: { status: Status, updatedAt: new Date() },
  });

  // Notify user their bank connection needs re-authorization
  await notifyUser(await getUserForConsent(ConsentId));
  res.sendStatus(200);
});
```

### Pattern: Plaid Integration with Webhook-Driven Updates

```typescript
// Create Link token for Plaid Link UI
const linkToken = await plaidClient.linkTokenCreate({
  user: { client_user_id: userId },
  client_name: 'My App',
  products: ['transactions', 'auth'],
  country_codes: ['US', 'GB'],
  language: 'en',
  webhook: 'https://api.myapp.com/webhooks/plaid',
  // For returning users, include access_token to update existing connection
});

// Exchange public token after Link completion
const exchangeResponse = await plaidClient.itemPublicTokenExchange({
  public_token: publicToken,  // From Plaid Link onSuccess callback
});
const accessToken = exchangeResponse.access_token;  // Store encrypted

// Handle TRANSACTIONS_REMOVED webhook (Plaid can remove transactions on restatement)
app.post('/webhooks/plaid', async (req, res) => {
  await verifyPlaidWebhookSignature(req);

  if (req.body.webhook_type === 'TRANSACTIONS' &&
      req.body.webhook_code === 'TRANSACTIONS_REMOVED') {
    await db.transaction.deleteMany({
      where: { plaidTransactionId: { in: req.body.removed_transactions } },
    });
  }
});
```

## Anti-Patterns

### Anti-Pattern: Storing Raw Bank Credentials

Some older integrations use screen scraping with stored username/password. This violates PSD2 Article 67, exposes users to credential theft, and gets your application blocked by banks' bot detection. Always use OAuth-based Open Banking APIs or aggregation platforms that do.

### Anti-Pattern: Skipping SCA on Payment Initiation

Even with a valid TRA exemption, the ASPSP may still challenge. Your payment initiation flow must handle `Status: AuthorisationRequired` responses gracefully and redirect the user back through SCA. Building a flow that assumes frictionless will break for real users.

### Anti-Pattern: No Refresh Token Rotation

When you use a refresh token to get a new access token, you must store the new refresh token returned and invalidate the old one. Reusing old refresh tokens after rotation will result in consent revocation by the ASPSP.

```typescript
// WRONG: Reusing same refresh token
async function refreshAccessToken(refreshToken: string) {
  const response = await aspsp.post('/token', { grant_type: 'refresh_token', refresh_token: refreshToken });
  return response.access_token; // forgot to store new refresh_token
}

// RIGHT: Always update stored refresh token
async function refreshAccessToken(consentId: string) {
  const consent = await db.consent.findUnique({ where: { consentId } });
  const response = await aspsp.post('/token', {
    grant_type: 'refresh_token',
    refresh_token: decrypt(consent.refreshToken),
  });
  await db.consent.update({
    where: { consentId },
    data: {
      accessToken: encrypt(response.access_token),
      refreshToken: encrypt(response.refresh_token), // Always update
      tokenExpiresAt: new Date(Date.now() + response.expires_in * 1000),
    },
  });
  return response.access_token;
}
```

## References

- **UK Open Banking Standards**: https://standards.openbanking.org.uk/
- **Berlin Group NextGenPSD2**: https://www.berlin-group.org/nextgenpsd2-downloads
- **FAPI 1.0 Advanced**: https://openid.net/specs/openid-financial-api-part-2-1_0.html
- **PSD2 RTS on SCA**: Commission Delegated Regulation (EU) 2018/389
- **Plaid API Docs**: https://plaid.com/docs/api/
- **TrueLayer API Docs**: https://docs.truelayer.com/
- **OWASP OAuth 2.0 Security**: https://cheatsheetseries.owasp.org/cheatsheets/OAuth2_Cheat_Sheet.html
