#!/bin/bash
# Runs the muffet link checker on a site the way the verify action does,
# writing its JSON report to a file. Exits with muffet's status: non-zero
# if anything is broken. CI runs it on a test site too.
#
# Usage: run-muffet.sh URL REPORT_FILE
# MUFFET_EXCLUDES, if set, holds URL regular expressions to skip, one per
# line.
set -e

URL=$1
REPORT=$2

EXCLUDE_ARGS=()
while IFS= read -r pattern; do
  if [ -n "$pattern" ]; then
    EXCLUDE_ARGS+=("--exclude=$pattern")
  fi
done <<< "$MUFFET_EXCLUDES"

# Identify honestly as a link checker: Cloudflare-fronted sites
# (e.g. sourceforge.io, linuxgizmos.com) challenge requests that
# claim to be Chrome but don't behave like it.
# Invalid TLS certificates on linked sites are only warned about
# (by summarise-muffet.py), so muffet skips verification
muffet \
  --skip-tls-verification \
  --format=json \
  --verbose \
  --timeout=30 \
  --max-connections=10 \
  --max-connections-per-host=5 \
  --rate-limit=20 \
  --buffer-size=16384 \
  "${EXCLUDE_ARGS[@]}" \
  --header="User-Agent:Mozilla/5.0 (compatible; wafer.space-link-checker; +https://wafer.space/)" \
  --header="Accept:text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
  --header="Accept-Language:en-US,en;q=0.9" \
  --header="Accept-Encoding:gzip, deflate, br" \
  --header="Cache-Control:no-cache" \
  --header="Pragma:no-cache" \
  "$URL" > "$REPORT"
