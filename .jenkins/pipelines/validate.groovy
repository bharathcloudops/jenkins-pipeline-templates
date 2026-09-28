//==============================================================================
// JENKINS PIPELINE TEMPLATE VALIDATION
//==============================================================================

@Library('jenkins-pipeline-templates@v1.4.0') _

repositoryValidationPipeline(
    githubRepository: 'bharathcloudops/jenkins-pipeline-templates',
    groovySearchPath: 'vars',
    shellSearchPath: '.',
    validationScript: 'resources/scripts/validate-library.sh',
    validateWorkflows: true
)