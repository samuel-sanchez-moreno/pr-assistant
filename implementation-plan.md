# PR Assistant Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents
> available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`)
> syntax for tracking.

**Goal:** Build a macOS login-time PR assistant that checks open Bitbucket PRs, detects new
unresolved comments, invokes an AI agent to write per-PR markdown recommendations, and sends
actionable notifications.

**Architecture:** A standalone `pr-assistant/` repo under `workspace/`. A `launchd` job
invokes a workspace-aware orchestration script. The script uses vendored `dt-bitbucket`
sanitization, compares live unresolved comments with tracked markdown state under each local
repo, and only generates recommendations plus notifications when new unresolved comments are
detected. Analysis is performed by `opencode run` with assembled prompt files; a deterministic
template is used as fallback.

**Tech Stack:** macOS `launchd`, bash, `bkt`, vendored `bkt-sanitize`, `jq`,
`terminal-notifier`, `opencode`, markdown files under local repos

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `pr-assistant/design.md` | Canonical design document |
| `pr-assistant/implementation-plan.md` | This file — canonical execution plan |
| `pr-assistant/.gitignore` | Ignore logs and generated `.prs/` artifacts |
| `pr-assistant/prompts/analyze-comments.md` | Base agent prompt: context injection, three-approach framework |
| `pr-assistant/prompts/lens-licoco.md` | LiCoCo enrichment lens (correctness, security, performance, simplicity) |
| `pr-assistant/prompts/lens-debugging.md` | Bug/failure escalation lens (root cause tracing) |
| `pr-assistant/scripts/pr-review-login-check.sh` | Main orchestration entrypoint executed by `launchd` |
| `pr-assistant/scripts/lib/pr-assistant-bitbucket.sh` | Safe Bitbucket access helpers via vendored sanitizer |
| `pr-assistant/scripts/lib/pr-assistant-state.sh` | Read existing PR markdown state and compute comment deltas |
| `pr-assistant/scripts/lib/pr-assistant-analysis.sh` | Build agent prompt, invoke `opencode run`, fallback renderer |
| `pr-assistant/scripts/lib/pr-assistant-render.sh` | Render full per-PR markdown (calls analysis, writes file) |
| `pr-assistant/scripts/lib/pr-assistant-notify.sh` | Wrap `terminal-notifier` calls |
| `pr-assistant/launchd/com.samuel.pr-assistant.plist` | LaunchAgent that runs once at login |
| `pr-assistant/scripts/vendor/dt-bitbucket/bkt-sanitize` | Vendored sanitizer wrapper |
| `pr-assistant/scripts/vendor/dt-bitbucket/pii-fields.json` | Vendored Bitbucket PII field configuration |
| `pr-assistant/scripts/vendor/dt-pii-sanitize/pii-sanitize` | Vendored sanitize engine |
| `pr-assistant/tests/pr-assistant-smoke.sh` | Manual smoke-test script for local verification |
| `pr-assistant/tests/fixtures/` | Sanitized sample JSON for PRs and unresolved comments |
| `pr-assistant/README.md` | Setup guide, manual run instructions, log location, LaunchAgent steps |

### Generated runtime files

| File | Source |
|------|--------|
| `workspace/<repository-name>/.prs/<pr-number>.md` | Generated per changed PR at login |
| `~/Library/Logs/pr-assistant.log` | Script and launchd execution log |

---

## Chunk 1: Bootstrap The Repository

### Task 1: Seed design docs ✅ DONE

`pr-assistant/design.md` and `pr-assistant/implementation-plan.md` already exist on disk.

### Task 2: Git init and directory scaffold

**Files:**
- Create: `pr-assistant/.gitignore`
- Create directories: `scripts/lib/`, `scripts/vendor/`, `prompts/`, `launchd/`, `tests/`

- [x] **Step 1: Initialize git repository**

  Run: `git init /Users/samuel.sanchez-moreno/workspace/pr-assistant`
  Expected: `Initialized empty Git repository` (or already initialized)

- [x] **Step 2: Create directory structure**

  Run:
  ```bash
  mkdir -p pr-assistant/scripts/lib
  mkdir -p pr-assistant/scripts/vendor
  mkdir -p pr-assistant/prompts
  mkdir -p pr-assistant/launchd
  mkdir -p pr-assistant/tests/fixtures
  ```
  Expected: all directories created

- [x] **Step 3: Write `.gitignore`**

  Contents:
  ```
  # Generated PR review files (live under each workspace repo, not here)
  workspace/

  # macOS
  .DS_Store

  # Logs
  *.log
  ```

- [x] **Step 4: Verify layout**

  Run: `ls -R /Users/samuel.sanchez-moreno/workspace/pr-assistant`
  Expected: all directories visible

---

## Chunk 2: Vendor and Verify Safe Bitbucket Access

### Task 3: Vendor the sanitizer bundle

**Files:**
- Create: `pr-assistant/scripts/vendor/dt-bitbucket/bkt-sanitize`
- Create: `pr-assistant/scripts/vendor/dt-bitbucket/pii-fields.json`
- Create: `pr-assistant/scripts/vendor/dt-pii-sanitize/pii-sanitize`

Source originals are at:
- `rnd-ai-knowledgebase/skills/dt-bitbucket/scripts/bkt-sanitize`
- `rnd-ai-knowledgebase/skills/dt-bitbucket/scripts/pii-fields.json`
- `rnd-ai-knowledgebase/utils/dt-pii-sanitize/pii-sanitize`

- [x] **Step 1: Create the vendor directories**

  Run:
  ```bash
  mkdir -p pr-assistant/scripts/vendor/dt-bitbucket
  mkdir -p pr-assistant/scripts/vendor/dt-pii-sanitize
  ```
  Expected: directories created

- [x] **Step 2: Copy the sanitizer wrapper**

  Run:
  ```bash
  cp rnd-ai-knowledgebase/skills/dt-bitbucket/scripts/bkt-sanitize \
     pr-assistant/scripts/vendor/dt-bitbucket/bkt-sanitize
  ```
  Expected: file copied

- [x] **Step 3: Copy the PII fields config**

  Run:
  ```bash
  cp rnd-ai-knowledgebase/skills/dt-bitbucket/scripts/pii-fields.json \
     pr-assistant/scripts/vendor/dt-bitbucket/pii-fields.json
  ```
  Expected: file copied

- [x] **Step 4: Copy the sanitize engine**

  Run:
  ```bash
  cp rnd-ai-knowledgebase/utils/dt-pii-sanitize/pii-sanitize \
     pr-assistant/scripts/vendor/dt-pii-sanitize/pii-sanitize
  ```
  Expected: file copied

- [x] **Step 5: Update internal relative paths in the vendored wrapper**

  The original `bkt-sanitize` resolves the engine via two relative candidates:
  ```
  "$SCRIPT_DIR/../../utils/dt-pii-sanitize/pii-sanitize"
  "$SCRIPT_DIR/../../../utils/dt-pii-sanitize/pii-sanitize"
  ```
  After vendoring, the engine is at `../dt-pii-sanitize/pii-sanitize` relative to
  `vendor/dt-bitbucket/`. Update the ENGINE resolution candidates in the copy to:
  ```bash
  "$SCRIPT_DIR/../dt-pii-sanitize/pii-sanitize"
  ```
  Verify: read the vendored file after editing and confirm the path is correct.

- [x] **Step 6: Set executable bits**

  Run:
  ```bash
  chmod +x pr-assistant/scripts/vendor/dt-bitbucket/bkt-sanitize
  chmod +x pr-assistant/scripts/vendor/dt-pii-sanitize/pii-sanitize
  ```
  Expected: bits set

- [x] **Step 7: Smoke-test the vendored wrapper**

  Run:
  ```bash
  pr-assistant/scripts/vendor/dt-bitbucket/bkt-sanitize auth status
  ```
  Expected: wrapper starts without engine-not-found error; auth status printed

### Task 4: Implement Bitbucket helper functions

**Files:**
- Create: `pr-assistant/scripts/lib/pr-assistant-bitbucket.sh`

```bash
#!/usr/bin/env bash
# pr-assistant-bitbucket.sh — safe Bitbucket access helpers

VENDOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../vendor" && pwd)"
BKT_SANITIZE="$VENDOR_DIR/dt-bitbucket/bkt-sanitize"

# check_prerequisites — exits non-zero with a message if required tools are missing
check_prerequisites() {
  local missing=()
  command -v bkt              &>/dev/null || missing+=("bkt")
  command -v jq               &>/dev/null || missing+=("jq")
  command -v terminal-notifier &>/dev/null || missing+=("terminal-notifier")
  command -v opencode          &>/dev/null || true  # optional — fallback handles absence
  [[ -x "$BKT_SANITIZE" ]]                || missing+=("bkt-sanitize (vendored)")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "pr-assistant: missing prerequisites: ${missing[*]}" >&2
    return 1
  fi
}

# fetch_my_open_prs — outputs sanitized JSON array of open PRs authored by current user
fetch_my_open_prs() {
  "$BKT_SANITIZE" pr list --mine --state OPEN --json \
    | jq '[.[] | {id, title, state,
                  source: .source.branch.name,
                  destination: .destination.branch.name,
                  repo: .destination.repository.slug,
                  updated_on}]'
}

# fetch_unresolved_comments <repo> <pr_id>
# Outputs sanitized JSON array of unresolved comments for a given PR
fetch_unresolved_comments() {
  local repo="$1"
  local pr_id="$2"
  "$BKT_SANITIZE" api \
    "/rest/api/1.0/projects/SPINE/repos/${repo}/pull-requests/${pr_id}/activities" \
    --json \
    | jq '[.values[]
           | select(.action == "COMMENTED")
           | select(.comment.state == "OPEN")
           | {
               id: .comment.id,
               state: .comment.state,
               updated_on: .comment.updatedDate,
               text: .comment.text,
               anchor: (.commentAnchor // null | {path, line, lineType} // null)
             }]'
}
```

- [x] **Step 1: Create `pr-assistant/scripts/lib/` directory**

  Run: `mkdir -p pr-assistant/scripts/lib`
  Expected: directory created (may already exist from Task 2)

- [x] **Step 2: Write `pr-assistant-bitbucket.sh`**

- [x] **Step 3: Verify `fetch_my_open_prs` outputs safe fields only**

  Run:
  ```bash
  source pr-assistant/scripts/lib/pr-assistant-bitbucket.sh
  fetch_my_open_prs | jq .
  ```
  Expected: JSON array with id, title, state, source, destination, repo, updated_on — no PII fields

- [x] **Step 4: Verify `fetch_unresolved_comments` for a known PR**

  Run: `fetch_unresolved_comments <repo> <pr_id>` against a live PR
  Expected: JSON array with id, state, updated_on, text, anchor — no author/user fields

---

## Chunk 3: Detect Changed PR Comment State

### Task 5: Implement markdown state reader and delta calculator

**Files:**
- Create: `pr-assistant/scripts/lib/pr-assistant-state.sh`

```bash
#!/usr/bin/env bash
# pr-assistant-state.sh — read existing PR markdown state and compute comment deltas

WORKSPACE_DIR="/Users/samuel.sanchez-moreno/workspace"

# pr_md_path <repo> <pr_id>
# Returns the path to the PR markdown file
pr_md_path() {
  echo "$WORKSPACE_DIR/$1/.prs/$2.md"
}

