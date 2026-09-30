#!/usr/bin/env bash
# Session Start Hook - FinTech (libre-fintech-hooks)
# Detects FinTech project context and tells Claude which signals it found.
#
# Claude Code sends the hook input as JSON on stdin; this reads "cwd".
# Prints one short line on stdout (added to the session context) only when
# the project looks like a financial system. Prints nothing otherwise.

# No set -e on purpose: a hook that exits 2 blocks the tool call, so every
# path here ends in exit 0. Written for bash 3.2 (macOS) and later.

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

dir="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
[ -n "$dir" ] && [ -d "$dir" ] || dir="$PWD"

signals=()

# Ledger and payments code folders
if [ -d "$dir/src/ledger" ] || [ -d "$dir/ledger" ]; then signals+=("ledger code"); fi
if [ -d "$dir/src/payments" ] || [ -d "$dir/payments" ]; then signals+=("payments code"); fi

# Payment, banking, or Open Banking SDKs in the dependency manifests
deps=""
for f in package.json requirements.txt pyproject.toml go.mod Gemfile composer.json pom.xml build.gradle build.gradle.kts; do
  [ -f "$dir/$f" ] && deps="$deps $(grep -oiE '(^|[^a-z0-9])(stripe|plaid|adyen|braintree|paypal|dwolla|truelayer|banking)([^a-z0-9]|$)' "$dir/$f" 2>/dev/null | tr 'A-Z' 'a-z' | tr -cd 'a-z\n' | sort -u | tr '\n' ' ')"
done
deps="$(tr ' ' '\n' <<<"$deps" | grep -v '^$' | sort -u | tr '\n' ' ')"
[ -n "${deps// /}" ] && signals+=("SDKs: ${deps% }")

# Compliance folder
[ -d "$dir/compliance" ] && signals+=("compliance folder")

[ "${#signals[@]}" -eq 0 ] && exit 0

list="$(printf '%s, ' "${signals[@]}")"
echo "[libre-fintech] FinTech project detected (${list%, }). The libre-fintech agents, commands, and skills apply here."
exit 0
