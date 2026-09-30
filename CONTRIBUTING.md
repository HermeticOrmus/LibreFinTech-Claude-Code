# Contributing

FinTech is wide and jurisdiction-specific. PRs welcome — especially for regional patterns, real-world case studies, and compliance translations beyond the US/EU baseline.

## Ways to contribute

### Take a Menu item

[`pantry/MENU.md`](pantry/MENU.md) lists the next pieces of work for this pack, each with a Done-when anyone can check, and names one as up next. Open items also show up as [`[menu]` issues](https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/issues?q=is%3Aopen+label%3Amenu), and smaller starter tasks as [good first issues](https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/contribute). Claim one by commenting on its issue, then open a pull request that says `Closes #N`. The research behind the Menu is in [`pantry/`](pantry/README.md).

### Report or fix a routing miss

When Claude picks the wrong agent or skill for a fintech question, or none at all, open a [routing miss](https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/issues/new?template=routing-miss.yml). The fix is almost always a sharper `description` in the frontmatter of the agent, command or skill that should have answered, which makes it a good first pull request. Leave real card numbers, account numbers, keys and customer data out of the report.

### Propose or build a plugin

Open a [plugin proposal](https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/issues/new?template=plugin-proposal.yml) first, so the scope is agreed before you write it. A plugin in this pack has this layout:

```text
plugins/<name>/
├── .claude-plugin/plugin.json   # name, version, description, author, homepage, repository, license, keywords
├── README.md                    # what the plugin covers
├── agents/<agent-name>.md       # frontmatter: name, description, model: inherit
├── commands/<command-name>.md   # frontmatter: description, argument-hint
└── skills/<skill-name>/SKILL.md # frontmatter: name, description
```

Every `description` is a routing description: it tells Claude when to use that agent, command or skill (agents start with "Use this agent when ..."). Then add the plugin to `.claude-plugin/marketplace.json` with the same `name`, `"source": "./plugins/<name>"`, the same one-sentence `description` as its `plugin.json`, and a `version`, and add a row to the matching table in the README. To deepen an existing plugin instead, edit its agent, command or skill in place and keep the frontmatter.

In regulated areas (compliance, KYC and AML, PCI DSS, lending, insurance), write the engineering: the systems, data flows, controls and evidence. State that legal interpretation, certification and sign-off stay with the operator's legal and compliance function, the way the existing `regulatory-compliance`, `kyc-aml` and `financial-security` descriptions do. Nothing in this pack is financial, legal or compliance advice.

### Translate

The pack is English only. If you want to translate the README, QUICK_START or a learning path, open a [feedback issue](https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/issues/new?template=feedback.yml) first so the translation has a home and can be kept in step with the English files. Adapting a plugin to another jurisdiction's rails or rules is a different job: see the regional patterns under "What we welcome" below.

### Share what you built

Built a payment flow, a ledger or a plugin with this pack? Share it in [Discussions](https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/discussions/categories/show-and-tell) under Show and tell.com/HermeticOrmus/LibreFinTech-Claude-Code/issues/new?template=feedback.yml). Anonymized war stories are how the Menu learns what to build next.

### Test your change locally

Load one plugin straight from your working folder, for a single session:

```bash
claude --plugin-dir ./plugins/<plugin>
```

Validate the marketplace and every plugin you touched:

```bash
claude plugin validate .
claude plugin validate plugins/<plugin>
```

Install from your clone into a throwaway config, the way CI does, and check what loaded:

```bash
export CLAUDE_CONFIG_DIR=$(mktemp -d)
claude plugin marketplace add ./
claude plugin install <plugin>@libre-fintech
claude plugin details <plugin>@libre-fintech
claude plugin list
unset CLAUDE_CONFIG_DIR
```

`claude plugin details` lists the plugin's skills (its commands appear there too) and agents, so you can confirm a new one is picked up. CI (`.github/workflows/validate.yml`) runs the same validate and clean-install checks on every pull request. A second `grok` job checks that `.grok-plugin/marketplace.json` matches the Claude manifest, validates every plugin with `grok plugin validate`, and installs them into a clean Grok Build home; after you change `.claude-plugin/marketplace.json`, run `python3 scripts/sync-grok-manifest.py` and commit the file it writes. If this is your first contribution to the repo, GitHub holds that CI run until a maintainer approves it.

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

Before opening a PR, run `claude plugin validate .` and `claude plugin validate plugins/<plugin>` for each plugin you touched. CI runs the same checks and a clean install of every plugin. Agents live in `plugins/<plugin>/agents/<name>.md`, commands in `plugins/<plugin>/commands/<name>.md`, and skills in `plugins/<plugin>/skills/<name>/SKILL.md`, each with a frontmatter `description` that says when to use it.

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
├── .claude-plugin/plugin.json   # plugin manifest
├── README.md
├── agents/<name>.md             # specialist agent prompt
├── commands/<name>.md           # slash command logic
└── skills/<name>/SKILL.md       # reference pattern library
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
