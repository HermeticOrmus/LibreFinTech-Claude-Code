<p align="center">
  <img src="https://ormus.solutions/mascot/golden_swan.gif" alt="LibreFinTech Claude Code" width="128" style="image-rendering: pixelated;" />
</p>

<h1 align="center">LibreFinTech Claude Code</h1>

<p align="center">
  <em>Financial technology development with Claude Code — 20 specialized plugins for payments, ledgers, trading, compliance, and risk</em>
</p>

<p align="center">
  <a href="https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/stargazers"><img src="https://img.shields.io/github/stars/HermeticOrmus/LibreFinTech-Claude-Code?style=flat-square&color=aa8142" alt="Stars" /></a>
  <a href="https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/blob/main/LICENSE"><img src="https://img.shields.io/github/license/HermeticOrmus/LibreFinTech-Claude-Code?style=flat-square&color=aa8142" alt="License" /></a>
  <a href="https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/commits"><img src="https://img.shields.io/github/last-commit/HermeticOrmus/LibreFinTech-Claude-Code?style=flat-square&color=aa8142" alt="Last Commit" /></a>
  <img src="https://img.shields.io/badge/FinTech-aa8142?style=flat-square&logo=stripe&logoColor=white" alt="FinTech" />
  <img src="https://img.shields.io/badge/Claude_Code-aa8142?style=flat-square&logo=anthropic&logoColor=white" alt="Claude Code" />
</p>

---

> **Skills, agents, commands, and workflows for shipping financial technology with Claude Code.**

FinTech is where wrong code costs real money. A payment processor that double-charges. A ledger that loses a cent in rounding. A fraud system that approves the wrong transaction. Generic LLM coding patterns don't have the domain awareness to catch these. **LibreFinTech gives Claude Code the financial-specific expertise needed to ship systems that handle money correctly.**

Twenty domain plugins. Three flagship areas depth-complete (payment processing, ledger design, fraud detection). 3-tier learning paths covering compliance, security, and operational reality. The substance you'd expect from a senior fintech engineer.

---

## The shift this kit responds to

Karpathy, December 2025:

> *"I've never felt this much behind as a programmer. The profession is being dramatically refactored."*

For fintech specifically, the refactor is harder than other domains. AI codegen that produces a working webapp can produce a payment system that "works" but silently drops 0.01% of transactions. The cost of wrong is high; the time to discover wrong can be months. **LibreFinTech encodes the patterns that catch these defects at design time.**

### Where LibreFinTech fits in the Claude Code stack

| Claude Code component | LibreFinTech provides |
|---|---|
| **Plugins** | 20 fintech subdomain plugins (payments, ledger, trading, compliance, risk, fraud, more) |
| **Agents** | Specialist agents per plugin (payment engineer, ledger architect, fraud analyst) |
| **Commands** | Quick-access slash commands per plugin |
| **Skills** | Pattern libraries (idempotency keys, double-entry invariants, fraud rules) |
| **Templates** | Webhook handlers, ledger schemas, compliance report scaffolds |

---

## The 20 plugins

### Money movement

| Plugin | Agent / Command | What it covers |
|---|---|---|
| **payment-processing** ⭐ | `/payments` | Stripe + Adyen + native rails, 3DS, idempotency keys, webhook reliability, refund + chargeback flows, payment retries |
| **real-time-settlement** | `/settlement` | RTGS, instant payments (FedNow, SEPA Instant, Faster Payments), clearing, netting |
| **open-banking** | `/open-banking` | PSD2 + Open Banking Standard, consent flows, account aggregation, AISP/PISP roles |
| **banking-apis** | `/banking-api` | Direct bank integrations, ACH, wire transfers, ledger sync |

### Accounting + ledgers

| Plugin | Agent / Command | What it covers |
|---|---|---|
| **ledger-design** ⭐ | `/ledger` | Double-entry bookkeeping, balance invariants, event sourcing, immutability, multi-currency, rounding |
| **reconciliation** | `/reconcile` | Transaction matching, exception handling, bank statement parsing, settlement reconciliation |
| **financial-reporting** | `/fin-report` | GAAP / IFRS reporting, trial balance, P&L + balance sheet generation, audit packages |
| **audit-trails** | `/audit-trail` | Immutable audit logs, event sourcing, compliance trails, chain-of-custody |

