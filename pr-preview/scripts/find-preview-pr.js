/**
 * find-pr action (Stage 2, workflow_run): finds the pull request a Stage 1
 * run was for, and works out what the later jobs need, so none of it comes
 * from the pull request's own code.
 *
 * SECURITY: Uses only trusted data. GitHub leaves workflow_run.pull_requests
 * empty for fork PRs, so look up the open PR whose head is the triggering
 * run's repository and branch, and require its head SHA to be the commit
 * Stage 1 ran on.
 *
 * Needs PREVIEW_BASE_URL in the environment.
 *
 * Outputs:
 *   found           'true' if there is an open PR to deploy
 *   number, sha     the PR and its head commit
 *   theme_sha       the theme commit the PR's _theme submodule points at
 *   directory_name  e.g. pr-12
 *   preview_url     e.g. https://preview.wafer.space/pr-12/
 *   baseurl         Jekyll's --baseurl, e.g. /pr-12
 */

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
  console.log(`PR #${pr.number} from ${headRepo} at ${pr.head.sha}`);

  const { data: theme } = await github.rest.repos.getContent({
    owner: run.head_repository.owner.login,
    repo: run.head_repository.name,
    path: '_theme',
    ref: pr.head.sha
  });
  if (theme.type !== 'submodule' || !/^[0-9a-f]{40}$/.test(theme.sha)) {
    throw new Error(`_theme is not a submodule at ${pr.head.sha}`);
  }

  if (!/^https:\/\/[A-Za-z0-9.-]+(\/[A-Za-z0-9._-]+)*\/?$/.test(process.env.PREVIEW_BASE_URL)) {
    throw new Error(`Invalid PREVIEW_BASE_URL: ${process.env.PREVIEW_BASE_URL}`);
  }
  const baseUrl = process.env.PREVIEW_BASE_URL.replace(/\/+$/, '');
  // '' for https://preview.wafer.space, '/repo' for a project Pages site
  const basePath = new URL(baseUrl).pathname.replace(/\/+$/, '');
  const directoryName = `pr-${pr.number}`;

  core.setOutput('found', 'true');
  core.setOutput('number', pr.number.toString());
  core.setOutput('sha', pr.head.sha);
  core.setOutput('theme_sha', theme.sha);
  core.setOutput('directory_name', directoryName);
  core.setOutput('preview_url', `${baseUrl}/${directoryName}/`);
  core.setOutput('baseurl', `${basePath}/${directoryName}`);
};
