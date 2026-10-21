#!/usr/bin/env python3
"""Update the pinned muffet version and checksum.

pr-preview/scripts/install-verification-tools.sh installs muffet from a
pinned release:

    MUFFET_VERSION="v2.11.6"
    MUFFET_SHA256="<sha256 of muffet_linux_amd64.tar.gz>"

This script finds the newest muffet release that is newer than the pinned
one and at least --min-age-days old, downloads its muffet_linux_amd64.tar.gz,
checks its SHA256 against the release's own checksums file, and rewrites
MUFFET_VERSION and MUFFET_SHA256 in the install script.

It never runs the new binary: CI does, on the pull request
(tests/test-muffet.sh).

Writes updated/version/previous_version/release_url to $GITHUB_OUTPUT when
set. Uses only the standard library plus the `gh` CLI (for authenticated
GitHub API requests), so it runs on a bare GitHub runner.
"""

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request

REPO = "raviqqe/muffet"
ASSET = "muffet_linux_amd64.tar.gz"
VERSION_RE = re.compile(r'^(\s*MUFFET_VERSION=")(v[0-9][^"]*)(")$', re.M)
SHA256_RE = re.compile(r'^(\s*MUFFET_SHA256=")([0-9a-f]{64})(")$', re.M)
# The tag ends up in a commit message and the install script
TAG_RE = re.compile(r"v\d+\.\d+\.\d+")


def parse_version(tag):
    return tuple(int(part) for part in re.findall(r"\d+", tag))


def single_match(pattern, text, what, where):
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        sys.exit(f"Expected exactly one {what} in {where}, found {len(matches)}")
    return matches[0]


def releases():
    out = subprocess.run(
        ["gh", "api", f"repos/{REPO}/releases?per_page=30"],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


def newest_eligible(all_releases, current, min_age):
    """The newest full release newer than current and at least min_age old."""
    now = datetime.datetime.now(datetime.timezone.utc)
    eligible = []
    for release in all_releases:
        tag = release["tag_name"]
        if release["draft"] or release["prerelease"] or not TAG_RE.fullmatch(tag):
            continue
        if parse_version(tag) <= parse_version(current):
            continue
        published = datetime.datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
        if now - published < min_age:
            print(f"{tag} is only {(now - published).days} days old, skipping it for now")
            continue
        eligible.append(release)
    return max(eligible, key=lambda r: parse_version(r["tag_name"]), default=None)


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as resp:
        return resp.read()


def asset_url(release, name):
    asset = next((a for a in release["assets"] if a["name"] == name), None)
    if asset is None:
        sys.exit(f"{release['tag_name']} has no {name} asset")
    return asset["browser_download_url"]


def published_checksum(release):
    name = f"muffet_{release['tag_name'].lstrip('v')}_checksums.txt"
    for line in fetch(asset_url(release, name)).decode().splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == ASSET:
            return parts[0]
    sys.exit(f"{name} has no entry for {ASSET}")


def set_outputs(**outputs):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            for key, value in outputs.items():
                f.write(f"{key}={value}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("install_script", type=pathlib.Path,
                        help="the script with MUFFET_VERSION and MUFFET_SHA256")
    parser.add_argument("--min-age-days", type=int, default=7,
                        help="skip releases newer than this, to let problems surface first")
    args = parser.parse_args()

    text = args.install_script.read_text(encoding="utf-8")
    current = single_match(VERSION_RE, text, "MUFFET_VERSION", args.install_script).group(2)
    single_match(SHA256_RE, text, "MUFFET_SHA256", args.install_script)

    release = newest_eligible(releases(), current, datetime.timedelta(days=args.min_age_days))
    if release is None:
        print(f"Pinned: {current}; no newer release is {args.min_age_days} days old yet")
        set_outputs(updated="false")
        return
    version = release["tag_name"]
    print(f"Pinned: {current}, updating to {version}")

    expected = published_checksum(release)
    actual = hashlib.sha256(fetch(asset_url(release, ASSET))).hexdigest()
    if actual != expected:
        sys.exit(f"Checksum mismatch for {ASSET}: published {expected}, downloaded {actual}")
    print(f"{ASSET} matches the published SHA256 {expected}")

    text = VERSION_RE.sub(lambda m: f"{m.group(1)}{version}{m.group(3)}", text)
    text = SHA256_RE.sub(lambda m: f"{m.group(1)}{expected}{m.group(3)}", text)
    args.install_script.write_text(text, encoding="utf-8")
    print(f"Updated {args.install_script} from {current} to {version}")
    set_outputs(updated="true", version=version, previous_version=current,
                release_url=release["html_url"])


if __name__ == "__main__":
    main()
