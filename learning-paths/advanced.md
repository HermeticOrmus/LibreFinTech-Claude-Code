# Advanced — compliance, scale, and ops

You operate at scale. Now: SOC 2, PCI DSS audit prep, multi-region settlement, custom risk models, regulatory reporting at multiple jurisdictions, live-ops.

## SOC 2

For SaaS or fintech B2B, SOC 2 is table stakes. Auditor checks:

- **Security**: access controls, encryption, vulnerability management
- **Availability**: SLA compliance, incident response, disaster recovery
- **Processing integrity**: data accuracy, change management
- **Confidentiality**: data classification, data handling
- **Privacy** (optional): GDPR/CCPA compliance

**Timeline**: 6-12 months for Type 1 (point-in-time); add 12 months for Type 2 (period-of-time, more credible).

**Cost**: audit fees ($30-100k+ depending on scope) + internal time (significant).

**Auditor expectation**: documented controls, evidence of operation, no major exceptions.

## PCI DSS

Required for any system that touches card data. Levels:

- **Level 1**: > 6M transactions/year. Full audit by QSA (Qualified Security Assessor). ~$50-200k.
- **Level 2-4**: smaller volumes. SAQ (Self-Assessment Questionnaire) + quarterly ASV scans.

**Scope minimization**:
- Stripe Elements + tokenized methods → SAQ-A (lightest)
- Server proxies card data → SAQ-D (full audit equivalent)
- Storage of PAN → highest scope (expensive)

**Aim for SAQ-A**. Use tokenization everywhere; never let raw card data touch your servers.

## Multi-region settlement

Operating in multiple regions means:

- Multi-currency ledger (already covered)
- Per-region payment provider relationships (Stripe in US/EU; local PSPs in BR/IN/etc.)
- Per-jurisdiction tax handling (VAT, GST, sales tax)
- Per-jurisdiction reporting requirements
- Different settlement cadences per rail

**Architecture pattern**: regional sub-ledgers that consolidate to a global ledger via FX events.

## Custom risk models

At scale, off-the-shelf fraud detection has ceiling. Custom ML pays off when:

- Transaction volume > 100k/month
- You have labeled training data (1k+ chargebacks)
- You can dedicate an ML engineer

**Architecture**:
- Feature pipeline: from transaction event → feature vector
- Training pipeline: monthly retrain on rolling 90-day window
- Inference pipeline: real-time (< 100ms p99) scoring
- A/B testing pipeline: rule changes + model changes evaluated as experiments

## Regulatory reporting

Per jurisdiction:

- **US**: FinCEN (BSA, SAR, CTR), state money transmitter licenses, IRS 1099-K for marketplaces
- **EU**: MiFID II (trading), PSD2 (payments), GDPR (data), per-country tax reporting
- **UK**: FCA reporting, post-Brexit specifics
- **AU**: AUSTRAC reporting
- **CA**: FINTRAC reporting

The reporting is structured + scheduled. Build the reporting pipeline as part of the platform, not as a manual quarterly scramble.

## Live-ops

Financial systems are 24/7. Build:

- **On-call rotation** with clear escalation paths
- **Runbooks** for known incidents (provider outages, fraud waves, regulatory inquiries)
- **Telemetry dashboards** for fraud rate, chargeback rate, decline rate, settlement times, reconciliation drift
- **Alerting** for SLO violations + anomaly detection
- **Postmortems** for every incident (no blame; collect signal)
- **Capacity planning** for peak events (Black Friday, regional holidays)

## Read deeper

- [`docs/soc2-prep`](../docs/) — SOC 2 control mapping + evidence collection
- [`docs/pci-scope-minimization`](../docs/) — keeping PCI scope tight
- [`docs/multi-region-settlement`](../docs/) — patterns for global ops
- [`docs/regulatory-reporting`](../docs/) — per-jurisdiction filing requirements
- [`docs/live-ops-runbooks`](../docs/) — incident response, capacity, alerting

## What's still hard

- **License acquisition**: most fintech requires a license somewhere. The license process is jurisdiction-specific and takes months-to-years. Plan for it from Day 1.
- **Partnership management**: relationships with payment processors, banks, KYC providers, AML compliance vendors. Each has its own SLA, integration nuances, and renegotiation cycles.
- **Adversarial adaptation**: fraudsters update tactics. Your detection must update too. Annual red-team exercises.
- **Cultural challenges**: fintech engineers need to think differently than typical SaaS engineers. Build the culture early.

## Where to go from here

- **Contribute back**: real-world case studies (anonymized) are gold for the community. See [`CONTRIBUTING.md`](../CONTRIBUTING.md).
- **Deepen specific plugins**: the bundle has 20 plugins; depth varies. The maturity matrix tracks which are depth-complete.
- **Pair with other Libre-X-Claude-Code repos**:
  - [`LibreSecOps-Claude-Code`](https://github.com/HermeticOrmus/LibreSecOps-Claude-Code) — security ops practices
  - [`LibreDevOps-Claude-Code`](https://github.com/HermeticOrmus/LibreDevOps-Claude-Code) — infrastructure patterns
  - [`LibreUIUX-Claude-Code`](https://github.com/HermeticOrmus/LibreUIUX-Claude-Code) — when your fintech has a customer-facing UI
