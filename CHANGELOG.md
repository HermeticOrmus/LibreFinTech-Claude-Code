# Changelog

## [0.2.0] — 2026-05-23

Major content depth pass. 20 plugin shells filled with the LibreUIUX template chrome plus three flagship plugins promoted to depth-complete.

### Added

- 3 flagship plugins promoted to depth-complete:
  - `payment-processing` — Stripe + Adyen patterns, idempotency keys, webhook reliability (out-of-order delivery, retries), 3DS flow, refund + chargeback handling, PCI scope minimization
  - `ledger-design` — double-entry bookkeeping with event sourcing, immutability invariants, multi-currency support, rounding semantics (integer minor units), reconciliation patterns
  - `fraud-detection` — rule engines, ML scoring, velocity checks, device fingerprinting, dispute defense workflows, the cost-of-false-positive vs cost-of-false-negative trade-off
- README rewrite matching the LibreUIUX template (mascot + brass badges + Karpathy framing + plugin catalog)
- QUICK_START with 30-minute Stripe + ledger walkthrough
- CONTRIBUTING with plugin-authoring conventions + jurisdictional considerations
- CHANGELOG with per-plugin maturity matrix
- TROUBLESHOOTING covering common fintech failure modes
- setup.sh installer with `--only` for selective install
- 3-tier learning paths (beginner → intermediate → advanced) covering fintech-specific concerns

### Per-plugin maturity matrix

| Plugin | v0.1 state | v0.2 state |
|---|---|---|
| audit-trails | templated | shell-improved |
| banking-apis | templated | shell-improved |
| cryptocurrency | templated | shell-improved |
| financial-reporting | templated | shell-improved |
| financial-security | templated | shell-improved |
| **fraud-detection** | templated | **depth-complete** |
| insurance-tech | templated | shell-improved |
| kyc-aml | templated | shell-improved |
| **ledger-design** | templated | **depth-complete** |
| lending-platforms | templated | shell-improved |
| market-data | templated | shell-improved |
| open-banking | templated | shell-improved |
| **payment-processing** | templated | **depth-complete** |
| portfolio-management | templated | shell-improved |
| pricing-engines | templated | shell-improved |
| real-time-settlement | templated | shell-improved |
| reconciliation | templated | shell-improved |
| regulatory-compliance | templated | shell-improved |
| risk-management | templated | shell-improved |
| trading-systems | templated | shell-improved |

### Planned for v0.3

- 4-5 more plugins to depth-complete (priorities: `kyc-aml`, `regulatory-compliance`, `reconciliation`, `cryptocurrency`, `financial-security`)
- Provider-specific worked examples per major rail (Stripe, Adyen, Plaid, native ACH/SEPA/FedNow)
- Real-world anonymized case studies in `examples/`
- Regional patterns (PIX, UPI, M-Pesa) — currently US/EU-centric

### Planned for v0.4

- Remaining 10 plugins to depth-complete
- Crypto/DeFi protocol-specific depth (currently broad-strokes)
- Insurtech depth (currently light)
- Compliance-jurisdiction matrix (per regulatory regime, per plugin)

## [0.1.0] — 2026-03-01

Initial release. 20 plugin shells with templated content. Established the directory structure and naming conventions.
