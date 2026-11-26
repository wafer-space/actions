#!/usr/bin/env python3
"""Opens or updates the pull request for a muffet update that
update-muffet.py has written to the working tree.

Run by update-muffet.yml after update-muffet.py reports an update, with
a GitHub App token in GH_TOKEN. Everything goes on one branch, so a newer
release replaces an unmerged update instead of opening a second pull
request. The branch is only rewritten when it would change and holds
nothing but the App's own commits, so a fix someone pushes to the update
pull request (say, to tests/expected-failures.txt) is never thrown away,
and an unchanged update doesn't re-run CI every week. A pull request for
this version that was closed without merging means the release was
declined, so it isn't opened again.

Needs GH_TOKEN, APP_SLUG, VERSION, PREVIOUS_VERSION, RELEASE_URL, BASE (the
branch the pull request targets) and GitHub's GITHUB_REPOSITORY and
GITHUB_REPOSITORY_OWNER.
"""

import json
import os
import subprocess
import sys

BRANCH = "automation/update-muffet"


def run(*args, check=True):
    print("+", " ".join(args), flush=True)
    return subprocess.run(args, check=check, text=True, stdout=subprocess.PIPE)


def gh_api(path, *args):
    """The GitHub API's JSON for path, or None if it is a 404."""
    result = subprocess.run(["gh", "api", path, *args], text=True, capture_output=True)
    if result.returncode != 0:
        if "HTTP 404" in result.stderr:
            return None
        sys.stderr.write(result.stderr)
        raise SystemExit(f"gh api {path} failed")
    return json.loads(result.stdout) if result.stdout.strip() else None


def main():
    env = os.environ
    repo, owner, base = env["GITHUB_REPOSITORY"], env["GITHUB_REPOSITORY_OWNER"], env["BASE"]
    version, previous, release_url = env["VERSION"], env["PREVIOUS_VERSION"], env["RELEASE_URL"]
    bot_user = f"{env['APP_SLUG']}[bot]"

    # Commit as the App's bot user, so the commits link to it
    bot_id = gh_api(f"users/{bot_user}")["id"]
    run("git", "config", "user.name", bot_user)
    run("git", "config", "user.email", f"{bot_id}+{bot_user}@users.noreply.github.com")
    run("git", "switch", "-c", BRANCH)
    run("git", "commit", "-am", f"CI: update muffet from {previous} to {version}")
    tree = run("git", "rev-parse", "HEAD^{tree}").stdout.strip()

    title = f"CI: update muffet to {version}"
    # By owner and branch: a fork's branch of the same name isn't ours
    head = f"{owner}:{BRANCH}"
    open_prs = gh_api(f"repos/{repo}/pulls?head={head}&state=open&per_page=10")
    if not open_prs:
        # Before pushing, so a declined update's branch isn't rewritten
        # whenever the base branch moves
        closed = gh_api(f"repos/{repo}/pulls?head={head}&state=closed&per_page=100")
        declined = [pr["number"] for pr in closed or [] if pr["title"] == title and not pr["merged_at"]]
        if declined:
            print(f"::notice::muffet {version} was declined in #{declined[0]} (closed without merging); "
                  "not opening it again")
            return 0

    pushed = False
    remote = gh_api(f"repos/{repo}/branches/{BRANCH}")
    if remote is None:
        push = ["git", "push", "origin", BRANCH]
    else:
        remote_sha = remote["commit"]["sha"]
        compare = gh_api(f"repos/{repo}/compare/{base}...{remote_sha}")
        # Author and committer: amending or rebasing the App's commit keeps
        # it as the author, and only shows the person as committer. One
        # that isn't linked to a GitHub user counts as someone else's
        others = [c["sha"][:7] for c in compare["commits"]
                  if (c.get("author") or {}).get("login") != bot_user
                  or (c.get("committer") or {}).get("login") != bot_user]
        if others:
            print(f"::warning::{BRANCH} has commits by someone other than {bot_user} "
                  f"({', '.join(others)}), so it isn't updated to muffet {version}. "
                  "Update it by hand, or delete the branch to let this start again.")
            return 0
        push = None if remote["commit"]["commit"]["tree"]["sha"] == tree else \
            ["git", "push", f"--force-with-lease={BRANCH}:{remote_sha}", "origin", BRANCH]
    if push:
        # git uses GH_TOKEN through gh's credential helper
        run("gh", "auth", "setup-git")
        run(*push)
        pushed = True
    else:
        print(f"{BRANCH} already has this update")

    body = (
        f"Updates the muffet link checker used by the `pr-preview/verify` action from {previous} to {version}.\n\n"
        f"Release notes: {release_url}\n\n"
        "`update-muffet.py` checked that `muffet_linux_amd64.tar.gz` matches the SHA256 in the release's "
        "published checksums file. CI's muffet job runs the new version on the test site.\n\n"
        "Opened automatically by `.github/workflows/update-muffet.yml`. If this release shouldn't be used, "
        "close this pull request without merging: it won't be opened again for this version.\n"
    )
    if open_prs:
        number = open_prs[0]["number"]
        if pushed:
            gh_api(f"repos/{repo}/pulls/{number}", "-X", "PATCH", "-f", f"title={title}", "-f", f"body={body}")
            print(f"Updated pull request #{number}")
        else:
            print(f"Pull request #{number} is already up to date")
        return 0

    run("gh", "pr", "create", "--repo", repo, "--base", base, "--head", BRANCH, "--title", title, "--body", body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
