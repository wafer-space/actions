#!/bin/bash
# deploy and verify actions: waits for GitHub Pages to serve the preview
# built from EXPECTED_COMMIT, which the site's pages name in a
# "<!-- Generated from git commit: <sha>" comment. Sets the step output
# deployed=true or false and exits 0 either way, so the caller can report
# before failing.
#
# Needs PREVIEW_URL and EXPECTED_COMMIT. WAIT_MINUTES defaults to 10.
set -e

MINUTES=${WAIT_MINUTES:-10}
ATTEMPTS=$((MINUTES * 6))
for ((i = 1; i <= ATTEMPTS; i++)); do
  PAGE=$(curl -sf "$PREVIEW_URL" || true)
  FOUND=$(grep -oE -m1 '<!-- Generated from git commit: [0-9a-f]{40}' <<< "$PAGE" | grep -oE '[0-9a-f]{40}' || true)
  if [ "$FOUND" = "$EXPECTED_COMMIT" ]; then
    echo "$PREVIEW_URL is serving $EXPECTED_COMMIT"
    echo "deployed=true" >> "$GITHUB_OUTPUT"
    exit 0
  fi
  echo "Attempt $i/$ATTEMPTS: serving ${FOUND:-nothing yet}, waiting for $EXPECTED_COMMIT"
  sleep 10
done

echo "::error::$PREVIEW_URL wasn't serving $EXPECTED_COMMIT after $MINUTES minutes"
echo "deployed=false" >> "$GITHUB_OUTPUT"
