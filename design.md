# PR Assistant Design

## Goal

Create a macOS login-time automation that checks your open Bitbucket PRs, detects newly
unresolved comments, invokes an AI agent to generate actionable recommendation markdown per
PR, and notifies you only when there is something new to review.

## Chosen Decisions

- Trigger: `launchd` at macOS user login
- Repo scope:
  - discover your open PRs from Bitbucket
  - only process them if the repo exists locally at `workspace/<repository-name>`
- Analysis mode:
  - deterministic shell script for PR discovery, comment diffing, file updates, notifications
  - agent-driven reasoning (via `opencode run`) only when there are new unresolved comments
  - deterministic template fallback when `opencode` is unavailable
- Notification mode: one notification per changed PR
- Notification action: button `Open review`
- PR markdown evolution: stable per-comment sections, updated in place
- Project location: standalone repo at `workspace/pr-assistant/` (not part of dotfiles)

## Architecture

1. A `launchd` LaunchAgent runs once when you log in.
2. It starts a local orchestration script from `pr-assistant/scripts/`.
3. The script verifies required tools:
   - `bkt`
   - `jq`
   - `terminal-notifier`
   - vendored `bkt-sanitize` wrapper and sanitization engine
4. The script retrieves your open PRs from Bitbucket using sanitized JSON output.
5. For each open PR:
   - resolve the repository slug
   - map it to `workspace/<repository-name>`
   - skip if the local repo folder does not exist
6. For each matching PR:
   - fetch unresolved comments/tasks
   - compare them with the existing state in `workspace/<repository-name>/.prs/<pr-number>.md`
   - if there are no new unresolved comments, do nothing
   - if there are new unresolved comments:
     a. build a prompt from template files (base + conditional lenses)
     b. invoke `opencode run` to generate deep analysis
     c. write the agent's output into the per-PR markdown
     d. send a macOS notification
7. After the run:
   - if at least one PR had new recommendations, one notification per changed PR was sent
   - if none had new comments, send one notification: `Pull Requests all up to date`

## Agent-Assisted Analysis

When new unresolved comments are detected, the system invokes `opencode run` to perform
deep analysis rather than generating static templates.

### Prompt Assembly

The `build_agent_prompt` function in `pr-assistant-analysis.sh`:

1. Reads the base prompt from `pr-assistant/prompts/analyze-comments.md`
2. Substitutes `{{variables}}` with actual values:
   - `{{REPO}}`, `{{PR_ID}}`, `{{PR_TITLE}}`, `{{SOURCE_BRANCH}}`, `{{DEST_BRANCH}}`
   - `{{COMMENT_ID}}`, `{{COMMENT_TEXT}}`, `{{COMMENT_ANCHOR}}`
   - `{{ALL_COMMENTS_JSON}}` (for full PR context)
3. Conditionally appends `prompts/lens-licoco.md` for LiCoCo repos:
   - `entitlement-service`, `lima-bas-adapter`, `lima-tenant-config`, `bas`
4. Conditionally appends `prompts/lens-debugging.md` when comment text matches
   bug/failure heuristics (`bug|fail|broken|regression|throws|exception|npe|error|crash`)

### Agent Invocation

The assembled prompt is piped to `opencode run`:

```bash
# Try reusing running TUI server first
echo "$prompt" | opencode run --attach http://localhost:4096 --dir "$repo_path"

# If attach fails, fall back to standalone execution
echo "$prompt" | opencode run --dir "$repo_path"
```

### Fallback Behavior

If `opencode` is not installed or both invocation methods fail, the system falls back to
a deterministic template renderer that produces a simpler but still structured analysis
using the three-approach framework (Comply / Middle Point / Reasoned Alternative).

## Prompt Files

Three prompt templates live in `pr-assistant/prompts/`:

| File | Role |
|------|------|
| `analyze-comments.md` | Base prompt: context injection, three-approach framework, verification checklist. Distilled from `receiving-code-review` skill. |
| `lens-licoco.md` | LiCoCo enrichment: correctness, security, performance, simplicity lenses. Distilled from `lima-pr-reviewer` and `socratic-reviewer-checklist`. |
| `lens-debugging.md` | Bug/failure escalation: root cause tracing before proposing fixes. Distilled from `systematic-debugging` skill. |

These are **static prompt files** — no runtime skill dependencies. The lenses are distilled
from skill reference material into portable, self-contained prompt text.

## Bitbucket Access

Use `dt-bitbucket` conventions strictly:

- never use raw `bkt` output for PR/comment data
- always go through `bkt-sanitize`
- always request `--json`
- always reduce fields with `jq`
- never expose author/reviewer/user identity fields to the analysis layer

