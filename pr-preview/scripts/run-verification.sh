#!/bin/bash
# verify action: checks a preview site and writes verification-report.md.
#
# Needs PREVIEW_URL (ending in /) and PR_NUMBER, and optionally
# MUFFET_EXCLUDES (URL regular expressions for muffet to skip, one per
# line). Sets the step outputs verification_status (success or failed) and
# report_content.
# Expects muffet, curl and bc to be installed.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$PREVIEW_URL" ] || [ -z "$PR_NUMBER" ]; then
  echo "PREVIEW_URL and PR_NUMBER must be set" >&2
  exit 1
fi
PREVIEW_URL="${PREVIEW_URL%/}/"

# Split the preview URL into origin and path, e.g.
# https://preview.wafer.space and /pr-12 (or /preview.wafer.space/pr-12
# for a fork's previews served from a project Pages site)
PREVIEW_ORIGIN=$(grep -oE '^https://[^/]+' <<< "$PREVIEW_URL")
PREVIEW_PATH=$(sed -E 's#^https://[^/]+##; s#/+$##' <<< "$PREVIEW_URL")

# The HTTP status of a URL, or 000 if it couldn't be fetched at all
http_status() {
  curl -s -o /dev/null --max-time 30 -w "%{http_code}" "$1" || true
}

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
echo "## 1. Basic Connectivity" >> $REPORT_FILE
HTTP_STATUS=$(http_status "$PREVIEW_URL")
if [ "$HTTP_STATUS" = 200 ]; then
  echo "- ✅ Site is accessible (HTTP $HTTP_STATUS)" >> $REPORT_FILE
else
  echo "- ❌ Site is not accessible (HTTP $HTTP_STATUS)" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi
echo "" >> $REPORT_FILE

# 2. Content verification
echo "## 2. Content Verification" >> $REPORT_FILE
CONTENT=$(curl -s --max-time 30 "$PREVIEW_URL" || true)

if grep -q "wafer.space" <<< "$CONTENT"; then
  echo "- ✅ Site contains expected content" >> $REPORT_FILE
else
  echo "- ❌ Site missing expected content" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi

if grep -q "Budget silicon manufacturing" <<< "$CONTENT"; then
  echo "- ✅ Tagline present" >> $REPORT_FILE
else
  echo "- ❌ Tagline missing" >> $REPORT_FILE
  VERIFICATION_PASSED=false
fi

# Check for baseurl configuration (flexible check for different implementations)
if grep -qF "window.siteBaseurl = '$PREVIEW_PATH'" <<< "$CONTENT"; then
  echo "- ✅ JavaScript baseurl configuration found" >> $REPORT_FILE
elif grep -qE "(src|href)=\"$PREVIEW_PATH/" <<< "$CONTENT"; then
  echo "- ✅ Assets use correct PR baseurl paths" >> $REPORT_FILE
else
  echo "- ⚠️  Baseurl configuration not detected (checking asset accessibility)" >> $REPORT_FILE
fi
echo "" >> $REPORT_FILE

# 3. Assets on the home page and the pages it links to, including ones in
# data-* attributes, which muffet doesn't check. External assets are left
# to muffet. Only failures are listed.
echo "## 3. Multi-Page Asset Verification" >> $REPORT_FILE
ASSETS_FAILED=0
ASSETS_TOTAL=0

