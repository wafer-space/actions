/**
 * find-pr action (Stage 2, workflow_run): finds the pull request a Stage 1 run
 * was for, decides whether it is safe to build, and works out everything
 * the later jobs need, so none of it comes from the PR's own code.
 *
 * SECURITY: Uses only trusted data. GitHub leaves workflow_run.pull_requests
 * empty for fork PRs, so look up the open PR whose head is the triggering
 * run's repository and branch, and require its head SHA to be the commit
 * Stage 1 ran on.
 *
 * Needs PREVIEW_REPOSITORY and PREVIEW_BASE_URL in the environment.
 *
 * Outputs:
 *   found               'true' if there is an open PR to deploy
 *   number, sha, title, is_fork
 *   deployment_allowed  'false' for fork PRs that change executable code
 *   dangerous_files     those files, one per line
 *   gemfile_modified    'true' if the PR changes Gemfile or Gemfile.lock
 *   theme_sha           the theme commit the PR's _theme submodule points at
 *   directory_name      e.g. pr-12
 *   slugified_name      e.g. pr-12-fix-the-faq, for a redirect
 *   base_url            PREVIEW_BASE_URL without a trailing slash
 *   base_path           '' or its path, e.g. /preview.wafer.space
 *   baseurl_path        Jekyll's --baseurl, e.g. /pr-12
 */

const { listPrFiles, executableFiles } = require('./preview-executable-changes.js');
const generatePrDirectoryName = require('./generate-pr-directory-name.js');

function previewLocation(core, prNumber, prTitle) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(process.env.PREVIEW_REPOSITORY)) {
    throw new Error(`Invalid PREVIEW_REPOSITORY: ${process.env.PREVIEW_REPOSITORY}`);
  }
  if (!/^https:\/\/[A-Za-z0-9.-]+(\/[A-Za-z0-9._-]+)*\/?$/.test(process.env.PREVIEW_BASE_URL)) {
    throw new Error(`Invalid PREVIEW_BASE_URL: ${process.env.PREVIEW_BASE_URL}`);
  }
  const baseUrl = process.env.PREVIEW_BASE_URL.replace(/\/+$/, '');
  // '' for https://preview.wafer.space, '/repo' for a project Pages site
  const basePath = new URL(baseUrl).pathname.replace(/\/+$/, '');

  // Main directory uses just PR number for simplicity
  const directoryName = `pr-${prNumber}`;
  // Slugified version for user-friendly redirect
  const slugifiedName = generatePrDirectoryName(prNumber, prTitle);

  console.log(`Main directory: ${directoryName}`);
  console.log(`Slugified redirect: ${slugifiedName}`);
  console.log(`Preview URL: ${baseUrl}/${directoryName}/`);

  core.setOutput('directory_name', directoryName);
  core.setOutput('slugified_name', slugifiedName);
  core.setOutput('base_url', baseUrl);
  core.setOutput('base_path', basePath);
  core.setOutput('baseurl_path', `${basePath}/${directoryName}`);
}

async function themeCommit(github, run) {
  const { data } = await github.rest.repos.getContent({
    owner: run.head_repository.owner.login,
    repo: run.head_repository.name,
    path: '_theme',
    ref: run.head_sha
  });
  if (data.type !== 'submodule' || !/^[0-9a-f]{40}$/.test(data.sha)) {
    throw new Error(`_theme is not a submodule at ${run.head_sha}`);
  }
  return data.sha;
}

module.exports = async function findPreviewPr(github, context, core) {
  const run = context.payload.workflow_run;
  const headRepo = run.head_repository.full_name;

  const prs = await github.paginate(github.rest.pulls.list, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    state: 'open',
    head: `${run.head_repository.owner.login}:${run.head_branch}`,
    per_page: 100
  });
  const pr = prs.find(p =>
    p.head.sha === run.head_sha && p.head.repo && p.head.repo.full_name === headRepo
  );
  if (!pr) {
    // A newer push (which gets its own run) or a closed PR
    core.notice(`No open PR from ${headRepo}:${run.head_branch} has head ${run.head_sha}; nothing to deploy`);
    core.setOutput('found', 'false');
    return;
  }

  const prNumber = pr.number;
  const prTitle = pr.title.slice(0, 100).replace(/[\r\n]/g, ' ');
  const isFork = headRepo !== `${context.repo.owner}/${context.repo.repo}`;
  core.setOutput('found', 'true');
  core.setOutput('number', prNumber.toString());
  core.setOutput('sha', pr.head.sha);
  core.setOutput('title', prTitle);
  core.setOutput('is_fork', isFork.toString());

  console.log(`PR #${prNumber} from ${headRepo} at ${pr.head.sha} (fork: ${isFork})`);

  const files = await listPrFiles(github, context, prNumber);
  core.setOutput('gemfile_modified', files.some(f => f === 'Gemfile' || f === 'Gemfile.lock').toString());

  // Fork PRs: block ones that change executable code
  const dangerousFiles = isFork ? executableFiles(files) : [];
  if (dangerousFiles.length > 0) {
    core.setOutput('deployment_allowed', 'false');
    core.setOutput('dangerous_files', dangerousFiles.join('\n'));
    core.warning(`🚫 Fork PR modifies executable code: ${dangerousFiles.join(', ')}`);
    return;
  }
  core.setOutput('deployment_allowed', 'true');
  console.log(isFork
    ? '✅ Fork PR — content-only changes — deployment allowed'
    : '✅ Internal PR — deployment always allowed');

  const themeSha = await themeCommit(github, run);
  console.log(`Theme commit: ${themeSha}`);
  core.setOutput('theme_sha', themeSha);

  previewLocation(core, prNumber, prTitle);
};
