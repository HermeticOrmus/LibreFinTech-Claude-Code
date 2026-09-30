# libre-fintech-hooks

> Optional safety and context hooks for financial projects. Install it on its own, or get it with a full `./setup.sh` run.

## What it does

| Event | Script | Behavior |
|---|---|---|
| SessionStart | `hooks/session-start.sh` | When the project has `src/ledger/`, `ledger/`, `src/payments/`, `payments/`, or `compliance/` folders, or a dependency manifest that names Stripe, Plaid, Adyen, Braintree, PayPal, Dwolla, TrueLayer, or banking packages, prints one line naming what it found. Prints nothing in other projects. |
| PreToolUse | `hooks/pre-tool-use.sh` | Asks you to confirm before a tool reads or writes a sensitive file: `.env` files (not `.env.example`), `.pem`, `.key`, `.p12`, `.pfx`, `.jks`, `.keystore`, `credentials` and `secrets` files, `*.csv.encrypted`, or anything under `ledger-data/`, `transaction-dumps/`, or `pii-exports/`. Also asks before `rm -rf`, `git push --force`, `git reset --hard`, and SQL `DROP`, `TRUNCATE`, or `DELETE FROM` in a shell command, since ledger and audit rows are corrected with compensating entries. Silent otherwise. |
| PostToolUse | `hooks/post-tool-use.sh` | Tells Claude when a file is empty after a write, and once per session, after the first code change, reminds it to run the tests, including idempotency, rounding, and balance invariant cases. |

The hooks read the JSON that Claude Code sends on stdin, so they need `jq` on your `PATH`. Without `jq` they exit quietly and do nothing. They never write inside the plugin directory; the once-per-session marker goes to the system temp directory.

These hooks are a guard rail for day-to-day work, not a security or compliance control.

## Install

```
/plugin install libre-fintech-hooks@libre-fintech
```

Or from a terminal: `claude plugin install libre-fintech-hooks@libre-fintech`, or `./setup.sh --only libre-fintech-hooks` from the repo root. Restart Claude Code to load the hooks, and run `/hooks` to see them registered.

## Test a hook by hand

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM ledger_entries\""}}' | hooks/pre-tool-use.sh
```

It prints a `permissionDecision: "ask"` JSON object for a risky call and nothing for an ordinary one.
