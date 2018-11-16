node {
    psScript = """
    Import-Module C:/jenkins/modules/HostingTechnologyModuleLoader.psm1 -ArgumentList 'DockerEEPlusIIS' -Force

    if ('${params.Address}' -ne '') {
        UpdateConfigurations    -Address '${params.Address}' `
                                -ApplicationName '${params.ApplicationName}' `
                                -ApplicationKey '${params.ApplicationKey}' `
                                -OperationId '${params.OperationId}' `
                                -TargetPath '${params.TargetPath}' `
                                -ResultPath '${params.ResultPath}' `
                                -ConfigPath '${params.ConfigPath}' `
                                -AdditionalParameters @{}
    }
    """

    powershell(returnStdout: true, script: psScript)
}
