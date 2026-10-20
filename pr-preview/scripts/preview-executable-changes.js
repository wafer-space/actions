/**
 * Finds the files a pull request changes that run during the preview
 * build: Jekyll plugins, and the workflows and scripts themselves.
 * find-pr won't let fork PRs that change any of these be built.
 */

const EXECUTABLE_PATTERNS = [
  /^_plugins\//,
  /^\.github\//,
];

async function listPrFiles(github, context, prNumber) {
  const files = await github.paginate(github.rest.pulls.listFiles, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    pull_number: prNumber,
    per_page: 100
  });
  return files.map(f => f.filename);
}

function executableFiles(filenames) {
  return filenames.filter(f => EXECUTABLE_PATTERNS.some(p => p.test(f)));
}

module.exports = { EXECUTABLE_PATTERNS, listPrFiles, executableFiles };