### Risk + fraud

| Plugin | Agent / Command | What it covers |
|---|---|---|
| **fraud-detection** ⭐ | `/fraud-detect` | Rule engines, ML scoring, anomaly detection, velocity checks, device fingerprinting, dispute defense |
| **risk-management** | `/risk` | Market / credit / operational risk, VaR, stress testing, capital adequacy |
| **regulatory-compliance** | `/compliance` | SOX, MiFID II, Dodd-Frank, GDPR for financial data, regulatory reporting cadences |
| **kyc-aml** | `/kyc-aml` | Identity verification (KYC), sanctions screening (OFAC, EU), ongoing monitoring, transaction monitoring (AML) |
| **financial-security** | `/fin-security` | PCI DSS scope minimization, encryption at rest + in transit, tokenization, key management, HSM patterns |

### Trading + markets

| Plugin | Agent / Command | What it covers |
|---|---|---|
| **trading-systems** | `/trading` | Order management, matching engines, FIX protocol, market connectivity, smart order routing |
| **market-data** | `/market-data` | Real-time + historical market data, tick data, OHLCV normalization, exchange feeds |
| **portfolio-management** | `/portfolio` | Portfolio construction, rebalancing, allocation strategies, performance attribution |
| **pricing-engines** | `/pricing` | Dynamic pricing, fee calculation, interest computation, FX rates, yield curves |

### Specialized verticals

| Plugin | Agent / Command | What it covers |
|---|---|---|
| **lending-platforms** | `/lending` | Loan origination, credit scoring, underwriting, servicing, collections |
| **insurance-tech** | `/insurtech` | Claims processing, underwriting automation, policy management, actuarial models |
| **cryptocurrency** | `/crypto` | Wallet management, smart contracts, DeFi protocols, custody patterns, chain analysis |

⭐ = depth-complete plugins (substantive expert content). The other 17 are shell-improved (better than templates, deeper in v0.3).

---

## Quick start

```bash
git clone https://github.com/HermeticOrmus/LibreFinTech-Claude-Code.git ~/projects/LibreFinTech-Claude-Code
cd ~/projects/LibreFinTech-Claude-Code
./setup.sh
```

Then in any Claude Code session at your fintech project root:

```
/payments design idempotent payment processing for a marketplace with split payouts, support for refunds + partial refunds, and 3DS challenge flow for EU customers
```

See [QUICK_START.md](QUICK_START.md) for the full walkthrough (build a working payment flow with Stripe + idempotency in 30 minutes).

---

## Learning paths

### Beginner — *"My first fintech feature"*

You've shipped web apps. You're now building something that handles money. The beginner path covers the foundational mindset shifts: idempotency, double-entry, the difference between "transaction succeeded" and "money actually moved."

→ [`learning-paths/beginner.md`](learning-paths/beginner.md)

### Intermediate — *"Production fintech without the disasters"*

Your fintech feature is live. Now you need to handle: chargebacks, fraud attempts, reconciliation, regulatory inquiries, multi-currency, FX, partial outages, settlement delays.

→ [`learning-paths/intermediate.md`](learning-paths/intermediate.md)

### Advanced — *"Compliance, scale, and ops"*

You operate at scale. Now: SOC 2, PCI DSS audit prep, multi-region settlement, custom risk models, regulatory reporting at multiple jurisdictions, live-ops for financial systems.

→ [`learning-paths/advanced.md`](learning-paths/advanced.md)

---

## Compatibility

- **Languages covered**: Python, TypeScript, Go, Rust, Java (for high-frequency contexts)
- **Payment providers covered deeply**: Stripe, Adyen, PayPal, Square, native rails (ACH, SEPA, FedNow, Faster Payments)
- **Bank API providers**: Plaid, Tink, TrueLayer, Belvo (LatAm), Mono (Africa)
- **Compliance frameworks**: PCI DSS, SOC 2, ISO 27001, GDPR + CCPA, regional KYC/AML (US BSA, EU AMLD, UK MLR)
- **Skill level**: experienced web developers entering fintech (most useful) through senior fintech engineers (still useful as a reference)

