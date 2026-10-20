#!/bin/bash
# verify action: checks a preview site and writes verification-report.md.
#
# Needs PREVIEW_URL and PR_NUMBER. Sets the step outputs
# verification_status (success or failed) and report_content.
# Expects muffet, curl and bc to be installed.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$PREVIEW_URL" ] || [ -z "$PR_NUMBER" ]; then
  echo "PREVIEW_URL and PR_NUMBER must be set" >&2
  exit 1
fi

# Split the preview URL into origin and path, e.g.
# https://preview.wafer.space and /pr-12 (or /preview.wafer.space/pr-12
# for a fork's previews served from a project Pages site)
PREVIEW_ORIGIN=$(echo "$PREVIEW_URL" | grep -oE '^https://[^/]+')
PREVIEW_PATH=$(echo "$PREVIEW_URL" | sed -E 's#^https://[^/]+##; s#/+$##')

echo "Starting comprehensive verification of: $PREVIEW_URL"

# Create verification report
REPORT_FILE="verification-report.md"
echo "# Preview Site Verification Report" > $REPORT_FILE
echo "**PR:** #$PR_NUMBER" >> $REPORT_FILE
echo "**URL:** $PREVIEW_URL" >> $REPORT_FILE
echo "**Timestamp:** $(date -u)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# Track verification status
VERIFICATION_PASSED=true

# 1. Basic connectivity test
echo "## 1. Basic Connectivity ✅" >> $REPORT_FILE
if curl -s --fail --head "$PREVIEW_URL" > /dev/null; then
  echo "- ✅ Site is accessible" >> $REPORT_FILE
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PREVIEW_URL")
  echo "- ✅ HTTP Status: $HTTP_STATUS" >> $REPORT_FILE
else
  echo "- ❌ Site is not accessible" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi
echo "" >> $REPORT_FILE

# 2. Content verification
echo "## 2. Content Verification" >> $REPORT_FILE
CONTENT=$(curl -s "$PREVIEW_URL")

if echo "$CONTENT" | grep -q "wafer.space"; then
  echo "- ✅ Site contains expected content" >> $REPORT_FILE
else
  echo "- ❌ Site missing expected content" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi

if echo "$CONTENT" | grep -q "Budget silicon manufacturing"; then
  echo "- ✅ Tagline present" >> $REPORT_FILE
else
  echo "- ❌ Tagline missing" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi

# Check for baseurl configuration (flexible check for different implementations)
if echo "$CONTENT" | grep -qF "window.siteBaseurl = '$PREVIEW_PATH'"; then
  echo "- ✅ JavaScript baseurl configuration found" >> $REPORT_FILE
elif echo "$CONTENT" | grep -qE "(src|href)=\"$PREVIEW_PATH/"; then
  echo "- ✅ Assets use correct PR baseurl paths" >> $REPORT_FILE
else
  echo "- ⚠️  Baseurl configuration not detected (checking asset accessibility)" >> $REPORT_FILE
fi
echo "" >> $REPORT_FILE

# 3. Comprehensive Multi-Page Asset Verification
echo "## 3. Multi-Page Asset Verification" >> $REPORT_FILE
ASSETS_FAILED=0
ASSETS_TOTAL=0

# Extract all internal pages from homepage
echo "Discovering all pages in the site..." >> $REPORT_FILE
DISCOVERED_PAGES=$(echo "$CONTENT" | grep -oE 'href="[^"#]*\.html"' | grep -oE '"[^"]*"' | tr -d '"' | grep -v "^http" | sort -u)

# Add homepage (empty string) and all discovered pages
ALL_PAGES=$(echo -e "\n$DISCOVERED_PAGES")

# Debug: Log discovered pages
echo "Found pages: $(echo "$DISCOVERED_PAGES" | wc -l) discovered + homepage" >> $REPORT_FILE

# Test critical predefined assets from homepage
echo "Testing critical assets..." >> $REPORT_FILE
CRITICAL_ASSETS=(
  "favicon.png"
  "assets/css/style.css"
  "assets/js/jquery.min.js"
  "assets/images/logo-light.webp"
)

for asset in "${CRITICAL_ASSETS[@]}"; do
  ASSET_URL="$PREVIEW_URL$asset"
  ASSETS_TOTAL=$((ASSETS_TOTAL + 1))
  if curl -s --fail --head "$ASSET_URL" > /dev/null; then
    echo "- ✅ $asset" >> $REPORT_FILE
  else
    echo "- ❌ $asset (HTTP $(curl -s -o /dev/null -w "%{http_code}" "$ASSET_URL"))" >> $REPORT_FILE
    ASSETS_FAILED=$((ASSETS_FAILED + 1))
  fi
