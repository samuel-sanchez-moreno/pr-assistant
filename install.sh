#!/usr/bin/env bash
# install.sh — set up pr-assistant on a new macOS machine
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHD_DIR="$REPO_DIR/launchd"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# ── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RESET='\033[0m'
info()  { echo -e "${GREEN}[install]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[warn]${RESET}   $*"; }
error() { echo -e "${RED}[error]${RESET}  $*"; }

# ── 1. Check required tools ──────────────────────────────────────────────────
MISSING=()
for tool in jq terminal-notifier; do
  if ! command -v "$tool" &>/dev/null; then
    MISSING+=("$tool")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "The following required tools are missing:"
  for t in "${MISSING[@]}"; do
    echo "  - $t  →  brew install $t"
  done
  exit 1
fi
info "Required tools OK (jq, terminal-notifier)"

# ── 2. Check bkt ─────────────────────────────────────────────────────────────
if ! command -v bkt &>/dev/null; then
  warn "bkt not found on PATH."
  warn "Install it from the Dynatrace internal Homebrew tap and authenticate:"
  warn "  bkt auth login --context spine-dc"
  warn "pr-assistant will fail at runtime without bkt. Continuing setup..."
else
  info "bkt found: $(command -v bkt)"
fi

# ── 3. Detect opencode binary ─────────────────────────────────────────────────
OPENCODE_BIN="${OPENCODE_BIN:-}"
if [[ -z "$OPENCODE_BIN" ]]; then
  OPENCODE_BIN="$(command -v opencode 2>/dev/null || echo '/opt/homebrew/bin/opencode')"
fi
if [[ ! -x "$OPENCODE_BIN" ]]; then
  warn "opencode not found at '$OPENCODE_BIN'."
  warn "Install it (e.g. brew install opencode) for AI-assisted analysis."
  warn "A static fallback will be used until opencode is available."
else
  info "opencode found: $OPENCODE_BIN"
fi

# ── 4. Workspace directory ────────────────────────────────────────────────────
DEFAULT_WORKSPACE="$HOME/workspace"
if [[ -t 0 ]]; then
  read -r -p "Workspace directory [$DEFAULT_WORKSPACE]: " WORKSPACE_DIR
  WORKSPACE_DIR="${WORKSPACE_DIR:-$DEFAULT_WORKSPACE}"
else
  WORKSPACE_DIR="$DEFAULT_WORKSPACE"
fi
info "Workspace directory: $WORKSPACE_DIR"

# ── 5. Generate plists from templates ─────────────────────────────────────────
mkdir -p "$LAUNCH_AGENTS_DIR"

generate_plist() {
  local template="$1"
  local out="$2"
  sed \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__REPO_DIR__|$REPO_DIR|g" \
    -e "s|__WORKSPACE_DIR__|$WORKSPACE_DIR|g" \
    -e "s|__OPENCODE_BIN__|$OPENCODE_BIN|g" \
    "$template" > "$out"
  info "Generated: $out"
}

generate_plist \
  "$LAUNCHD_DIR/com.samuel.pr-assistant.plist.template" \
  "$LAUNCHD_DIR/com.samuel.pr-assistant.plist"

generate_plist \
  "$LAUNCHD_DIR/com.samuel.opencode-serve.plist.template" \
  "$LAUNCHD_DIR/com.samuel.opencode-serve.plist"

# ── 6. Unload existing agents (idempotent) ─────────────────────────────────────
# Always attempt unload (guarded with || true). `launchctl list <label>` is unreliable
# across macOS versions, so unconditional unload is the safe pattern.
for label in com.samuel.pr-assistant com.samuel.opencode-serve; do
  launchctl unload "$LAUNCH_AGENTS_DIR/$label.plist" 2>/dev/null || true
  info "Unloaded agent (if it was loaded): $label"
done

# ── 7. Symlink plists ──────────────────────────────────────────────────────────
ln -sf "$LAUNCHD_DIR/com.samuel.pr-assistant.plist" \
       "$LAUNCH_AGENTS_DIR/com.samuel.pr-assistant.plist"
ln -sf "$LAUNCHD_DIR/com.samuel.opencode-serve.plist" \
       "$LAUNCH_AGENTS_DIR/com.samuel.opencode-serve.plist"
info "Symlinked plists to $LAUNCH_AGENTS_DIR"

# ── 8. Load agents ──────────────────────────────────────────────────────────────
launchctl load "$LAUNCH_AGENTS_DIR/com.samuel.pr-assistant.plist"
launchctl load "$LAUNCH_AGENTS_DIR/com.samuel.opencode-serve.plist"
info "LaunchAgents loaded"

# ── 9. Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  pr-assistant installed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Verify:"
echo "  launchctl list | grep samuel"
echo "  curl http://localhost:4096/global/health"
echo "  tail -f ~/Library/Logs/pr-assistant.log"
echo ""
echo "Manual trigger:"
echo "  launchctl start com.samuel.pr-assistant"
echo ""
echo "Uninstall:"
echo "  launchctl unload ~/Library/LaunchAgents/com.samuel.pr-assistant.plist"
echo "  launchctl unload ~/Library/LaunchAgents/com.samuel.opencode-serve.plist"
