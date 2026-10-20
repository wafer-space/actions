/**
 * check-changes action (Stage 1, pull_request): tells fork PR authors
 * early when Stage 2 will refuse to build their preview. Informational
 * only: find-pr checks again for itself in Stage 2.
 */

const { listPrFiles, executableFiles } = require('./preview-executable-changes.js');

module.exports = async function checkPrExecutableChanges(github, context, core) {
  const pr = context.payload.pull_request;
  const isFork = pr.head.repo.full_name !== `${context.repo.owner}/${context.repo.repo}`;
  console.log(`PR #${pr.number} from ${pr.head.repo.full_name} at ${pr.head.sha}`);
  console.log(isFork ? '🌍 External contributor (fork PR)' : '🏠 Internal contributor');

  const dangerousFiles = executableFiles(await listPrFiles(github, context, pr.number));

  if (dangerousFiles.length === 0) {
    console.log('✅ No executable code changes');
  } else if (isFork) {
    core.warning(`Executable code modified, so Stage 2 will not deploy a preview for this fork PR: ${dangerousFiles.join(', ')}`);
  } else {
    console.log(`Executable code modified (allowed for internal PRs): ${dangerousFiles.join(', ')}`);
  }
};
