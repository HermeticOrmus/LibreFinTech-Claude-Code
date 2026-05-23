# Contributing

FinTech is wide and jurisdiction-specific. PRs welcome — especially for regional patterns, real-world case studies, and compliance translations beyond the US/EU baseline.

## What we welcome

- **Bug fixes** in any plugin
- **Regional fintech patterns**:
  - SEA: PayNow (SG), GrabPay, Vietnam payment rails, Indonesia QRIS
  - LATAM: PIX (BR), Mercado Pago, Belvo, dLocal, regional remittance
  - Africa: M-Pesa, Mono, Flutterwave, Paystack
  - India: UPI, RBI compliance, NPCI rails
  - Middle East: Saudi Arabian Monetary Authority, UAE Central Bank rules
- **Vertical depth**:
  - Insurtech (current depth is light)
  - Lending in non-US jurisdictions
  - Wealth management at scale
  - Crypto custody (current depth is broad-strokes)
- **Compliance + regulatory translations** beyond US/EU
- **Real war stories**: anonymized case studies of fintech systems that broke + how they were fixed
- **Worked code examples** with real provider integrations (Stripe, Plaid, Adyen, PayPal)

## What we don't accept

- Patterns that violate regulatory requirements in major jurisdictions
- Closed-source dependencies in the core plugin content
- Plugins that require paid services without a free-tier alternative
- "Trust me" code without explainable reasoning
- AI-generated content with no real-fintech verification

## What this kit is NOT

- **Legal advice**. Compliance with financial regulation is the operator's responsibility.
- **A compliance certification**. SOC 2, PCI DSS, ISO 27001 require auditors.
- **A replacement for licensed expertise**. Licensed payment processors, regulated bank charters, FINRA-licensed broker-dealers — these are required for what they're required for.

The kit helps you write code that handles money correctly. The legal + regulatory layer is separate.

## Setup

```bash
git clone https://github.com/<your-username>/LibreFinTech-Claude-Code.git
cd LibreFinTech-Claude-Code
./setup.sh
```

## Branch + PR workflow

```
git checkout -b feat/<slug>      # new plugin or major content
git checkout -b fix/<slug>       # bug fix
git checkout -b deepen/<plugin>  # deepening a shell plugin
git checkout -b region/<plugin>  # adding regional variant
git checkout -b casestudy/<slug> # real-world case study (anonymized)
```

Commit format: `type(scope): description` (e.g., `deepen(kyc-aml): add OFAC SDN list integration patterns`).

PR template:

```markdown
## Why
<motivation in 1-3 sentences>

## What changed
<bulleted list>

## How to verify
<scenario to pose to the agent + expected response>

## Real-world verification (if applicable)
<which payment provider, which jurisdiction, which compliance regime>

## Regulatory considerations
<any compliance/legal implications callers should be aware of>

## Notes
<follow-ups, related issues>
```

## Plugin-authoring conventions

Each plugin lives in `plugins/<name>/` with three subdirectories:

```
plugins/<name>/
├── README.md
├── agents/<name>.md       # specialist agent prompt
├── commands/<name>.md     # slash command logic
└── skills/<name>.md       # reference pattern library
```

### Agent prompts should include

- Frontmatter `name:` + `description:`
- Purpose + core principles
- Domain-specific failure modes named explicitly
- Real provider grounding (Stripe / Adyen / PayPal / regional rail names)
- Regulatory grounding where applicable (PCI scope, PSD2, AML triggers)
- 150-300 lines of substantive content

### Commands should include

- Clear job-to-be-done framing
- Concrete code examples with real provider API names
- Idempotency + retry + reconciliation patterns where applicable
- Anti-patterns specific to fintech (storing card data, sync webhook handlers, etc.)
- 200-400 lines

### Skills should include

- Pattern library, not tutorial
- Common fintech mistakes catalog
- Regulatory considerations per pattern
- Cross-references to other plugins
- 100-200 lines

## The substance bar

LibreFinTech's flagship plugins (`payment-processing`, `ledger-design`, `fraud-detection`) match LibreUIUX-Claude-Code substance — real provider expertise, real code, real regulatory grounding. New contributions should aim for that depth.

The CHANGELOG maturity matrix tracks which plugins are depth-complete vs. shell-improved.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

MIT. By submitting a PR you agree your contribution is licensed under MIT. No CLA.
