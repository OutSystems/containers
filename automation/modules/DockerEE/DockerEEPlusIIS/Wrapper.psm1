$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "../BaseDockerEEWrapper.psm1") -Force


Function GetExtraContainerRunParameters {}

Function CreateRewriteRulesOnContainerRun {
    Param (
        [Parameter(Mandatory=$true)][Object]$ContainerInfo,
        [Parameter(Mandatory=$true)][Hashtable]$DeployInfo,
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters
    )

    $SiteName = $(DetermineSiteName -SiteName $DeployInfo.SiteName)

    $(CreateSiteForWildcard -SiteName $SiteName `
                            -SiteFolderPath $DeployInfo.FilePaths.SiteFolderPath)

    # $ContainerInfo.Config.Hostname is not working on Windows Server Core, using IPAddress
    $ContainerHostname = $ContainerInfo.NetworkSettings.Networks.nat.IPAddress

    $ModuleNames = $DeployInfo.AppInfo.ModuleNames

    if ($ModuleNames) {
        $(AddReroutingRules -SiteName $SiteName `
                            -TargetHostName $ContainerHostname `
                            -Paths $ModuleNames)
    } else {
        WriteLog -Level "WARN" -Message "No modules found. No rewrites rules added."
    }

    $CreatedDefaultRewriteRule = $false

    if ($AdditionalParameters.PlatformServerFQMN) {
        $ResolveDnsInfo = $(Resolve-DnsName $AdditionalParameters.PlatformServerFQMN) 2>$null

        if ($ResolveDnsInfo) {
            AddDefaultRewriteRule   -SiteName $SiteName `
                                    -TargetHostName $AdditionalParameters.PlatformServerFQMN

            $CreatedDefaultRewriteRule = $true
        } else {
            $ErrorMessage = "Could not resolve '$($AdditionalParameters.PlatformServerFQMN)'!"
        }
    } else {
        $ErrorMessage = "PlatformServerFQMN is empty!"
    }

    if (-not $CreatedDefaultRewriteRule) {
        WriteLog -Level "WARN" -Message "$ErrorMessage No URL Rewrite Inbound Rule to add rerouting back to target host name was created! Any references your app has to modules living in Classical VMs will be broken!"
    }
}

Function RemoveRewriteRulesOnContainerRemove {
    Param (
        [Parameter(Mandatory=$true)][Hashtable]$DeployInfo,
        [Parameter(Mandatory=$true)][String[]]$ModuleNames
    )

    $SiteName = $(DetermineSiteName -SiteName $DeployInfo.SiteName)

    $(RemoveReroutingRules  -SiteName $(DetermineSiteName $SiteName) `
                            -Paths $ModuleNames)
    
    WriteLog "Rewrite Rules for '$($DeployInfo.AppInfo.ApplicationName)' were removed."
}

Function DetermineSiteName {
    Param (
        [Parameter(Mandatory=$false)][String]$SiteName
    )

    # if nothing or default, it's the "Default Web Site"
    if ( (-not $SiteName) -or ($SiteName -eq "default") ) {
        $SiteName = ""
    }

    return $SiteName
}
