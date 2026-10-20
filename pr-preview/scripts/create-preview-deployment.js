/**
 * deploy action: records the preview as a
 * GitHub deployment, so it shows in the PR's timeline and the repository's
 * environments. Failing to create it doesn't fail the workflow.
 *
 * Needs PR_NUMBER, HEAD_SHA and PREVIEW_URL in the environment.
 */

module.exports = async function createPreviewDeployment(github, context) {
  const prNumber = Number(process.env.PR_NUMBER);
  const sha = process.env.HEAD_SHA;
  const previewUrl = process.env.PREVIEW_URL;

  try {
    const { data: deployment } = await github.rest.repos.createDeployment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      ref: sha,
      environment: `pr-preview-${prNumber}`,
      transient_environment: true,
      production_environment: false,
      required_contexts: [],
      description: `PR #${prNumber} preview`,
      auto_merge: false
    });

    await github.rest.repos.createDeploymentStatus({
      owner: context.repo.owner,
      repo: context.repo.repo,
      deployment_id: deployment.id,
      state: 'success',
      environment_url: previewUrl,
      description: 'Preview deployment successful'
    });

    console.log(`Created deployment ${deployment.id} for PR #${prNumber}`);
  } catch (error) {
    console.error('Failed to create deployment:', error.message);
  }
};