# The site URL for a link on a page: root-relative links are under the
# origin, others relative to the page's directory. Prints nothing for
# links to other sites.
resolve_url() {
  local link=$1 page_url=$2
  case "$link" in
    http:* | https:* | //* | data:* | mailto:*) ;;
    /*) echo "$PREVIEW_ORIGIN$link" ;;
    *) echo "${page_url%/*}/$link" ;;
  esac
}

DISCOVERED_PAGES=$(grep -oE 'href="[^"#]*\.html"' <<< "$CONTENT" | cut -d'"' -f2 | sort -u || true)
CRITICAL_ASSETS=(
  "favicon.png"
  "assets/css/style.css"
  "assets/js/jquery.min.js"
  "assets/images/logo-light.webp"
)

for asset in "${CRITICAL_ASSETS[@]}"; do
  ASSETS_TOTAL=$((ASSETS_TOTAL + 1))
  CODE=$(http_status "$PREVIEW_URL$asset")
  if [ "$CODE" != 200 ]; then
    echo "- ❌ $asset (HTTP $CODE)" >> $REPORT_FILE
    ASSETS_FAILED=$((ASSETS_FAILED + 1))
  fi
done

PAGE_COUNT=0
declare -A CHECKED
while IFS= read -r page_url; do
  [ -n "$page_url" ] || continue
  PAGE_COUNT=$((PAGE_COUNT + 1))
  if [ "$page_url" = "$PREVIEW_URL" ]; then
    PAGE_CONTENT="$CONTENT"
  else
    PAGE_CONTENT=$(curl -s --max-time 30 "$page_url" || true)
  fi
  if [ -z "$PAGE_CONTENT" ]; then
    echo "- ❌ Couldn't fetch $page_url" >> $REPORT_FILE
    ASSETS_FAILED=$((ASSETS_FAILED + 1))
    continue
  fi

  ASSETS=$(
    {
      grep -oE 'href="[^"]*\.css"' <<< "$PAGE_CONTENT" || true
      grep -oE 'src="[^"]*\.js"' <<< "$PAGE_CONTENT" || true
      grep -oE '(src|href)="[^"]*\.(png|jpg|jpeg|webp|ico)"' <<< "$PAGE_CONTENT" || true
      grep -oE 'data-[^=]*="[^"]*\.(png|jpg|jpeg|webp|ico)"' <<< "$PAGE_CONTENT" || true
    } | cut -d'"' -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u
  )
  while IFS= read -r asset; do
    [ -n "$asset" ] || continue
    ASSET_URL=$(resolve_url "$asset" "$page_url")
    [ -n "$ASSET_URL" ] || continue
    # Most assets are on every page: check each once
    [ -z "${CHECKED[$ASSET_URL]}" ] || continue
    CHECKED[$ASSET_URL]=1
    ASSETS_TOTAL=$((ASSETS_TOTAL + 1))
    CODE=$(http_status "$ASSET_URL")
    if [ "$CODE" != 200 ]; then
      echo "- ❌ $asset (HTTP $CODE) on $page_url" >> $REPORT_FILE
      ASSETS_FAILED=$((ASSETS_FAILED + 1))
    fi
  done <<< "$ASSETS"
done < <(
  echo "$PREVIEW_URL"
  while IFS= read -r page; do
    [ -n "$page" ] && resolve_url "$page" "$PREVIEW_URL"
  done <<< "$DISCOVERED_PAGES"
)

if [ $ASSETS_FAILED -gt 0 ]; then
  echo "- ❌ $ASSETS_FAILED of $ASSETS_TOTAL assets failed to load, on $PAGE_COUNT pages" >> $REPORT_FILE
  VERIFICATION_PASSED=false
else
  echo "- ✅ All $ASSETS_TOTAL assets loaded, on $PAGE_COUNT pages" >> $REPORT_FILE
fi
echo "" >> $REPORT_FILE

# 4. Links and assets across the whole site, with muffet
echo "## 4. Link and Asset Verification (muffet)" >> $REPORT_FILE
if "$SCRIPT_DIR/run-muffet.sh" "$PREVIEW_URL" muffet-report.json; then
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
  # Each broken link is a tab-indented "<status or error> <URL>" line
  # under the page it's on
  BROKEN=$(grep -c $'^\t' muffet-report.txt || true)
  echo "- ❌ muffet found $BROKEN broken links or assets:" >> $REPORT_FILE
  echo "\`\`\`" >> $REPORT_FILE
  head -60 muffet-report.txt >> $REPORT_FILE
  if [ "$(wc -l < muffet-report.txt)" -gt 60 ]; then
    echo "... (the full list is in the workflow run's log)" >> $REPORT_FILE
  fi
  echo "\`\`\`" >> $REPORT_FILE
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
LOAD_TIME=$(curl -s --max-time 30 -w "%{time_total}" -o /dev/null "$PREVIEW_URL" || echo 30)
echo "- Page load time: ${LOAD_TIME}s" >> $REPORT_FILE

if (( $(echo "$LOAD_TIME < 5.0" | bc -l) )); then
  echo "- ✅ Load time acceptable" >> $REPORT_FILE
else
  echo "- ⚠️  Load time may be slow" >> $REPORT_FILE
fi
echo "" >> $REPORT_FILE

# 6. Mobile responsiveness check
echo "## 6. Mobile Responsiveness" >> $REPORT_FILE
MOBILE_CONTENT=$(curl -s --max-time 30 -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15" "$PREVIEW_URL" || true)

if grep -q "viewport" <<< "$MOBILE_CONTENT"; then
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
  echo "verification_status=success" >> "$GITHUB_OUTPUT"
else
  echo "❌ **Some verification checks failed**" >> $REPORT_FILE
  echo "verification_status=failed" >> "$GITHUB_OUTPUT"
fi

# Save the report for the comment: kept well under GitHub's 65536
# character limit, with a delimiter no report line can be
DELIMITER="REPORT_$(openssl rand -hex 16)"
{
  echo "report_content<<$DELIMITER"
  head -c 60000 $REPORT_FILE
  if [ "$(wc -c < $REPORT_FILE)" -gt 60000 ]; then
    printf '\n\n... (truncated; the full report is in the workflow run log)'
  fi
  echo ""
  echo "$DELIMITER"
} >> "$GITHUB_OUTPUT"

# Show summary
echo "Verification completed. Status: $VERIFICATION_PASSED"
cat $REPORT_FILE
echo "Full muffet failures:"
cat muffet-report.txt
