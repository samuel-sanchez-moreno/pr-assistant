# Easy Setup on New macOS — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make it frictionless for a fellow Dynatrace/SPINE engineer to adopt pr-assistant on a new macOS machine, ideally by running a single `install.sh`.

**Architecture:** Replace all hard-coded user paths in scripts with `$HOME`-relative variables; introduce `.plist.template` files that use `__HOME__` and `__WORKSPACE_DIR__` placeholders; write `install.sh` that resolves values, substitutes placeholders into generated `.plist` copies, symlinks them, and loads both agents. Improve README with `bkt` and `opencode` config guidance.

**Tech Stack:** bash, sed, launchctl, Homebrew

---

## Chunk 1: Fix hard-coded paths in scripts

### Task 1: Replace `WORKSPACE_DIR` hard-code in `pr-review-login-check.sh`

**Files:**
- Modify: `scripts/pr-review-login-check.sh:7`

- [ ] **Step 1: Replace hard-coded path with `$HOME`-relative default**

Change line 7 from:
```bash
WORKSPACE_DIR="/Users/samuel.sanchez-moreno/workspace"
```
to:
```bash
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspace}"
```

This makes the variable overridable via environment (useful for `install.sh` and launchd `EnvironmentVariables`) while defaulting to `$HOME/workspace`.

- [ ] **Step 2: Verify the file looks correct**

Read `scripts/pr-review-login-check.sh` and confirm line 7 is correct and no other hard-coded paths remain.

- [ ] **Step 3: Commit**

```bash
git add scripts/pr-review-login-check.sh
git commit -m "fix: replace hard-coded WORKSPACE_DIR with \$HOME-relative default in entrypoint

Refs: NOISSUE"
```

---

### Task 2: Replace `WORKSPACE_DIR` hard-code in `pr-assistant-state.sh`

**Files:**
- Modify: `scripts/lib/pr-assistant-state.sh:4`

- [ ] **Step 1: Replace hard-coded path with `$HOME`-relative default**

Change line 4 from:
```bash
WORKSPACE_DIR="/Users/samuel.sanchez-moreno/workspace"
```
to:
```bash
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspace}"
```

- [ ] **Step 2: Verify**

Read `scripts/lib/pr-assistant-state.sh` and confirm line 4 is correct and no other hard-coded paths remain.

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/pr-assistant-state.sh
git commit -m "fix: replace hard-coded WORKSPACE_DIR with \$HOME-relative default in state lib

Refs: NOISSUE"
```

---

## Chunk 2: Convert `.plist` files to templates

launchd requires absolute paths in `ProgramArguments` and log path keys — it does **not** expand `$HOME` or environment variables. The solution is to keep the originals as `.plist.template` files with `__HOME__` and `__WORKSPACE_DIR__` placeholders, and have `install.sh` generate the real `.plist` files from them.

### Task 3: Convert `com.samuel.pr-assistant.plist` to a template

**Files:**
- Rename/modify: `launchd/com.samuel.pr-assistant.plist` → `launchd/com.samuel.pr-assistant.plist.template`

- [ ] **Step 1: Replace all hard-coded user paths with placeholders**

The template content should replace every occurrence of `/Users/samuel.sanchez-moreno` with `__HOME__` and every occurrence of `/Users/samuel.sanchez-moreno/workspace/pr-assistant` with `__REPO_DIR__`. Result:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.samuel.pr-assistant</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>__REPO_DIR__/scripts/pr-review-login-check.sh</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StartCalendarInterval</key>
  <array>
    <dict>
      <key>Hour</key>
      <integer>8</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
    <dict>
      <key>Hour</key>
      <integer>13</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
    <dict>
      <key>Hour</key>
      <integer>16</integer>
      <key>Minute</key>
      <integer>0</integer>
    </dict>
  </array>

  <key>StandardOutPath</key>
  <string>__HOME__/Library/Logs/pr-assistant.log</string>

  <key>StandardErrorPath</key>
  <string>__HOME__/Library/Logs/pr-assistant.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>__HOME__</string>
    <key>WORKSPACE_DIR</key>
    <string>__WORKSPACE_DIR__</string>
  </dict>
</dict>
</plist>
```

