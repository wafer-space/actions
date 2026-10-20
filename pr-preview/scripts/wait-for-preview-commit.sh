#!/bin/bash
# verify action: waits up to 10 minutes for the preview to be serving the
# expected commit.
#
# Needs PREVIEW_URL and EXPECTED_COMMIT.
set -e

if [ -z "$PREVIEW_URL" ] || [ -z "$EXPECTED_COMMIT" ]; then
  echo "PREVIEW_URL and EXPECTED_COMMIT must be set" >&2
  exit 1
fi

echo "Waiting for preview deployment with commit $EXPECTED_COMMIT at: $PREVIEW_URL"

# Wait up to 10 minutes for the deployment to complete with the correct commit
for i in {1..120}; do
  echo "Attempt $i/120: Checking preview site availability..."

  if curl -s --fail --head "$PREVIEW_URL" > /dev/null; then
    echo "✅ Preview site is responding"

    # Check for actual content and correct commit hash
    PAGE_CONTENT=$(curl -s "$PREVIEW_URL")
    if echo "$PAGE_CONTENT" | grep -q "wafer.space"; then
      # Extract git commit hash from HTML comment or meta tag
      COMMIT_COMMENT=$(echo "$PAGE_CONTENT" | grep -oE '<!-- Generated from git commit: [a-f0-9]{40}' | grep -oE '[a-f0-9]{40}' || echo "")
      COMMIT_META=$(echo "$PAGE_CONTENT" | grep -oE '<meta name="git-commit" content="[a-f0-9]{40}"' | grep -oE 'content="[a-f0-9]{40}"' | grep -oE '[a-f0-9]{40}' || echo "")

      FOUND_COMMIT="${COMMIT_COMMENT:-$COMMIT_META}"

      if [ "$FOUND_COMMIT" = "$EXPECTED_COMMIT" ]; then
        echo "✅ Preview site has correct commit: $FOUND_COMMIT"
        echo "✅ Preview site is ready for verification"
        break
      elif [ -n "$FOUND_COMMIT" ]; then
        echo "⚠️  Preview site has different commit: $FOUND_COMMIT (expected: $EXPECTED_COMMIT)"
        echo "⚠️  Waiting for correct deployment..."
      else
        echo "⚠️  Preview site content ready but commit hash not found"
      fi
    else
      echo "⚠️  Preview site responding but content not yet ready"
    fi
  else
    echo "❌ Preview site not yet responding (may still be deploying)"
  fi

  if [ "$i" -eq 120 ]; then
    echo "ERROR: Preview site not ready with correct commit after 10 minutes"
    echo "Expected commit: $EXPECTED_COMMIT"
    if [ -n "$FOUND_COMMIT" ]; then
      echo "Found commit: $FOUND_COMMIT"
    fi
    echo "This may indicate a deployment failure or very slow deployment"
    exit 1
  fi

  sleep 5
done

echo "Preview site is ready for comprehensive verification"
