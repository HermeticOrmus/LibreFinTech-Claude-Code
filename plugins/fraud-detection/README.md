# Fraud Detection

> Rule engines + ML scoring + behavioral baselines + velocity checks + device fingerprinting + dispute defense. The patterns that catch fraud without driving away legitimate customers.

## Overview

Fraud detection is a balance. Block too much, you lose legitimate customers (false positives). Block too little, you eat chargebacks and losses (false negatives). The math of "what threshold is right" depends on your business model, your chargeback rate, your customer LTV, and your tolerance for friction.

This plugin encodes the patterns that let you reason about that trade-off explicitly, plus the technical patterns for implementing rules, scores, and defenses.

## Contents

### Agents

- **fraud-analyst** -- Senior fraud detection engineer. Designs rule + ML hybrid systems, calibrates false-positive vs. false-negative trade-offs against business model, walks dispute defense workflows. Defaults to measuring both error rates, not just the one that's visible.

### Commands

- **/fraud-detect** -- Rule design + ML scoring + signal selection + threshold tuning.

### Skills

- **fraud-detection** -- Reference library: signal taxonomy, common rule patterns, threshold-tuning math, dispute evidence packaging.

## Key capabilities

- **Signal taxonomy**: velocity, device fingerprint, geolocation, BIN, behavioral baseline, network analysis (graph of accounts), 3DS challenge response, AVS/CVV mismatch
- **Rule design**: rule engines (per-feature thresholds), composed rules (AND / OR), graduated responses (allow / step-up auth / decline)
- **ML scoring**: feature engineering, training data, retraining cadence, A/B testing model versions, scoring + rule hybrid systems
- **Threshold calibration**: trade-off math (false-positive cost vs. false-negative cost), ROC curve, business-model-specific calibration
- **Dispute defense**: chargeback response evidence packages, provider-specific dispute APIs, win-rate optimization
- **Adversarial considerations**: card testing attacks, account takeover patterns, synthetic identity fraud

## When to use

- Designing fraud rules for a new payment system
- Tuning existing rules that are over- or under-blocking
- Debugging "we're losing too many transactions" or "chargebacks are climbing"
- Designing dispute response workflows
- Adversarial pattern analysis (responding to a specific attack vector)

## When NOT to use

- Identity verification (KYC) — see [`kyc-aml`](../kyc-aml/)
- AML compliance — see [`kyc-aml`](../kyc-aml/)
- Risk modeling for lending — see [`risk-management`](../risk-management/)
- Cryptocurrency-specific fraud (e.g., chain analysis) — see [`cryptocurrency`](../cryptocurrency/)

## Compatibility

- **Payment providers**: Stripe Radar, Adyen RevenueProtect, custom rule engines, ML platforms (SageMaker, Vertex AI, custom)
- **Devices**: Web (FingerprintJS + JS), mobile SDKs (iOS / Android)
- **Languages**: any backend; rule engines often as DSL (CEL, Rego) or imperative

## Limitations

- Specific ML model selection is project-dependent; the agent helps with feature engineering + evaluation, not model architecture decisions
- Adversarial machine learning (defending the model itself from poisoning) is light coverage
- Real-time fraud requires < 100ms decision time; some patterns trade latency for accuracy