# read_tracked_comments <md_file>
# Extracts the machine-readable tracked comments JSON block from an existing markdown file.
# Returns empty array if file does not exist or block is absent.
read_tracked_comments() {
  local md_file="$1"
  if [[ ! -f "$md_file" ]]; then
    echo "[]"
    return
  fi
  # Extract JSON between <!-- machine-readable block --> and the next closing ]
  awk '/<!-- machine-readable block -->/{found=1; next} found && /^\[/{capture=1} capture{print} capture && /^\]/{exit}' "$md_file"
}

# compute_delta <stored_json> <live_json>
# Prints "changed" if there are new, updated, or re-opened comments; "unchanged" otherwise.
compute_delta() {
  local stored="$1"
  local live="$2"

  # Build a lookup of stored comment id -> updated_on
  local stored_map
  stored_map=$(echo "$stored" | jq 'map({(.id | tostring): .updated_on}) | add // {}')

  # Check for any live comment that is new or has a newer updated_on
  local has_new
  has_new=$(echo "$live" | jq --argjson stored "$stored_map" '
    map(
      .id as $id |
      .updated_on as $ts |
      ($stored[($id | tostring)] // null) as $prev |
      if $prev == null then true
      elif $prev < $ts then true
      else false
      end
    ) | any
  ')

  if [[ "$has_new" == "true" ]]; then
    echo "changed"
  else
    echo "unchanged"
  fi
}
```

- [x] **Step 1: Write `pr-assistant-state.sh`**

- [x] **Step 2: Test `read_tracked_comments` on a nonexistent file**

  Run:
  ```bash
  source pr-assistant/scripts/lib/pr-assistant-state.sh
  read_tracked_comments "/nonexistent/path.md"
  ```
  Expected: `[]`

- [x] **Step 3: Test `compute_delta` with identical stored and live comments**

  Run:
  ```bash
  stored='[{"id":1,"state":"OPEN","updated_on":"2026-01-01T00:00:00Z"}]'
  live='[{"id":1,"state":"OPEN","updated_on":"2026-01-01T00:00:00Z","text":"fix this"}]'
  compute_delta "$stored" "$live"
  ```
  Expected: `unchanged`

- [x] **Step 4: Test `compute_delta` with a new comment in live**

  Run:
  ```bash
  stored='[{"id":1,"state":"OPEN","updated_on":"2026-01-01T00:00:00Z"}]'
  live='[{"id":1,"state":"OPEN","updated_on":"2026-01-01T00:00:00Z","text":"fix this"},{"id":2,"state":"OPEN","updated_on":"2026-01-02T00:00:00Z","text":"also this"}]'
  compute_delta "$stored" "$live"
  ```
  Expected: `changed`

- [x] **Step 5: Test `compute_delta` with an updated timestamp on an existing comment**

  Run:
  ```bash
  stored='[{"id":1,"state":"OPEN","updated_on":"2026-01-01T00:00:00Z"}]'
  live='[{"id":1,"state":"OPEN","updated_on":"2026-01-02T00:00:00Z","text":"fix this, updated"}]'
  compute_delta "$stored" "$live"
  ```
  Expected: `changed`

---

## Chunk 4: Write Prompt Files

### Task 6: Write the three agent prompt templates

**Files:**
- Create: `pr-assistant/prompts/analyze-comments.md`
- Create: `pr-assistant/prompts/lens-licoco.md`
- Create: `pr-assistant/prompts/lens-debugging.md`

#### `prompts/analyze-comments.md`

```markdown
# PR Comment Analysis

You are analyzing unresolved review comments on a pull request. Your job is to produce
actionable, technically rigorous recommendations — not performative agreement.

## Context

- Repository: {{REPO}}
- PR: {{PR_ID}} — {{PR_TITLE}}
- Branch: {{SOURCE_BRANCH}} → {{DEST_BRANCH}}

## All Unresolved Comments (for context)

```json
{{ALL_COMMENTS_JSON}}
```

## Comment to Analyze

- ID: {{COMMENT_ID}}
- Location: {{COMMENT_ANCHOR}}
- Text: {{COMMENT_TEXT}}

## Instructions

Before proposing any approach, verify:
1. Is the reviewer's observation technically correct in the current codebase?
2. Does the suggestion break existing tests or behavior?
3. Is there a deliberate reason the current implementation was written this way?
4. Does the reviewer have full context, or might they be missing something?

Do NOT blindly agree. Do NOT add performative agreement ("great point", "you're right").
State technical facts. Push back with reasoning when warranted.

## Output Format

Produce the following sections for comment {{COMMENT_ID}}:

### Comment {{COMMENT_ID}}

**Location:** {{COMMENT_ANCHOR}}

### Summary
One or two sentences summarizing what the reviewer is asking.

### Reviewer Intent
What is the reviewer actually trying to achieve? What quality concern are they raising?

### Technical Assessment
Is the reviewer's observation correct in this codebase? Verify before answering.
Note any context the reviewer might be missing. Note any risks in their suggestion.

### Approach 1: Comply
Implement exactly what the reviewer asks, as described.

**When to use:** The reviewer is correct and the suggestion is a clear improvement with no
architectural side-effects.

**Proposed direction:** Specific code change at the anchor location.

### Approach 2: Middle Point
Accept the spirit of the comment but adapt the implementation to the existing codebase
patterns, constraints, or surrounding code.

**When to use:** The reviewer's intent is valid but the literal suggestion does not fit
the current design, naming conventions, or surrounding context.

**Proposed direction:** What change satisfies the concern while preserving existing patterns.

### Approach 3: Reasoned Alternative
Push back with a technical rationale explaining why the current implementation is correct
or preferable, and offer a narrower improvement that addresses the underlying concern.

**When to use:** The reviewer may lack full context, the suggestion introduces a regression,
or there is a deliberate reason the code was written this way.

**Proposed direction:** A targeted improvement or code comment that surfaces the intent,
rather than adopting the suggestion.

### Recommendation
Which approach to use and why — based on the technical assessment above.
If the reviewer is correct, say so plainly. If they are not, say so plainly.

### Verification Notes
- What to run to confirm no regressions after the chosen approach.
- Any edge cases to check.
- Whether to reply in the PR thread and what to say.
```

#### `prompts/lens-licoco.md`

```markdown
## LiCoCo Repository Lens

This is a LiCoCo Team repository. In addition to the base analysis, assess the comment
through these four lenses and add findings to the Technical Assessment and each Approach.

### Correctness
- Does the suggested change preserve idempotency where required (Kafka event handlers)?
- Are transaction boundaries maintained? Multi-step DB writes need a wrapping transaction.
- Are null/blank/missing-timestamp edge cases handled?
- For lima-bas-adapter: there is NO BAS HTTP client. Any reference to a BAS endpoint path
  means a direct DB DAO call — never an HTTP call.

### Security
- Does the change introduce or resolve a SQL injection risk?
  (LBA uses raw SQL via JdbcTemplate/MyBatis — check parameter binding)
- Is sensitive data (PII, credentials) at risk of being logged or exposed?
- Do new endpoints enforce RBAC (role or scope checks), not just authentication?
- Are audit logs produced for sensitive operations (tenant deletion, license changes,
  account status changes, entitlement grants)?

### Performance
- Does the change introduce N+1 query patterns (loops calling DAO per element)?
- Are there unbounded queries (SELECT without LIMIT on large tables)?
- For entitlement-service: ADA API calls cost ~50ms each — flag any call inside a loop.
- Are expensive operations (regex compilation, reflection, JSON serialisation) in hot paths?

### Simplicity (Socratic)
Phrase findings as Socratic questions, not directives:
- Is there unnecessary indirection (wrapper/adapter/interface with one implementation)?
- Is there duplicated logic that could be unified with a shared method or base class?
- Does the test prove real behaviour, or only what the compiler already guarantees?
- Is naming unambiguous in context? (e.g., "Consumer" collides with java.util.function.Consumer)
- Is mutable state scoped as narrowly as possible?
```

#### `prompts/lens-debugging.md`

```markdown
## Debugging Lens

This comment references a bug, failure, regression, or exception. Apply the systematic
debugging protocol before proposing any fix.

### Before Proposing a Fix

1. **Reproduce first.** Do not propose a fix without confirming the issue exists in the
   current codebase. Describe how you would reproduce it.

2. **Trace the root cause.** Where does the bad value or behavior originate?
   Trace backward through the call stack to the actual source — not the symptom.

3. **Check recent changes.** What changed that could have introduced this? Look at git
   history, new dependencies, config changes.

4. **Verify the reviewer's diagnosis.** Is the reviewer's identified root cause correct?
   They may have spotted the symptom but misidentified the cause.

### Output Additions

Add a **Root Cause Analysis** section to your output, before the Approaches:

### Root Cause Analysis
- How to reproduce the issue
- Where in the call stack the failure originates
- Whether the reviewer's diagnosis is correct or incomplete
- What the actual fix target is (may differ from the anchor location)

### Approach Constraints
- Approach 1 (Comply) must fix the root cause, not just mask the symptom.
- Approach 3 (Reasoned Alternative) is only valid if the reviewer's diagnosis is wrong
  AND you can prove the actual root cause is elsewhere.
- Do NOT propose a fix that passes the test but leaves the underlying cause in place.
```

- [x] **Step 1: Write `pr-assistant/prompts/analyze-comments.md`**

- [x] **Step 2: Write `pr-assistant/prompts/lens-licoco.md`**

- [x] **Step 3: Write `pr-assistant/prompts/lens-debugging.md`**

- [x] **Step 4: Verify all three files exist and are non-empty**

  Run: `ls -lh pr-assistant/prompts/`
  Expected: three `.md` files with non-zero size

---

## Chunk 5: Generate Recommendation Content

### Task 7: Implement comment analysis with agent invocation and fallback

**Files:**
- Create: `pr-assistant/scripts/lib/pr-assistant-analysis.sh`

```bash
#!/usr/bin/env bash
# pr-assistant-analysis.sh — build agent prompt, invoke opencode run, fallback renderer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$(cd "$SCRIPT_DIR/../../prompts" && pwd)"
OPENCODE="${OPENCODE_BIN:-/opt/homebrew/bin/opencode}"
OPENCODE_ATTACH_URL="${OPENCODE_ATTACH_URL:-http://localhost:4096}"

# build_agent_prompt <repo> <pr_id> <pr_title> <source_branch> <dest_branch>
#                   <comment_id> <comment_text> <comment_anchor> <all_comments_json>
# Assembles the full prompt by substituting variables into the base template and
# conditionally appending lens files.
build_agent_prompt() {
  local repo="$1"
  local pr_id="$2"
  local pr_title="$3"
  local source_b="$4"
  local dest_b="$5"
  local comment_id="$6"
  local comment_text="$7"
  local comment_anchor="$8"
  local all_comments_json="$9"

  # Read base prompt and substitute variables
  local prompt
  prompt=$(sed \
    -e "s|{{REPO}}|${repo}|g" \
    -e "s|{{PR_ID}}|${pr_id}|g" \
    -e "s|{{PR_TITLE}}|${pr_title}|g" \
    -e "s|{{SOURCE_BRANCH}}|${source_b}|g" \
    -e "s|{{DEST_BRANCH}}|${dest_b}|g" \
    -e "s|{{COMMENT_ID}}|${comment_id}|g" \
    -e "s|{{COMMENT_ANCHOR}}|${comment_anchor}|g" \
    "$PROMPTS_DIR/analyze-comments.md")

  # Substitute multi-line values using python3 (sed can't handle embedded newlines safely)
  prompt=$(python3 -c "
import sys
content = open('/dev/stdin').read()
content = content.replace('{{COMMENT_TEXT}}', sys.argv[1])
content = content.replace('{{ALL_COMMENTS_JSON}}', sys.argv[2])
print(content, end='')
" "$comment_text" "$all_comments_json" <<< "$prompt")

  # Conditionally append LiCoCo lens
  case "$repo" in
    entitlement-service|lima-bas-adapter|lima-tenant-config|bas)
      prompt="${prompt}"$'\n\n'"$(cat "$PROMPTS_DIR/lens-licoco.md")"
      ;;
  esac

  # Conditionally append debugging lens (heuristic on comment text)
  if echo "$comment_text" | grep -qiE 'bug|fail|broken|regression|throws|exception|npe|error|crash'; then
    prompt="${prompt}"$'\n\n'"$(cat "$PROMPTS_DIR/lens-debugging.md")"
  fi

  echo "$prompt"
}

# invoke_agent <prompt> <repo_path>
# Pipes the prompt to opencode run. Tries --attach first, falls back to standalone.
# Returns the agent's stdout output. Returns non-zero if both attempts fail.
invoke_agent() {
  local prompt="$1"
  local repo_path="$2"

  if [[ ! -x "$OPENCODE" ]]; then
    return 1
  fi

  # Try reusing a running TUI server
  if echo "$prompt" | "$OPENCODE" run \
      --attach "$OPENCODE_ATTACH_URL" \
      --dir "$repo_path" 2>/dev/null; then
    return 0
  fi

  # Fall back to standalone execution
  echo "$prompt" | "$OPENCODE" run --dir "$repo_path"
}

# analyze_comment_fallback <repo> <comment_json>
# Deterministic fallback when opencode is unavailable.
# Prints a structured three-approach block for one unresolved comment.
analyze_comment_fallback() {
  local repo="$1"
  local comment_json="$2"

  local id text anchor
  id=$(echo "$comment_json"     | jq -r '.id')
  text=$(echo "$comment_json"   | jq -r '.text')
  anchor=$(echo "$comment_json" | jq -r \
    '.anchor | if . then "File: \(.path // "unknown") line \(.line // "unknown")" else "General comment" end')

  local licoco_note=""
  case "$repo" in
    entitlement-service|lima-bas-adapter|lima-tenant-config|bas)
      licoco_note="
> LiCoCo repo: also assess through correctness, security, performance, and simplicity lenses."
      ;;
  esac

  local debug_note=""
  if echo "$text" | grep -qiE 'bug|fail|broken|regression|throws|exception|npe|error|crash'; then
    debug_note="
> Bug/failure comment: reproduce the issue before choosing an approach."
  fi

  cat <<FALLBACK
### Comment ${id}

**Location:** ${anchor}
${licoco_note}${debug_note}

#### Summary
${text}

#### Reviewer Intent
The reviewer is raising a concern about the code at the location above.
Verify whether the observation is technically correct before proceeding.

#### Technical Assessment
Read the current code at the anchor location and assess whether the reviewer is correct.

#### Approach 1: Comply
Implement exactly what the reviewer asks.
**When to use:** Reviewer is correct and the suggestion is a clear improvement.

#### Approach 2: Middle Point
Accept the spirit of the comment but adapt to the existing codebase patterns.
**When to use:** The intent is valid but the literal suggestion does not fit the current design.

#### Approach 3: Reasoned Alternative
Push back with a technical rationale and offer a narrower improvement.
**When to use:** You have a concrete technical reason and can explain it in the PR thread.

#### Recommendation
Verify the technical assessment above before choosing. Prefer Approach 1 when the reviewer
is correct. Use Approach 3 only when you have a concrete technical reason.

#### Verification Notes
- Run the test suite after any change.
- Confirm the reviewer's concern is resolved (Approaches 1 or 2) or explain your reasoning
  in the PR thread (Approach 3).
FALLBACK
}

# analyze_pr_comments <repo> <pr_id> <pr_title> <source_branch> <dest_branch>
#                     <comments_json> <repo_path>
# For each unresolved comment: attempts agent analysis, falls back to template.
# Prints the full analysis section to stdout.
analyze_pr_comments() {
  local repo="$1"
  local pr_id="$2"
  local pr_title="$3"
  local source_b="$4"
  local dest_b="$5"
  local comments_json="$6"
  local repo_path="$7"

  local count
  count=$(echo "$comments_json" | jq 'length')

  for (( i=0; i<count; i++ )); do
    local comment
    comment=$(echo "$comments_json" | jq ".[$i]")
    local cid ctext canchor
    cid=$(echo "$comment"    | jq -r '.id')
    ctext=$(echo "$comment"  | jq -r '.text')
    canchor=$(echo "$comment" | jq -r \
      '.anchor | if . then "File: \(.path // "unknown") line \(.line // "unknown")" else "General comment" end')

    local prompt
    prompt=$(build_agent_prompt \
      "$repo" "$pr_id" "$pr_title" "$source_b" "$dest_b" \
      "$cid" "$ctext" "$canchor" "$comments_json")

    local analysis
    if analysis=$(invoke_agent "$prompt" "$repo_path" 2>/dev/null); then
      echo "$analysis"
    else
      echo "<!-- opencode unavailable — using fallback template -->"
      analyze_comment_fallback "$repo" "$comment"
    fi
    echo ""
  done
}
```

- [x] **Step 1: Write `pr-assistant-analysis.sh`**

- [x] **Step 2: Verify `build_agent_prompt` substitutes variables correctly**

  Run:
  ```bash
  source pr-assistant/scripts/lib/pr-assistant-analysis.sh
  build_agent_prompt "entitlement-service" "42" "feat: add X" "feature/x" "main" \
    "1" "consider splitting this" "General comment" "[]" | head -30
  ```
  Expected: prompt text with repo/PR metadata substituted; LiCoCo lens appended at end

- [x] **Step 3: Verify debugging lens triggers on a bug-like comment**

  Run:
  ```bash
  build_agent_prompt "some-repo" "1" "fix Y" "fix/y" "main" \
    "2" "this throws an NPE when input is null" "File: Foo.java line 42" "[]" | grep -c "Debugging Lens"
  ```
  Expected: `1`

- [x] **Step 4: Verify fallback produces valid output when opencode is absent**

  Run:
  ```bash
  analyze_comment_fallback "some-repo" '{"id":3,"text":"rename this variable","anchor":null}'
  ```
  Expected: structured markdown with all six subsections (Summary through Verification Notes)

### Task 8: Implement the markdown renderer

**Files:**
- Create: `pr-assistant/scripts/lib/pr-assistant-render.sh`

```bash
#!/usr/bin/env bash
# pr-assistant-render.sh — render per-PR markdown files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pr-assistant-analysis.sh
source "$SCRIPT_DIR/pr-assistant-analysis.sh"
# shellcheck source=pr-assistant-state.sh
source "$SCRIPT_DIR/pr-assistant-state.sh"

# render_pr_md <repo> <pr_id> <pr_title> <source_branch> <dest_branch>
#              <comments_json> <repo_path>
# Renders the full PR markdown file content to stdout.
render_pr_md() {
  local repo="$1"
  local pr_id="$2"
  local title="$3"
  local source_b="$4"
  local dest_b="$5"
  local comments_json="$6"
  local repo_path="$7"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build tracked comments block (id, state, updated_on only)
  local tracked_block
  tracked_block=$(echo "$comments_json" | jq '[.[] | {id, state, updated_on}]')

  cat <<HEADER
# PR Review Notes: ${repo} PR ${pr_id}

## PR Metadata
- Repo: ${repo}
- PR: ${pr_id}
- Title: ${title}
- Source: ${source_b}
- Target: ${dest_b}
- Last checked: ${timestamp}

## Tracked Comments
<!-- machine-readable block -->
${tracked_block}

HEADER

  # Generate analysis (agent or fallback) for all comments
  analyze_pr_comments "$repo" "$pr_id" "$title" "$source_b" "$dest_b" \
    "$comments_json" "$repo_path"
}

# write_pr_md <repo> <pr_id> <pr_title> <source_branch> <dest_branch>
#             <comments_json> <repo_path>
# Writes the rendered markdown to workspace/<repo>/.prs/<pr_id>.md.
# Returns the path to the written file.
write_pr_md() {
  local repo="$1"
  local pr_id="$2"
  local md_path
  md_path=$(pr_md_path "$repo" "$pr_id")
  mkdir -p "$(dirname "$md_path")"
  render_pr_md "$@" > "$md_path"
  echo "$md_path"
}
```

- [x] **Step 1: Write `pr-assistant-render.sh`**

- [x] **Step 2: Verify the rendered file has correct sections**

  Run:
  ```bash
  source pr-assistant/scripts/lib/pr-assistant-render.sh
  render_pr_md "some-repo" "42" "feat: add X" "feature/x" "main" \
    '[{"id":1,"state":"OPEN","updated_on":"2026-01-01T00:00:00Z","text":"rename this","anchor":null}]' \
    "/tmp" | head -20
  ```
  Expected: PR metadata header with tracked-comments block, followed by comment analysis

- [x] **Step 3: Verify `write_pr_md` creates the file at the correct path**

  Run:
  ```bash
  WORKSPACE_DIR="/tmp/test-workspace"
  mkdir -p "$WORKSPACE_DIR/my-repo"
  write_pr_md "my-repo" "99" "test PR" "feat/x" "main" \
    '[{"id":1,"state":"OPEN","updated_on":"2026-01-01T00:00:00Z","text":"fix this","anchor":null}]' \
    "$WORKSPACE_DIR/my-repo"
  ls "$WORKSPACE_DIR/my-repo/.prs/"
  ```
  Expected: `99.md` exists at the correct path

---

## Chunk 6: Wire Notifications and Orchestration

### Task 9: Implement notification helpers

**Files:**
- Create: `pr-assistant/scripts/lib/pr-assistant-notify.sh`

```bash
#!/usr/bin/env bash
# pr-assistant-notify.sh — terminal-notifier wrappers

NOTIFIER="/opt/homebrew/bin/terminal-notifier"

# notify_pr_changed <repo> <pr_id> <md_file>
# Sends a notification for a PR with new unresolved comments.
notify_pr_changed() {
  local repo="$1"
  local pr_id="$2"
  local md_file="$3"
  "$NOTIFIER" \
    -title "PR Review Assistant" \
    -subtitle "${repo} PR #${pr_id}" \
    -message "There are PR comments" \
    -actions "Open review" \
    -execute "open '${md_file}'" \
    -group "pr-assistant-${repo}-${pr_id}" \
    -sound default
}

# notify_all_clear
# Sends a notification when no PRs have new comments.
notify_all_clear() {
  "$NOTIFIER" \
    -title "PR Review Assistant" \
    -message "Pull Requests all up to date" \
    -group "pr-assistant-all-clear" \
    -sound default
}

# notify_error <message>
# Sends a notification for setup or auth errors.
notify_error() {
  "$NOTIFIER" \
    -title "PR Review Assistant" \
    -subtitle "Setup required" \
    -message "$1" \
    -group "pr-assistant-error" \
    -sound Basso
}
```

- [x] **Step 1: Write `pr-assistant-notify.sh`**

- [x] **Step 2: Test `notify_all_clear` manually**

  Run:
  ```bash
  source pr-assistant/scripts/lib/pr-assistant-notify.sh
  notify_all_clear
  ```
  Expected: macOS notification appears with title `PR Review Assistant` and message `Pull Requests all up to date`

- [x] **Step 3: Test `notify_pr_changed` with a real markdown file path**

  Run:
  ```bash
  notify_pr_changed "entitlement-service" "123" \
    "/Users/samuel.sanchez-moreno/workspace/entitlement-service/.prs/123.md"
  ```
  Expected: notification appears with subtitle `entitlement-service PR #123`, action button `Open review`

### Task 10: Implement the main orchestration script

**Files:**
- Create: `pr-assistant/scripts/pr-review-login-check.sh`

```bash
#!/usr/bin/env bash
# pr-review-login-check.sh — login-time PR review assistant entrypoint
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/Library/Logs/pr-assistant.log"
WORKSPACE_DIR="/Users/samuel.sanchez-moreno/workspace"

exec >> "$LOG_FILE" 2>&1
echo "=== pr-assistant run at $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

# Load helpers
source "$SCRIPT_DIR/lib/pr-assistant-bitbucket.sh"
source "$SCRIPT_DIR/lib/pr-assistant-state.sh"
source "$SCRIPT_DIR/lib/pr-assistant-render.sh"
source "$SCRIPT_DIR/lib/pr-assistant-notify.sh"

# Check prerequisites
if ! check_prerequisites; then
  notify_error "Missing prerequisites — check ~/Library/Logs/pr-assistant.log"
  exit 1
fi

# Fetch open PRs
echo "Fetching open PRs..."
open_prs=$(fetch_my_open_prs) || {
  notify_error "Could not fetch PRs — check auth with: bkt auth status"
  exit 1
}

pr_count=$(echo "$open_prs" | jq 'length')
echo "Found ${pr_count} open PR(s)"

if [[ "$pr_count" -eq 0 ]]; then
  notify_all_clear
  exit 0
fi

changed_count=0

for (( i=0; i<pr_count; i++ )); do
  pr=$(echo "$open_prs" | jq ".[$i]")
  pr_id=$(echo "$pr"    | jq -r '.id')
  repo=$(echo "$pr"     | jq -r '.repo')
  title=$(echo "$pr"    | jq -r '.title')
  source_b=$(echo "$pr" | jq -r '.source')
  dest_b=$(echo "$pr"   | jq -r '.destination')

  # Skip if repo is not cloned locally
  local_repo="$WORKSPACE_DIR/$repo"
  if [[ ! -d "$local_repo" ]]; then
    echo "Skipping PR ${pr_id} — repo '${repo}' not found locally"
    continue
  fi

  echo "Processing PR ${pr_id} in ${repo}..."

  # Fetch unresolved comments
  live_comments=$(fetch_unresolved_comments "$repo" "$pr_id") || {
    echo "WARNING: could not fetch comments for PR ${pr_id} in ${repo}" >&2
    continue
  }

  # Read stored state and compute delta
  md_file=$(pr_md_path "$repo" "$pr_id")
  stored=$(read_tracked_comments "$md_file")
  delta=$(compute_delta "$stored" "$live_comments")

  if [[ "$delta" == "unchanged" ]]; then
    echo "PR ${pr_id} in ${repo}: no new comments — skipping"
    continue
  fi

  echo "PR ${pr_id} in ${repo}: new or updated comments detected — running agent analysis"

  # Render and write markdown (agent-assisted, with fallback)
  written=$(write_pr_md "$repo" "$pr_id" "$title" "$source_b" "$dest_b" \
    "$live_comments" "$local_repo")
  echo "Wrote: ${written}"

  # Send notification
  notify_pr_changed "$repo" "$pr_id" "$written"
  (( changed_count++ )) || true
done

if [[ "$changed_count" -eq 0 ]]; then
  notify_all_clear
fi

echo "=== pr-assistant complete — ${changed_count} PR(s) with new comments ==="
```

- [x] **Step 1: Write `pr-review-login-check.sh`**

- [x] **Step 2: Make it executable**

  Run: `chmod +x pr-assistant/scripts/pr-review-login-check.sh`
  Expected: executable bit set

- [x] **Step 3: Run manually with no live auth issues expected**

  Run: `bash pr-assistant/scripts/pr-review-login-check.sh`
  Expected: script completes, output in `~/Library/Logs/pr-assistant.log`

- [x] **Step 4: Verify unchanged PRs are skipped and produce no notification**

  Precondition: run once so `.prs/<pr>.md` is written. Run again.
  Expected: log shows "no new comments — skipping" for existing PRs

- [x] **Step 5: Verify changed PR triggers agent and produces notification**

  Precondition: delete one `.prs/<pr>.md` file or update a stored timestamp to an older value.
  Run the script again.
  Expected: log shows "running agent analysis", notification fires, file is rewritten

---

## Chunk 7: Install with launchd

### Task 11: Add the LaunchAgent plist

**Files:**
- Create: `pr-assistant/launchd/com.samuel.pr-assistant.plist`

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
    <string>/Users/samuel.sanchez-moreno/workspace/pr-assistant/scripts/pr-review-login-check.sh</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/Users/samuel.sanchez-moreno/Library/Logs/pr-assistant.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/samuel.sanchez-moreno/Library/Logs/pr-assistant.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>/Users/samuel.sanchez-moreno</string>
  </dict>
</dict>
</plist>
```

- [x] **Step 1: Create `pr-assistant/launchd/` directory**

  Run: `mkdir -p pr-assistant/launchd`
  Expected: directory created (may already exist from Task 2)

- [x] **Step 2: Write `com.samuel.pr-assistant.plist`**

- [x] **Step 3: Validate plist syntax**

  Run: `plutil -lint pr-assistant/launchd/com.samuel.pr-assistant.plist`
  Expected: `pr-assistant/launchd/com.samuel.pr-assistant.plist: OK`

- [x] **Step 4: Symlink the plist to `~/Library/LaunchAgents/`**

  Run:
  ```bash
  ln -sf /Users/samuel.sanchez-moreno/workspace/pr-assistant/launchd/com.samuel.pr-assistant.plist \
         ~/Library/LaunchAgents/com.samuel.pr-assistant.plist
  ```
  Expected: symlink created

- [x] **Step 5: Load the agent without rebooting**

  Run:
  ```bash
  launchctl load ~/Library/LaunchAgents/com.samuel.pr-assistant.plist
  ```
  Expected: agent loaded; check `~/Library/Logs/pr-assistant.log` for a run entry

### Task 12: Write the README

**Files:**
- Create: `pr-assistant/README.md`

- [x] **Step 1: Write `README.md` with these sections:**
  - Prerequisites (bkt, jq, terminal-notifier, opencode)
  - Setup (clone, vendor check, LaunchAgent installation)
  - Manual run instructions
  - Log location and how to tail the log
  - How to unload and reload the LaunchAgent
  - How to disable without removing the plist
  - How the prompt files work and how to customize them

---

## Chunk 8: Verification

### Task 13: Manual end-to-end verification

- [x] **Step 1: Run the main script manually with live Bitbucket auth**

  Run: `bash pr-assistant/scripts/pr-review-login-check.sh`
  Expected: log shows full run, PRs fetched, repos matched or skipped

- [x] **Step 2: Verify generated files under real repo `.prs/` directories**

  Run: `ls workspace/<repo>/.prs/` and read the generated file
  Expected: valid markdown with metadata header, tracked-comments block, and agent analysis per comment

- [x] **Step 3: Verify unchanged PRs are skipped on second run**

  Run: script again without modifying any stored state
  Expected: log shows all PRs as "no new comments — skipping", no notifications, all-clear fires

- [x] **Step 4: Verify changed PR triggers agent analysis and produces notification**

  Run: remove or modify a `.prs/*.md` file, run the script again
  Expected: log shows "running agent analysis", notification fires with `Open review`, file rewritten

- [x] **Step 5: Verify the notification action opens the correct markdown file**

  Click `Open review` on a notification
  Expected: the correct `.prs/<pr>.md` file opens

- [x] **Step 6: Verify fallback template works without opencode**

  Run with `OPENCODE_BIN=/nonexistent`:
  ```bash
  OPENCODE_BIN=/nonexistent bash pr-assistant/scripts/pr-review-login-check.sh
  ```
  Expected: log shows fallback used, markdown written with deterministic template, notification fires

- [x] **Step 7: Verify LaunchAgent runs correctly at login**

  Log out and log back in (or use `launchctl kickstart`)
  Expected: log shows a fresh run entry at login time

---

## Discoveries

- `pr-assistant` is a standalone repo at `workspace/pr-assistant/` — not part of dotfiles.
- `terminal-notifier` is installed at `/opt/homebrew/bin/terminal-notifier`.
- `opencode` is installed at `/opt/homebrew/bin/opencode` and supports `--attach`, `--dir`,
  `--file` flags; accepts piped prompts; `--attach` reuses a running TUI server.
- `bkt` is authenticated against `bitbucket.lab.dynatrace.org` with context `spine-dc`
  pointing to project `SPINE`.
- `jq` 1.7.1 is installed.
- `bkt-sanitize` source is at `rnd-ai-knowledgebase/skills/dt-bitbucket/scripts/bkt-sanitize`.
  The canonical `pii-sanitize` engine is at `rnd-ai-knowledgebase/utils/dt-pii-sanitize/pii-sanitize`.
  After vendoring, the engine path in `bkt-sanitize` must be updated from the original
  two-candidate relative paths to `../dt-pii-sanitize/pii-sanitize`.
- No existing `lib/` or `vendor/` subdirectories — all created during Task 2 scaffold.
- No existing LaunchAgent infrastructure — new `launchd/` directory under `pr-assistant/`.
- Three prompt files distilled from skills: `receiving-code-review` → base prompt;
  `lima-pr-reviewer` + `socratic-reviewer-checklist` → lens-licoco; `systematic-debugging` → lens-debugging.
- `opencode serve` default port is 4096. The TUI uses a **random port** by default unless
  `--port` is passed. So `--attach http://localhost:4096` against the TUI always fails unless
  the TUI was explicitly started with `--port 4096`. The correct fix is a persistent
  `opencode serve` daemon — not starting the TUI with a fixed port.

---

## Chunk 9: Production Hardening (post-implementation)

### Task 14: Add scheduled runs to pr-assistant LaunchAgent ✅ DONE

The original plist had only `RunAtLoad: true` — it fired once at login and never again.
`StartCalendarInterval` was added for 08:00, 13:00, and 16:00 daily.

**Files changed:**
- `launchd/com.samuel.pr-assistant.plist` — added `StartCalendarInterval` array

**Verification:**
```bash
launchctl list | grep pr-assistant   # exit code 0, PID assigned
```

### Task 15: Add persistent opencode serve daemon ✅ DONE

`opencode run --attach` was silently failing because the TUI uses a random port.
A new launchd agent starts `opencode serve --port 4096` at login and keeps it alive.

**Files added:**
- `launchd/com.samuel.opencode-serve.plist`

**Symlink:**
```bash
ln -sf ~/workspace/pr-assistant/launchd/com.samuel.opencode-serve.plist \
       ~/Library/LaunchAgents/com.samuel.opencode-serve.plist
```

**Verification:**
```bash
curl http://localhost:4096/global/health   # {"healthy":true,"version":"1.3.13"}
```

**Log:** `~/Library/Logs/opencode-serve.log`
