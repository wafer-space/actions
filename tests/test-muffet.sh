#!/bin/bash
# Runs muffet the way the verify action does on tests/site, served
# locally, and checks that summarise-muffet.py lists exactly the broken
# links in tests/expected-failures.txt. This catches a muffet release that
# drops an option run-muffet.sh uses, stops crawling the pages it finds, or
# changes its JSON report.
#
# Needs muffet, python3 and curl. Usage: tests/test-muffet.sh [PORT]
set -e

TESTS="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$TESTS/../pr-preview/scripts"
PORT=${1:-8123}
URL="http://127.0.0.1:$PORT/"
OUT=$(mktemp -d)

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$TESTS/site" > "$OUT/server.log" 2>&1 &
SERVER=$!
# `|| true`: if the server already died, kill fails, and under set -e that
# would skip the cleanup and change the exit status
trap 'kill "$SERVER" || true; rm -rf "$OUT"' EXIT
for _ in {1..50}; do
  curl -sf -o /dev/null "$URL" && break
  sleep 0.1
done
# Fail clearly if it never came up, or exited because something else
# already has the port (curl would then have reached that instead)
if ! kill -0 "$SERVER" || ! curl -sf -o /dev/null "${URL}good.html"; then
  echo "The test site's server isn't serving $URL:" >&2
  cat "$OUT/server.log" >&2
  exit 1
fi

if MUFFET_EXCLUDES='.*excluded\.html.*' "$SCRIPTS/run-muffet.sh" "$URL" "$OUT/report.json"; then
  echo "muffet passed, but the test site has broken links" >&2
  exit 1
fi
python3 "$SCRIPTS/summarise-muffet.py" "$OUT/report.json" \
  --site-url "$URL" --failures "$OUT/failures.txt" --tls-warnings "$OUT/tls.md"

sed "s#@URL@#$URL#g" "$TESTS/expected-failures.txt" | sort > "$OUT/expected"
sort "$OUT/failures.txt" > "$OUT/actual"
if ! diff -u "$OUT/expected" "$OUT/actual"; then
  echo "muffet's broken links (+) differ from the expected ones (-)" >&2
  exit 1
fi
echo "muffet reported exactly the expected broken links"
python3 "$TESTS/check-report.py" "$OUT/report.json" good.html pixel.png
