#!/bin/bash
# Runs muffet the way the verify action does on tests/site, served
# locally, and checks that summarise-muffet.py lists exactly the broken
# links in tests/expected-failures.txt. This catches a muffet release that
# drops an option run-muffet.sh uses or changes its JSON report.
#
# Needs muffet and python3. Usage: tests/test-muffet.sh [PORT]
set -e

TESTS="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$TESTS/../pr-preview/scripts"
PORT=${1:-8123}
URL="http://127.0.0.1:$PORT/"
OUT=$(mktemp -d)

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$TESTS/site" > "$OUT/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER; rm -rf "$OUT"' EXIT
for _ in {1..50}; do
  curl -sf -o /dev/null "$URL" && break
  sleep 0.1
done

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
