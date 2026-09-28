#!/usr/bin/env bash

#==============================================================================
# OCI TERRAFORM CREDENTIAL TEST
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# TEST WORKSPACE
#==============================================================================

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
install -d "$temporary_directory/bin" "$temporary_directory/workspace/root"
printf 'bucket = "state"\n' > "$temporary_directory/workspace/root/backend.hcl.example"

#==============================================================================
# DOCKER TEST DOUBLE
#==============================================================================

cat > "$temporary_directory/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$OCI_TERRAFORM_TEST_CALLS"
if [[ "$*" == *'--user 0:0'* && "$*" == *'--entrypoint /bin/sh'* ]]; then
  rm -rf -- "$TERRAFORM_DIRECTORY/.terraform"
fi
if [[ "$*" == *' plan '* ]]; then
  test "$OCI_CONFIG_FILE" = "$TOOL_CONTAINER_HOME/.oci/config"
  test -d "$TOOL_CONTAINER_HOME/.terraform.d"
  cp "$OCI_CONFIG_FILE" "$OCI_TERRAFORM_TEST_CONFIG"
  printf '%s' "$TF_VAR_cloudflare_api_token" > "$OCI_TERRAFORM_TEST_CLOUDFLARE_TOKEN"
  printf '%s' "$TF_VAR_oci_fingerprint" > "$OCI_TERRAFORM_TEST_FINGERPRINT"
  printf '%s' "$TF_VAR_oci_private_key" > "$OCI_TERRAFORM_TEST_PRIVATE_KEY"
  printf '%s' "$TF_VAR_backstage_secret_bundle" > "$OCI_TERRAFORM_TEST_BACKSTAGE_SECRET"
  printf '%s' "$TF_VAR_github_runner_token" > "$OCI_TERRAFORM_TEST_GITHUB_RUNNER_TOKEN"
  printf '%s' "$TF_VAR_wordpress_registry_token" > "$OCI_TERRAFORM_TEST_REGISTRY_TOKEN"
  printf '%s' "$TF_VAR_clinirova_secret_bundle" > "$OCI_TERRAFORM_TEST_CLINIROVA_SECRET"
  printf 'saved-plan\n' > "$TERRAFORM_DIRECTORY/$TERRAFORM_PLAN_FILE"
fi
EOF
chmod +x "$temporary_directory/bin/docker"

#==============================================================================
# TEST EXECUTION
#==============================================================================

export HOSTNAME=jenkins-controller
export OCI_TERRAFORM_TEST_CALLS="$temporary_directory/docker-calls"
export OCI_TERRAFORM_TEST_BACKSTAGE_SECRET="$temporary_directory/backstage-secret"
export OCI_TERRAFORM_TEST_CLOUDFLARE_TOKEN="$temporary_directory/cloudflare-token"
export OCI_TERRAFORM_TEST_CONFIG="$temporary_directory/oci-config"
export OCI_TERRAFORM_TEST_FINGERPRINT="$temporary_directory/fingerprint"
export OCI_TERRAFORM_TEST_GITHUB_RUNNER_TOKEN="$temporary_directory/github-runner-token"
export OCI_TERRAFORM_TEST_PRIVATE_KEY="$temporary_directory/private-key"
export OCI_TERRAFORM_TEST_REGISTRY_TOKEN="$temporary_directory/registry-token"
export OCI_TERRAFORM_TEST_CLINIROVA_SECRET="$temporary_directory/clinirova-secret"
export PATH="$temporary_directory/bin:$PATH"
export TERRAFORM_BACKEND_CONFIG_FILE=backend.hcl.example
cat > "$temporary_directory/terraform-credentials.json" <<'EOF'
{
  "backstage_secret_bundle":"{\"backend_secret\":\"backend\"}",
  "tenancy_ocid":"ocid1.tenancy.oc1..test",
  "user_ocid":"ocid1.user.oc1..test",
  "fingerprint":"aa:bb:cc",
  "private_key":"-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
  "ssh_allowed_cidr":"203.0.113.10/32",
  "ssh_public_key":"ssh-ed25519 test",
  "budget_alert_recipients":"alerts@example.com",
  "cloudflare_account_id":"0123456789abcdef0123456789abcdef",
  "cloudflare_api_token":"cloudflare-token",
  "github_token":"github-token-at-least-twenty",
  "monitoring_smtp_app_password":"abcdefghijklmnop"
}
EOF
chmod 0600 "$temporary_directory/terraform-credentials.json"
export TERRAFORM_CREDENTIAL_FILE="$temporary_directory/terraform-credentials.json"
export GITHUB_RUNNER_TOKEN=github-runner-token-at-least-twenty
export WORDPRESS_REGISTRY_TOKEN=registry-token-at-least-twenty
export CLINIROVA_SECRET_BUNDLE='{"SMTP_PASSWORD":"synthetic-password"}'
export TERRAFORM_DIRECTORY=root
export TERRAFORM_PLAN_FILE=terraform.tfplan

