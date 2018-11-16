$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "../../utils/Logger.psm1")
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "../../utils/DockerUtils.psm1") -Force
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "../../utils/IISUtils.psm1") -Force

Function TryToConvertHostPathUsedForVolumeFromNetworkShare {
    Param (
        [Parameter(Mandatory=$true)][String]$Path
    )

    # checks if path is a network share
    if ([bool]([System.Uri]$Path).IsUnc) {
        # split the network share by the \s
        # e.g. \\share.com\potato\cabbage to [ share.com , potato , cabbage]
        $SplittedPath = $($Path -replace '\\\\','' -split '\\')
        
        # windows represents internally the share by a name 
        # this name maps to the first element of the path. e.g. 'potato'
        $SmbShareName = $SplittedPath[1]

        try {
            # we try to get the samba share object by the name we calculated
            # if no samba share exists for the name an exception is thrown
            $SmbShare = $(Get-SmbShare -name $SmbShareName)

            # we replace the domain part of the share plus the share name for the 'physical' path of the share
            # hopefully
            $InferredPath = $($Path -replace "\\\\$($SplittedPath[0])\\$($SplittedPath[1])", "$($SmbShare.Path)")

            WriteLog -Level "DEBUG" -Message "Inferred that [$Path] is actually [$InferredPath]."
        } catch {
            # lets set an invalid path to ensure it will fail next
            $InferredPath = ""
        }

        <# 
            lets check if we have a valid path
            if not, throw a informative message
            this could have some additional logic, though:
            if the network share is located a different computer copy the file to a local folder
        #>
        if (-not $InferredPath) {
            throw "Unable to infer local path for network share ('$Path'). Docker does not map volumes to network shares. Additional transformations to the path are required."
        }

        if (-not (Test-Path $InferredPath)) {
            WriteLog -Level "WARN" "The path ('$Path') does not yet exist! Moving on nonetheless."
        }
    } else {
        $InferredPath = $Path
    }

    return $InferredPath
}

Function GetIISInfo {
    Param (
        [Parameter(Mandatory=$true)][AllowEmptyString()][String]$SiteName
    )

    $IISInfo = @{}    

    if (-not $SiteName) {
        # no site given
        $IISInfo.IsDefaultWebSite = $True
        $IISInfo.SiteName = "Default Web Site"
    } else {
        $IISInfo.IsDefaultWebSite = $False
        $IISInfo.SiteName = $SiteName
    }

    return $IISInfo
}

Function GetFilePaths {
    Param (
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters,
        [Parameter(Mandatory=$true)][String]$SiteName,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$ArtefactsBasePath,
        [Parameter(Mandatory=$true)][String]$BaseConfigPath
    )

    $BaseConfigPath = TryToConvertHostPathUsedForVolumeFromNetworkShare -Path $BaseConfigPath
    
    $FilePaths = @{}

    $SiteName = $SiteName -replace " ", ""

    $FilePaths.UnzippedBundlesPath = $(Join-Path -Path "$ArtefactsBasePath" -ChildPath "$SiteName/$($global:UnzippedBundlesFolderName)")
    $FilePaths.SiteFolderPath = $(Join-Path -Path "$ArtefactsBasePath" -ChildPath "$SiteName/site")
    $FilePaths.AppConfigPath = $(Join-Path -Path $BaseConfigPath -ChildPath $ApplicationKey)
    $FilePaths.SecretPath = $AdditionalParameters.SecretPath

    if (-not $FilePaths.SecretPath) {
        $FilePaths.SecretPath = $(Join-Path -Path "$ArtefactsBasePath" -ChildPath "$SiteName/$($global:SecretsFolderName)")
    } else {
        $FilePaths.SecretPath = $(TryToConvertHostPathUsedForVolumeFromNetworkShare -Path $FilePaths.SecretPath)
    }

    foreach ($PathName in @("UnzippedBundlesPath", "SiteFolderPath", "AppConfigPath", "SecretPath")) {
        $Path = $FilePaths[$PathName]

        # forcing folder creation to ensure that the folders exists
        $(New-Item -Force -Path $Path -ItemType Directory) 2>&1>$null

        # forcing the paths to be fully absolute (e,g with no /../ )
        # in particular, IIS does not support a path with those characteristics for the physical path
        $FilePaths[$PathName] = $(Resolve-Path $Path)
    }

    return $FilePaths
}

