# shellcheck shell=bash
# Sourced by deploy-preview.sh and cleanup-previews.sh: clones the preview
# repository and pushes changes to it.
#
# Needs PREVIEW_REPOSITORY, PREVIEW_BASE_URL and PREVIEW_KEY (a deploy key
# that can push to PREVIEW_REPOSITORY).

# Clones PREVIEW_REPOSITORY into ./preview-repo and changes into it
clone_preview_repo() {
  eval "$(ssh-agent -s)"
  printf '%s\n' "$PREVIEW_KEY" | ssh-add -
  mkdir -p ~/.ssh
  ssh-keyscan github.com >> ~/.ssh/known_hosts

  git clone -q "git@github.com:${PREVIEW_REPOSITORY}.git" preview-repo
  cd preview-repo || return 1
  git config user.name 'github-actions[bot]'
  git config user.email 'github-actions[bot]@users.noreply.github.com'
}

# push_preview_repo APPLY [CHECK]: on a fresh copy of main, runs APPLY,
# which makes the changes and sets COMMIT_MESSAGE, then commits and pushes.
# Other runs push to the same repository, so if the push is rejected it
# starts again from the new main. If CHECK is given it runs before each
# attempt, and when it fails nothing is pushed and SKIPPED is set to true.
# shellcheck disable=SC2034  # SKIPPED is read by the sourcing script
push_preview_repo() {
  local apply=$1 check=$2 host
  host=$(sed -E 's#^https://([^/]+).*#\1#' <<< "$PREVIEW_BASE_URL")
  SKIPPED=false
  for attempt in 1 2 3 4 5; do
    git fetch -q origin main
    git reset -q --hard origin/main
    git clean -qfdx
    if [ -n "$check" ] && ! "$check"; then
      SKIPPED=true
      return 0
    fi
    "$apply"
    # A fork of the preview repository mustn't claim the original's domain
    if [ -f CNAME ] && [ "$(tr -d '[:space:]' < CNAME)" != "$host" ]; then
      echo "Removing CNAME: it doesn't match $host"
      git rm -q CNAME
    fi

    git add -A
    if git diff --staged --quiet; then
      echo "No changes to commit"
      return 0
    fi
    git commit -q -m "$COMMIT_MESSAGE"
    if git push -q origin main; then
      return 0
    fi
    echo "Push rejected (attempt $attempt), retrying"
    sleep $((attempt * 5))
  done
  echo "Couldn't push after 5 attempts" >&2
  return 1
}