LibreFinTech makes no calls to external services from within the plugin content itself — the plugins are documentation + prompt-engineering, not runtime middleware.

---

## Contributing

FinTech is wide and jurisdiction-specific. PRs especially welcome for:

- **Regional patterns**: SEA fintech (PayNow, GrabPay), LATAM fintech (PIX, Mercado Pago, Belvo), African fintech (M-Pesa, Mono, Flutterwave), Indian fintech (UPI, RBI compliance)
- **Vertical depth**: insurtech is currently light; lending compliance varies wildly by jurisdiction
- **Compliance translations**: this kit is US/EU-centric; non-Western regulatory regimes under-served
- **Real war stories**: case studies of fintech systems that broke + how they were fixed (anonymized)
- **Crypto / DeFi depth**: currently broad-strokes; deeper protocol-specific content welcome

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Disclaimer

This is documentation and prompt-engineering tooling. **It is not financial advice. It is not legal advice. It is not compliance certification.**

Building fintech systems in regulated jurisdictions requires:
- Licensed legal counsel
- Compliance officer or compliance partner
- Regulatory approval (most jurisdictions require some form)
- Audit (SOC 2, PCI DSS, etc., as applicable)

This toolkit helps you build correctly; it does not absolve you of the regulatory + legal responsibility for what you ship.

---

## Part of the Libre Open-Source Stack for Claude Code

This repository is part of a growing family of open-source toolkits for Claude Code.

### Libre suite — comprehensive plugin bundles

