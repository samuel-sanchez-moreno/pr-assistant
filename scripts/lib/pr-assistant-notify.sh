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