Function GetAppVolumeFolders {
    Param (
        [Parameter(Mandatory=$true)][String]$ConfigsFolderInHost,
        [Parameter(Mandatory=$true)][String]$ConfigsFolderInContainer,
        [Parameter(Mandatory=$true)][String]$SecretsFolderInHost,
        [Parameter(Mandatory=$true)][String]$SecretsFolderInContainer
    )

    $AppVolumeFolders = @{}
    $AppVolumeFolders.ConfigsFolderInHost = $ConfigsFolderInHost
    $AppVolumeFolders.ConfigsFolderInContainer = $ConfigsFolderInContainer
    $AppVolumeFolders.SecretsFolderInHost = $SecretsFolderInHost
    $AppVolumeFolders.SecretsFolderInContainer = $SecretsFolderInContainer

    if (-not $(Test-Path $AppVolumeFolders.ConfigsFolderInHost)) {
        $(New-item -Force $AppVolumeFolders.ConfigsFolderInHost -ItemType directory) 2>&1>$null
    }

    if (-not $(Test-Path $AppVolumeFolders.SecretsFolderInHost)) {
        $(New-item -Force $AppVolumeFolders.SecretsFolderInHost -ItemType directory) 2>&1>$null
    }

    $AppVolumeFolders.Mappings = @{}
    $AppVolumeFolders.Mappings[$AppVolumeFolders.ConfigsFolderInHost] = $AppVolumeFolders.ConfigsFolderInContainer
    $AppVolumeFolders.Mappings[$AppVolumeFolders.SecretsFolderInHost] = $AppVolumeFolders.SecretsFolderInContainer

    return $AppVolumeFolders
}

Function GetDeployInfo {
    Param (
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$BaseConfigPath
    )

    $IISInfo = $(GetIISInfo -SiteName $AdditionalParameters.SiteName)

    $FilePaths = $(GetFilePaths -AdditionalParameters $AdditionalParameters `
                                -SiteName $IISInfo.SiteName `
                                -ApplicationKey $ApplicationKey `
                                -ArtefactsBasePath $global:ArtefactsBasePath `
                                -BaseConfigPath $BaseConfigPath)

    $AppInfo = $(GetAppInfo -ApplicationKey $ApplicationKey `
                            -OperationId $OperationId `
                            -TargetPath $TargetPath `
                            -UnzippedBundlesPath $FilePaths.UnzippedBundlesPath)

    $AppVolumeFolders = $(GetAppVolumeFolders   -ConfigsFolderInHost $FilePaths.AppConfigPath `
                                                -ConfigsFolderInContainer $global:ConfigsFolderInContainer `
                                                -SecretsFolderInHost $FilePaths.SecretPath `
                                                -SecretsFolderInContainer $global:SecretsFolderInContainer)

    $DeployInfo = @{}
    $DeployInfo.IISInfo = $IISInfo
    $DeployInfo.FilePaths = $FilePaths
    $DeployInfo.AppInfo = $AppInfo
    $DeployInfo.AppVolumeFolders = $AppVolumeFolders

    return $DeployInfo
}

Function GetLabels {
    Param (
        [Parameter()][String]$ApplicationKey,
        [Parameter()][String]$OperationId,
        [Parameter()][String]$SiteName
    )

    $Labels = @{}

    if ($ApplicationKey) {
        $Labels.ApplicationKey = $(CleanUpLabel $ApplicationKey)
    }

    if ($OperationId) {
        $Labels.OperationId = $(CleanUpLabel $OperationId)
    }

    if ($SiteName) {
        $Labels.SiteName = $(CleanUpLabel $SiteName)
    }

    return $Labels
}

Function CleanUpContainerArtefacts {
    Param (
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$UnzippedBundlePath,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter()][String]$OperationIdToKeep
    )

    foreach ($Path in @($TargetPath, $UnzippedBundlePath)) {
        if (-not (Test-Path $Path)) {
            WriteLog "The path '$Path' doesn't seem to exist. Ignoring."
            continue
        }

        foreach ($Artefact in $(Get-ChildItem $Path -Filter "*$ApplicationKey*")) {
            try {
                if ($OperationIdToKeep -and ($(Split-Path -Path $Artefact.FullName -Leaf) -like "*$OperationIdToKeep*")) {
                    continue
                }

                if ($Artefact.Attributes -eq "Directory") {
                    $(Remove-Item -LiteralPath $Artefact.FullName -Force -Recurse) 2>$FileDeleteError
                } else {
                    $(Remove-Item -LiteralPath $Artefact.FullName -Force) 2>$FileDeleteError
                }

                if ($FileDeleteError) {
                    WriteLog -Level "DEBUG" -Message "Unable to delete '$Artefact.FullName'. Moving on..."
                    # WriteLog -Level "DEBUG" -Message "More info: $FileDeleteError"
                }

                WriteLog "Deleted '$($Artefact.FullName)'."
            } catch {
                WriteLog -Level "WARN" -Message "Unable to delete '$($Artefact.FullName)'. Moving on..."
                # WriteLog -Level "DEBUG" -Message "More info: $_"
            }
        }
    }
}

