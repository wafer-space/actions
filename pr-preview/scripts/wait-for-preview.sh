#!/bin/bash
# deploy action: waits for GitHub Pages to serve a newly pushed preview.
#
# Needs PREVIEW_URL. Sets the step outputs deployment_status (success,
# partial or failed), preview_url and error_message. Reports failed if
# the site doesn't respond within 3 minutes, but exits 0 so the caller
# can comment on the PR before failing the job.
set -e

if [ -z "$PREVIEW_URL" ]; then
  echo "PREVIEW_URL is not set" >&2
  exit 1
fi

echo "⏳ Waiting for GitHub Pages deployment..."
echo "Preview URL: $PREVIEW_URL"

# Wait for basic HTTP response (3 minutes max)
for i in {1..18}; do
  sleep 10
  echo "Attempt $i/18: Checking HTTP response..."

  if curl -s --fail --head "$PREVIEW_URL" > /dev/null; then
    echo "✅ Site is responding"
    break
  fi

  if [ "$i" -eq 18 ]; then
    echo "deployment_status=failed" >> "$GITHUB_OUTPUT"
    echo "error_message=No HTTP response after 3 minutes" >> "$GITHUB_OUTPUT"
    exit 0
  fi
done

# Verify content is correct (2 minutes max)
for i in {1..24}; do
  sleep 5
  echo "Content verification attempt $i/24..."

  PAGE_CONTENT=$(curl -s "$PREVIEW_URL")
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PREVIEW_URL")

  if [ "$HTTP_STATUS" = "200" ] && echo "$PAGE_CONTENT" | grep -q "wafer.space"; then
    echo "✅ Deployment verified successfully"
    echo "deployment_status=success" >> "$GITHUB_OUTPUT"
    echo "preview_url=$PREVIEW_URL" >> "$GITHUB_OUTPUT"
    exit 0
  fi
done

echo "⚠️  Verification timeout - deployment may still be propagating"
echo "deployment_status=partial" >> "$GITHUB_OUTPUT"
echo "preview_url=$PREVIEW_URL" >> "$GITHUB_OUTPUT"
echo "error_message=Content verification timeout" >> "$GITHUB_OUTPUT"
