node {
    psScript = """
    Import-Module C:/jenkins/modules/HostingTechnologyModuleLoader.psm1 -ArgumentList 'DockerEEPlusIIS' -Force

    if ('${params.Address}' -ne '') {
        UpdateConfigurations    -PlatformParameters @{ 
                                    Address = '${params.Address}' ; 
                                    ApplicationName = '${params.ApplicationName}' ; 
                                    ApplicationKey = '${params.ApplicationKey}' ; 
                                    OperationId = '${params.OperationId}' ; 
                                    TargetPath = '${params.TargetPath}' ; 
                                    ResultPath = '${params.ResultPath}' ; 
                                    ConfigPath = '${params.ConfigPath}' ;
                                    ModuleNames = '${params.ModuleNames}' ;
                                }
    }
    """

    powershell(returnStdout: true, script: psScript)
}
