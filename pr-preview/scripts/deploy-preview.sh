#!/bin/bash
# deploy action: pushes a built preview to the preview repository and
# regenerates its index.
#
# SECURITY: SITE_DIR is the build action's artifact, made from the pull
# request's code, so it is only ever copied as data: nothing in it is run,
# symlinks are refused and .git directories removed.
#
# Needs SITE_DIR (absolute path), DIR_NAME (e.g. pr-12), PR_NUMBER,
# PR_SHA, PREVIEW_REPOSITORY, PREVIEW_BASE_URL and PREVIEW_KEY (a deploy
# key that can push to PREVIEW_REPOSITORY). Clones into ./preview-repo.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for var in SITE_DIR DIR_NAME PR_NUMBER PR_SHA PREVIEW_REPOSITORY PREVIEW_BASE_URL PREVIEW_KEY; do
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

eval "$(ssh-agent -s)"
printf '%s\n' "$PREVIEW_KEY" | ssh-add -
mkdir -p ~/.ssh
ssh-keyscan github.com >> ~/.ssh/known_hosts

git clone "git@github.com:${PREVIEW_REPOSITORY}.git" preview-repo
cd preview-repo
git config user.name 'github-actions[bot]'
git config user.email 'github-actions[bot]@users.noreply.github.com'

# Other PRs' previews may be pushed at the same time, so if the push is
# rejected, start again from the new main
for attempt in 1 2 3 4 5; do
  git fetch -q origin main
  git reset -q --hard origin/main
  rm -rf "$DIR_NAME"
  cp -r "$SITE_DIR" "$DIR_NAME"
  "$SCRIPT_DIR/generate-preview-index.sh"

  git add -A
  if git diff --staged --quiet; then
    echo "No changes to commit"
    exit 0
  fi
  git commit -q -m "Deploy preview for PR #${PR_NUMBER} - ${PR_SHA}"
  if git push origin main; then
    exit 0
  fi
  echo "Push rejected (attempt $attempt), retrying"
  sleep $((attempt * 5))
done
echo "Couldn't push after 5 attempts" >&2
exit 1
