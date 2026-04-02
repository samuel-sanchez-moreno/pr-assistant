#!/usr/bin/env bash
# pr-review-login-check.sh — login-time PR review assistant entrypoint
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/Library/Logs/pr-assistant.log"
WORKSPACE_DIR="/Users/samuel.sanchez-moreno/workspace"

exec >> "$LOG_FILE" 2>&1
echo "=== pr-assistant run at $(TZ="Europe/Berlin" date +"%Y-%m-%dT%H:%M:%S %Z") ==="

# Load helpers (render.sh last — it sources analysis.sh and state.sh which reset SCRIPT_DIR)
source "$SCRIPT_DIR/lib/pr-assistant-bitbucket.sh"
source "$SCRIPT_DIR/lib/pr-assistant-notify.sh"
source "$SCRIPT_DIR/lib/pr-assistant-state.sh"
source "$SCRIPT_DIR/lib/pr-assistant-render.sh"

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
