#!/bin/bash
# deploy action: waits up to 5 minutes for GitHub Pages to serve the
# preview. Sets the step output deployed=true or false; exits 0 either way
# so the caller can comment on the PR before failing the job.
#
# Needs PREVIEW_URL.
set -e

for i in {1..30}; do
  sleep 10
  if curl -sf "$PREVIEW_URL" | grep -q "wafer.space"; then
    echo "Preview is being served at $PREVIEW_URL"
    echo "deployed=true" >> "$GITHUB_OUTPUT"
    exit 0
  fi
  echo "Attempt $i/30: not served yet"
done

echo "::error::$PREVIEW_URL wasn't served within 5 minutes"
echo "deployed=false" >> "$GITHUB_OUTPUT"
