/**
 * verify action: posts the verification report on the pull request,
 * archives the older verification comments, and sets the link check's
 * commit status.
 *
 * Only comments older than the new one are archived, so runs that finish
 * at the same time each leave the newest comment current.
 *
 * Needs PR_NUMBER, HEAD_SHA, VERIFICATION_STATUS (success or failed) and
 * REPORT_CONTENT.
 */

const MARKER = '<!-- VERIFICATION_COMMENT_MARKER -->';
const ARCHIVED = '**📋 Previous verification results (archived)**';
const STATUS_CONTEXT = 'PR preview / link check';
// The account GITHUB_TOKEN comments as
const BOT_LOGIN = 'github-actions[bot]';

module.exports = async function commentVerificationResults(github, context, core) {
  const { owner, repo } = context.repo;
  const prNumber = Number(process.env.PR_NUMBER);
  const passed = process.env.VERIFICATION_STATUS === 'success';
  const runUrl = `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`;

  const { data: newComment } = await github.rest.issues.createComment({
    owner, repo, issue_number: prNumber,
    body: `## ${passed ? '✅' : '❌'} Preview Site Verification ${passed ? 'PASSED' : 'FAILED'}

${process.env.REPORT_CONTENT}

---
<sub>🔍 Automated verification • [Run ${context.runId}](${runUrl}) • ${new Date().toISOString()}</sub>
${MARKER}`
  });

  // Before archiving, so a failure there can't leave the status pending
  await github.rest.repos.createCommitStatus({
    owner, repo,
    sha: process.env.HEAD_SHA,
    state: passed ? 'success' : 'failure',
    context: STATUS_CONTEXT,
    description: passed ? 'All checks passed' : 'Some checks failed',
    target_url: `${newComment.html_url}`
  });
  // So the verify action doesn't overwrite it if archiving fails
  core.setOutput('status-set', 'true');

  const comments = await github.paginate(github.rest.issues.listComments, {
    owner, repo, issue_number: prNumber, per_page: 100
  });
  // Ours only: another app's comment quoting the marker can't be edited
  const older = comments.filter(c =>
    c.id < newComment.id &&
    c.user.login === BOT_LOGIN &&
    c.body.includes(MARKER) &&
    !c.body.includes(ARCHIVED)
  );
  for (const comment of older) {
    const original = comment.body.replace(MARKER, '').trim();
    await github.rest.issues.updateComment({
      owner, repo, comment_id: comment.id,
      body: `${ARCHIVED}

<details>
<summary>Verification results from ${comment.created_at}</summary>

${original}

</details>

${MARKER}`
    });
  }
  core.info(`Posted comment ${newComment.id}, archived ${older.length} older ones`);
};
