/**
 * deploy action: posts, or updates, the pull request's preview comment,
 * and sets the "PR preview" commit status on its head commit so the result
 * shows in the pull request's checks. Once deployed, it also sets the
 * link check's status to pending until the verify action reports.
 *
 * Needs PR_NUMBER, PREVIEW_URL, HEAD_SHA and RESULT: deployed, not-served,
 * push-failed or build-failed.
 */

const MARKER = '<!-- PR_PREVIEW_COMMENT -->';
const STATUS_CONTEXT = 'PR preview';
const LINK_CHECK_CONTEXT = 'PR preview / link check';
// The account GITHUB_TOKEN comments as
const BOT_LOGIN = 'github-actions[bot]';

module.exports = async function commentPreviewStatus(github, context) {
  const { owner, repo } = context.repo;
  const prNumber = Number(process.env.PR_NUMBER);
  const previewUrl = process.env.PREVIEW_URL;
  const sha = process.env.HEAD_SHA;
  const commit = sha.substring(0, 7);
  const runUrl = `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`;

  const results = {
    'deployed': {
      state: 'success',
      description: 'Preview deployed',
      targetUrl: previewUrl,
      body: `## ✅ Preview deployed\n\n${previewUrl} (commit \`${commit}\`)\n\nIt's removed when the PR closes.`
    },
    'not-served': {
      state: 'failure',
      description: "Preview wasn't served in time",
      targetUrl: runUrl,
      body: `## ❌ Preview deployment failed\n\nCommit \`${commit}\` wasn't served at ${previewUrl} in time. See the [workflow run](${runUrl}).`
    },
    'build-failed': {
      state: 'failure',
      description: "Preview build failed",
      targetUrl: runUrl,
      body: `## ❌ Preview build failed\n\nCommit \`${commit}\` didn't build. See the [workflow run](${runUrl}).`
    },
    'push-failed': {
      state: 'failure',
      description: "Preview couldn't be deployed",
      targetUrl: runUrl,
      body: `## ❌ Preview deployment failed\n\nCommit \`${commit}\` built, but couldn't be deployed to the preview site. See the [workflow run](${runUrl}).`
    }
  };
  const result = results[process.env.RESULT];
  if (!result) {
    throw new Error(`Unknown RESULT: ${process.env.RESULT}`);
  }

  await github.rest.repos.createCommitStatus({
    owner, repo, sha,
    state: result.state,
    context: STATUS_CONTEXT,
    description: result.description,
    target_url: result.targetUrl
  });

  const body = `${MARKER}\n${result.body}`;
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner, repo, issue_number: prNumber, per_page: 100
  });
  // Ours only: another app's comment quoting the marker can't be edited
  const existing = comments.find(c => c.user.login === BOT_LOGIN && c.body.includes(MARKER));
  if (existing) {
    await github.rest.issues.updateComment({ owner, repo, comment_id: existing.id, body });
  } else {
    await github.rest.issues.createComment({ owner, repo, issue_number: prNumber, body });
  }

  // Last, so nothing here can fail after it and leave the link check's
  // status pending with no link check started
  if (process.env.RESULT === 'deployed') {
    await github.rest.repos.createCommitStatus({
      owner, repo, sha,
      state: 'pending',
      context: LINK_CHECK_CONTEXT,
      description: 'Waiting for the link check'
    });
  }
};
