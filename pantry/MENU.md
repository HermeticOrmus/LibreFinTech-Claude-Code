# Menu: LibreFinTech-Claude-Code

Queue: 2026-09-30-pantry-queue.md
Counts: open 7, in flight 0, shipped 0, parked 0, dropped 0, needs fixing 0

## Steer

- none

## Up next

**hooks-test**: Test the hook scripts with a `hooks-test` script in CI (queue #3, high, repo, since 2026-09-30)

- Done when: `bash plugins/libre-fintech-hooks/tests/run.sh` exits 0; it pipes one JSON input per sensitive path, export folder and destructive command listed in `plugins/libre-fintech-hooks/README.md` (including SQL `DROP TABLE`, `TRUNCATE` and `DELETE FROM`) into `hooks/pre-tool-use.sh` and asserts `"permissionDecision":"ask"` for each, asserts empty output for an ordinary file and an ordinary command, and fails when a case breaks; `.github/workflows/validate.yml` runs it on pull requests
- Verify on: repo
- Evidence: Matrix: "Safety hooks (secrets, card data, destructive SQL)" (Us Y, asks; PayGrade Y, blocks; RavenPay P). Matrix: "Evals proving agent quality" (Us N). Repo: the hooks README makes each claim the test checks
- Issue: none yet (promote after merge)
- Order: hooks-test, ledger-schema, webhook-handler, compliance-report, provider-mcp, regional-rails, payments-evals
- Tie: hooks-test over ledger-schema, webhook-handler, by key order (jev off)

## Atoms

| Key | Title | State | Confidence | Class | Since | Queue # | Issue | Because |
|-----|-------|-------|------------|-------|-------|---------|-------|---------|
| compliance-report | Ship the `compliance-report` scaffold as an evidence export | open | medium | repo | 2026-09-30 | 4 | - | - |
| hooks-test | Test the hook scripts with a `hooks-test` script in CI | open | high | repo | 2026-09-30 | 3 | - | - |
| ledger-schema | Ship the `ledger-schema` template the README promises | open | high | repo | 2026-09-30 | 1 | - | - |
| payments-evals | Add a `payments-evals` suite for payment-processing | open | low | eval | 2026-09-30 | 7 | - | - |
| provider-mcp | Add a `provider-mcp` section on pairing with vendor MCP servers | open | medium | repo | 2026-09-30 | 5 | - | - |
| regional-rails | Add a `regional-rails` skill for Pix, UPI and M-Pesa | open | medium | repo | 2026-09-30 | 6 | - | - |
| webhook-handler | Ship the `webhook-handler` template the README promises | open | high | repo | 2026-09-30 | 2 | - | - |

## Retired

| Key | Title | State | Since | Issue | Because |
|-----|-------|-------|-------|-------|---------|
| none | | | | | |

## Notes

- none