Function Wrapper_ContainerBuild {
    Param (
        [Parameter(Mandatory=$true)][String]$Address,
        [Parameter(Mandatory=$true)][String]$ApplicationName,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$ResultPath, 
        [Parameter(Mandatory=$true)][String]$ConfigPath,
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters
    )

    $DeployInfo = $(GetDeployInfo   -AdditionalParameters $AdditionalParameters `
                                    -ApplicationKey $ApplicationKey `
                                    -OperationId $OperationId `
                                    -TargetPath $TargetPath `
                                    -BaseConfigPath $ConfigPath) 

    if (-not (Test-Path $DeployInfo.AppInfo.BundleFilePath)) {
        throw "No bundle found with path '$($DeployInfo.AppInfo.BundleFilePath)'. Aborting."
    }

    if (-not $(CheckIfZipIsLikelyADockerBundle -DockerBundleFile $DeployInfo.AppInfo.BundleFilePath)) {
        throw "No Dockerfile found in root of '$($DeployInfo.AppInfo.BundleFilePath)'. Aborting."
    }

    $Labels = $(GetLabels   -ApplicationKey $ApplicationKey `
                            -OperationId $OperationId `
                            -SiteName $DeployInfo.IISInfo.SiteName)

    $ContainerIds = $(GetRunningDockerContainersWithLabels -Labels $Labels)

    if (($AdditionalParameters.Force) -or (-not $ContainerIds)) {
        $(UnzipContainerBundle  -BundleFilePath $DeployInfo.AppInfo.BundleFilePath `
                                -UnzipFolder $DeployInfo.AppInfo.UnzippedBundlePath)

        $(BuildDockerImageWithRetries   -RepositoryName $DeployInfo.AppInfo.FullName `
                                        -RepositoryTag "latest" `
                                        -Labels $Labels `
                                        -DockerfilePath $DeployInfo.AppInfo.UnzippedBundlePath) | Out-Null
    } else {
        WriteLog "A container is already running for '$($DeployInfo.AppInfo.FullName)'. Doing nothing."
    }
}

Function RunJustBeforeDeployDone {
    Param (
        [Parameter(Mandatory=$true)][String]$ScriptsPath,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$SiteName,
        [Parameter(Mandatory=$true)][object]$ContainerInfo
    )

    if ($ScriptsPath) {
        $GlobalScriptPath = $(Join-Path -Path $ScriptsPath -ChildPath "global.ps1")
        $AppSpecificScriptPath = $(Join-Path -Path $ScriptsPath -ChildPath "$ApplicationKey.ps1")

        foreach ($ScriptPath in @($GlobalScriptPath, $AppSpecificScriptPath)) {
            if (Test-Path $ScriptPath) {
                try {
                    WriteLog -Level "DEBUG" -Message "Found script ($ScriptPath). Executing..."

                    &$ScriptPath $ApplicationKey $OperationId $SiteName $ContainerInfo

                    WriteLog "Executed $ScriptPath"
                } catch {
                    WriteLog -Level "WARN" -Message "Something went wrong when executing '$ScriptPath': $_ ($($Error[0].ScriptStackTrace)). Ignoring..."
                }
            }
        }
    }
}