cd "$temporary_directory/workspace"
install -d root/.terraform
printf 'stale-backend\n' > root/.terraform/terraform.tfstate
bash "$repository_root/resources/scripts/terraform.sh" validate >/dev/null
test ! -e root/.terraform/terraform.tfstate
bash "$repository_root/resources/scripts/terraform-credential-bootstrap.sh" >/dev/null
bash "$repository_root/resources/scripts/oci-terraform.sh" plan >/dev/null

#==============================================================================
# TEST ASSERTIONS
#==============================================================================

grep -Fq -- '-backend-config=backend.hcl.example' "$OCI_TERRAFORM_TEST_CALLS"
grep -Fq -- '--user 0:0' "$OCI_TERRAFORM_TEST_CALLS"
grep -Fq -- '--entrypoint /bin/sh' "$OCI_TERRAFORM_TEST_CALLS"
grep -Fq -- "--user $(id -u):$(id -g)" "$OCI_TERRAFORM_TEST_CALLS"
grep -Fq -- "--env HOME=$temporary_directory/workspace/.jenkins-oci." "$OCI_TERRAFORM_TEST_CALLS"
grep -Fq -- '--env OCI_CONFIG_FILE' "$OCI_TERRAFORM_TEST_CALLS"
grep -Fq 'tenancy=ocid1.tenancy.oc1..test' "$OCI_TERRAFORM_TEST_CONFIG"
grep -Fq 'user=ocid1.user.oc1..test' "$OCI_TERRAFORM_TEST_CONFIG"
test "$(cat "$OCI_TERRAFORM_TEST_BACKSTAGE_SECRET")" = '{"backend_secret":"backend"}'
test "$(cat "$OCI_TERRAFORM_TEST_CLOUDFLARE_TOKEN")" = 'cloudflare-token'
test "$(cat "$OCI_TERRAFORM_TEST_FINGERPRINT")" = 'aa:bb:cc'
test "$(cat "$OCI_TERRAFORM_TEST_GITHUB_RUNNER_TOKEN")" = 'github-runner-token-at-least-twenty'
test "$(cat "$OCI_TERRAFORM_TEST_REGISTRY_TOKEN")" = 'registry-token-at-least-twenty'
jq -e '.SMTP_PASSWORD == "synthetic-password"' "$OCI_TERRAFORM_TEST_CLINIROVA_SECRET" >/dev/null
grep -Fq -- '-----BEGIN PRIVATE KEY-----' "$OCI_TERRAFORM_TEST_PRIVATE_KEY"

if find "$temporary_directory/workspace" -maxdepth 1 -type d -name '.jenkins-oci.*' | grep -q .; then
  printf 'Temporary OCI credentials were not removed.\n' >&2
  exit 1
fi

printf 'oci_terraform_test=ready\n'