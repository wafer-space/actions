#!/bin/bash
# Writes index.html, the list of previews, in the current directory (a
# checkout of the preview repository) from its pr-<number> directories.
#
# Needs PREVIEW_BASE_URL, e.g. https://preview.wafer.space, or a project
# Pages site with a path such as https://user.github.io/preview.wafer.space.
set -e

TEMPLATE_FILE="$(dirname "$0")/../templates/preview-index.html"
PREVIEW_BASE_URL="${PREVIEW_BASE_URL%/}"
BASE_PATH=$(echo "$PREVIEW_BASE_URL" | sed -E 's#^https://[^/]+##')

# Only pr-<number> directories: the names are digits, so need no escaping
ITEMS=""
COUNT=0
for dir in $(find . -maxdepth 1 -type d -regex './pr-[0-9]+' -printf '%f\n' | sort -t- -k2 -n); do
  if [ -f "$dir/index.html" ]; then
    ITEMS+="<li><a href=\"$BASE_PATH/$dir/\">PR #${dir#pr-}</a><div class=\"preview-url\">$PREVIEW_BASE_URL/$dir/</div></li>"
    COUNT=$((COUNT + 1))
  fi
done
if [ "$COUNT" -eq 0 ]; then
  ITEMS="<script>document.getElementById('empty-state').style.display = 'block';</script>"
fi

sed "s|<!-- PREVIEW_ITEMS_PLACEHOLDER -->|$ITEMS|" "$TEMPLATE_FILE" > index.html
echo "Generated preview index with $COUNT previews"