Function Wrapper_ContainerRun {
    Param (
        [Parameter(Mandatory=$true)][String]$Address,
        [Parameter(Mandatory=$true)][String]$ApplicationName,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$ResultPath, 
        [Parameter(Mandatory=$true)][String]$ConfigPath,
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters
    )

    $DeployInfo = $(GetDeployInfo   -AdditionalParameters $AdditionalParameters `
                                    -ApplicationKey $ApplicationKey `
                                    -OperationId $OperationId `
                                    -TargetPath $TargetPath `
                                    -BaseConfigPath $ConfigPath)

    $LabelsForThisAppVersion = $(GetLabels -ApplicationKey $ApplicationKey -OperationId $OperationId -SiteName $DeployInfo.IISInfo.SiteName)
    $LabelsForAllAppVersions = $(GetLabels -ApplicationKey $ApplicationKey -SiteName $DeployInfo.IISInfo.SiteName)

    $(ForceRemoveAllDockerContainersWithLabels -Labels $LabelsForAllAppVersions) | Out-Null

    # We need to force the 'cast' to String Array:
    # PowerShell will interpret a single item array as a string
    $ImageIds = [String[]]$(GetDockerImagesWithLabels -Labels $LabelsForThisAppVersion)
    If ($ImageIds) {
        $ImageId = $ImageIds[0]
    }

    if (-not $ImageId) {
        throw "Check if the ContainerBuild operation ran successfully. No image was found for the labels."
    }

    [String]$ContainerId = $(RunDockerContainerWithRetries  -ImageId $ImageId `
                                                            -Labels $LabelsForThisAppVersion `
                                                            -VolumeMappings $DeployInfo.AppVolumeFolders.Mappings)

    if (-not $IISWebSiteInfo.IsDefaultWebSite) {
        CreateSiteForWildcard   -SiteFolderPath $DeployInfo.FilePaths.SiteFolderPath `
                                -SiteName $DeployInfo.IISInfo.SiteName
    } else {
        WriteLog -Level "DEBUG" -Message "Using '$($DeployInfo.IISInfo.SiteName)' for rewrite rules. No specific website was created."
    }

    $ContainerInfo = $(GetDockerContainerInfoWithRetries -ContainerId $ContainerId)

    # $ContainerInfo.Config.Hostname is not working on Windows Server Core, using IPAddress
    $ContainerHostname = $ContainerInfo.NetworkSettings.Networks.nat.IPAddress

    $(AddReroutingRules -SiteName $DeployInfo.IISInfo.SiteName `
                        -TargetHostName $ContainerHostname `
                        -Paths $DeployInfo.AppInfo.ModuleNames)

    $CreatedDefaultRewriteRule = $false

    if ($AdditionalParameters.PlatformServerFQMN) {
        $ResolveDnsInfo = $(Resolve-DnsName $AdditionalParameters.PlatformServerFQMN) 2>$null

        if ($ResolveDnsInfo) {
            AddDefaultRewriteRule   -SiteName $DeployInfo.IISInfo.SiteName `
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

    $(RunJustBeforeDeployDone   -ScriptsPath $DeployInfo.FilePaths.SiteFolderPath `
                                -ApplicationKey $ApplicationKey `
                                -OperationId $OperationId `
                                -SiteName $DeployInfo.IISInfo.SiteName `
                                -ContainerInfo $ContainerInfo)

    $(CleanUpContainerArtefacts -TargetPath $TargetPath `
                                -UnzippedBundlePath $DeployInfo.FilePaths.UnzippedBundlesPath `
                                -ApplicationKey $ApplicationKey `
                                -OperationIdToKeep $OperationId)
}

Function Wrapper_ContainerRemove {
    Param (
        [Parameter(Mandatory=$true)][String]$Address,
        [Parameter(Mandatory=$true)][String]$ApplicationName,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$ResultPath, 
        [Parameter(Mandatory=$true)][String]$ConfigPath,
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters
    )

    $DeployInfo = $(GetDeployInfo   -AdditionalParameters $AdditionalParameters `
                                    -ApplicationKey $ApplicationKey `
                                    -OperationId $OperationId `
                                    -TargetPath $TargetPath `
                                    -BaseConfigPath $ConfigPath)

    $LabelsForAllAppVersions = $(GetLabels -ApplicationKey $ApplicationKey -SiteName $DeployInfo.IISInfo.SiteName)

    if (-not $AdditionalParameters.KeepDockerContainers) {
        $(ForceRemoveAllDockerContainersWithLabels -Labels $LabelsForAllAppVersions) | Out-Null
    }

    if (-not $AdditionalParameters.KeepDockerImages) {
        $(ForceRemoveDockerImagesWithLabels -Labels $LabelsForAllAppVersions) | Out-Null
    }

    $AppFullName = $DeployInfo.AppInfo.FullName

    WriteLog "Trying to remove Rewrite Rules for '$AppFullName'..."

    $ModuleNames = $DeployInfo.AppInfo.ModuleNames

    if ($ModuleNames) {
        $(RemoveReroutingRules  -SiteName $DeployInfo.IISInfo.SiteName `
                                -Paths $ModuleNames)

        WriteLog "Rewrite Rules for '$AppFullName' were removed."
    } else {
        WriteLog "Could not figure out which modules '$AppFullName' has. No Rewrite Rules were removed."
    }

    $(CleanUpContainerArtefacts -TargetPath $TargetPath `
                                -UnzippedBundlePath $DeployInfo.FilePaths.UnzippedBundlesPath `
                                -ApplicationKey $ApplicationKey)

    #Remove-Item $ApplicationConfigsFolder -Recurse
    #WriteLog "'$AppFullName' config folder was deleted."
}

Function Wrapper_UpdateConfigurations {
    Param (
        [Parameter(Mandatory=$true)][String]$Address,
        [Parameter(Mandatory=$true)][String]$ApplicationName,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$ResultPath, 
        [Parameter(Mandatory=$true)][String]$ConfigPath,
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters
    )

    # Nothing to do
}
