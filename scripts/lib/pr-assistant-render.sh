#!/usr/bin/env bash
# pr-assistant-render.sh — render per-PR markdown files

_RENDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pr-assistant-analysis.sh
source "$_RENDER_DIR/pr-assistant-analysis.sh"
# shellcheck source=pr-assistant-state.sh
source "$_RENDER_DIR/pr-assistant-state.sh"

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
  timestamp=$(TZ="Europe/Berlin" date +"%Y-%m-%dT%H:%M:%S %Z")

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
