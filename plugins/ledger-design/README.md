# Ledger Design

> Double-entry bookkeeping for financial systems — balance invariants, event sourcing, immutability, multi-currency, rounding semantics. The accounting layer that catches what payment processors miss.

## Overview

Every financial system has a ledger, whether explicit or implicit. The implicit ones — "we'll just look at Stripe's dashboard" — fail at scale and during audits. The explicit ones encode money movement as events with invariants that can be verified.

This plugin encodes the patterns for ledgers that:

- Track money correctly under retries, partial failures, and out-of-order events
- Survive audits (every dollar can be traced)
- Reconcile against payment providers automatically
- Handle multi-currency, rounding, and FX correctly
- Scale to millions of events without losing the audit trail

## Contents

### Agents

- **ledger-architect** -- Senior financial systems engineer. Designs event-sourced ledgers with double-entry invariants, immutable event tables, materialized balance views. Knows the trade-offs between strict double-entry, simplified single-entry, and modern event-sourced approaches.

### Commands

- **/ledger** -- Ledger schema design + invariant enforcement + reconciliation patterns.

### Skills

- **ledger-design** -- Reference library: double-entry rules, event sourcing patterns, balance materialization, multi-currency handling, common ledger mistakes.

## Key capabilities

- **Double-entry bookkeeping**: every event is a pair (debit one account, credit another); the sum of all debits equals the sum of all credits — the integrity invariant
- **Event sourcing**: append-only events; balances are derived views; audit trail is the source of truth
- **Immutability**: events never update or delete; corrections are new compensating events
- **Multi-currency**: per-currency balances; FX events as their own pair; snapshot rates at execution
- **Rounding semantics**: integer minor units always; bankers' rounding for half-cent splits; explicit rounding accounts when subtotals don't sum
- **Materialized balance views**: derived from events; recomputed via projections; cache-friendly
- **Reconciliation**: ledger vs. external provider (Stripe, bank statement); flag discrepancies for human review

## When to use

- Designing a new financial system (do this FIRST, before payment integration)
- Migrating from "spreadsheet" or "dashboard-only" tracking to a real ledger
- Adding multi-currency to an existing single-currency system
- Audit preparation (SOC 2, financial reporting)
- Debugging "balance doesn't match" scenarios
- Designing dispute / refund / chargeback flows that touch the ledger

## When NOT to use

- Read-only analytics (ledger is for state-of-record, not analytics — use a separate analytical DB)
- Logging (audit trail and logs serve different purposes)
- Reporting (the ledger is the source; reporting layers on top)

## Compatibility

- **Databases**: PostgreSQL (preferred for ACID + JSONB), MySQL, CockroachDB (for global), DynamoDB (for high-throughput)
- **Languages**: Python (with Pydantic), TypeScript, Go, Java
- **Scale**: from 100s to 10s of millions of events; partitioning patterns covered for the high end

## Limitations

- The agent doesn't design GL (general ledger) for full accounting departments — that's a CPA's job, this is the system-of-record below
- Tax calculations are not part of ledger design; they're a separate concern (see `pricing-engines`)
- The agent doesn't design the analytical / reporting layer on top — see `financial-reporting`
