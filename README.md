<p align="center">
  <h1 align="center">LibreFinTech</h1>
  <p align="center">Claude Code Plugins for Financial Technology Development</p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/plugins-20-b58900?style=for-the-badge" alt="20 Plugins">
  <img src="https://img.shields.io/badge/license-MIT-b58900?style=for-the-badge" alt="MIT License">
  <img src="https://img.shields.io/badge/claude--code-plugins-b58900?style=for-the-badge" alt="Claude Code">
  <img src="https://img.shields.io/badge/fintech-ready-b58900?style=for-the-badge" alt="FinTech Ready">
</p>

---

A curated collection of Claude Code plugins for financial technology development. From payment processing to trading systems, ledger design to regulatory compliance, risk management to real-time settlement.

## Plugin Collection

| # | Plugin | Domain | Command | Description |
|---|--------|--------|---------|-------------|
| 1 | [audit-trails](plugins/audit-trails/) | Compliance | `/audit-trail` | Immutable audit logs, event sourcing, compliance trails |
| 2 | [banking-apis](plugins/banking-apis/) | Banking | `/banking-api` | Open banking APIs, PSD2, account aggregation |
| 3 | [cryptocurrency](plugins/cryptocurrency/) | Crypto | `/crypto` | Blockchain integration, wallets, smart contracts, DeFi |
| 4 | [financial-reporting](plugins/financial-reporting/) | Reporting | `/fin-report` | Financial statements, GAAP/IFRS, automated reporting |
| 5 | [financial-security](plugins/financial-security/) | Security | `/fin-security` | PCI DSS, encryption, tokenization, secure transactions |
| 6 | [fraud-detection](plugins/fraud-detection/) | Risk | `/fraud-detect` | Rule engines, ML fraud detection, anomaly scoring |
| 7 | [insurance-tech](plugins/insurance-tech/) | Insurance | `/insurtech` | Claims processing, underwriting, policy management |
| 8 | [kyc-aml](plugins/kyc-aml/) | Compliance | `/kyc-aml` | Identity verification, sanctions screening, monitoring |
| 9 | [ledger-design](plugins/ledger-design/) | Core | `/ledger` | Double-entry bookkeeping, ledger architecture |
| 10 | [lending-platforms](plugins/lending-platforms/) | Lending | `/lending` | Loan origination, credit scoring, servicing |
| 11 | [market-data](plugins/market-data/) | Data | `/market-data` | Market data feeds, tick data, OHLCV normalization |
| 12 | [open-banking](plugins/open-banking/) | Banking | `/open-banking` | Open banking standards, consent management |
| 13 | [payment-processing](plugins/payment-processing/) | Payments | `/payments` | Payment gateways, Stripe/Adyen, 3DS, billing |
| 14 | [portfolio-management](plugins/portfolio-management/) | Investment | `/portfolio` | Portfolio construction, rebalancing, allocation |
| 15 | [pricing-engines](plugins/pricing-engines/) | Pricing | `/pricing` | Dynamic pricing, fee calculation, interest computation |
| 16 | [real-time-settlement](plugins/real-time-settlement/) | Settlement | `/settlement` | RTGS, instant payments, clearing, netting |
| 17 | [reconciliation](plugins/reconciliation/) | Operations | `/reconcile` | Transaction reconciliation, matching, exceptions |
| 18 | [regulatory-compliance](plugins/regulatory-compliance/) | Compliance | `/compliance` | SOX, MiFID II, Dodd-Frank, regulatory reporting |
| 19 | [risk-management](plugins/risk-management/) | Risk | `/risk` | Market/credit/operational risk, VaR, stress testing |
| 20 | [trading-systems](plugins/trading-systems/) | Trading | `/trading` | Order management, matching engines, FIX protocol |

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/HermeticOrmus/LibreFinTech-Claude-Code.git
```

### 2. Copy a Plugin to Your Project

```bash
# Copy a single plugin
cp -r LibreFinTech-Claude-Code/plugins/payment-processing/.claude/ your-project/.claude/

# Or symlink for updates
ln -s /path/to/LibreFinTech-Claude-Code/plugins/ledger-design/.claude/ your-project/.claude/
```

### 3. Use the FinTech Template

```bash
cp LibreFinTech-Claude-Code/templates/CLAUDE.md your-project/CLAUDE.md
```

### 4. Activate Hooks (Optional)

```bash
cp LibreFinTech-Claude-Code/hooks/*.sh your-project/.claude/hooks/
chmod 755 your-project/.claude/hooks/*.sh
```

## Architecture

```
LibreFinTech-Claude-Code/
├── plugins/                    # 20 domain-specific plugins
│   └── {plugin-name}/
│       ├── README.md           # Plugin documentation
│       ├── agents/             # Agent definitions (AGENT.md)
│       ├── commands/           # Slash commands (COMMAND.md)
│       └── skills/             # Knowledge & patterns (SKILL.md)
├── hooks/                      # Session lifecycle hooks
│   ├── session-start.sh        # Financial project detection
│   ├── pre-tool-use.sh         # PII/data safety checks
│   └── post-tool-use.sh        # Compliance verification
├── learning-paths/             # Structured learning progressions
│   ├── beginner.md             # FinTech fundamentals
│   ├── intermediate.md         # Integration & risk
│   └── advanced.md             # Trading & settlement systems
├── templates/                  # Project templates
│   └── CLAUDE.md               # FinTech project CLAUDE.md
└── .github/                    # GitHub community files
```

### Plugin Anatomy

Each plugin provides three components that map to Claude Code's extension model:

- **Agent** (`AGENT.md`) -- Defines a specialist persona with domain expertise, behavioral guidelines, and output conventions. Agents understand the "why" behind financial patterns.

- **Command** (`COMMAND.md`) -- Provides a slash command interface for common workflows. Commands define triggers, inputs, processing steps, and expected outputs.

- **Skill** (`SKILL.md`) -- Encodes domain knowledge as pattern libraries. Skills contain proven patterns, anti-patterns, and references to standards and regulations.

### Learning Paths

Three progressive tracks guide developers from FinTech fundamentals through production-grade systems:

1. **Beginner** -- Payment basics, ledger concepts, regulatory landscape
2. **Intermediate** -- Payment integration, risk scoring, KYC/AML workflows
3. **Advanced** -- Trading systems, real-time settlement, algorithmic pricing

### Hooks

Lifecycle hooks add financial-domain safety to every Claude Code session:

- **session-start** -- Detects project type, loads relevant compliance frameworks
- **pre-tool-use** -- Scans for PII exposure, validates data handling
- **post-tool-use** -- Verifies compliance posture, logs audit events

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. All contributions must align with the project's commitment to empowering developers and rejecting extractive patterns.

## License

[MIT](LICENSE) -- Copyright (c) 2025-2026 Hermetic Ormus