done

# Check assets on all discovered pages
echo "Checking assets across all pages..." >> $REPORT_FILE
PAGE_COUNT=0
while IFS= read -r page_path; do
  PAGE_COUNT=$((PAGE_COUNT + 1))
  if [ -z "$page_path" ]; then
    PAGE_URL="$PREVIEW_URL"
    PAGE_NAME="homepage"
    PAGE_CONTENT="$CONTENT"
    echo "Processing page $PAGE_COUNT: $PAGE_NAME" >> $REPORT_FILE
  else
    # Handle both relative and absolute paths
    if [[ "$page_path" == /* ]]; then
      # For absolute paths like /pr-46/about.html, use them directly with the origin
      PAGE_URL="$PREVIEW_ORIGIN$page_path"
    else
      # For relative paths like how.html, append to PREVIEW_URL
      PAGE_URL="$PREVIEW_URL$page_path"
    fi
    PAGE_NAME="$(basename "$page_path")"
    echo "Processing page $PAGE_COUNT: $PAGE_NAME ($page_path) -> $PAGE_URL" >> $REPORT_FILE
    PAGE_CONTENT=$(curl -s "$PAGE_URL" 2>/dev/null || echo "")
  fi

  if [ -n "$PAGE_CONTENT" ]; then
    # Extract assets from this page
    CSS_ASSETS=$(echo "$PAGE_CONTENT" | grep -oE 'href="[^"]*\.css"' | grep -oE '"[^"]*"' | tr -d '"')
    JS_ASSETS=$(echo "$PAGE_CONTENT" | grep -oE 'src="[^"]*\.js"' | grep -oE '"[^"]*"' | tr -d '"')
    IMAGE_ASSETS=$(echo "$PAGE_CONTENT" | grep -oE '(src|href)="[^"]*\.(png|jpg|jpeg|webp|ico)"' | grep -oE '"[^"]*"' | tr -d '"')
    DATA_IMAGE_ASSETS=$(echo "$PAGE_CONTENT" | grep -oE 'data-[^=]*="[^"]*"' | grep -E '\.(png|jpg|jpeg|webp|ico)' | grep -oE '"[^"]*"' | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    ALL_PAGE_ASSETS="$CSS_ASSETS"$'\n'"$JS_ASSETS"$'\n'"$IMAGE_ASSETS"$'\n'"$DATA_IMAGE_ASSETS"

    # Process assets found on this page
    while IFS= read -r asset_path; do
      if [ -n "$asset_path" ]; then
        # Handle relative vs absolute paths
        if [[ "$asset_path" == /* ]]; then
          FULL_ASSET_URL="$PREVIEW_ORIGIN$asset_path"
        else
          FULL_ASSET_URL="$PREVIEW_URL$asset_path"
        fi

        ASSETS_TOTAL=$((ASSETS_TOTAL + 1))
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$FULL_ASSET_URL")
        if [ "$HTTP_CODE" = "200" ]; then
          echo "- ✅ $(basename "$asset_path") ($PAGE_NAME)" >> $REPORT_FILE
        else
          echo "- ❌ $(basename "$asset_path") (HTTP $HTTP_CODE) on $PAGE_NAME - $asset_path" >> $REPORT_FILE
          ASSETS_FAILED=$((ASSETS_FAILED + 1))
        fi
      fi
    done <<< "$ALL_PAGE_ASSETS"
  else
    echo "- ⚠️  Could not fetch $PAGE_NAME" >> $REPORT_FILE
  fi
done <<< "$ALL_PAGES"

echo "Checked $PAGE_COUNT pages total." >> $REPORT_FILE

echo "**Asset Summary:** $ASSETS_FAILED/$ASSETS_TOTAL failed" >> $REPORT_FILE

if [ $ASSETS_FAILED -gt 0 ]; then
  echo "- ❌ $ASSETS_FAILED assets failed to load" >> $REPORT_FILE
  VERIFICATION_PASSED=false
else
  echo "- ✅ All assets loaded successfully" >> $REPORT_FILE
fi
echo "" >> $REPORT_FILE

# 4. Comprehensive Link and Asset Verification with muffet
echo "## 4. Link and Asset Verification (muffet)" >> $REPORT_FILE
echo "Running comprehensive muffet validation..." >> $REPORT_FILE

# Run muffet with proper configuration for thorough checking
# Identify honestly as a link checker: Cloudflare-fronted sites
# (e.g. sourceforge.io, linuxgizmos.com) challenge requests that
# claim to be Chrome but don't behave like it.
# Invalid TLS certificates on linked sites are only warned about
# (by summarise-muffet.py below), so muffet skips verification
if muffet \
  --skip-tls-verification \
  --format=json \
  --verbose \
  --timeout=30 \
  --max-connections=10 \
  --max-connections-per-host=5 \
  --rate-limit=20 \
  --buffer-size=16384 \
  --exclude=".*mailto:.*" \
  --exclude=".*linkedin\.com.*" \
  --exclude=".*hawaii\.edu.*" \
  --exclude=".*timeanddate\.com.*" \
  --exclude=".*reddit\.com.*" \
  --exclude=".*electronics-lab\.com.*" \
  --exclude=".*matrix\.to.*" \
  --exclude=".*tinytapeout\.com/chips/silicon-proven.*" \
  --exclude=".*siliconprawn\.org.*" \
  --header="User-Agent:Mozilla/5.0 (compatible; wafer.space-link-checker; +https://wafer.space/)" \
  --header="Accept:text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
  --header="Accept-Language:en-US,en;q=0.9" \
  --header="Accept-Encoding:gzip, deflate, br" \
  --header="Cache-Control:no-cache" \
  --header="Pragma:no-cache" \
  "$PREVIEW_URL" > muffet-report.json; then
  MUFFET_PASSED=true
else
  MUFFET_PASSED=false
fi
python3 "$SCRIPT_DIR/summarise-muffet.py" muffet-report.json \
  --site-url "$PREVIEW_URL" \
  --failures muffet-report.txt \
  --tls-warnings tls-warnings.md

if [ "$MUFFET_PASSED" = true ]; then
  echo "- ✅ All links and assets are valid (muffet)" >> $REPORT_FILE
else
  echo "- ❌ muffet found broken links or assets:" >> $REPORT_FILE
  echo "\`\`\`" >> $REPORT_FILE
  # Show muffet output with details about broken links/assets
  cat muffet-report.txt | head -30 >> $REPORT_FILE 2>/dev/null || echo "No detailed report available" >> $REPORT_FILE
  echo "\`\`\`" >> $REPORT_FILE

  # Count different types of failures for summary
  BROKEN_LINKS=$(grep -c "broken link" muffet-report.txt 2>/dev/null || echo "0")
  TIMEOUTS=$(grep -c "timeout" muffet-report.txt 2>/dev/null || echo "0")
  HTTP_ERRORS=$(grep -c "HTTP" muffet-report.txt 2>/dev/null || echo "0")

  echo "**Summary:** $BROKEN_LINKS broken links, $TIMEOUTS timeouts, $HTTP_ERRORS HTTP errors" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi

# Warnings only: these sites still load if the visitor clicks through
if [ -s tls-warnings.md ]; then
  echo "" >> $REPORT_FILE
  echo "**Linked sites with invalid TLS certificates (warning only):**" >> $REPORT_FILE
  cat tls-warnings.md >> $REPORT_FILE
fi
echo "" >> $REPORT_FILE

# 5. Performance check
echo "## 5. Performance Check" >> $REPORT_FILE
LOAD_TIME=$(curl -s -w "%{time_total}" -o /dev/null "$PREVIEW_URL")
echo "- Page load time: ${LOAD_TIME}s" >> $REPORT_FILE

if (( $(echo "$LOAD_TIME < 5.0" | bc -l) )); then
  echo "- ✅ Load time acceptable" >> $REPORT_FILE
else
  echo "- ⚠️  Load time may be slow" >> $REPORT_FILE
fi
echo "" >> $REPORT_FILE

# 6. Mobile responsiveness check
echo "## 6. Mobile Responsiveness" >> $REPORT_FILE
MOBILE_CONTENT=$(curl -s -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15" "$PREVIEW_URL")

if echo "$MOBILE_CONTENT" | grep -q "viewport"; then
  echo "- ✅ Viewport meta tag present" >> $REPORT_FILE
else
  echo "- ❌ Viewport meta tag missing" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi
echo "" >> $REPORT_FILE

# Final summary
echo "## Summary" >> $REPORT_FILE
if [ "$VERIFICATION_PASSED" = true ]; then
  echo "✅ **All verification checks passed!**" >> $REPORT_FILE
  echo "verification_status=success" >> $GITHUB_OUTPUT
else
  echo "❌ **Some verification checks failed**" >> $REPORT_FILE
  echo "verification_status=failed" >> $GITHUB_OUTPUT
fi

# Save report for comment
echo "report_content<<EOF" >> $GITHUB_OUTPUT
cat $REPORT_FILE >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

# Show summary
echo "Verification completed. Status: $VERIFICATION_PASSED"
cat $REPORT_FILE
