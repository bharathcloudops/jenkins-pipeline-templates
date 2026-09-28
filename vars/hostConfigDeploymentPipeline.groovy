//==============================================================================
// REPOSITORY-CONFIGURED HOST DEPLOYMENT PIPELINE
//==============================================================================

def call(Map configuration = [:]) {
    //==========================================================================
    // PIPELINE CONFIGURATION
    //==========================================================================

    def toolType = configuration.toolType ?: ''
    def markerPrefix = toolType.replace('-', '_')
    def supportedActions = configuration.supportedActions ?: ['validate', 'dry-run', 'deploy']
    def mutatingActions = configuration.mutatingActions ?: ['deploy', 'backup', 'restore', 'rollback', 'recover', 'test-alert', 'test-restore']
    def runtimeConfiguration = [:]

    if (!(toolType in ['backstage', 'github-runner', 'jenkins', 'monitoring'])) {
        error('toolType must be backstage, github-runner, jenkins, or monitoring')
    }

    //==========================================================================
    // ACTION CONFIGURATION
    //==========================================================================

    def targetsForAction = { String selectedAction ->
        def targets = new groovy.json.JsonSlurperClassic().parseText(runtimeConfiguration.targetsJson)
        targets.each { target ->
            if (!(target.arguments instanceof List) || target.arguments.isEmpty()) {
                error('Host configuration target arguments must include a lifecycle action')
            }
            target.arguments[0] = selectedAction
        }
        groovy.json.JsonOutput.toJson(targets)
    }

    def configurationForAction = { String selectedAction ->
        def actionConfiguration = runtimeConfiguration + [
            action: selectedAction,
            prependAction: false,
            requiredOutputMarker: selectedAction == 'validate' && configuration.validationMarker
                ? configuration.validationMarker
                : "${markerPrefix}_${selectedAction.replace('-', '_')}=ready",
            targetsJson: targetsForAction(selectedAction)
        ]

        if (selectedAction != 'deploy') {
            actionConfiguration.vaultSecretName = ''
            actionConfiguration.additionalVaultSecretName = ''
            actionConfiguration.tertiaryVaultSecretName = ''
        }

        actionConfiguration
    }

    //==========================================================================
    // MANAGED PIPELINE
    //==========================================================================

    pipeline {
        agent { label 'platform' }

        options {
            ansiColor('xterm')
            disableConcurrentBuilds()
            timeout(time: configuration.timeoutMinutes ?: 40, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: configuration.buildRetention ?: '20'))
        }

        parameters {
            choice(
                name: 'ACTION',
                choices: supportedActions,
                description: 'Versioned lifecycle action'
            )
            string(
                name: 'RESTORE_ARCHIVE',
                defaultValue: '',
                description: 'Managed backup archive used only by restore'
            )
        }

        stages {
            stage('Checkout Configuration') {
                steps {
                    checkout scm
                }
            }

            stage('Prepare') {
                steps {
                    script {
                        def outputFile = "${pwd(tmp: true)}/${toolType}-pipeline-outputs"
                        def restoreVariable = [
                            backstage: 'BACKSTAGE_RESTORE_ARCHIVE',
                            jenkins: 'JENKINS_RESTORE_ARCHIVE',
                            monitoring: 'MONITORING_RESTORE_ARCHIVE'
                        ][toolType]
                        def prepareEnvironment = [
                            "GITHUB_OUTPUT=${outputFile}",
                            "HOST_CONFIG_ACTION=${params.ACTION}",
                            "HOST_CONFIG_TOOL_TYPE=${toolType}"
                        ]
                        if (restoreVariable) {
                            prepareEnvironment << "${restoreVariable}=${params.RESTORE_ARCHIVE ?: ''}"
                        }

                        withEnv(prepareEnvironment) {
                            sh '''
                                set -eu
                                : > "$GITHUB_OUTPUT"
                                bash scripts/validate-config.sh
                                bash scripts/prepare-tool-inputs.sh "$HOST_CONFIG_TOOL_TYPE" "$HOST_CONFIG_ACTION"
                            '''
                        }

                        def preparedOutputs = [:]
                        readFile(file: outputFile).readLines().findAll { it }.each { line ->
                            def delimiter = line.indexOf('=')
                            if (delimiter <= 0) {
                                error('Invalid prepared host configuration output')
                            }
                            preparedOutputs[line.substring(0, delimiter)] = line.substring(delimiter + 1)
                        }

                        sh "rm -f -- '${outputFile}'"

                        [
                            'automation_ref',
                            'automation_repository',
                            'compartment_ocid',
                            'region',
                            'targets',
                            'verification_url'
                        ].each { requiredOutput ->
                            if (!preparedOutputs[requiredOutput]) {
                                error("Missing prepared host configuration output: ${requiredOutput}")
                            }
                        }

                        runtimeConfiguration.putAll([
                            authenticationMode: 'instance-principal',
                            automationRef: preparedOutputs.automation_ref,
                            automationRepository: preparedOutputs.automation_repository,
                            compartmentOcid: preparedOutputs.compartment_ocid,
                            displayName: configuration.displayName ?: toolType,
                            region: preparedOutputs.region,
                            targetsJson: preparedOutputs.targets,
                            timeoutSeconds: configuration.timeoutSeconds ?: 1200,
                            vaultSecretName: preparedOutputs.vault_secret_name ?: '',
                            additionalVaultSecretName: preparedOutputs.additional_vault_secret_name ?: '',
                            tertiaryVaultSecretName: preparedOutputs.tertiary_vault_secret_name ?: '',
                            verificationUrl: preparedOutputs.verification_url
                        ])
                    }
                }
            }

            stage('Checkout Automation') {
                steps {
                    script {
                        dir('.host-automation') {
                            deleteDir()
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "refs/tags/${runtimeConfiguration.automationRef}"]],
                                userRemoteConfigs: [[
                                    url: "https://github.com/${runtimeConfiguration.automationRepository}.git"
                                ]]
                            ])
                        }

                        runtimeConfiguration.scriptPath = "${pwd()}/.host-automation/${configuration.scriptPath ?: 'scripts/bootstrap.sh'}"
                    }
                }
            }

            stage('Validate') {
                steps {
                    script {
                        ociRunCommand(configurationForAction('validate'))
                    }
                }
            }

            stage('Dry Run') {
                when {
                    expression { params.ACTION in ['dry-run', 'deploy'] }
                }
                steps {
                    script {
                        ociRunCommand(configurationForAction('dry-run'))
                    }
                }
            }

            stage('Approve') {
                when {
                    expression { params.ACTION in mutatingActions }
                }
                steps {
                    input message: "Run ${params.ACTION} for ${runtimeConfiguration.displayName}?", ok: 'Run'
                }
            }

            stage('Execute') {
                when {
                    expression { !(params.ACTION in ['validate', 'dry-run']) }
                }
                steps {
                    script {
                        def actionConfiguration = configurationForAction(params.ACTION)
                        if (toolType == 'jenkins' && params.ACTION in mutatingActions) {
                            actionConfiguration.detached = true
                        }
                        ociRunCommand(actionConfiguration)
                    }
                }
            }

            stage('Verify Public Route') {
                when {
                    expression { params.ACTION == 'deploy' && !(toolType in ['github-runner', 'jenkins']) }
                }
                steps {
                    sh "bash scripts/verify-public-ingress.sh '${runtimeConfiguration.verificationUrl}'"
                }
            }
        }
    }
}