#!/bin/bash
# cleanup action: removes the previews of closed (or deleted) pull requests
# from the preview repository and regenerates its index.
#
# Needs GH_TOKEN (to read pull requests) and what preview-repo.sh needs.
# PR_NUMBER, if set, limits the cleanup to that pull request. Clones into
# ./preview-repo.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=preview-repo.sh
source "$SCRIPT_DIR/preview-repo.sh"

if [ -n "$PR_NUMBER" ] && ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid PR_NUMBER: $PR_NUMBER" >&2
  exit 1
fi

remove_closed_previews() {
  local numbers number state removed=()
  # pr-<number>, and pr-<number>-<slug> left by the old workflows
  numbers=$(find . -maxdepth 1 -type d -regextype posix-extended -regex './pr-[0-9]+(-.*)?' -printf '%f\n' \
    | sed -E 's/^pr-([0-9]+).*/\1/' | sort -un)
  for number in $numbers; do
    if [ -n "$PR_NUMBER" ] && [ "$number" != "$PR_NUMBER" ]; then
      continue
    fi
    if ! state=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$number" --jq .state 2>&1); then
      if [[ "$state" != *"HTTP 404"* ]]; then
        echo "::warning::Couldn't check PR #$number, keeping its preview: $state"
        continue
      fi
      state=deleted
    fi
    if [ "$state" != open ]; then
      echo "PR #$number is $state, removing its preview"
      find . -maxdepth 1 -type d -regextype posix-extended -regex "./pr-$number(-.*)?" -exec rm -rf {} +
      removed+=("#$number")
    fi
  done
  "$SCRIPT_DIR/generate-preview-index.sh"
  COMMIT_MESSAGE="Remove previews of closed PRs: ${removed[*]}"
}

clone_preview_repo
push_preview_repo remove_closed_previews
