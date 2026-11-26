#!/usr/bin/env python3
"""Checks muffet's JSON report on the test site lists the links that
worked, not only the broken ones: summarise-muffet.py's TLS certificate
warnings come from those (its https_hosts), and the failures test can't
see them.

Usage: check-report.py REPORT_JSON URL_SUFFIX...
Fails unless each URL_SUFFIX ends the URL of a link the report lists
without an error.
"""

import json
import sys


def main():
    report, *suffixes = sys.argv[1:]
    with open(report, encoding="utf-8") as f:
        pages = json.load(f)
    working = {link["url"] for page in pages for link in page.get("links", []) if "error" not in link}
    missing = [suffix for suffix in suffixes if not any(url.endswith(suffix) for url in working)]
    if missing:
        print(f"muffet's report doesn't list these working links: {', '.join(missing)}", file=sys.stderr)
        return 1
    print(f"muffet's report lists working links, including {', '.join(suffixes)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
