# Troubleshooting

Common fintech failure modes the plugin agents help diagnose, plus general fintech debug patterns.

## Plugin issues

### Plugins copied but Claude Code doesn't see them

```bash
ls ~/.claude/plugins/ | grep -c '^libre-fintech-'
```

Should print 20. If not, re-run `./setup.sh` and restart Claude Code.

### Agent gives generic answers, not fintech-specific

As of v0.2, three plugins are depth-complete (`payment-processing`, `ledger-design`, `fraud-detection`). Others are shell-improved. See CHANGELOG maturity matrix.

If a depth-complete plugin gives generic answers, file an issue.

## Real fintech failure modes the agents help with

### "We're double-charging customers"

Almost always idempotency. The `/payments` agent walks the diagnosis:

- Are you sending an `Idempotency-Key` header to Stripe? (or equivalent for other providers)
- Is the key unique per attempt, OR per intent? (the latter is what you want)
- Is the key persistent across retries? (must survive client retries, browser refreshes, network blips)
- Is the key truly unique? (UUIDv4 per attempt, not derived from non-unique data)

### "Balance doesn't match the bank statement"

Reconciliation drift. Common causes:

- Timezone mismatch in day-boundary (Stripe UTC vs. your local)
- Fees not accounted for (Stripe takes fees before settlement; ledger may not record the fee event)
- FX rates differ between when you recorded and when the bank settled (multi-currency rounds at different points)
- Refunds applied to a different period than the original charge
- Missing webhook events (some never arrived; system never updated)

The `/reconcile` agent walks through each cause systematically.

### "Webhook arrived but the database wasn't updated"

- Webhook signature verification failed (signature mismatch — caller intercepted or your endpoint URL is wrong)
- Webhook hit a stale endpoint (you redeployed but didn't update Stripe's webhook URL)
- Webhook handler errored and your retry logic isn't right (Stripe retries with exponential backoff; you must return 2xx within timeout)
- Idempotency check rejected as a duplicate (this may be correct; verify with the event ID)
- Database transaction rolled back silently (handler returned 2xx but didn't commit)

### "Fraud false-positive rate is too high"

The `/fraud-detect` agent walks the rule audit:

- What rules currently fire? What's the false-positive rate per rule?
- Are you tuning the threshold or removing the rule entirely?
- Is there a step-up auth path (3DS challenge) before declining?
- Are you measuring both false-positives AND false-negatives, or only one?

Most fintech fraud teams over-tune on false-positives because they're visible (customer complaints). Under-tuning on false-negatives is invisible until the chargeback arrives.

### "Customer says they were charged but doesn't see the charge"

- Authorization vs. capture distinction (pre-auth holds appear differently in card statements)
- Settled vs. settled date (Stripe charges may take 1-2 business days to appear on the customer's statement)
- The charge was on a different payment method (split tender, fallback)
- Customer's card issuer is rejecting Stripe's merchant descriptor (rare but happens)

### "We're failing PCI scope"

The `/fin-security` agent walks PCI scope minimization:

- Are you storing PAN, full magnetic stripe, CAV2/CVC2/CVV2/CID? Don't.
- Are you storing tokens from Stripe/Adyen/etc.? OK.
- Are you logging raw card data? Check logs systematically.
- Are you transmitting raw card data through your servers? Use client-side tokenization (Stripe Elements, etc.) to avoid touching it.
- Is your inbound network surface minimized? PCI requires specific hardening.

The cleanest PCI strategy is to never touch raw card data. Stripe + Stripe Elements + tokenized payment methods keeps you out of PCI scope (Service Provider Validation Type 1 or self-assessment).

### "AML team is flagging legitimate customers"

The `/kyc-aml` agent walks the alert audit:

- What rules currently trigger? What's the false-positive rate per rule?
- Are you using static thresholds or behavioral baselines? (Behavioral usually fewer false-positives.)
- Are you sanctions-screening against the current OFAC/EU lists?
- Is the alert prioritization right? (Most fintech AML teams drown in noise; prioritize by transaction amount × suspicion score.)

### "Settlement is delayed"

- Provider-side delay (Stripe payouts have schedules; check the dashboard)
- Multi-region complications (ACH takes 1-3 business days; international wires longer)
- Compliance hold (KYC/AML check triggered)
- Reserve held against future chargebacks
- Manual review

The `/settlement` agent traces each cause.

### "Crypto withdrawal failed"

- Wallet balance insufficient (account for pending withdrawals)
- Gas estimate wrong (Ethereum gas spikes)
- Smart contract revert (the recipient contract rejected)
- KYT (Know Your Transaction) hit on the destination address (sanctions-listed wallet)
- Custody system rate-limited the withdrawal
- Multi-sig approval pending

The `/crypto` agent walks each case.

## When to file an issue

- A depth-complete plugin gives templated / generic answers — include the prompt
- A regulatory pattern is wrong (cite the regulation + the correct interpretation)
- A provider-specific pattern is outdated (Stripe / Adyen / etc. change APIs)

See [CONTRIBUTING.md](CONTRIBUTING.md) for the issue template.
