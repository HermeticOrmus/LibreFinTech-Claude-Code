# /banking-api

Manage Open Banking and bank aggregation API integrations: connect accounts, fetch transaction history, initiate payments, and debug consent flows.

## Trigger

`/banking-api <action> [options]`

## Actions

- `connect` - Generate OAuth 2.0 / FAPI authorization flow for a bank connection
- `accounts` - Fetch and normalize account data from connected institution
- `transactions` - Retrieve and categorize transactions for a consent
- `payments` - Initiate a domestic or international payment via PIS

## Options

- `--provider <plaid|truelayer|tink|finicity|custom>` - Aggregation provider
- `--standard <uk-ob|nextgenpsd2|stet|cdr>` - Open Banking standard (for custom/direct integration)
- `--consent-id <id>` - Operate on specific consent object
- `--account-id <id>` - Scope to specific account
- `--from <ISO8601>` - Transaction date range start
- `--to <ISO8601>` - Transaction date range end
- `--sandbox` - Use provider sandbox environment

## Process

### connect

Generates the complete authorization flow. For UK Open Banking (FAPI 1.0 Advanced):

```typescript
// Step 1: Create account-access-consent at ASPSP
const consent = await aspsp.post('/open-banking/v3.1/aisp/account-access-consents', {
  Data: {
    Permissions: [
      'ReadAccountsDetail',
      'ReadBalances',
      'ReadTransactionsDetail',
      'ReadTransactionsCredits',
      'ReadTransactionsDebits',
    ],
    ExpirationDateTime: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString(),
    TransactionFromDateTime: new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString(),
  },
  Risk: {},
}, { headers: { Authorization: `Bearer ${clientCredentialsToken}` } });

const consentId = consent.data.Data.ConsentId;

// Step 2: Build PKCE authorization request with PAR
const codeVerifier = generateCodeVerifier(); // 32 random bytes, base64url encoded
const codeChallenge = base64url(sha256(codeVerifier));

const authParams = {
  response_type: 'code id_token',  // Hybrid flow for FAPI
  client_id: CLIENT_ID,
  redirect_uri: REDIRECT_URI,
  scope: 'openid accounts',
  state: generateState(),
  nonce: generateNonce(),
  code_challenge: codeChallenge,
  code_challenge_method: 'S256',
  request: buildSignedJWT({   // Signed request object per FAPI
    intent_id: consentId,
  }),
};

// Step 3: Push authorization request (PAR) - FAPI Advanced requires this
const parResponse = await aspsp.post('/as/par', authParams);
const authUrl = `${aspsp.authEndpoint}?request_uri=${parResponse.request_uri}`;

// Redirect user to authUrl
```

### accounts

After authorization, fetch accounts using the access token:

```typescript
const accounts = await aspsp.get('/open-banking/v3.1/aisp/accounts', {
  headers: {
    Authorization: `Bearer ${accessToken}`,
    'x-fapi-interaction-id': generateUUID(),  // Required by UK OB spec
    'x-fapi-financial-id': ASPSP_FINANCIAL_ID,
  },
});

// Normalize to common format
const normalized = accounts.data.Data.Account.map(acct => ({
  id: acct.AccountId,
  type: acct.AccountType,    // 'Personal', 'Business'
  subType: acct.AccountSubType,  // 'CurrentAccount', 'Savings'
  currency: acct.Currency,   // ISO 4217
  name: acct.Nickname ?? acct.Account[0].Name,
  sortCode: acct.Account[0]?.SchemeName === 'UK.OBIE.SortCodeAccountNumber'
    ? acct.Account[0].Identification.slice(0, 6) : null,
  accountNumber: acct.Account[0]?.SchemeName === 'UK.OBIE.SortCodeAccountNumber'
    ? acct.Account[0].Identification.slice(6) : null,
  iban: acct.Account[0]?.SchemeName === 'UK.OBIE.IBAN'
    ? acct.Account[0].Identification : null,
}));
```

### payments

Domestic payment initiation (UK Open Banking PIS):

```typescript
// Create domestic payment consent
const paymentConsent = await aspsp.post(
  '/open-banking/v3.1/pisp/domestic-payment-consents',
  {
    Data: {
      Initiation: {
        InstructionIdentification: generateIdempotencyKey(),
        EndToEndIdentification: referenceId,
        InstructedAmount: { Amount: '10.00', Currency: 'GBP' },
        CreditorAccount: {
          SchemeName: 'UK.OBIE.SortCodeAccountNumber',
          Identification: '20000319570703',
          Name: 'John Smith',
        },
        RemittanceInformation: { Reference: 'Invoice-12345' },
      },
    },
    Risk: {
      PaymentContextCode: 'EcommerceGoods',
    },
  },
  { headers: { Authorization: `Bearer ${clientCredentialsToken}` } }
);
```

## Examples

```bash
# Generate Plaid Link token for account connection
/banking-api connect --provider plaid --sandbox

# Fetch accounts after UK Open Banking consent
/banking-api accounts --provider custom --standard uk-ob --consent-id aac-00001

# Get last 30 days transactions for specific account
/banking-api transactions --account-id 22289 --from 2024-10-01 --to 2024-10-31

# Initiate a domestic GBP payment via UK Open Banking PIS
/banking-api payments --provider custom --standard uk-ob
```
