# Payment Processing

> Stripe, Adyen, PayPal, and native rails — idempotency keys, webhook reliability, 3DS flows, refund + chargeback handling, PCI scope minimization. The patterns that make payment systems correct under real-world failure modes.

## Overview

Payment processing is where fintech bugs are most expensive. Double-charges erode trust. Missed webhooks leave money unaccounted for. PCI scope creep multiplies audit cost. Storing card data badly is a regulatory incident. This plugin encodes the patterns that make payment systems correct under retries, partial outages, out-of-order webhooks, and adversarial inputs.

## Contents

### Agents

- **payment-engineer** -- Senior payment specialist. Designs idempotent endpoints, webhook handlers that survive Stripe's retry semantics, 3DS flows for SCA compliance, refund + chargeback paths. Defaults to skepticism on "this worked in the demo" — payment systems require thinking about all retry + race + partial-failure modes.

### Commands

- **/payments** -- Endpoint design + provider integration + failure-mode walkthrough.

### Skills

- **payment-processing** -- Reference library: idempotency-key patterns, webhook signature verification, 3DS state machine, common provider quirks (Stripe vs. Adyen vs. PayPal).

## Key capabilities

- **Idempotency**: per-attempt UUID keys, retry-safe POST design, idempotency at every layer (client → API → provider → ledger)
- **Webhook reliability**: signature verification, retry-tolerance, out-of-order delivery handling, event-id deduplication, sync vs. async webhook processing
- **3DS / SCA compliance**: when 3DS challenges fire (EU PSD2 triggers, high-amount fallback), client-side challenge flow, server-side intent state machine
- **Refunds + chargebacks**: full vs. partial refund flows, chargeback dispute filing, evidence package format per provider, refund-vs-chargeback decision tree
- **PCI scope minimization**: never touching raw PAN, tokenized payment methods (Stripe PaymentMethods, Adyen vault), Service Provider Validation Type 1 vs. self-assessment
- **Multi-currency**: integer minor units (cents, not floats), zero-decimal currencies (JPY, KRW), FX rate snapshotting at authorization time
- **Provider-specific patterns**: Stripe Elements, Adyen Drop-in, PayPal Smart Buttons, native ACH (Plaid + Dwolla), SEPA, FedNow

## When to use

- Building a new payment integration
- Adding a new provider to an existing system
- Debugging a "we're double-charging" / "webhook didn't arrive" / "3DS challenge isn't firing" scenario
- Designing refund / chargeback flows
- Pre-launch payment-system review
- PCI audit preparation

## Compatibility

- **Providers**: Stripe (deepest), Adyen, PayPal, Square, Mollie, Razorpay, Stripe Connect (marketplaces)
- **Rails**: card networks, ACH, SEPA, SEPA Instant, FedNow, Faster Payments, Interac, Pix (BR), UPI (IN), PayNow (SG)
- **Languages**: TypeScript, Python, Go, Ruby, Java
- **Compliance**: PCI DSS, PSD2, SCA, Dodd-Frank Section 1075 (for prepaid)

## Limitations

- Crypto payments — see [`cryptocurrency`](../cryptocurrency/) plugin instead
- BNPL providers (Affirm, Klarna, Afterpay) — covered at high level; deep integration requires per-provider knowledge
- Card-present (POS) terminals — software covered; hardware not
