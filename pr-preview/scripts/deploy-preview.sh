#!/bin/bash
# deploy action: pushes a built preview to the preview repository, adds a
# redirect from the slugified directory name, and regenerates the preview
# index.
#
# SECURITY: SITE_DIR is the build action's artifact, made by running the
# PR's content through Jekyll, so it is only ever copied as data: nothing
# in it is run, symlinks are refused and .git directories removed. The
# templates and the index script come from this repository.
#
# Needs:
#   SITE_DIR            the built site (absolute path)
#   DIR_NAME            e.g. pr-12
#   SLUG_NAME           e.g. pr-12-fix-the-faq
#   BASE_PATH           '' or the path previews are served under, e.g.
#                       /preview.wafer.space
#   PR_NUMBER, PR_SHA   for the commit message
#   PREVIEW_REPOSITORY, PREVIEW_BASE_URL
#   PREVIEW_KEY         deploy key with write access to PREVIEW_REPOSITORY
# Clones the preview repository into ./preview-repo.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"

for var in SITE_DIR DIR_NAME SLUG_NAME PR_NUMBER PR_SHA PREVIEW_REPOSITORY PREVIEW_BASE_URL PREVIEW_KEY; do
  if [ -z "${!var}" ]; then
    echo "$var is not set" >&2
    exit 1
  fi
done
if ! [[ "$DIR_NAME" =~ ^pr-[0-9]+$ ]] || ! [[ "$SLUG_NAME" =~ ^pr-[0-9]+(-[a-z0-9-]+)?$ ]]; then
  echo "Invalid directory names: $DIR_NAME, $SLUG_NAME" >&2
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

echo "🚀 Deploying to $PREVIEW_REPOSITORY..."

eval "$(ssh-agent -s)"
printf '%s\n' "$PREVIEW_KEY" | ssh-add -
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan github.com >> ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

git clone "git@github.com:${PREVIEW_REPOSITORY}.git" preview-repo
cd preview-repo

git config user.name 'github-actions[bot]'
git config user.email 'github-actions[bot]@users.noreply.github.com'

# Create PR directory and copy built site
mkdir -p "$DIR_NAME"
cp -r "$SITE_DIR/"* "$DIR_NAME/"

# Create redirect page for slugified URL if different
if [ "$SLUG_NAME" != "$DIR_NAME" ]; then
  mkdir -p "$SLUG_NAME"
  cp "$TEMPLATE_DIR/redirect-template.html" "$SLUG_NAME/index.html"
  sed -i "s|{{TARGET_URL}}|${BASE_PATH}/${DIR_NAME}|g" "$SLUG_NAME/index.html"
  echo "Created redirect from $SLUG_NAME to $DIR_NAME"
fi

# Ensure CNAME file exists when previews have their own domain
# (a project Pages site under a path uses its owner's domain)
if [ -z "$BASE_PATH" ] && [ ! -f CNAME ]; then
  echo "$PREVIEW_BASE_URL" | sed -E 's#^https://##; s#/.*$##' > CNAME
fi

"$SCRIPT_DIR/generate-preview-index.sh"

git add .
if git diff --staged --quiet; then
  echo "ℹ️  No changes to commit"
  exit 0
fi

git commit -m "Deploy preview for PR #${PR_NUMBER} - ${PR_SHA}"
git push origin main

echo "✅ Deployment complete"
