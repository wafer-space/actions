/**
 * verify action: validates the inputs and looks up the pull request.
 *
 * Needs INPUT_PR_NUMBER and INPUT_PREVIEW_URL, and optionally
 * INPUT_HEAD_SHA (default: the PR's current head).
 * Outputs pr_number, preview_url, pr_title and head_sha.
 */

module.exports = async function getVerificationPrInfo(github, context, core) {
  const prNumber = process.env.INPUT_PR_NUMBER;
  const previewUrl = process.env.INPUT_PREVIEW_URL;
  if (!/^[0-9]{1,5}$/.test(prNumber)) {
    core.setFailed(`Invalid PR number: ${prNumber}`);
    return;
  }
  if (!/^https:\/\/[A-Za-z0-9.-]+(\/[A-Za-z0-9._\/-]*)?$/.test(previewUrl)) {
    core.setFailed(`Invalid preview URL: ${previewUrl}`);
    return;
  }

  const { data: pullRequest } = await github.rest.pulls.get({
    owner: context.repo.owner,
    repo: context.repo.repo,
    pull_number: Number(prNumber)
  });
  const headSha = process.env.INPUT_HEAD_SHA || pullRequest.head.sha;
  if (!/^[0-9a-f]{40}$/.test(headSha)) {
    core.setFailed(`Invalid head SHA: ${headSha}`);
    return;
  }

  console.log(`PR #${prNumber}: ${pullRequest.title}`);
  console.log(`Preview URL: ${previewUrl}`);
  console.log(`Expected commit: ${headSha}`);

  core.setOutput('pr_number', prNumber);
  core.setOutput('preview_url', previewUrl);
  core.setOutput('pr_title', pullRequest.title);
  core.setOutput('head_sha', headSha);
};