Note: `WORKSPACE_DIR` is now passed explicitly via `EnvironmentVariables` so the scripts pick it up via the `${WORKSPACE_DIR:-...}` default.

- [ ] **Step 2: Write the template file**

Write the content above to `launchd/com.samuel.pr-assistant.plist.template`.

- [ ] **Step 3: Remove (git rm) the old `.plist` file**

```bash
git rm launchd/com.samuel.pr-assistant.plist
```

The `.plist` files (generated by `install.sh`) should be gitignored. We will add them to `.gitignore` in Task 5.

- [ ] **Step 4: Commit**

```bash
git add launchd/com.samuel.pr-assistant.plist.template
git commit -m "feat: convert pr-assistant plist to parameterised template

Refs: NOISSUE"
```

---

### Task 4: Convert `com.samuel.opencode-serve.plist` to a template

**Files:**
- Rename/modify: `launchd/com.samuel.opencode-serve.plist` → `launchd/com.samuel.opencode-serve.plist.template`

- [ ] **Step 1: Write template with placeholders**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.samuel.opencode-serve</string>

  <key>ProgramArguments</key>
  <array>
    <string>__OPENCODE_BIN__</string>
    <string>serve</string>
    <string>--port</string>
    <string>4096</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>__HOME__/Library/Logs/opencode-serve.log</string>

  <key>StandardErrorPath</key>
  <string>__HOME__/Library/Logs/opencode-serve.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>__HOME__</string>
  </dict>
</dict>
</plist>
```

Note: `__OPENCODE_BIN__` will be resolved by `install.sh` via `command -v opencode`.

- [ ] **Step 2: Write the template file**

Write the content above to `launchd/com.samuel.opencode-serve.plist.template`.

- [ ] **Step 3: Remove (git rm) the old `.plist` file**

```bash
git rm launchd/com.samuel.opencode-serve.plist
```

- [ ] **Step 4: Commit**

```bash
git add launchd/com.samuel.opencode-serve.plist.template
git commit -m "feat: convert opencode-serve plist to parameterised template

