/**
 * verify action: sets the link check's commit status to failure when the
 * run ended before reporting (it failed early, was cancelled or timed out),
 * so the pending status the deploy action set doesn't stay pending.
 *
 * Needs HEAD_SHA: the commit checked, or '' if it was never worked out, in
 * which case there's nothing to set.
 */

const STATUS_CONTEXT = 'PR preview / link check';

module.exports = async function failLinkCheckStatus(github, context, core) {
  const sha = process.env.HEAD_SHA;
  if (!/^[0-9a-f]{40}$/.test(sha || '')) {
    core.warning('The link check stopped before it knew which commit it was checking, so no status was set');
    return;
  }
  const { owner, repo } = context.repo;
  await github.rest.repos.createCommitStatus({
    owner, repo, sha,
    state: 'failure',
    context: STATUS_CONTEXT,
    description: "The link check didn't finish",
    target_url: `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`
  });
};
