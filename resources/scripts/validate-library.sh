#!/usr/bin/env bash

#==============================================================================
# JENKINS SHARED LIBRARY VALIDATION
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# REPOSITORY PATHS
#==============================================================================

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

#==============================================================================
# REQUIRED LIBRARY FILES
#==============================================================================

required_files=(
  vars/containerImagePipeline.groovy
  vars/kubernetesApplicationPipeline.groovy
  vars/libraryScript.groovy
  vars/terraformPipeline.groovy
  vars/ociTerraformPipeline.groovy
  vars/repositoryValidationPipeline.groovy
  vars/shellPipeline.groovy
  vars/composePipeline.groovy
  vars/ociRunCommand.groovy
  vars/hostDeploymentPipeline.groovy
  vars/hostConfigDeploymentPipeline.groovy
  vars/hostConfigIngressPipeline.groovy
  vars/hostConfigNetworkPipeline.groovy
  vars/monitoringDeploymentPipeline.groovy
  vars/jenkinsDeploymentPipeline.groovy
  vars/releasePipeline.groovy
  vars/backupPipeline.groovy
  vars/githubStatus.groovy
  resources/scripts/tool-container.sh
  resources/scripts/container-image.sh
  resources/scripts/terraform.sh
  resources/scripts/oci-terraform.sh
  resources/scripts/oci-vault-secret.sh
  resources/scripts/actionlint.sh
  resources/scripts/groovy-validate.sh
  resources/scripts/shell-validate.sh
  resources/scripts/compose.sh
  resources/scripts/oci-run-command.sh
  resources/scripts/release.sh
  resources/scripts/github-status.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$repository_root/$required_file" ]]; then
    printf 'Missing required library file: %s\n' "$required_file" >&2
    exit 1
  fi
done

#==============================================================================
# BLOCK COMMENT VALIDATION
#==============================================================================

while IFS= read -r source_file; do
  if ! grep -Fq '==============================================================================' "$source_file"; then
    printf 'Missing block section comment: %s\n' "$source_file" >&2
    exit 1
  fi
done < <(find "$repository_root/vars" "$repository_root/resources" -type f -print)

#==============================================================================
# MUTATION GUARD VALIDATION
#==============================================================================

grep -Fq 'TERRAFORM_APPROVED_PLAN_SHA256' "$repository_root/resources/scripts/terraform.sh"
grep -Fq 'DEPLOY_SCRIPT is required' "$repository_root/resources/scripts/compose.sh"
grep -Fq "docker_socket_gid=\$(stat" "$repository_root/resources/scripts/container-image.sh"
grep -Fq -- "--group-add \"\$docker_socket_gid\"" "$repository_root/resources/scripts/container-image.sh"
grep -Fq -- '--driver docker-container' "$repository_root/resources/scripts/container-image.sh"
grep -Fq -- '--provenance=mode=max --sbom=true --push' "$repository_root/resources/scripts/container-image.sh"
grep -Fq 'trap cleanup_builder EXIT' "$repository_root/resources/scripts/container-image.sh"
grep -Fq 'build job: configuration.deploymentJob, wait: false' "$repository_root/vars/containerImagePipeline.groovy"
grep -Fq 'OCI_RUN_COMMAND_ACTION' "$repository_root/resources/scripts/oci-run-command.sh"
grep -Fq 'instance-principal' "$repository_root/vars/ociRunCommand.groovy"
grep -Fq 'RUN_COMMAND_ADDITIONAL_VAULT_SECRET_NAME' "$repository_root/resources/scripts/oci-run-command.sh"
grep -Fq 'RUN_COMMAND_TERTIARY_VAULT_SECRET_NAME' "$repository_root/resources/scripts/oci-run-command.sh"
grep -Fq 'scripts/prepare-tool-inputs.sh' "$repository_root/vars/hostConfigDeploymentPipeline.groovy"
grep -Fq "['backstage', 'github-runner', 'jenkins', 'monitoring']" "$repository_root/vars/hostConfigDeploymentPipeline.groovy"
grep -Fq "backstage: 'BACKSTAGE_RESTORE_ARCHIVE'" "$repository_root/vars/hostConfigDeploymentPipeline.groovy"
grep -Fq 'configuration.validationMarker' "$repository_root/vars/hostConfigDeploymentPipeline.groovy"
grep -Fq 'prependAction: false' "$repository_root/vars/hostConfigDeploymentPipeline.groovy"
grep -Fq 'target.arguments[0] = selectedAction' "$repository_root/vars/hostConfigDeploymentPipeline.groovy"
grep -Fq 'targetsJson: targetsForAction(selectedAction)' "$repository_root/vars/hostConfigDeploymentPipeline.groovy"
grep -Fq 'VALIDATION_SCRIPT' "$repository_root/vars/shellPipeline.groovy"
grep -Fq 'Repository Validation' "$repository_root/vars/shellPipeline.groovy"
grep -Fq 'terraformDirectories' "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq 'validationCommands' "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq 'githubRepository' "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq "libraryScript('actionlint.sh')" "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq 'cleanup {' "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq 'deleteDir()' "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq "libraryScript('groovy-validate.sh')" "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq "state: 'pending'" "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq "state: 'success'" "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq "state: 'failure'" "$repository_root/vars/repositoryValidationPipeline.groovy"
grep -Fq "def credentialFile = \"\${pwd()}/.terraform-credentials.json\"" \
  "$repository_root/vars/ociTerraformPipeline.groovy"
grep -Fq "name: 'GITHUB_RUNNER_TOKEN'" \
  "$repository_root/vars/ociTerraformPipeline.groovy"
grep -Fq "name: 'WORDPRESS_REGISTRY_TOKEN'" \
  "$repository_root/vars/ociTerraformPipeline.groovy"
grep -Fq "libraryScript('terraform-credential-bootstrap.sh')" \
  "$repository_root/vars/ociTerraformPipeline.groovy"
grep -Fq 'OCI_VAULT_CREDENTIAL_OWNER_UID' \
  "$repository_root/resources/scripts/oci-vault-secret.sh"
grep -Fq 'OCI_VAULT_CREDENTIAL_OWNER_GID' \
  "$repository_root/resources/scripts/oci-vault-secret.sh"
if grep -Fq 'pwd(tmp: true)' "$repository_root/vars/ociTerraformPipeline.groovy"; then
  printf 'OCI Terraform credentials must use the shared Jenkins workspace.\n' >&2
  exit 1
fi

#==============================================================================
# PIPELINE EXECUTION VALIDATION
#==============================================================================

pipeline_files=(
  backupPipeline.groovy
  containerImagePipeline.groovy
  kubernetesApplicationPipeline.groovy
  composePipeline.groovy
  hostConfigDeploymentPipeline.groovy
  hostConfigIngressPipeline.groovy
  hostConfigNetworkPipeline.groovy
  hostDeploymentPipeline.groovy
  ociTerraformPipeline.groovy
  releasePipeline.groovy
  repositoryValidationPipeline.groovy
  shellPipeline.groovy
  terraformPipeline.groovy
)

for pipeline_file in "${pipeline_files[@]}"; do
  if ! grep -Fq "agent { label 'platform' }" "$repository_root/vars/$pipeline_file" || \
    ! grep -Fq "ansiColor('xterm')" "$repository_root/vars/$pipeline_file"; then
    printf 'Pipeline must use the platform agent and ANSI console rendering: %s\n' \
      "$pipeline_file" >&2
    exit 1
  fi
done

bash "$repository_root/tests/test-oci-run-command.sh"
bash "$repository_root/tests/test-oci-terraform.sh"
bash "$repository_root/tests/test-clinirova-credential-bootstrap.sh"
bash "$repository_root/tests/test-container-image-target.sh"
bash "$repository_root/tests/test-oci-vault-secret.sh"

#==============================================================================
# VALIDATION RESULT
#==============================================================================

printf 'jenkins_library_validation=ready\n'