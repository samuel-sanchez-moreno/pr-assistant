# pr-assistant

A macOS login-time automation that monitors your open Bitbucket pull requests, detects newly unresolved review comments, invokes an AI agent to produce structured recommendation markdown, and sends a macOS notification — only when there is something new to act on.

## How it works

1. A **launchd LaunchAgent** fires once at macOS login.
2. The entrypoint script fetches your open PRs from Bitbucket via a PII-sanitizing wrapper (`bkt-sanitize`).
3. For each open PR whose repository exists locally under `~/workspace/<repo>/`:
   - Unresolved comments are fetched and compared against the last stored state.
   - If nothing changed, the PR is skipped silently.
   - If new or updated comments are found, `opencode run` is invoked to generate a deep analysis (with a deterministic fallback if `opencode` is unavailable).
4. The analysis is written to `~/workspace/<repo>/.prs/<pr-id>.md`.
5. A macOS notification is sent for each PR with new recommendations. If all PRs are up to date, a single "all clear" notification is sent instead.

## Prerequisites

| Tool | Purpose |
|------|---------|
| [`bkt`](https://bitbucket.lab.dynatrace.org) | Bitbucket CLI (authenticated against `bitbucket.lab.dynatrace.org`, context `spine-dc`) |
| `jq` | JSON processing (1.7+) |
| `terminal-notifier` | macOS notifications (`/opt/homebrew/bin/terminal-notifier`) |
| `opencode` | AI agent for comment analysis (`/opt/homebrew/bin/opencode`, optional — fallback available) |
| vendored `bkt-sanitize` | PII-stripping wrapper (bundled at `scripts/vendor/dt-bitbucket/bkt-sanitize`) |

## Installation

### 1. Clone

```bash
git clone https://github.com/samuel-sanchez-moreno/pr-assistant ~/workspace/pr-assistant
```

### 2. Install the launchd agent

```bash
cp ~/workspace/pr-assistant/launchd/com.samuel.pr-assistant.plist \
   ~/Library/LaunchAgents/com.samuel.pr-assistant.plist

launchctl load ~/Library/LaunchAgents/com.samuel.pr-assistant.plist
```

The agent runs once at login. To trigger it manually:

```bash
launchctl start com.samuel.pr-assistant
```

### 3. Verify prerequisites

```bash
~/workspace/pr-assistant/scripts/pr-review-login-check.sh
```

Check the log for errors:

```bash
tail -f ~/Library/Logs/pr-assistant.log
```

## Repository layout

```
pr-assistant/
├── scripts/
│   ├── pr-review-login-check.sh      # entrypoint — sourced by launchd
│   └── lib/
│       ├── pr-assistant-bitbucket.sh  # Bitbucket fetch helpers
│       ├── pr-assistant-state.sh      # state read + delta computation
│       ├── pr-assistant-analysis.sh   # prompt assembly + opencode invocation
│       ├── pr-assistant-render.sh     # markdown render + write
│       └── pr-assistant-notify.sh     # terminal-notifier wrappers
├── prompts/
│   ├── analyze-comments.md            # base analysis prompt
│   ├── lens-licoco.md                 # enrichment for LiCoCo repos
│   └── lens-debugging.md              # escalation for bug/failure comments
├── launchd/
│   └── com.samuel.pr-assistant.plist  # LaunchAgent definition
└── scripts/vendor/
    ├── dt-bitbucket/bkt-sanitize      # PII-filtering bkt wrapper
    └── dt-pii-sanitize/pii-sanitize   # sanitization engine
```

## Output format

For each changed PR, analysis is written to `~/workspace/<repo>/.prs/<pr-id>.md`:

```
## Comment <id>
### Summary
### Reviewer Intent
### Technical Assessment
### Approach 1: Comply
### Approach 2: Middle Point
### Approach 3: Alternative
### Recommendation
### Proposed Code Change
### Verification Notes
```

The file also contains a `<!-- machine-readable block -->` section with a JSON array of tracked comment IDs and timestamps, used for delta detection on the next run.

## Analysis lenses

| Lens | When applied |
|------|-------------|
| `analyze-comments.md` | Always — reviewer intent, technical validity, three-approach framework |
| `lens-licoco.md` | Repos: `entitlement-service`, `lima-bas-adapter`, `lima-tenant-config`, `bas` |
| `lens-debugging.md` | Comment text matches: `bug`, `fail`, `broken`, `regression`, `throws`, `exception`, `npe`, `error`, `crash` |

## Configuration

| Environment variable | Default | Purpose |
|---------------------|---------|---------|
| `OPENCODE_BIN` | `/opt/homebrew/bin/opencode` | Override opencode binary path |
| `OPENCODE_ATTACH_URL` | `http://localhost:4096` | Attach to a running opencode TUI session |
| `BKT_SANITIZE_FIELDS` | bundled `pii-fields.json` | Override PII field definitions |
| `BKT_SANITIZE_STRICT` | `0` | Set to `1` to block output if residual PII is detected |

## Privacy

All Bitbucket data is routed through `bkt-sanitize`, which strips author, reviewer, and user identity fields before any data reaches the analysis layer or is written to disk.

## Logs

```
~/Library/Logs/pr-assistant.log
```