## Recommendation Engine

When a new unresolved comment is found, the agent prompt uses these lenses:

1. `receiving-code-review` (always applied via base prompt)
   - understand reviewer intent
   - verify whether the comment is technically correct in this codebase
   - avoid blind agreement
   - allow reasoned alternatives

2. `lima-pr-reviewer` (applied only for LiCoCo repos)
   - apply only for:
     - `entitlement-service`
     - `lima-bas-adapter`
     - `lima-tenant-config`
     - `bas`
   - enrich the result with correctness, security, performance, and simplicity concerns

3. `systematic-debugging` (applied only when comment matches bug/failure heuristics)
   - reproduce the issue before choosing an approach
   - trace root cause before proposing fixes

## Per-Comment Output Model

For each unresolved comment, the markdown contains:

- Comment summary
- Reviewer intent
- Technical validity in the current codebase
- Approach 1: fully comply with the comment
- Approach 2: middle point between the PR solution and the comment proposal
- Approach 3: reasoned alternative or pushback
- Why each approach might be appropriate
- Recommended approach
- Proposed code-change direction
- Risks and verification notes

## Markdown Location

Per PR:

```
workspace/<repository-name>/.prs/<pr-number>.md
```

## Markdown Structure

```md
# PR Review Notes: <repo> PR <number>

## PR Metadata
- Repo: <repo>
- PR: <number>
- Title: <title>
- Source: <branch>
- Target: <branch>
- Last checked: <timestamp>

## Tracked Comments
<!-- machine-readable block -->
[
  {
    "id": "...",
    "state": "UNRESOLVED",
    "updated_on": "..."
  }
]

## Comment <id>
### Summary
...

### Reviewer Intent
...

### Technical Assessment
...

### Approach 1: Comply
...

### Approach 2: Middle Point
...

### Approach 3: Alternative
...

### Recommendation
...

### Proposed Code Change
...

### Verification Notes
...
```

## Comment Identity and Diffing

To decide whether a comment is new:

- track comment id
- track unresolved state
- track last updated timestamp

A PR is considered changed if:

- a new unresolved comment id appears
- an existing unresolved comment has a newer update timestamp
- a previously resolved comment becomes unresolved again

A PR is considered unchanged if:

- all current unresolved comments already exist in the tracked block
- none of them changed since the last stored version

If unchanged:

- do not rewrite the file
- do not notify

## Notification Behavior

For a changed PR:

- title: `PR Review Assistant`
- message: `There are PR comments`
- action button: `Open review`
- action target: the exact `.md` file for that PR

For a fully clean run:

- title: `PR Review Assistant`
- message: `Pull Requests all up to date`

## Storage and Ownership

Machine-managed artifacts:

- scripts and lib in `pr-assistant/scripts/`
- LaunchAgent plist in `pr-assistant/launchd/`
- prompt templates in `pr-assistant/prompts/`
- vendored sanitizer in `pr-assistant/scripts/vendor/`

Repo-managed generated artifacts:

- `workspace/<repository-name>/.prs/<pr-number>.md`

## Why Vendor the Sanitizer

The current `bkt-sanitize` wrapper exists inside `rnd-ai-knowledgebase`, but depending on
another repo by path is brittle. Vendoring the needed sanitizer pieces into the automation
location makes the login workflow self-contained.

## Error Handling

The login script should fail soft:

- if Bitbucket auth is missing, notify once with a setup/error message
- if a repo is not cloned locally, skip it silently
- if a PR fetch fails, continue with the rest
- if markdown generation fails for one PR, continue with the others
- if `opencode run` fails, fall back to deterministic template
- log all failures to a dedicated file for later debugging

## Logging

Use a predictable log location for `launchd` stdout/stderr and script-level logging so login
failures are diagnosable. Default: `~/Library/Logs/pr-assistant.log`

## Testing Strategy

Before enabling the LaunchAgent:

1. Run the script manually.
2. Test with:
   - no open PRs
   - open PRs with no local repo
   - local repo with no `.prs` file
   - existing `.prs` file with unchanged comments
   - existing `.prs` file with one new unresolved comment
   - multiple changed PRs
3. Verify:
   - markdown format
   - no duplicate comment sections
   - no notifications when unchanged
   - correct notification action opens the right file
   - agent analysis produces meaningful output (not template boilerplate)
   - fallback template works when opencode is unavailable

## Minimal Implementation Shape

- one orchestration script
- one LaunchAgent plist
- one vendored sanitizer bundle
- three prompt templates
- one per-PR markdown file format

No index file, database, daemon loop, or periodic scheduler in v1.
