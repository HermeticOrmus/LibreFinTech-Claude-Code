# /open-banking

Open Banking workflows: TPP registration, consent creation, account data access, and payment initiation.

## Trigger

`/open-banking <action> [options]`

## Actions

- `register` - Register TPP with an ASPSP via Dynamic Client Registration (DCR)
- `consent` - Create and manage account-access or payment consent
- `accounts` - Fetch account data using an authorised consent
- `payments` - Initiate domestic or international payment

## Options

- `--aspsp <id>` - ASPSP (bank) identifier
- `--standard <uk-ob|nextgenpsd2|stet>` - Open Banking standard
- `--consent-id <id>` - Operate on existing consent
- `--consent-type <ais|pis|cbpii>` - Consent type
- `--sandbox` - Use ASPSP sandbox environment

## Process

### DCR Flow (UK Open Banking)

```
TPP Directory (OBIE/OBL)
         |
         | 1. Get Software Statement Assertion (SSA)
         |    - JWT signed by OBL directory
         |    - Contains TPP identity, software_id, redirect_uris
         v
    ASPSPs DCR Endpoint
         |
         | 2. POST /register with SSA + client metadata
         |    (RFC 7591 Dynamic Client Registration)
         |
         | 3. Receive client_id and client_secret (or public key registered)
         v
    Client Credentials Flow
         |
         | 4. POST /token with client_id + mTLS cert
         |    grant_type=client_credentials scope=accounts
         |
         | 5. Receive client_credentials access_token
         v
    Create Consent
```

DCR request body:
```json
{
  "redirect_uris": ["https://api.myapp.com/callback/open-banking"],
  "token_endpoint_auth_method": "tls_client_auth",
  "grant_types": ["authorization_code", "client_credentials", "refresh_token"],
  "response_types": ["code id_token"],
  "software_id": "12345-abcde-67890",
  "scope": "openid accounts payments",
  "software_statement": "<SSA JWT from OBL directory>"
}
```

### consent

Create account-access consent (UK OB):

```typescript
// Step 1: Create consent with client credentials token
const consentResponse = await fetch(`${aspspBaseUrl}/open-banking/v3.1/aisp/account-access-consents`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${clientCredentialsToken}`,
    'Content-Type': 'application/json',
    'x-fapi-interaction-id': crypto.randomUUID(),
    'x-fapi-financial-id': aspspFinancialId,
  },
  body: JSON.stringify({
    Data: {
      Permissions: [
        'ReadAccountsDetail',
        'ReadBalances',
        'ReadTransactionsDetail',
        'ReadTransactionsCredits',
        'ReadTransactionsDebits',
        'ReadDirectDebits',
        'ReadStandingOrders',
      ],
      ExpirationDateTime: new Date(Date.now() + 90 * 24 * 3600 * 1000).toISOString(),
      TransactionFromDateTime: new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString(),
      TransactionToDateTime: new Date().toISOString(),
    },
    Risk: {},
  }),
});

const { Data: { ConsentId } } = await consentResponse.json();

// Step 2: Build FAPI Advanced authorization URL with PAR
const pkce = generatePKCE();  // { verifier, challenge }
const state = crypto.randomUUID();
const nonce = crypto.randomUUID();

// Build signed request object (required for FAPI Advanced)
const requestJWT = await signJWT({
  iss: clientId,
  aud: aspspIssuer,
  response_type: 'code id_token',
  client_id: clientId,
  redirect_uri: redirectUri,
  scope: 'openid accounts',
  state,
  nonce,
  code_challenge: pkce.challenge,
  code_challenge_method: 'S256',
  claims: {
    id_token: {
      openbanking_intent_id: { value: ConsentId, essential: true },
    },
  },
});

// POST to PAR endpoint
const parResponse = await fetch(`${aspspBaseUrl}/as/par`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    client_id: clientId,
    request: requestJWT,
  }),
});
const { request_uri } = await parResponse.json();

// Step 3: Authorization URL (short - PAR moved the bulk of params server-side)
const authUrl = `${aspspAuthEndpoint}?request_uri=${request_uri}&client_id=${clientId}`;
// Redirect user to authUrl

// Step 4: Exchange code for tokens (after user authorization)
const tokenResponse = await fetch(`${aspspBaseUrl}/token`, {
  method: 'POST',
  body: new URLSearchParams({
    grant_type: 'authorization_code',
    code: authorizationCode,
    redirect_uri: redirectUri,
    code_verifier: pkce.verifier,
  }),
});
const { access_token, refresh_token, expires_in } = await tokenResponse.json();
```

Consent state machine:
```
AwaitingAuthorisation
    ├── [User authorises] → Authorised
    └── [User rejects]   → Rejected

Authorised
    ├── [Consent expires]     → Expired
    └── [User/TPP revokes]    → Revoked
```

### accounts

```typescript
// Use authorization code access token for data access
const accounts = await fetch(`${aspspBaseUrl}/open-banking/v3.1/aisp/accounts`, {
  headers: {
    'Authorization': `Bearer ${accessToken}`,
    'x-fapi-interaction-id': crypto.randomUUID(),
    'x-fapi-financial-id': aspspFinancialId,
  },
});

// Get transactions for a specific account
const transactions = await fetch(
  `${aspspBaseUrl}/open-banking/v3.1/aisp/accounts/${accountId}/transactions?fromBookingDateTime=${from}`,
  { headers: { 'Authorization': `Bearer ${accessToken}`, ... } }
);
```

## Examples

```bash
# Register TPP with Barclays sandbox via DCR
/open-banking register --aspsp barclays --standard uk-ob --sandbox

# Create 90-day AIS consent for account aggregation
/open-banking consent --aspsp barclays --consent-type ais --standard uk-ob

# Fetch accounts using authorized consent
/open-banking accounts --consent-id aac-001234 --aspsp barclays

# Initiate GBP domestic payment
/open-banking payments --consent-id pip-001234 --aspsp barclays --standard uk-ob
```
