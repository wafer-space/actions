# github-actions

Shared GitHub Actions for wafer-space repositories.

Reference them pinned to a full commit SHA, with the tag in a comment:

```yaml
- uses: wafer-space/github-actions/pr-preview/find-pr@<commit SHA>  # v1.0
```

A workflow that runs with secrets then runs exactly the code that was reviewed here, and a pull request to the calling repository can't change it.

## pr-preview

Builds a preview site for every pull request to [wafer-space.github.io](https://github.com/wafer-space/wafer-space.github.io), including pull requests from forks, and checks it. See [pr-preview/README.md](pr-preview/README.md).

## License

[Apache License 2.0](LICENSE)
