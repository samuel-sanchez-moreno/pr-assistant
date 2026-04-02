#!/usr/bin/env bash
# pr-assistant-analysis.sh — build agent prompt, invoke opencode run, fallback renderer

_ANALYSIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$(cd "$_ANALYSIS_DIR/../../prompts" && pwd)"
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
