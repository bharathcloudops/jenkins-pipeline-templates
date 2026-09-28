#!/usr/bin/env bash

#==============================================================================
# TERRAFORM CREDENTIAL BOOTSTRAP
#==============================================================================

set -euo pipefail
set +x
umask 077

#==============================================================================
# BOOTSTRAP INPUTS
#==============================================================================

: "${TERRAFORM_CREDENTIAL_FILE:?TERRAFORM_CREDENTIAL_FILE is required}"
github_runner_token="${GITHUB_RUNNER_TOKEN:-}"
wordpress_registry_token="${WORDPRESS_REGISTRY_TOKEN:-}"
export CLINIROVA_SECRET_BUNDLE="${CLINIROVA_SECRET_BUNDLE:-}"

if [[ -z "$github_runner_token" && -z "$wordpress_registry_token" && -z "$CLINIROVA_SECRET_BUNDLE" ]]; then
  printf 'terraform_credential_bootstrap=skipped\n'
  exit 0
fi
if [[ -n "$github_runner_token" ]] && [[ ${#github_runner_token} -lt 20 || "$github_runner_token" == *$'\n'* ]]; then
  printf 'GITHUB_RUNNER_TOKEN must be a single-line token of at least 20 characters.\n' >&2
  exit 1
fi
if [[ -n "$wordpress_registry_token" ]] && [[ ${#wordpress_registry_token} -lt 20 || "$wordpress_registry_token" == *$'\n'* ]]; then
  printf 'WORDPRESS_REGISTRY_TOKEN must be a single-line token of at least 20 characters.\n' >&2
  exit 1
fi
if [[ ! -r "$TERRAFORM_CREDENTIAL_FILE" ]]; then
  printf 'TERRAFORM_CREDENTIAL_FILE must identify a readable file.\n' >&2
  exit 1
fi

if [[ -n "$CLINIROVA_SECRET_BUNDLE" ]] && ! jq -en '
  env.CLINIROVA_SECRET_BUNDLE | fromjson |
  type == "object" and length > 0 and
  (keys - ["SMTP_PASSWORD", "META_APP_SECRET", "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"] | length == 0) and
  all(.[]; type == "string" and length > 0 and (test("[\\r\\n]") | not))
' >/dev/null 2>&1; then
  printf 'CLINIROVA_SECRET_BUNDLE must contain supported nonempty credential strings.\n' >&2
  exit 1
fi

#==============================================================================
# ATOMIC CREDENTIAL UPDATE
#==============================================================================

temporary_file=$(mktemp "${TERRAFORM_CREDENTIAL_FILE}.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT
export GITHUB_RUNNER_TOKEN="$github_runner_token"
export WORDPRESS_REGISTRY_TOKEN="$wordpress_registry_token"
if ! jq '
  if env.GITHUB_RUNNER_TOKEN != "" then .github_runner_token = env.GITHUB_RUNNER_TOKEN else . end |
  if env.WORDPRESS_REGISTRY_TOKEN != "" then .wordpress_registry_token = env.WORDPRESS_REGISTRY_TOKEN else . end |
  if env.CLINIROVA_SECRET_BUNDLE != "" then
    .clinirova_secret_bundle = (((.clinirova_secret_bundle // "{}" | fromjson) + (env.CLINIROVA_SECRET_BUNDLE | fromjson)) | tojson)
  else . end
' "$TERRAFORM_CREDENTIAL_FILE" > "$temporary_file" 2>/dev/null; then
  printf 'Unable to merge the credential bundle.\n' >&2
  exit 1
fi
chmod 0600 "$temporary_file"
mv "$temporary_file" "$TERRAFORM_CREDENTIAL_FILE"
trap - EXIT

printf 'terraform_credential_bootstrap=ready\n'