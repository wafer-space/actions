# pr-preview

Actions that build, deploy and check a preview site for each pull request to [wafer-space.github.io](https://github.com/wafer-space/wafer-space.github.io), including pull requests from forks, without the pull request's code running anywhere near a secret.

## How the website's workflows use them

```
pull_request ─▶ Stage 1: pr-preview-build.yml        one no-op step, no permissions
                       │ finishing triggers
                       ▼
workflow_run ─▶ Stage 2: pr-preview-deploy.yml (runs from the default branch)
                  find-pr        read-only                  finds the PR, theme commit, URLs
                  fetch-theme    JEKYLL_THEME_KEY           theme ─▶ artifact
                  build          NO secrets, contents:read  PR + theme ─▶ site artifact
                  deploy         PREVIEW_KEY                site artifact ─▶ preview repo;
                                                            comment and "PR preview" status
                       │ workflow_dispatch
                       ▼
                preview-verification.yml
                  verify                                    link check; comment and
                                                            "PR preview / link check" status
```

`cleanup-previews.yml` uses `cleanup` to remove closed pull requests' previews.

Only `build` runs the pull request's code (its content, plugins and Gemfile). No other action runs anything from the pull request.

Results are reported as commit statuses on the pull request's head commit as well as comments, so they show in its checks and can be made required. If the build fails, `deploy` still runs, to report that.

`deploy` checks that the pull request is still at the commit it built before each push, so a slow run for an older commit can't replace a newer preview. It waits until Pages serves the pages generated from that commit, then reports. Deploys and cleanups push to the same repository, so each retries from the new `main` if its push is rejected.

## The theme

`fetch-theme` fetches the commit the pull request's `_theme` submodule points at. GitHub serves every commit in a fork network from each of its repositories, so a pull request can point `_theme` at a commit in the author's own fork of the theme, and the website's key fetches it from the theme repository.

The pull request's code can read the theme, and could publish it, or anything else, on the preview site. That's accepted: the theme isn't secret enough to matter, and the preview site isn't trusted. The theme artifact is likewise downloadable by anyone signed in to GitHub, for its one-day retention.

## Security model

- **The pull request is identified from trusted data only.** `find-pr` uses the `workflow_run` event's head repository, branch and SHA, which GitHub sets, and checks them against the API. Stage 1 runs the pull request's own copy of its workflow, so nothing it produces is used.
- **The build has nothing to steal.** Its job gets no secrets and a read-only token. The private theme arrives as files from `fetch-theme`, never the key.
- **The built site is data.** `deploy` copies the artifact into the preview repository and runs nothing from it; it refuses symlinks and removes `.git` directories.
- **No Actions caches.** Jobs in a `workflow_run` workflow share the default branch's cache scope, so `build` could write a poisoned cache for anything on the default branch that restores one. Nothing does: `build` uses no cache, and the website's production build doesn't either. **Don't add caching to the website's workflows.**
- **Untrusted values go through `env:`**, never `${{ }}` inside a script, and every action used here is pinned to a commit SHA.

Previews are served from one domain, so a pull request's HTML and JavaScript share an origin with the other previews. Don't treat the preview site as trusted.

## muffet

`verify` installs the [muffet](https://github.com/raviqqe/muffet) link checker from [`scripts/install-verification-tools.sh`](scripts/install-verification-tools.sh) and runs it with [`scripts/run-muffet.sh`](scripts/run-muffet.sh). The calling workflow passes its list of URLs to skip as `muffet-excludes`.

## Copies of the website

A copy of the website in someone's own account (a fork of wafer-space.github.io) runs these workflows too. There they use the owner's own fork of the theme and deploy to the owner's own copy of the preview repository, and only if configured: the website's workflows describe how. A copy of the preview repository mustn't keep the original's `CNAME`, so `deploy` and `cleanup` remove a `CNAME` that doesn't match the preview base URL's host.

## Changing these actions

Open a pull request here. Once it merges, update the commit SHAs in the website's workflows. To test an unmerged change, point a copy of the website at the branch's head commit.
