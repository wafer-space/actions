/**
 * deploy action: posts, or updates, the pull request's preview comment.
 *
 * Needs PR_NUMBER, PREVIEW_URL, HEAD_SHA and DEPLOYED ('true' or 'false').
 */

const MARKER = '<!-- PR_PREVIEW_COMMENT -->';

module.exports = async function commentPreviewStatus(github, context) {
  const prNumber = Number(process.env.PR_NUMBER);
  const previewUrl = process.env.PREVIEW_URL;
  const commit = process.env.HEAD_SHA.substring(0, 7);
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;

  const body = process.env.DEPLOYED === 'true'
    ? `${MARKER}\n## ✅ Preview deployed\n\n${previewUrl} (commit \`${commit}\`)\n\nIt's removed when the PR closes.`
    : `${MARKER}\n## ❌ Preview deployment failed\n\nCommit \`${commit}\` wasn't served at ${previewUrl} in time. See the [workflow run](${runUrl}).`;

  const comments = await github.paginate(github.rest.issues.listComments, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: prNumber,
    per_page: 100
  });
  const existing = comments.find(c => c.user.type === 'Bot' && c.body.includes(MARKER));
  if (existing) {
    await github.rest.issues.updateComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: existing.id,
      body
    });
  } else {
    await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: prNumber,
      body
    });
  }
};
