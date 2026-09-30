#!/usr/bin/env bash
# LibreFinTech installer.
#
# Registers this checkout as a Claude Code plugin marketplace and installs its
# plugins through the Claude Code CLI, so Claude Code actually loads them.
# It does the same thing as running, inside Claude Code:
#   /plugin marketplace add HermeticOrmus/LibreFinTech-Claude-Code
#   /plugin install <plugin>@libre-fintech
#
# With --grok it installs into Grok Build through the grok CLI instead, the
# same as `grok plugin marketplace add <this checkout>` followed by
# `grok plugin install <plugin>@<checkout folder name> --trust`. Grok asks you
# to trust a plugin before it installs it; running this script with --grok is
# that decision, so the script passes --trust.
#
# Usage:
#   ./setup.sh                      install every plugin
#   ./setup.sh --only p1,p2         install only the named plugins
#   ./setup.sh --list               list the plugins in this pack
#   ./setup.sh --scope project      install for this project only (user|project|local)
#   ./setup.sh --uninstall          remove this pack's plugins and marketplace
#   ./setup.sh --grok               install into Grok Build instead of Claude Code
#                                   (works with --only, --list, and --uninstall)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_DIR/.claude-plugin/marketplace.json"
ONLY=""
LIST=0
UNINSTALL=0
SCOPE="user"
GROK=0

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --list) LIST=1; shift ;;
    --scope) SCOPE="${2:?--scope needs user, project, or local}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --grok) GROK=1; shift ;;
    --plugins-dir)
      echo "note: --plugins-dir is no longer used; Claude Code manages plugin storage itself." >&2
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if (( GROK )); then
  command -v grok >/dev/null 2>&1 || { echo "error: the Grok Build CLI (grok) is not on PATH. Install it first: curl -fsSL https://x.ai/cli/install.sh | bash" >&2; exit 1; }
else
  command -v claude >/dev/null 2>&1 || { echo "error: the Claude Code CLI (claude) is not on PATH. Install it first: https://docs.claude.com/en/docs/claude-code" >&2; exit 1; }
fi
command -v jq >/dev/null 2>&1 || { echo "error: jq is required (sudo apt install jq / brew install jq)." >&2; exit 1; }

MARKETPLACE="$(jq -r '.name' "$MANIFEST")"
mapfile -t ALL < <(jq -r '.plugins[].name' "$MANIFEST")

if (( LIST )); then
  jq -r '.plugins[] | "\(.name)\t\(.description)"' "$MANIFEST" | column -t -s $'\t'
  exit 0
fi

SELECTED=("${ALL[@]}")
if [[ -n "$ONLY" ]]; then
  IFS=',' read -r -a SELECTED <<< "$ONLY"
  for p in "${SELECTED[@]}"; do
    printf '%s\n' "${ALL[@]}" | grep -qx "$p" || { echo "error: '$p' is not a plugin in this pack (see --list)" >&2; exit 1; }
  done
fi

if (( GROK )); then
  # Grok Build registers a local marketplace under its folder name.
  GROK_MK="$(basename "$REPO_DIR")"
  [[ "$SCOPE" == "user" ]] || echo "note: --scope applies to Claude Code only; Grok Build installs plugins for your user." >&2
  listing="$(grok plugin list --json 2>/dev/null || echo '[]')"
  mine="$(jq -r --arg mk "$GROK_MK" '.[] | select(.marketplace == $mk) | .name' <<<"$listing")"
  # grok plugin uninstall and update take a bare plugin name, so they cannot
  # tell two installed plugins with the same name apart.
  shared() { (( $(jq --arg n "$1" '[.[] | select(.name == $n)] | length' <<<"$listing") > 1 )); }

  if (( UNINSTALL )); then
    if [[ -z "$ONLY" ]]; then
      grok plugin marketplace remove "$GROK_MK" || true
    else
      for p in "${SELECTED[@]}"; do
        grep -qx "$p" <<<"$mine" || continue
        if shared "$p"; then
          echo "note: another installed plugin is also named '$p', so it was left installed; ./setup.sh --grok --uninstall removes the whole pack." >&2
        else
          grok plugin uninstall "$p" --confirm
        fi
      done
    fi
    echo "Removed. Restart Grok Build to unload the plugins."
    exit 0
  fi

  known="$(grok plugin marketplace list 2>/dev/null || true)"
  grep -q "^  $GROK_MK: " <<<"$known" || grok plugin marketplace add "$REPO_DIR"
  for p in "${SELECTED[@]}"; do
    if grep -qx "$p" <<<"$mine" && ! shared "$p"; then
      grok plugin update "$p"
    else
      grok plugin install "$p@$GROK_MK" --trust
    fi
  done

  echo
  echo "Installed ${#SELECTED[@]} plugin(s) into Grok Build from $GROK_MK. Restart Grok Build to load them."
  echo "Tell us what worked and what is missing: https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/issues/new?template=feedback.yml"
  exit 0
fi

if (( UNINSTALL )); then
  installed="$(claude plugin list 2>/dev/null || true)"
  for p in "${SELECTED[@]}"; do
    if grep -q "$p@$MARKETPLACE" <<<"$installed"; then claude plugin uninstall "$p@$MARKETPLACE"; fi
  done
  [[ -z "$ONLY" ]] && claude plugin marketplace remove "$MARKETPLACE" || true
  echo "Removed. Restart Claude Code to unload the plugins."
  exit 0
fi

if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE"; then
  claude plugin marketplace update "$MARKETPLACE"
else
  claude plugin marketplace add "$REPO_DIR"
fi

for p in "${SELECTED[@]}"; do
  claude plugin install "$p@$MARKETPLACE" --scope "$SCOPE"
done

echo
echo "Installed ${#SELECTED[@]} plugin(s) from $MARKETPLACE. Restart Claude Code to load them."
echo "Tell us what worked and what is missing: https://github.com/HermeticOrmus/LibreFinTech-Claude-Code/issues/new?template=feedback.yml"
