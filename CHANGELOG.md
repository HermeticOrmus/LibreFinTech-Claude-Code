# Changelog

## [1.1.0] - 2026-09-30

### Added
- A public pantry in `pantry/`: a dated competitor map, X mine, people mine and pantry queue, every row cited, plus templates for the next run.
- `pantry/MENU.md`, generated from the newest pantry queue by the menu script, which orders the Goal atoms and names one as up next.
- Two issue forms with matching labels: `routing-miss`, for when Claude picks the wrong agent or skill, and `plugin-proposal`, for a new plugin, agent, skill or command.
- A Ways to contribute section in CONTRIBUTING.md (Menu items, routing misses, plugin proposals, translations, sharing builds, and how to test a change locally), and a Contribute section in the README.
- Grok Build support. Grok Build reads the same plugin folders; `.grok-plugin/marketplace.json`, generated from the Claude manifest by `scripts/sync-grok-manifest.py`, makes the repo a Grok marketplace too (`grok plugin marketplace add HermeticOrmus/LibreFinTech-Claude-Code`). A `grok` CI job fails when that file drifts, validates every plugin with `grok plugin validate`, and installs all 21 into a clean Grok home.
- `./setup.sh --grok` installs through the Grok Build CLI instead of Claude Code, with the same `--only`, `--list`, and `--uninstall` options.
- `LEDGER.md`, the kintsugi ledger: every crack the 1.0.0 release found and sealed, with its evidence, and the cracks still open.

### Fixed
- The plugin-authoring layout in CONTRIBUTING.md shows `.claude-plugin/plugin.json` and `skills/<name>/SKILL.md`, the layout the pack uses since 1.0.0, instead of `skills/<name>.md`.

## [1.0.0] - 2026-09-30

This release makes the pack installable. Before it, `setup.sh` copied folders into `~/.claude/plugins`, where Claude Code does not load plugins from, and the agents and commands sat in a nested layout Claude Code does not read, so none of the 20 plugins loaded. Now every plugin installs through the Claude Code plugin system, and every agent, command, and skill is discovered and routed.

### Added
- `.claude-plugin/marketplace.json` at the root and a `plugin.json` in every plugin: the repo is now the `libre-fintech` marketplace. Install with `/plugin marketplace add HermeticOrmus/LibreFinTech-Claude-Code`, then `/plugin install <plugin>@libre-fintech`.
- `libre-fintech-hooks`, an optional plugin that wires the pack's hook scripts into Claude Code. It asks before Claude touches `.env` files, private keys, keystores, credentials and secrets files, or the `ledger-data/`, `transaction-dumps/`, and `pii-exports/` folders, and before `rm -rf`, force pushes, hard resets, or SQL `DROP`, `TRUNCATE`, and `DELETE FROM`. It warns when a write leaves a file empty, reminds Claude once per session to run the tests after a code change, and notes detected ledger, payments, SDK, and compliance signals at session start.
- An `argument-hint` on every command, listing its actions and flags.
- CI (`.github/workflows/validate.yml`) that validates the marketplace and every plugin, then installs all of them into a clean config, on every push to main and every pull request.
- A feedback issue form and a Feedback section in the README.

### Changed
- Agents moved from `agents/<name>/AGENT.md` to `agents/<name>.md`, commands from `commands/<name>/COMMAND.md` to `commands/<name>.md`, and loose skill files into `skills/<name>/SKILL.md`, the layout Claude Code loads. File content is unchanged apart from new frontmatter.
- Every agent, command, and skill has a routing description that says when to use it. Every plugin has a one-sentence description, the same in `plugin.json` and in the marketplace. Descriptions for the compliance-heavy plugins (`regulatory-compliance`, `kyc-aml`, `financial-security`) state what engineering they do and leave legal and certification decisions with your compliance function, as the README disclaimer already says.
- Agents use `model: inherit`, so they run on the model you picked. `payment-engineer`, `ledger-architect`, and `fraud-analyst` were pinned to `sonnet` before.
- `setup.sh` installs through the Claude Code CLI and supports `--list`, `--only`, `--scope`, and `--uninstall`. `--plugins-dir` is still accepted but no longer used.
- `payment-processing`, `ledger-design`, and `fraud-detection` each carried two generations of every file. The older ones are merged into the current ones: the `payments-engineer` agent into `payment-engineer`, `fraud-engineer` into `fraud-analyst`, the nested `ledger-architect` into the flat one, the older `/payments`, `/ledger`, and `/fraud-detect` command files into the current ones, and the `payment-patterns`, `ledger-patterns`, and `fraud-detection-patterns` skills into `payment-processing`, `ledger-design`, and `fraud-detection`. Every section survived, including the per-action process and examples of each command and the core patterns, anti-patterns, and references of each skill.
- The repo-level `hooks/` scripts moved into `plugins/libre-fintech-hooks/hooks/` and now read Claude Code's JSON input on stdin. They no longer write log files.
- QUICK_START, TROUBLESHOOTING, and CONTRIBUTING show the Claude Code install path, check an install with `claude plugin list`, and describe the validation CI runs.

### Fixed
- None of the plugins loaded after `./setup.sh`. They load now.
- The hook scripts read `$1` and `$2`, which Claude Code never sets, and were never registered. They run now, once `libre-fintech-hooks` is installed.

### Upgrading from 0.2.0
- Run `./setup.sh` again (or `/plugin install <plugin>@libre-fintech`), restart Claude Code, then delete the old copies with `rm -rf ~/.claude/plugins/libre-fintech-*`.
- If you called `payments-engineer`, `fraud-engineer`, `payment-patterns`, `ledger-patterns`, or `fraud-detection-patterns` by name, use `payment-engineer`, `fraud-analyst`, `payment-processing`, `ledger-design`, and `fraud-detection` instead.

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
