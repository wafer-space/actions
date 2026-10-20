# pr-preview

Actions that build, deploy and check a preview site for each pull request to [wafer-space.github.io](https://github.com/wafer-space/wafer-space.github.io), including pull requests from forks, without letting a pull request's code near a secret.

## How the website's workflows use them

```
pull_request ─▶ Stage 1: pr-preview-build.yml
                  (one no-op step)                   no secrets, no permissions
                       │ finishing triggers
                       ▼
workflow_run ─▶ Stage 2: pr-preview-deploy.yml (runs from the default branch)
                  find-pr ───────┬──▶ fetch-theme   JEKYLL_THEME_KEY, runs no PR code
                                 │         │ theme artifact
                                 │         ▼
                                 ├──▶ build          NO secrets, runs the PR's content
                                 │         │ site artifact
                                 │         ▼
                                 ├──▶ deploy, comment PREVIEW_KEY, runs no PR code
                                 └──▶ comment (blocked)
                       │ workflow_dispatch
                       ▼
                Verification: preview-verification.yml
                  verify                              read-only, comments the report
```

| Action | Runs pull request code? | Needs |
|---|---|---|
| [`find-pr`](find-pr/action.yml) | no | read token |
| [`fetch-theme`](fetch-theme/action.yml) | no | theme deploy key |
| [`build`](build/action.yml) | **yes** | nothing: give its job no secrets and `contents: read` only |
| [`deploy`](deploy/action.yml) | no | preview repository deploy key, `deployments: write` |
| [`comment`](comment/action.yml) | no | `pull-requests: write` |
| [`update-index`](update-index/action.yml) | no | a checkout of the preview repository |
| [`verify`](verify/action.yml) | no | `pull-requests: write` |

## Security model

- **Identify the pull request from trusted data only.** `find-pr` uses the `workflow_run` event's head repository, branch and SHA (which GitHub sets, not Stage 1), and checks them against the API. Stage 1 runs the pull request's own copy of its workflow, so nothing it produces is used.
- **Only `build` runs the pull request's content**, in a job with no secrets. The theme it needs is fetched by `fetch-theme` and handed over as files, so the theme deploy key never reaches it. The pull request's content can read the theme, as it always could through Liquid includes.
- **The built site is data.** `deploy` copies the artifact into the preview repository and runs nothing from it; it refuses symlinks and removes `.git` directories. Every script and template it uses comes from this repository.
- **Fork pull requests that change `_plugins/` or `.github/` aren't built at all**, and for other fork pull requests `build` first puts back the default branch's `_plugins/` and `Gemfile`, removes `Gemfile.lock` and `.bundle/`, and stacks a config pinning `plugins_dir`, `source` and `destination`. The build has no secrets, so this is defence in depth: it stops a fork's code running even there.
- **No gem cache.** Jobs in a `workflow_run` workflow share the default branch's Actions cache scope, so `build` neither restores nor saves one, and the website's production build doesn't use one either: a pull request could otherwise poison it.
- **Untrusted values go through `env:`**, never `${{ }}` inside a script.

## Changing these actions

Open a pull request here. Once it merges, update the commit SHAs in the website's workflows. To test an unmerged change, point a fork of the website at the branch's head commit: its `PREVIEW_REPOSITORY` and `PREVIEW_BASE_URL` repository variables let it deploy to its own preview repository.