- [LibreUIUX-Claude-Code](https://github.com/HermeticOrmus/LibreUIUX-Claude-Code) — UI/UX development (152 agents, 70 plugins, 76 commands, 74 skills)
- [LibreArch-Claude-Code](https://github.com/HermeticOrmus/LibreArch-Claude-Code) — Software architecture and system design
- [LibreCopy-Claude-Code](https://github.com/HermeticOrmus/LibreCopy-Claude-Code) — Technical writing and documentation engineering
- [LibreDevOps-Claude-Code](https://github.com/HermeticOrmus/LibreDevOps-Claude-Code) — DevOps engineering and infrastructure automation
- [LibreEmbed-Claude-Code](https://github.com/HermeticOrmus/LibreEmbed-Claude-Code) — Embedded systems, firmware, and IoT development
- [LibreGEO-Claude-Code](https://github.com/HermeticOrmus/LibreGEO-Claude-Code) — AI-search optimization (ChatGPT, Perplexity, Gemini, Google AI Overviews)
- [LibreGameDev-Claude-Code](https://github.com/HermeticOrmus/LibreGameDev-Claude-Code) — Game development across Godot, Unity, Unreal
- [LibreMLOps-Claude-Code](https://github.com/HermeticOrmus/LibreMLOps-Claude-Code) — ML engineering and AI operations
- [LibreMobileDev-Claude-Code](https://github.com/HermeticOrmus/LibreMobileDev-Claude-Code) — Mobile app development (Flutter, React Native, native iOS, native Android)
- [LibreSecOps-Claude-Code](https://github.com/HermeticOrmus/LibreSecOps-Claude-Code) — Security operations
- [LibreSessionFlow-Claude-Code](https://github.com/HermeticOrmus/LibreSessionFlow-Claude-Code) — Session lifecycle: handoff, pickup, absorb, explore, close

### Skills mini-repos — single CLAUDE.md drop-ins

- [vibe-engineer-skills](https://github.com/HermeticOrmus/vibe-engineer-skills) — Direct AI codegen well: hypothesis before help, scoped prompts, validate before accepting
- [markdown-discipline-skills](https://github.com/HermeticOrmus/markdown-discipline-skills) — Strip AI-slop from markdown (no em dashes, no marketing fluff)
- [shell-safety-skills](https://github.com/HermeticOrmus/shell-safety-skills) — `set -euo pipefail` discipline plus 15 failure-mode examples
- [commit-standard-skills](https://github.com/HermeticOrmus/commit-standard-skills) — Ormus Commit Standard v1.0 plus commit-msg hook and commitlint
- [unwoke-skills](https://github.com/HermeticOrmus/unwoke-skills) — Strip AI theater (ten sins to eliminate, symmetric engagement)
- [python-conventions-skills](https://github.com/HermeticOrmus/python-conventions-skills) — Modern Python 3.11+ (types, pathlib, async, ruff, mypy, uv)
- [typescript-conventions-skills](https://github.com/HermeticOrmus/typescript-conventions-skills) — TypeScript strict mode, discriminated unions, Result types
- [hermetic-laws-skills](https://github.com/HermeticOrmus/hermetic-laws-skills) — Seven Hermetic Principles applied to engineering
- [riper-workflow-skills](https://github.com/HermeticOrmus/riper-workflow-skills) — Research / Innovate / Plan / Execute / Review systematic dev
- [six-day-cycle-skills](https://github.com/HermeticOrmus/six-day-cycle-skills) — Sustainable shipping cadence with mandatory rest
- [token-optimization-skills](https://github.com/HermeticOrmus/token-optimization-skills) — Claude Code token and context optimization
- [osint-skills](https://github.com/HermeticOrmus/osint-skills) — OSINT research methodology (multi-wave investigative spiral)
- [calcinate-skills](https://github.com/HermeticOrmus/calcinate-skills) — Stage 1 of the Magnum Opus (burn project bloat)
- [claude-md-overhaul-skills](https://github.com/HermeticOrmus/claude-md-overhaul-skills) — Audit CLAUDE.md and MEMORY.md against caps
- [session-handoff-skills](https://github.com/HermeticOrmus/session-handoff-skills) — Session handoff and pickup discipline
- [naming-skills](https://github.com/HermeticOrmus/naming-skills) — Product naming methodology (mine the brand's vocabulary)
- [magnum-opus-skills](https://github.com/HermeticOrmus/magnum-opus-skills) — Seven-stage alchemy applied to project transformation
- [mem-search-skills](https://github.com/HermeticOrmus/mem-search-skills) — Search claude-mem cross-session memory: search, filter, fetch
- [hypothesis-debugging-skills](https://github.com/HermeticOrmus/hypothesis-debugging-skills) — Hypothesis-driven debugging: reproduce, isolate, test, fix
- [vibe-proof-skills](https://github.com/HermeticOrmus/vibe-proof-skills) — Security hardening for vibe-coded full-stack apps
- [tdd-skills](https://github.com/HermeticOrmus/tdd-skills) — Test-driven development (Red-Green-Refactor) for JS/TS and Python
- [mars-skills](https://github.com/HermeticOrmus/mars-skills) — Production-readiness audit: the five mortal sins of vibe-coded MVPs
- [git-workflow-skills](https://github.com/HermeticOrmus/git-workflow-skills) — Clean git workflow: branch, atomic commits, reviewable PRs
- [code-review-skills](https://github.com/HermeticOrmus/code-review-skills) — Domain-aware code review: classify the code, then focus
- [code-comprehension-skills](https://github.com/HermeticOrmus/code-comprehension-skills) — Understand an unfamiliar codebase fast
- [dx-audit-skills](https://github.com/HermeticOrmus/dx-audit-skills) — Audit developer experience: docs, onboarding, tooling friction
- [setup-env-skills](https://github.com/HermeticOrmus/setup-env-skills) — Set up a project's development environment
- [automate-skills](https://github.com/HermeticOrmus/automate-skills) — Turn repetitive tasks into reliable automation scripts
- [quick-fix-skills](https://github.com/HermeticOrmus/quick-fix-skills) — Fast troubleshooting for common issues
- [prime-context-skills](https://github.com/HermeticOrmus/prime-context-skills) — Prime project context at the start of a session
- [auto-docs-skills](https://github.com/HermeticOrmus/auto-docs-skills) — Generate and maintain project documentation
- [learning-skills](https://github.com/HermeticOrmus/learning-skills) — Learn any technology: roadmaps, explanations, practice, cheatsheets, comparisons
- [linux-sysadmin-skills](https://github.com/HermeticOrmus/linux-sysadmin-skills) — Linux system administration: security, performance, diagnostics, monitoring, maintenance

### Template source

- [andrej-karpathy-skills](https://github.com/HermeticOrmus/andrej-karpathy-skills) — the canonical single-file CLAUDE.md pattern (fork of jiayuan_jy's original)

Star the family, not just one — that's how the suite stays coherent.
