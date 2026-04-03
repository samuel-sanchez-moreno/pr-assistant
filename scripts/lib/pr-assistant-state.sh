#!/usr/bin/env bash
# pr-assistant-state.sh — read existing PR markdown state and compute comment deltas

WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspace}"

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
