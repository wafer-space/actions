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
                  deploy         PREVIEW_KEY                site artifact ─▶ preview repo, comment
                       │ workflow_dispatch
                       ▼
                preview-verification.yml
                  verify                                    link check, comments the report
```

`cleanup-previews.yml` uses `update-index` after removing closed PRs' previews.

Only `build` runs the pull request's code (its content, plugins and Gemfile). No other action runs anything from the pull request.

## Security model

- **The pull request is identified from trusted data only.** `find-pr` uses the `workflow_run` event's head repository, branch and SHA, which GitHub sets, and checks them against the API. Stage 1 runs the pull request's own copy of its workflow, so nothing it produces is used.
- **The build has nothing to steal.** Its job gets no secrets and a read-only token. The private theme arrives as files from `fetch-theme`, never the key. The pull request's code can read the theme, as it always could through Liquid includes.
- **The built site is data.** `deploy` copies the artifact into the preview repository and runs nothing from it; it refuses symlinks and removes `.git` directories.
- **No Actions caches.** Jobs in a `workflow_run` workflow share the default branch's cache scope, so `build` could write a poisoned cache for anything on the default branch that restores one. Nothing does: `build` uses no cache, and the website's production build doesn't either. **Don't add caching to the website's workflows.**
- **Untrusted values go through `env:`**, never `${{ }}` inside a script, and every action used here is pinned to a commit SHA.

Previews are served from one domain, so a pull request's HTML and JavaScript share an origin with the other previews. Don't treat the preview site as trusted.

## muffet

`verify` installs the [muffet](https://github.com/raviqqe/muffet) link checker from [`scripts/install-verification-tools.sh`](scripts/install-verification-tools.sh). The calling workflow passes its list of URLs to skip as `muffet-excludes`.

## Changing these actions

Open a pull request here. Once it merges, update the commit SHAs in the website's workflows. To test an unmerged change, point a fork of the website at the branch's head commit: its `PREVIEW_REPOSITORY` and `PREVIEW_BASE_URL` repository variables let it deploy to its own preview repository.
