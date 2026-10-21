#!/bin/bash
# deploy action: pushes a built preview to the preview repository and
# regenerates its index, unless the pull request has moved on to a newer
# commit (whose own run deploys it) or closed.
#
# SECURITY: SITE_DIR is the build action's artifact, made from the pull
# request's code, so it is only ever copied as data: nothing in it is run,
# symlinks are refused and .git directories removed.
#
# Needs SITE_DIR (absolute path), DIR_NAME (e.g. pr-12), PR_NUMBER,
# PR_SHA, GH_TOKEN (to read the pull request), and what preview-repo.sh
# needs. Clones into ./preview-repo. Sets the step output superseded=true
# if it didn't deploy because the pull request moved on.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=preview-repo.sh
source "$SCRIPT_DIR/preview-repo.sh"

for var in SITE_DIR DIR_NAME PR_NUMBER PR_SHA GH_TOKEN PREVIEW_REPOSITORY PREVIEW_BASE_URL PREVIEW_KEY; do
  if [ -z "${!var}" ]; then
    echo "$var is not set" >&2
    exit 1
  fi
done
if ! [[ "$DIR_NAME" =~ ^pr-[0-9]+$ ]]; then
  echo "Invalid DIR_NAME: $DIR_NAME" >&2
  exit 1
fi
if [ ! -f "$SITE_DIR/index.html" ]; then
  echo "$SITE_DIR has no index.html" >&2
  exit 1
fi
if [ -n "$(find "$SITE_DIR" -type l)" ]; then
  echo "The built site contains symlinks:" >&2
  find "$SITE_DIR" -type l >&2
  exit 1
fi
# A .git directory would be committed as an embedded repository
find "$SITE_DIR" -name .git -prune -exec rm -rf {} +

pr_is_still_at_commit() {
  local head
  head=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq 'if .state == "open" then .head.sha else "closed" end')
  if [ "$head" != "$PR_SHA" ]; then
    echo "PR #$PR_NUMBER is now at $head, not $PR_SHA; not deploying"
    return 1
  fi
}

add_preview() {
  rm -rf "$DIR_NAME"
  cp -r "$SITE_DIR" "$DIR_NAME"
  "$SCRIPT_DIR/generate-preview-index.sh"
  COMMIT_MESSAGE="Deploy preview for PR #${PR_NUMBER} - ${PR_SHA}"
}

clone_preview_repo
push_preview_repo add_preview pr_is_still_at_commit
echo "superseded=$SKIPPED" >> "$GITHUB_OUTPUT"
