#!/usr/bin/env bash
# Post-Tool-Use Hook - FinTech (libre-fintech-hooks)
# Verifies results after file writes and edits.
#
# Claude Code sends the hook input as JSON on stdin; this reads "tool_name",
# "tool_input.file_path", and "session_id".
#
# - Warns Claude when a file is empty after a write.
# - After the first code change in a session, reminds Claude to run the
#   tests. The once-per-session marker lives in the system temp directory,
#   never inside the plugin.
# Prints nothing in every other case.

# No set -e on purpose: a hook that exits 2 blocks the tool call, so every
# path here ends in exit 0. Written for bash 3.2 (macOS) and later.

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null)"
session="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)"

case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac
[ -n "$path" ] || exit 0

notes=()

# Check the file was actually written
if [ -f "$path" ] && [ ! -s "$path" ]; then
  notes+=("WARNING: file appears empty after $tool: $path")
fi

# Remind about testing after the first code change of the session
if grep -qiE '\.(js|jsx|ts|tsx|py|go|rs|java|kt|rb|sql)$' <<<"$path" && [ -n "$session" ]; then
  marker_dir="${TMPDIR:-/tmp}/libre-fintech-hooks"
  marker="$marker_dir/${session//[^A-Za-z0-9_-]/}"
  if [ ! -e "$marker" ]; then
    mkdir -p "$marker_dir" 2>/dev/null && : > "$marker" 2>/dev/null
    notes+=("REMINDER: code that may move or record money changed. Run the tests (including idempotency, rounding, and balance invariant cases) before calling the change done.")
  fi
fi

[ "${#notes[@]}" -eq 0 ] && exit 0

msg="$(printf '%s\n' "${notes[@]}")"
jq -cn --arg ctx "${msg%$'\n'}" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
