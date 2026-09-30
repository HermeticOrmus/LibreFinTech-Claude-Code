#!/usr/bin/env bash
# Pre-Tool-Use Hook - FinTech (libre-fintech-hooks)
# Validates actions before execution.
#
# Claude Code sends the hook input as JSON on stdin; this reads "tool_name",
# "tool_input.file_path", and "tool_input.command".
#
# - A file tool that targets a sensitive file (.env, .pem, .key, credentials,
#   secrets, key stores) or financial data export (ledger-data/,
#   transaction-dumps/, pii-exports/) asks you to confirm first.
# - A shell command that touches one of those, or that is destructive
#   (rm -rf, force push, hard reset, DROP, TRUNCATE, DELETE FROM), asks you
#   to confirm first. Ledger rows are corrected with compensating entries,
#   not deleted.
# Everything else passes silently.

# No set -e on purpose: a hook that exits 2 blocks the tool call, so every
# path here ends in exit 0. Written for bash 3.2 (macOS) and later.

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' <<<"$input" 2>/dev/null)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null)"

ask() {
  jq -cn --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# Sensitive files: env files (not .example/.sample/.template), private keys
# and certificates, credentials and secrets files, and the financial data
# folders this pack's .gitignore marks as never-commit.
is_sensitive() {
  local full p
  full="$1"
  p="$(basename -- "$full")"
  case "$p" in
    *.example|*.sample|*.template|*.dist) return 1 ;;
  esac
  grep -qiE '(^|/)(ledger-data|transaction-dumps|pii-exports)(/|$)' <<<"$full" && return 0
  grep -qiE '^\.env($|\.)|\.(env|pem|key|p12|pfx|jks|keystore|kdbx)$|(^|[._-])(credentials?|secrets?)([._-]|$)|\.csv\.encrypted$' <<<"$p"
}

check_sensitive_files() {
  if [ -n "$path" ] && is_sensitive "$path"; then
    ask "libre-fintech: $tool targets a potentially sensitive file or financial data export ($path). Confirm before continuing."
  fi
  if [ -n "$cmd" ]; then
    local tok
    set -f
    for tok in $cmd; do
      tok="${tok//\"/}"; tok="${tok//\'/}"
      case "$tok" in
        */*|*.*) is_sensitive "$tok" && ask "libre-fintech: this command touches a potentially sensitive file or financial data export ($tok). Confirm before continuing." ;;
      esac
    done
    set +f
  fi
}

check_destructive_ops() {
  [ -n "$cmd" ] || return 0
  if grep -qE '(^|[;&|[:space:]])rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*f|(^|[;&|[:space:]])rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*[rR]|git[[:space:]]+push[^;&|]*(--force|[[:space:]]-f([[:space:]]|$))|git[[:space:]]+reset[[:space:]]+--hard' <<<"$cmd"; then
    ask "libre-fintech: destructive command detected ($cmd). Confirm before continuing."
  fi
  if grep -qiE '(^|[^a-z_])(drop[[:space:]]+(table|database|schema)([[:space:]]|;|$)|truncate[[:space:]]|delete[[:space:]]+from)' <<<"$cmd"; then
    ask "libre-fintech: this command drops, truncates, or deletes database rows ($cmd). Ledger and audit rows should be corrected with compensating entries. Confirm before continuing."
  fi
}

check_sensitive_files
check_destructive_ops
exit 0
