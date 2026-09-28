#!/usr/bin/env bash

#==============================================================================
# OCI TERRAFORM CREDENTIAL PREPARATION
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# TERRAFORM INPUTS
#==============================================================================

action="${1:-validate}"
: "${TERRAFORM_CREDENTIAL_FILE:?TERRAFORM_CREDENTIAL_FILE is required}"
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
credential_directory=$(mktemp -d "${PWD}/.jenkins-oci.XXXXXX")
trap 'rm -rf "$credential_directory"' EXIT

if [[ ! -r "$TERRAFORM_CREDENTIAL_FILE" ]]; then
  printf 'TERRAFORM_CREDENTIAL_FILE must identify a readable file.\n' >&2
  exit 1
fi

#==============================================================================
# CREDENTIAL BUNDLE VALIDATION
#==============================================================================

if ! jq -e '
  type == "object" and
  (.tenancy_ocid | type == "string" and startswith("ocid1.tenancy.oc1..")) and
  (.user_ocid | type == "string" and startswith("ocid1.user.oc1..")) and
  (.fingerprint | type == "string" and length > 0) and
  (.private_key | type == "string" and contains("PRIVATE KEY")) and
  (.ssh_allowed_cidr | type == "string" and length > 0) and
  (.ssh_public_key | type == "string" and length > 0) and
  (.budget_alert_recipients | type == "string" and length > 0) and
  (.cloudflare_account_id | type == "string" and length == 32) and
  (.cloudflare_api_token | type == "string" and length > 0) and
  (.github_token | type == "string" and length >= 20) and
  (.monitoring_smtp_app_password | type == "string" and length == 16) and
  ((has("backstage_secret_bundle") | not) or .backstage_secret_bundle == null or
    (.backstage_secret_bundle | type == "string" and (fromjson | type == "object")))
' "$TERRAFORM_CREDENTIAL_FILE" >/dev/null; then
  printf 'Terraform credential bundle is invalid.\n' >&2
  exit 1
fi

#==============================================================================
# OCI CONFIGURATION
#==============================================================================

oci_config_directory="$credential_directory/.oci"
install -d -m 0700 "$oci_config_directory"
install -d -m 0700 "$credential_directory/.terraform.d"
private_key_file="$oci_config_directory/api-key.pem"
config_file="$oci_config_directory/config"
jq -r '.private_key' "$TERRAFORM_CREDENTIAL_FILE" > "$private_key_file"
chmod 0600 "$private_key_file"

{
  printf '[DEFAULT]\n'
  printf 'user=%s\n' "$(jq -r '.user_ocid' "$TERRAFORM_CREDENTIAL_FILE")"
  printf 'fingerprint=%s\n' "$(jq -r '.fingerprint' "$TERRAFORM_CREDENTIAL_FILE")"
  printf 'tenancy=%s\n' "$(jq -r '.tenancy_ocid' "$TERRAFORM_CREDENTIAL_FILE")"
  printf 'key_file=%s\n' "$private_key_file"
} > "$config_file"
chmod 0600 "$config_file"

#==============================================================================
# TERRAFORM SECRET ENVIRONMENT
#==============================================================================

export CLOUDFLARE_API_TOKEN
export OCI_CONFIG_FILE="$config_file"
export TOOL_CONTAINER_HOME="$credential_directory"
export TF_VAR_budget_alert_recipients
export TF_VAR_cloudflare_account_id
export TF_VAR_cloudflare_api_token
export TF_VAR_github_runner_token
export TF_VAR_jenkins_github_token
export TF_VAR_oci_fingerprint
export TF_VAR_oci_private_key
export TF_VAR_monitoring_smtp_app_password
export TF_VAR_oci_user_ocid
export TF_VAR_ssh_allowed_cidr
export TF_VAR_ssh_public_key
export TF_VAR_tenancy_ocid
export TF_VAR_wordpress_registry_token

if jq -e '.clinirova_secret_bundle | type == "string"' "$TERRAFORM_CREDENTIAL_FILE" >/dev/null; then
  export TF_VAR_clinirova_secret_bundle
  TF_VAR_clinirova_secret_bundle=$(jq -r '.clinirova_secret_bundle' "$TERRAFORM_CREDENTIAL_FILE")
fi

if jq -e '.backstage_secret_bundle | type == "string"' "$TERRAFORM_CREDENTIAL_FILE" >/dev/null; then
  export TF_VAR_backstage_secret_bundle
  TF_VAR_backstage_secret_bundle=$(jq -r '.backstage_secret_bundle' "$TERRAFORM_CREDENTIAL_FILE")
fi

CLOUDFLARE_API_TOKEN=$(jq -r '.cloudflare_api_token' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_budget_alert_recipients=$(jq -r '.budget_alert_recipients' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_cloudflare_account_id=$(jq -r '.cloudflare_account_id' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_cloudflare_api_token="$CLOUDFLARE_API_TOKEN"
TF_VAR_github_runner_token=$(jq -r '.github_runner_token // empty' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_jenkins_github_token=$(jq -r '.github_token' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_monitoring_smtp_app_password=$(jq -r '.monitoring_smtp_app_password' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_oci_fingerprint=$(jq -r '.fingerprint' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_oci_private_key=$(jq -r '.private_key' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_oci_user_ocid=$(jq -r '.user_ocid' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_ssh_allowed_cidr=$(jq -r '.ssh_allowed_cidr' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_ssh_public_key=$(jq -r '.ssh_public_key' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_tenancy_ocid=$(jq -r '.tenancy_ocid' "$TERRAFORM_CREDENTIAL_FILE")
TF_VAR_wordpress_registry_token=$(jq -r '.wordpress_registry_token // empty' "$TERRAFORM_CREDENTIAL_FILE")

#==============================================================================
# TERRAFORM EXECUTION
#==============================================================================

bash "$script_directory/terraform.sh" "$action"