Refs: NOISSUE"
```

---

### Task 5: Gitignore generated `.plist` files

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add generated plist pattern to `.gitignore`**

Open `.gitignore` and add at the bottom:

```
# Generated by install.sh — not committed; contain absolute paths
launchd/*.plist
```

- [ ] **Step 2: Verify**

Read `.gitignore` and confirm the line is present.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore generated launchd plists

Refs: NOISSUE"
```

---

## Chunk 3: Write `install.sh`

### Task 6: Write `install.sh`

**Files:**
- Create: `install.sh` (repo root)

`install.sh` must:
1. Check for required tools (`jq`, `terminal-notifier`); print clear error + `brew install` hint for each missing one.
2. Check for `bkt` and warn (with auth instructions) if absent — do not abort, since some users may set it up later.
3. Detect `opencode` binary path (default `/opt/homebrew/bin/opencode`); warn if not found.
4. Ask the user for the workspace directory (default `$HOME/workspace`), reading from stdin.
5. Substitute `__HOME__`, `__REPO_DIR__`, `__WORKSPACE_DIR__`, and `__OPENCODE_BIN__` in each template to produce the real `.plist` files in `launchd/`.
6. Unload any already-loaded agent (so reload is idempotent).
7. Symlink both plists to `~/Library/LaunchAgents/` (using `-sf` so re-running is safe).
8. Load both agents with `launchctl load`.
9. Print a verification summary with the commands the user can run.

- [ ] **Step 1: Write `install.sh`**

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x install.sh
```

- [ ] **Step 3: Verify the script can be parsed by bash (dry syntax check)**

```bash
bash -n install.sh
```
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh for one-command setup on new macOS machine

Refs: NOISSUE"
```

---

## Chunk 4: Update README

### Task 7: Update README with install.sh, bkt auth, and opencode config sections

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the Installation section**

Replace the current "Installation" section (lines 29-69) with a new one that:
- Leads with `./install.sh` as the single install command
- Keeps the manual steps as a "Manual installation" subsection for reference
- Adds a "Prerequisites — getting bkt" subsection explaining how to install and authenticate `bkt`
- Adds an "opencode configuration" note pointing users to configure API keys

The new "Installation" section:

```markdown
## Installation

### 1. Clone

```bash
git clone https://github.com/samuel-sanchez-moreno/pr-assistant ~/workspace/pr-assistant
```

### 2. Run the installer

```bash
cd ~/workspace/pr-assistant
./install.sh
```

`install.sh` checks for `jq` and `terminal-notifier` (installs hints provided if missing), detects your `opencode` binary, asks for your workspace directory (default `~/workspace`), generates the launchd plists from templates, symlinks them to `~/Library/LaunchAgents/`, and loads both agents.

### 3. Verify

```bash
# Check agents are running
launchctl list | grep samuel

# Check opencode serve is healthy
curl http://localhost:4096/global/health

# Check pr-assistant log
tail -f ~/Library/Logs/pr-assistant.log
```

### 4. Manual trigger

```bash
launchctl start com.samuel.pr-assistant
```

<details>
<summary>Manual installation (without install.sh)</summary>

```bash
# PR assistant (runs at 08:00, 13:00, 16:00 and at login)
ln -sf ~/workspace/pr-assistant/launchd/com.samuel.pr-assistant.plist \
       ~/Library/LaunchAgents/com.samuel.pr-assistant.plist
launchctl load ~/Library/LaunchAgents/com.samuel.pr-assistant.plist

# opencode serve daemon (persistent backend on port 4096)
ln -sf ~/workspace/pr-assistant/launchd/com.samuel.opencode-serve.plist \
       ~/Library/LaunchAgents/com.samuel.opencode-serve.plist
launchctl load ~/Library/LaunchAgents/com.samuel.opencode-serve.plist
```

Note: the `.plist` files must be generated first by running `install.sh`, or by manually copying the `.plist.template` files and replacing `__HOME__`, `__REPO_DIR__`, `__WORKSPACE_DIR__`, and `__OPENCODE_BIN__` with the correct absolute paths.

</details>

## Getting bkt

`bkt` is the internal Dynatrace Bitbucket CLI. Install it from the internal Homebrew tap (available on the Dynatrace developer portal / DT Homebrew tap) then authenticate:

```bash
bkt auth login --context spine-dc
```

Verify:
```bash
bkt auth status
bkt pr list --mine --state OPEN
```

## opencode configuration

`opencode` is used for AI-assisted comment analysis. After installing it, ensure you have at least one model provider configured (API key in `~/.config/opencode/config.json` or via environment variable). The `opencode serve` daemon will fail to start without a valid provider.

See the [opencode documentation](https://opencode.ai/docs) for configuration details.
```

- [ ] **Step 2: Verify README renders correctly**

Read `README.md` and confirm the new sections are present and the document structure is coherent.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README with install.sh quickstart, bkt auth, and opencode config

Refs: NOISSUE"
```

---

## Chunk 5: Smoke-test `install.sh` manually

### Task 8: Dry-run verification

This is a manual verification task — not automated. The goal is to confirm `install.sh` works end-to-end without breaking the existing setup.

- [ ] **Step 1: Run `install.sh` from the repo root in a terminal**

```bash
cd ~/workspace/pr-assistant
./install.sh
```

Expected: all green `[install]` lines, no `[error]` lines. The workspace dir prompt should default to `~/workspace`.

- [ ] **Step 2: Verify generated plists contain correct absolute paths**

Check that `__HOME__`, `__REPO_DIR__`, etc. have been substituted:
```bash
grep -q "__" launchd/com.samuel.pr-assistant.plist && echo "FAIL: placeholders remain" || echo "OK: no placeholders"
grep -q "__" launchd/com.samuel.opencode-serve.plist && echo "FAIL: placeholders remain" || echo "OK: no placeholders"
```
Expected: both print `OK: no placeholders`.

- [ ] **Step 3: Verify both agents are loaded**

```bash
launchctl list | grep samuel
```
Expected: two entries — `com.samuel.pr-assistant` and `com.samuel.opencode-serve`.

- [ ] **Step 4: Verify opencode serve is healthy**

```bash
curl -s http://localhost:4096/global/health
```
Expected: HTTP 200 or a JSON health response.

- [ ] **Step 5: Run `install.sh` a second time (idempotency check)**

```bash
./install.sh
```
Expected: completes without error — agents are unloaded and reloaded cleanly.
