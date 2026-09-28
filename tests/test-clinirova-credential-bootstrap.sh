#!/usr/bin/env bash

#==============================================================================
# CLINIROVA SECRET BOOTSTRAP REGRESSIONS
#==============================================================================
set -euo pipefail
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
export TERRAFORM_CREDENTIAL_FILE="$temporary_directory/credentials.json"
export GITHUB_RUNNER_TOKEN=""
export WORDPRESS_REGISTRY_TOKEN=""

#==============================================================================
# PARTIAL BOOTSTRAP PRESERVES OTHER CREDENTIALS
#==============================================================================
printf '%s' '{"wordpress_registry_token":"existing-token","clinirova_secret_bundle":"{\"META_APP_SECRET\":\"existing-meta\"}"}' > "$TERRAFORM_CREDENTIAL_FILE"
export GITHUB_RUNNER_TOKEN='github-runner-token-at-least-twenty'
export CLINIROVA_SECRET_BUNDLE='{"SMTP_PASSWORD":"synthetic-smtp-secret"}'
output=$(bash "$repository_root/resources/scripts/terraform-credential-bootstrap.sh")
[[ "$output" == 'terraform_credential_bootstrap=ready' ]]
jq -e '.github_runner_token == "github-runner-token-at-least-twenty" and .wordpress_registry_token == "existing-token" and (.clinirova_secret_bundle | fromjson | .SMTP_PASSWORD == "synthetic-smtp-secret" and .META_APP_SECRET == "existing-meta")' "$TERRAFORM_CREDENTIAL_FILE" >/dev/null
cp "$TERRAFORM_CREDENTIAL_FILE" "$temporary_directory/expected.json"

#==============================================================================
# INVALID INPUT NEVER MODIFIES THE BUNDLE OR PRINTS SECRETS
#==============================================================================
for invalid in 'not-json' '{}' '{"DATABASE_URL":"forbidden"}' '{"SMTP_PASSWORD":""}' '{"SMTP_PASSWORD":123}' '{"SMTP_PASSWORD":"first\nsecond"}'; do
  export CLINIROVA_SECRET_BUNDLE="$invalid"
  if bash "$repository_root/resources/scripts/terraform-credential-bootstrap.sh" > "$temporary_directory/output" 2>&1; then
    printf 'Invalid bundle was accepted.\n' >&2
    exit 1
  fi
  cmp "$TERRAFORM_CREDENTIAL_FILE" "$temporary_directory/expected.json"
  if grep -Fq "$invalid" "$temporary_directory/output"; then
    printf 'Rejected credential input appeared in command output.\n' >&2
    exit 1
  fi
done

#==============================================================================
# INVALID RUNNER TOKEN NEVER MODIFIES THE BUNDLE OR PRINTS THE TOKEN
#==============================================================================

export CLINIROVA_SECRET_BUNDLE=""
for invalid_token in short-token $'github-runner-token-first\ngithub-runner-token-second'; do
  export GITHUB_RUNNER_TOKEN="$invalid_token"
  if bash "$repository_root/resources/scripts/terraform-credential-bootstrap.sh" > "$temporary_directory/output" 2>&1; then
    printf 'Invalid runner token was accepted.\n' >&2
    exit 1
  fi
  cmp "$TERRAFORM_CREDENTIAL_FILE" "$temporary_directory/expected.json"
  if grep -Fq "$GITHUB_RUNNER_TOKEN" "$temporary_directory/output"; then
    printf 'Rejected runner token appeared in command output.\n' >&2
    exit 1
  fi
done

#==============================================================================
# EMPTY INPUT LEAVES PERSISTED CREDENTIALS INTACT
#==============================================================================
export CLINIROVA_SECRET_BUNDLE=""
export GITHUB_RUNNER_TOKEN=""
[[ "$(bash "$repository_root/resources/scripts/terraform-credential-bootstrap.sh")" == 'terraform_credential_bootstrap=skipped' ]]
cmp "$TERRAFORM_CREDENTIAL_FILE" "$temporary_directory/expected.json"
printf 'clinirova_credential_bootstrap_tests=passed\n'