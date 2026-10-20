/**
 * comment action: the PR comments about a preview.
 *
 * deployed() and blocked() update the existing "Preview Deployment"
 * comment, or create one. failed() always adds a new comment.
 *
 * Environment:
 *   PR_NUMBER        all
 *   PREVIEW_URL, HEAD_SHA, IS_FORK, GEMFILE_MODIFIED   deployed()
 *   ERROR_MESSAGE    failed()
 *   DANGEROUS_FILES  blocked(), one per line
 */

function prNumber() {
  const n = Number(process.env.PR_NUMBER);
  if (!Number.isInteger(n) || n < 1) {
    throw new Error(`Invalid PR_NUMBER: ${process.env.PR_NUMBER}`);
  }
  return n;
}

async function upsertComment(github, context, issueNumber, body) {
  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: issueNumber,
  });

  const botComment = comments.find(comment =>
    comment.user.type === 'Bot' &&
    comment.body.includes('Preview Deployment')
  );

  if (botComment) {
    await github.rest.issues.updateComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: botComment.id,
      body
    });
    console.log(`Updated comment ${botComment.id} on PR #${issueNumber}`);
  } else {
    await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: issueNumber,
      body
    });
    console.log(`Created new comment on PR #${issueNumber}`);
  }
}

async function deployed(github, context) {
  const previewUrl = process.env.PREVIEW_URL;
  const commitSha = process.env.HEAD_SHA.substring(0, 7);
  const isFork = process.env.IS_FORK === 'true';
  const gemfileModified = process.env.GEMFILE_MODIFIED === 'true';

  const forkBadge = isFork ? '🌍 **External Contributor** (fork PR)' : '🏠 Internal PR';

  // Add Gemfile security notice for fork PRs with dependency changes
  let securityNotice = '';
  if (isFork && gemfileModified) {
    securityNotice = `\n\n> **🔒 Security Notice:** This PR includes changes to \`Gemfile\` or \`Gemfile.lock\`. For security, the preview was built using the trusted dependencies from the \`main\` branch. If you need to update dependencies, please work with a maintainer to submit those changes separately from an internal branch.\n`;
  }

  const body = [
    '## ✅ Preview Deployment Ready!',
    '',
    forkBadge,
    '',
    '| Preview URL | Commit |',
    '|-------------|--------|',
    `| [View Preview](${previewUrl}) | \`${commitSha}\` |`,
    '',
    '**🎉 Your preview has been deployed successfully!**',
    '',
    `The preview site is available at: ${previewUrl}${securityNotice}`,
    '',
    '---',
    '<sub>⚡ Deployed via workflow_run (two-stage deployment) • Preview will be removed when PR is closed</sub>',
  ].join('\n');

  await upsertComment(github, context, prNumber(), body);
}

async function failed(github, context) {
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  await github.rest.issues.createComment({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: prNumber(),
    body: `## ❌ Preview Deployment Failed\n\n**Error:** ${process.env.ERROR_MESSAGE}\n\nPlease check the [workflow logs](${runUrl}) for details.`
  });
}

async function blocked(github, context) {
  const body = [
    '## 🚫 Preview Deployment Blocked',
    '',
    'This pull request modifies executable code that runs during the preview build:',
    '',
    '```',
    process.env.DANGEROUS_FILES,
    '```',
    '',
    '**Why?** For security, fork PRs that modify files in `_plugins/` or `.github/` cannot receive automatic preview deployments. These files run code during the preview build, which runs in this repository\'s trusted workflow.',
    '',
    '**What to do:**',
    '- If you only need content changes previewed, please move executable code changes to a separate PR',
    '- A maintainer can review the executable changes and deploy a preview manually',
    '',
    '---',
    '<sub>🔒 Blocked by security gate (two-stage deployment)</sub>',
  ].join('\n');

  await upsertComment(github, context, prNumber(), body);
}

module.exports = { deployed, failed, blocked };
