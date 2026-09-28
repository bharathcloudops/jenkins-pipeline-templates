//==============================================================================
// OCI TERRAFORM DECLARATIVE PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    def terraformDirectories = configuration.directories ?: [configuration.directory ?: '.']

    pipeline {
        //======================================================================
        // PIPELINE AGENT
        //======================================================================

        agent { label 'platform' }

        //======================================================================
        // PIPELINE CONTROLS
        //======================================================================

        options {
            ansiColor('xterm')
            disableConcurrentBuilds()
            timeout(time: configuration.timeoutMinutes ?: 40, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        parameters {
            choice(
                name: 'ROOT',
                choices: terraformDirectories,
                description: 'Production Terraform root'
            )
            choice(
                name: 'ACTION',
                choices: ['validate', 'plan', 'apply'],
                description: 'Terraform lifecycle action'
            )
            password(
                name: 'GITHUB_RUNNER_TOKEN',
                defaultValue: '',
                description: 'One-time organization runner token bootstrap; leave empty after it is persisted in OCI Vault'
            )
            password(
                name: 'WORDPRESS_REGISTRY_TOKEN',
                defaultValue: '',
                description: 'One-time GHCR token bootstrap; leave empty after it is persisted in OCI Vault'
            )
            password(
                name: 'CLINIROVA_SECRET_BUNDLE',
                defaultValue: '',
                description: 'One-time Clinirova JSON credential bundle; leave empty after persistence in OCI Vault'
            )
        }

        //======================================================================
        // TERRAFORM ENVIRONMENT
        //======================================================================

        environment {
            TERRAFORM_BACKEND_CONFIG_FILE = "${configuration.backendConfigFile ?: 'backend.hcl.example'}"
            TERRAFORM_PLAN_FILE = "${configuration.planFile ?: 'terraform.tfplan'}"
        }

        //======================================================================
        // TERRAFORM STAGES
        //======================================================================

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('Validate') {
                steps {
                    withEnv(["TERRAFORM_DIRECTORY=${params.ROOT}"]) {
                        libraryScript('terraform.sh', 'validate')
                    }
                }
            }

            stage('Plan') {
                when {
                    expression { params.ACTION in ['plan', 'apply'] }
                }
                steps {
                    script {
                        def credentialFile = "${pwd()}/.terraform-credentials.json"
                        try {
                            withEnv([
                                "OCI_VAULT_SECRET_NAME=${configuration.vaultSecretName ?: ''}",
                                "OCI_VAULT_COMPARTMENT_OCID=${configuration.compartmentOcid ?: ''}",
                                "OCI_VAULT_REGION=${configuration.region ?: ''}",
                                "TERRAFORM_CREDENTIAL_FILE=${credentialFile}",
                                "TERRAFORM_DIRECTORY=${params.ROOT}"
                            ]) {
                                libraryScript('oci-vault-secret.sh')
                                libraryScript('terraform-credential-bootstrap.sh')
                                libraryScript('oci-terraform.sh', 'plan')
                            }
                        } finally {
                            sh "rm -f -- '${credentialFile}'"
                        }
                    }
                    archiveArtifacts artifacts: "${params.ROOT}/${env.TERRAFORM_PLAN_FILE}*", fingerprint: true
                }
            }

            stage('Approve') {
                when {
                    expression { params.ACTION == 'apply' }
                }
                steps {
                    script {
                        env.TERRAFORM_APPROVED_PLAN_SHA256 = input(
                            message: 'Approve the reviewed saved Terraform plan',
                            ok: 'Apply exact plan',
                            parameters: [string(name: 'PLAN_SHA256', description: 'SHA256 emitted by the plan stage')]
                        )
                    }
                }
            }

            stage('Apply') {
                when {
                    expression { params.ACTION == 'apply' }
                }
                steps {
                    script {
                        def credentialFile = "${pwd()}/.terraform-credentials.json"
                        try {
                            withEnv([
                                "OCI_VAULT_SECRET_NAME=${configuration.vaultSecretName ?: ''}",
                                "OCI_VAULT_COMPARTMENT_OCID=${configuration.compartmentOcid ?: ''}",
                                "OCI_VAULT_REGION=${configuration.region ?: ''}",
                                "TERRAFORM_CREDENTIAL_FILE=${credentialFile}",
                                "TERRAFORM_DIRECTORY=${params.ROOT}"
                            ]) {
                                libraryScript('oci-vault-secret.sh')
                                libraryScript('terraform-credential-bootstrap.sh')
                                libraryScript('oci-terraform.sh', 'apply')
                            }
                        } finally {
                            sh "rm -f -- '${credentialFile}'"
                        }
                    }
                }
            }
        }
    }
}