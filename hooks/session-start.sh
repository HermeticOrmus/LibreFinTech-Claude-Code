#!/bin/bash
# Session Start Hook - FinTech
# Detects project context and configures the session

LOG_DIR="$(dirname "$0")/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "[$(date +%H:%M:%S)] $1" >> "$LOG_FILE"
}

log "Session started"
log "Working directory: $(pwd)"

# Detect FinTech context
detect_context() {
  local indicators=0
  
  
  [ -d "src/ledger/" ] && indicators=$((indicators + 1))
  [ -d "src/payments/" ] && indicators=$((indicators + 1))
  grep -rq "stripe\|plaid\|banking" package.json 2>/dev/null && indicators=$((indicators + 1))
  [ -d "compliance/" ] && indicators=$((indicators + 1))

  
  echo "$indicators"
}

CONTEXT_SCORE=$(detect_context)
log "Context score: $CONTEXT_SCORE"

if [ "$CONTEXT_SCORE" -gt 0 ]; then
  log "FinTech project detected"
  echo "[FinTech] Project context detected. Relevant plugins activated."
else
  log "No FinTech context found"
fi

# Check for project-specific configuration
if [ -f "CLAUDE.md" ]; then
  log "Found project CLAUDE.md"
fi

if [ -f ".claude/settings.json" ]; then
  log "Found Claude settings"
fi

log "Session start hook complete"
