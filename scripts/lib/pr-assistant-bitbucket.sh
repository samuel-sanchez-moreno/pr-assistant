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
    | jq '[.pull_requests[] | {id, title, state,
                  source: .fromRef.displayId,
                  destination: .toRef.displayId,
                  repo: .toRef.repository.slug}]'
}

# fetch_unresolved_comments <repo> <pr_id>
# Outputs sanitized JSON array of unresolved comments for a given PR
fetch_unresolved_comments() {
  local repo="$1"
  local pr_id="$2"
  "$BKT_SANITIZE" api \
    "/rest/api/1.0/projects/SPINE/repos/${repo}/pull-requests/${pr_id}/activities" \
    | jq '[.values[]
           | select(.action == "COMMENTED")
           | select(.comment.threadResolved == false)
           | {
               id: .comment.id,
               state: .comment.state,
               threadResolved: .comment.threadResolved,
               updated_on: .comment.updatedDate,
               text: .comment.text,
               anchor: (.commentAnchor // null | {path, line, lineType} // null)
             }]'
}
