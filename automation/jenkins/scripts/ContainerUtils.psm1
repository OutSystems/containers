$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "GlobalSettings.psm1") -Force
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "GeneralUtils.psm1") -Force
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "IISUtils.psm1") -Force
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "DockerDapperWrapper.psm1") -Force

$DefaultNrRetries = 5

Function ListContainerBundleContents {
    param(
        [Parameter(mandatory=$true)][string]$ContainerBundleFile
    )

    $contents = ""

    try {
        if (Test-Path -Path $ContainerBundleFile) {
            [Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') 2>&1>$null

            $BundleFile = Get-ChildItem $ContainerBundleFile

            $contents = [IO.Compression.ZipFile]::OpenRead($BundleFile.FullName).Entries.FullName | `
                        ForEach-Object { $_.Replace($BundleFile.FullName, "") } | `
                        ConvertTo-Json -Compress
        } else {
            $contents = "File was deleted before we had the chance to check it."
        }
    } catch {
        $contents = "Something went wrong: $_."
    }

    return $contents
}

class ApplicationInfo {
    [string]$SiteName
    [string]$ApplicationKey
    [string]$OperationID
    [string]$ParentFolder
    [string]$FullName
}

Function GenerateApplicationInfo {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][String]$SubdomainFolder,
        [Parameter(Mandatory=$true)][String]$SiteName,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationID
    )

    [ApplicationInfo]$ApplicationInfo = [ApplicationInfo]::new()

    $ApplicationInfo.SiteName = $SiteName
    $ApplicationInfo.ApplicationKey = $ApplicationKey
    $ApplicationInfo.OperationID = $OperationID
    $ApplicationInfo.ParentFolder = $SubdomainFolder
    $ApplicationInfo.FullName = "$($ApplicationKey)_$($OperationID)"

    return $ApplicationInfo
}

Function RunJustBeforeDeployDone {
    param(
        [Parameter(mandatory=$true)][ApplicationInfo]$ApplicationInfo,
        [Parameter(mandatory=$true)][object]$ContainerInfo
    )

    try {
        if ($ApplicationInfo.ParentFolder) {
            $ScriptPath = $(Join-Path -Path $ApplicationInfo.ParentFolder -ChildPath "global.ps1")

            if (Test-Path $ScriptPath) {
                EchoAndLog "Found global script ($ScriptPath). Executing..."

                &$ScriptPath $ApplicationInfo $ContainerInfo

                EchoAndLog "Executed $ScriptPath"
            }

            $ScriptPath = $(Join-Path -Path $ApplicationInfo.ParentFolder -ChildPath "$($ApplicationInfo.ApplicationKey).ps1")

            if (Test-Path $ScriptPath) {
                EchoAndLog "Found specific app script ($ScriptPath). Executing..."

                &$ScriptPath $ApplicationInfo $ContainerInfo

                EchoAndLog "Executed $ScriptPath"
            }
        }
    } catch {
        EchoAndLog "Something went wrong when executing '$ScriptPath': $_ ($($Error[0].ScriptStackTrace)). Ignoring..."
    }
}

Function UnzipContainerBundle {
    param(
        [Parameter(mandatory=$true)][string]$UnzipFolder,
        [Parameter(mandatory=$true)][string]$ContainerBundleFile,
        [bool]$Force
    )

    $FileName = $(Split-Path $ContainerBundleFile -leaf)

    try {
        return $(RetryWithReturnValue   -NRetries $DefaultNrRetries `
                                        -ExceptionMessage "Unable to unzip bundle." `
                                        -Action {
                param (
                    [Parameter(Mandatory=$true)][string]$BlockUnzipFolder,
                    [Parameter(Mandatory=$true)][string]$BlockContainerBundleFile,
                    [Parameter(Mandatory=$true)][string]$BlockFileName,
                    [Parameter(Mandatory=$true)][bool]$BlockForce
                )

                $Unzip = $True

                if ($(Test-Path $BlockUnzipFolder)) {
                    if (-not $BlockForce) {
                        EchoAndLog "'$BlockFileName' already exists. Doing some checks..."

                        if (-not $(FastCrossCheckFilesInFolderAndZip -FolderPath $BlockUnzipFolder -ZipPath $BlockContainerBundleFile)) {
                            EchoAndLog "'$BlockFileName' zip bundle and unzipped bundle folder are not coherent. Deleting unzipped bundle folder."
                            Remove-Item -Path $BlockUnzipFolder -Recurse -Force
                        } else {
                            EchoAndLog "'$BlockFileName' Everything seems to be unchanged. Doing nothing."
                            $Unzip = $False
                        }
                    }
                }

                if ($Unzip) {
                    EchoAndLog "'$BlockFileName' unzipped bundle folder doesn't exist. Unzipping..."

                    Expand-Archive -Path $BlockContainerBundleFile -DestinationPath $BlockUnzipFolder

                    EchoAndLog "'$BlockFileName' unzipped to $BlockUnzipFolder."
                }

                return $BlockUnzipFolder
            } `
            -ArgumentList $UnzipFolder, $ContainerBundleFile, $FileName, $Force
        )

    } catch {
        throw "'$FileName' unzipping failed: $_"
    }
}

class ApplicationVolumesFolders {
    [string]$ConfigsFolderInHost
    [string]$ConfigsFolderInContainer
    [string]$SecretsFolderInHost
    [string]$SecretsFolderInContainer
}

Function GetApplicationVolumesFolders {
    param (
        [Parameter(Mandatory=$true)][ApplicationInfo]$ApplicationInfo,
        [Parameter(Mandatory=$true)][string]$ConfigsFolderInHost,
        [Parameter(Mandatory=$true)][string]$ConfigsFolderInContainer,
        [Parameter(Mandatory=$true)][string]$SecretsFolderInHost,
        [Parameter(Mandatory=$true)][string]$SecretsFolderInContainer
    )

    [ApplicationVolumesFolders]$ApplicationVolumesFolders = [ApplicationVolumesFolders]::new()
    $ApplicationVolumesFolders.ConfigsFolderInHost = $(Join-Path -Path $ConfigsFolderInHost -ChildPath $ApplicationInfo.ApplicationKey)
    $ApplicationVolumesFolders.ConfigsFolderInContainer = $ConfigsFolderInContainer
    $ApplicationVolumesFolders.SecretsFolderInHost = $SecretsFolderInHost
    $ApplicationVolumesFolders.SecretsFolderInContainer = $SecretsFolderInContainer

    if (-not $(Test-Path $ApplicationVolumesFolders.ConfigsFolderInHost)) {
        $(New-item -Force $ApplicationVolumesFolders.ConfigsFolderInHost -ItemType directory) 2>&1>$null
    }

    if (-not $(Test-Path $ApplicationVolumesFolders.SecretsFolderInHost)) {
        $(New-item -Force $ApplicationVolumesFolders.SecretsFolderInHost -ItemType directory) 2>&1>$null
    }

    return $ApplicationVolumesFolders
}

function Convert-ToCanonicalName {
    param (
        [Parameter(Mandatory=$true)][string]$RepositoryName
    )

    $StringBuilder = New-Object System.Text.StringBuilder
    [System.Security.Cryptography.HashAlgorithm]::Create("SHA1").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($RepositoryName)) | ForEach-Object {
        [Void]$StringBuilder.Append($_.ToString("x2"))
    }
    return $StringBuilder.ToString().Substring(0, 8)
}

Function BuildDockerImage {
    param (
        [Parameter(Mandatory=$true)][ApplicationInfo]$ApplicationInfo,
        [Parameter(Mandatory=$true)][string]$UnzippedBundleFolder
    )

    $RepositoryName = $ApplicationInfo.FullName

    try {
        if ($(Test-Path $UnzippedBundleFolder)) {
            EchoAndLog "'$RepositoryName' image is being built."

            $ExceptionMessage = "Image object is null: something went terribly wrong."

            # Docker does not handle names with upper case characters or white spaces
            $RepositoryName = Convert-ToCanonicalName $RepositoryName
            $RepositoryTag = "latest"

            return $(RetryWithReturnValue -NRetries $DefaultNrRetries `
                -ExceptionMessage $ExceptionMessage `
                -Action {
                    param (
                        [Parameter(Mandatory=$true)][ApplicationInfo]$BlockApplicationInfo,
                        [Parameter(Mandatory=$true)][string]$BlockRepositoryName,
                        [Parameter(Mandatory=$true)][string]$BlockRepositoryTag,
                        [Parameter(Mandatory=$true)][string]$BlockUnzippedBundleFolder
                    )

                    [string]$BlockImageID = $(BuildContainerImage   -ApplicationInfo $BlockApplicationInfo `
                                                                    -RepositoryName $BlockRepositoryName `
                                                                    -RepositoryTag $BlockRepositoryTag `
                                                                    -DockerfilePath $BlockUnzippedBundleFolder)

                    EchoAndLog "'$BlockRepositoryName' image was successfully built with ID: '$BlockImageID'."

                    return $BlockImageID
                } `
                -ArgumentList $ApplicationInfo, $RepositoryName, $RepositoryTag, $UnzippedBundleFolder
            )
        }
    } catch {
        throw "'$RepositoryName' image build failed!: $_"
    }
}

# Throws an exception if the container isn't running after checking enough times
Function TryToMakeSureThatDockerContainerIsRunning {
    param (
        [Parameter(Mandatory=$true)][string]$ContainerID,
        [Parameter(Mandatory=$true)][string]$AppName
    )

    EchoAndLog "Checking if everything is OK with container '$ContainerID'..."

    #Don't forget that the number of retries is multipled by $DefaultNrRetries, as this is inside a RetryWithReturnValue
    $NumTries = 2
    $Try = 0
    $WaitTime = 2

    do {
        EchoAndLog "[$($Try+1)/$NumTries]: Waiting $WaitTime seconds before checking on container '$ContainerID'..."

        Start-Sleep -Seconds $WaitTime

        if (-not $(ContainerIsRunning -ContainerID $ContainerID)) {
            EchoAndLog "[$($Try+1)/$NumTries]: '$AppName' container '$ContainerID' did not start! Giving it a push..."

            #  The output of this function needs to be /dev/null'ed or the id will be appended to the outer function's return value
            $(StartExistingContainer -ContainerID $ContainerID) 2>&1>$null
        } else {
            $Try = $NumTries
        }

        $Try++
    } while ($Try -lt $NumTries)

    if (-not $(ContainerIsRunning -ContainerID $ContainerID)) {
        throw "'$AppName' container's refused to start!"
    }
}

Function RunDockerContainer {
    param (
        [Parameter(Mandatory=$true)][string]$ImageID,
        [Parameter(Mandatory=$true)][ApplicationInfo]$ApplicationInfo,
        [Parameter(Mandatory=$true)][ApplicationVolumesFolders]$ApplicationVolumesFolders
    )

    try {
        if ($ImageID) {
            $FullAppName = $ApplicationInfo.FullName

            EchoAndLog "'$FullAppName' is being (fidget) spinned up."

            $ExceptionMessage = "Container object is null."

            return $(RetryWithReturnValue -NRetries $DefaultNrRetries `
                -ExceptionMessage $ExceptionMessage `
                -Action {
                    param ( 
                        [Parameter(Mandatory=$true)][string]$BlockImageID,
                        [Parameter(Mandatory=$true)][string]$BlockFullAppName,
                        [Parameter(Mandatory=$true)][ApplicationInfo]$BlockApplicationInfo,
                        [Parameter(Mandatory=$true)][ApplicationVolumesFolders]$BlockApplicationVolumesFolders
                    )

                    [string]$BlockContainerID = $(RunContainer  -ImageID $BlockImageID `
                                                                -ApplicationInfo $BlockApplicationInfo `
                                                                -ApplicationVolumesFolders $BlockApplicationVolumesFolders)

                    # We need to check if the container is actually running
                    # The container might exit as soon as it starts due to some transient state
                    $(TryToMakeSureThatDockerContainerIsRunning -ContainerID $BlockContainerID -AppName $BlockFullAppName)

                    EchoAndLog "'$BlockFullAppName' container's running with ID: '$BlockContainerID'."

                    return [string]$BlockContainerID
                } `
                -ArgumentList $ImageID, $FullAppName, $ApplicationInfo, $ApplicationVolumesFolders
            )
        } else {
            throw "We can't proceed, Docker Image object was null or not a Docker image at all!"
        }
    } catch {
        throw "'$FullAppName' container's spinning up failed!: $_"
    }
}

Function CreateErrorResultFile {
    param (
        [Parameter(Mandatory=$true)][string]$ResultsFolder,
        [Parameter(Mandatory=$true)][string]$ApplicationKey,
        [Parameter(Mandatory=$true)][string]$OperationID,
        [Parameter(Mandatory=$true)][string]$ErrorGUID
    )

    $ErrorMessage = @{}
    $ErrorMessage.Error = @{}
    $ErrorMessage.Error.Message = '[Guru Meditation Error]: Aborted deployment! Something went wrong when building the image or spinning up the container. For more info, search for [' + $ErrorGUID + '] in the log file.'

    CreateResultFile -ResultsFolder $ResultsFolder `
                     -ApplicationKey $ApplicationKey `
                     -OperationID $OperationID `
                     -Type $global:PrepareDone `
                     -InputObject $(ConvertTo-Json $ErrorMessage) `
                     -IsError

    CreateResultFile -ResultsFolder $ResultsFolder `
                     -ApplicationKey $ApplicationKey `
                     -OperationID $OperationID `
                     -Type $global:DeployDone `
                     -InputObject $(ConvertTo-Json $ErrorMessage) `
                     -IsError
}

Function CreateResultFile {
    param (
        [Parameter(Mandatory=$true)][string]$ResultsFolder,
        [Parameter(Mandatory=$true)][string]$ApplicationKey,
        [Parameter(Mandatory=$true)][string]$OperationID,
        [Parameter(Mandatory=$true)][string]$Type,
        [string]$InputObject="{}",
        [switch]$IsError=$False
    )

    $FileName = "$($ApplicationKey)_$($OperationID)"

    EchoAndLog "'$FileName' creating '$Type' file..."

    $ResultsFilePath = $(Join-Path -Path $ResultsFolder -ChildPath $FileName)

    # Apparently Out-File does not create subfolders, so we need to go the other way round
    New-Item -Force -Path $($ResultsFilePath + $Type)
    Out-File -Force -FilePath $($ResultsFilePath + $Type) -InputObject $InputObject

    $OperationType = switch ( $Type ) {
        "$global:PrepareDone"   { 'image build' }
        "$global:DeployDone"   { 'container run' }
        "$global:UndeployDone"   { 'container remove' }
    }

    if ($IsError) {
        $OperationType += " ERROR"
    }

    EchoAndLog "'$FileName' $OperationType info is available @ '$($ResultsFilePath + $Type)'."
}

Function CreatePrepareDoneFile {
    param (
        [Parameter(Mandatory=$true)][string]$ResultsFolder,
        [Parameter(Mandatory=$true)][string]$ApplicationKey,
        [Parameter(Mandatory=$true)][string]$OperationID
    )

    CreateResultFile -ResultsFolder $ResultsFolder `
                     -ApplicationKey $ApplicationKey `
                     -OperationID $OperationID `
                     -Type $global:PrepareDone
}

Function CreateDeployDoneFile {
    param (
        [Parameter(Mandatory=$true)][string]$ResultsFolder,
        [Parameter(Mandatory=$true)][string]$ApplicationKey,
        [Parameter(Mandatory=$true)][string]$OperationID,
        [Parameter(Mandatory=$true)][object]$ContainerInfo,
        [switch]$SkipPing=$False
    )

    if ($SkipPing) {
        $ContainerInfo | Add-Member -Name "SkipPing" -Value "True" -MemberType NoteProperty
    }

    CreateResultFile -ResultsFolder $ResultsFolder `
                     -ApplicationKey $ApplicationKey `
                     -OperationID $OperationID `
                     -Type $global:DeployDone `
                     -InputObject $(ConvertTo-Json $ContainerInfo)
}

Function CreateUndeployDoneFile {
    param (
        [Parameter(Mandatory=$true)][string]$ResultsFolder,
        [Parameter(Mandatory=$true)][string]$ApplicationKey,
        [Parameter(Mandatory=$true)][string]$OperationID
    )

    CreateResultFile -ResultsFolder $ResultsFolder `
                     -ApplicationKey $ApplicationKey `
                     -OperationID $OperationID `
                     -Type $global:UndeployDone
}

Function GetDockerContainerInfo {
    param (
        [Parameter(Mandatory=$true)][string]$ContainerID
    )

    $ExceptionMessage = "Could not obtain container info."

    return $(RetryWithReturnValue -NRetries $DefaultNrRetries `
        -ExceptionMessage $ExceptionMessage `
        -Action {
            param (
                [Parameter(Mandatory=$true)][string]$BlockContainerID
            )

            if (-not $BlockContainerID) {
                throw "No Container ID"
            }

            $computer = $(hostname)

            $ContainerInfo = $(GetContainerInfo -ContainerID $BlockContainerID)

            if ($ContainerInfo -eq "") {
                throw "No Container Info"
            }

            if ($computer -eq "") {
                throw "No Docker Host Hostname"
            }

            if (-not $ContainerInfo.Image -or $ContainerInfo.Image -eq "") {
                throw "No Parent Image ID"
            }

            if (-not $ContainerInfo.NetworkSettings.Networks.nat -or $ContainerInfo.NetworkSettings.Networks.nat -eq "") {
                throw "No IP"
            }

            if (-not $ContainerInfo.Config.Hostname -or $ContainerInfo.Config.Hostname -eq "") {
                throw "No Hostname"
            }

            if (-not $ContainerInfo.Name -or $ContainerInfo.Name -eq "") {
                throw "No Name"
            }

            return $ContainerInfo
        } `
        -ArgumentList $ContainerID
    )
}

Function GetContainerInfoFromDeployDoneFile {
    param (
        [Parameter(Mandatory=$true)][string]$ResultsFolder,
        [Parameter(Mandatory=$true)][string]$FileName
    )

    $ContainerInfoFile = ($(Join-Path -Path $ResultsFolder -ChildPath $FileName) + $global:DeployDone)

    $ContainerInfo = $null

    if (Test-Path $ContainerInfoFile) {
        $ContainerInfo = $(ConvertFrom-Json $([string]$(Get-Content $ContainerInfoFile)))
    }

    return $ContainerInfo
}

Function PurgeContainerArtefacts {
    param (
        [Parameter(Mandatory=$true)][string]$UnzippedBundleFolder,
        [Parameter(Mandatory=$true)][string]$ApplicationConfigsFolder,
        [Parameter(Mandatory=$true)][string]$ApplicationSecretsFolder,
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string]$ResultsFolder,
        [Parameter(Mandatory=$true)][object]$ContainerInfo,
        [switch]$KeepImage=$False,
        [switch]$KeepContainer=$False,
        [switch]$KeepMarkerFiles=$False,
        [switch]$KeepUnzippedBundle=$False,
        [switch]$KeepConfigs=$False,
        [switch]$KeepSecrets=$False
    )

    try {
        EchoAndLog "'$FileName' zip bundle was deleted or moved."

        if (-not $KeepContainer) {
            PurgeContainer $ContainerInfo.ID
            EchoAndLog "'$FileName' container with ID '$($ContainerInfo.ID)' was stopped and removed."
        }

        if (-not $KeepImage) {
            # TODO: This needs to be smarter
            PurgeContainerImage $ContainerInfo.Image
            EchoAndLog "'$FileName' image with ID '$($ContainerInfo.Image)' was removed."
        }

        try {
            if (-not $KeepMarkerFiles) {
                foreach ($Extension in ($global:PrepareDone, $global:DeployDone)) {
                    Remove-Item (Join-Path -Path $ResultsFolder -ChildPath $($FileName + $Extension))
                }
                EchoAndLog "'$FileName' marker files were removed."
            }

            if (-not $KeepUnzippedBundle) {
                Remove-Item $UnzippedBundleFolder -Recurse
                EchoAndLog "'$FileName' unzipped folder was deleted."
            }

            if (-not $KeepConfigs) {
                Remove-Item $ApplicationConfigsFolder -Recurse
                EchoAndLog "'$FileName' config folder was deleted."
            }

            if (-not $KeepSecrets) {
                Remove-Item $ApplicationSecretsFolder -Recurse
                EchoAndLog "'$FileName' secrets folder was deleted."
            }
        } catch {
            EchoAndLog "Something whent wrong when trying to deleting something related to '$FileName'. We are moving forward all the same. Error: $_"
        }
    } catch {
        throw "'$FileName' purging failed!: $_"
    }
}

Function HandlePrepareDeploy {
    param(
        [Parameter(Mandatory=$true)][String]$SourceIdentifier,
        [Parameter()][String]$SiteName="Default Web Site",
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationID,
        [Parameter(Mandatory=$true)][String]$BundlesFolder,
        [Parameter(Mandatory=$true)][String]$UnzippedBundlesFolder,
        [Parameter(Mandatory=$true)][String]$ResultsFolder
    )

    $ApplicationInfo = $(GenerateApplicationInfo    -SubdomainFolder "" `
                                                    -SiteName $SiteName `
                                                    -ApplicationKey $ApplicationKey `
                                                    -OperationID $OperationID)

    $FileName = $ApplicationInfo.FullName

    $ContainerBundleFile = $(Join-Path -Path $BundlesFolder -ChildPath "$FileName.zip")

    if (-not $(CheckIfZipIsLikelyADockerBundle -DockerBundleFile $ContainerBundleFile)) {
        throw "'$SourceIdentifier': No Dockerfile found in root of '$ContainerBundleFile'. Aborting."
    }

    $ContainerInfo = $(GetContainerInfoFromDeployDoneFile   -ResultsFolder $ResultsFolder `
                                                            -FileName $FileName)

    if ($ContainerInfo -and $ContainerInfo.ID) {
        EchoAndLog "'$SourceIdentifier': A valid result file already exists for '$FileName'. Doing nothing."

        return $null
    }

    $UnzippedBundleFolder = $(UnzipContainerBundle  -UnzipFolder $(Join-Path -Path $UnzippedBundlesFolder -ChildPath $FileName)`
                                                    -ContainerBundleFile $ContainerBundleFile)

    $(BuildDockerImage  -ApplicationInfo $ApplicationInfo `
                        -UnzippedBundleFolder $UnzippedBundleFolder)

    $(CreatePrepareDoneFile -ResultsFolder $ResultsFolder `
                            -ApplicationKey $ApplicationKey `
                            -OperationID $OperationID)

    return $true
}

Function HandleDeploy {
    param(
        [Parameter(Mandatory=$true)][String]$SourceIdentifier,
        [Parameter(Mandatory=$true)][String]$OriginMachineFullyQualifiedName,
        [Parameter()][String]$SiteName="Default Web Site",
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationID,
        [Parameter()][AllowEmptyString()][String]$SubdomainsFolder="",
        [Parameter(Mandatory=$true)][String]$UnzippedBundlesFolder,
        [Parameter(Mandatory=$true)][String]$ConfigsFolder,
        [Parameter(Mandatory=$true)][String]$SecretsFolder,
        [Parameter(Mandatory=$true)][String]$ResultsFolder
    )

    $ApplicationInfo = $(GenerateApplicationInfo    -SubdomainFolder $SubdomainsFolder `
                                                    -SiteName $SiteName `
                                                    -ApplicationKey $ApplicationKey `
                                                    -OperationID $OperationID)

    $ApplicationVolumesFolders = $(GetApplicationVolumesFolders -ApplicationInfo $ApplicationInfo `
                                                                -ConfigsFolderInHost $ConfigsFolder `
                                                                -ConfigsFolderInContainer $global:ConfigsFolderInContainer `
                                                                -SecretsFolderInHost $SecretsFolder `
                                                                -SecretsFolderInContainer $global:SecretsFolderInContainer)

    $(StopContainersForAppInSite -ApplicationInfo $ApplicationInfo)

    $ImageID = $(GetContainerImage -ApplicationInfo $ApplicationInfo)

    [string]$ContainerID = $(RunDockerContainer -ImageID $ImageID `
                                                -ApplicationInfo $ApplicationInfo `
                                                -ApplicationVolumesFolders $ApplicationVolumesFolders)

    $ContainerInfo = $(GetDockerContainerInfo -ContainerID $ContainerID)

    # $ContainerInfo.Config.Hostname is not working on Windows Server Core, using IPAddress
    $ContainerHostname = $ContainerInfo.NetworkSettings.Networks.nat.IPAddress

    $UnzippedBundleFolder = $(Join-Path -Path $UnzippedBundlesFolder -ChildPath $ApplicationInfo.FullName)
    $ModuleNames = $(GetSubFolders $(Join-Path -Path $UnzippedBundleFolder -ChildPath $global:ModulesFolder))

    $(AddReroutingRules -ApplicationInfo $ApplicationInfo `
                        -OriginMachineFullyQualifiedName $OriginMachineFullyQualifiedName `
                        -TargetHostName $ContainerHostname `
                        -ModuleNames $ModuleNames)

    $(RunJustBeforeDeployDone   -ApplicationInfo $ApplicationInfo `
                                -ContainerInfo $ContainerInfo)

    $(CreateDeployDoneFile  -ResultsFolder $ResultsFolder `
                            -ApplicationKey $ApplicationKey `
                            -OperationID $OperationID `
                            -ContainerInfo $ContainerInfo)

    return $true
}

Function HandleContainerBundleDeletion {
    param(
        [Parameter(Mandatory=$true)][String]$SourceIdentifier,
        [Parameter()][String]$SiteName="Default Web Site",
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationID,
        [Parameter()][AllowEmptyString()][String]$SubdomainsFolder,
        [Parameter(Mandatory=$true)][String]$UnzippedBundlesFolder,
        [Parameter(Mandatory=$true)][String]$ConfigsFolder,
        [Parameter(Mandatory=$true)][String]$SecretsFolder,
        [Parameter(Mandatory=$true)][String]$ResultsFolder
    )

    $ApplicationInfo = $(GenerateApplicationInfo    -SubdomainFolder $SubdomainsFolder `
                                                    -SiteName $SiteName `
                                                    -ApplicationKey $ApplicationKey `
                                                    -OperationID $OperationID)

    $FileName = $ApplicationInfo.FullName

    $ContainerInfoFromFile = $(GetContainerInfoFromDeployDoneFile   -ResultsFolder $ResultsFolder `
                                                                    -FileName $FileName)

    if ($ContainerInfoFromFile -and -not $ContainerInfoFromFile.ID) {
        EchoAndLog "Container info for '$FileName' has errors, doing nothing."
        return
    }

    $ContainerInfo = GetDockerContainerInfo -ContainerID $(GetContainerID -ApplicationInfo $ApplicationInfo)

    $UnzippedBundleFolder = $(Join-Path -Path $UnzippedBundlesFolder -ChildPath "$($ApplicationInfo.FullName)")
    $ModuleNames = $(GetSubFolders $(Join-Path -Path $UnzippedBundleFolder -ChildPath $global:ModulesFolder))

    EchoAndLog "'$SourceIdentifier': Trying to remove Rewrite Rules for '$FileName'..."

    if ($ModuleNames) {
        # $ContainerInfo.Config.Hostname is not working on Windows Server Core, using IPAddress
        $ContainerHostname = $ContainerInfo.NetworkSettings.Networks.nat.IPAddress

        if (CheckIfRewriteRulesCanBeRemoved -ApplicationInfo $ApplicationInfo `
                                            -TargetHostName $ContainerHostname `
                                            -ModuleNames $ModuleNames) {

            RemoveReroutingRules    -ApplicationInfo $ApplicationInfo `
                                    -ModuleNames $ModuleNames

            EchoAndLog "'$SourceIdentifier': '$FileName' Rewrite Rules were removed."
        } else {
            EchoAndLog "'$SourceIdentifier': rewrite rules similar to '$FileName' are being used by some other container. No Rewrite Rules were removed."
        }
    } else {
        EchoAndLog "'$SourceIdentifier': could not figure out which modules for '$FileName'. No Rewrite Rules were removed."
    }

    $ApplicationVolumesFolders = $(GetApplicationVolumesFolders -ApplicationInfo $ApplicationInfo `
                                                                -ConfigsFolderInHost $ConfigsFolder `
                                                                -ConfigsFolderInContainer $global:ConfigsFolderInContainer `
                                                                -SecretsFolderInHost $SecretsFolder `
                                                                -SecretsFolderInContainer $global:SecretsFolderInContainer)

    $(PurgeContainerArtefacts   -UnzippedBundleFolder $UnzippedBundleFolder `
                                -ApplicationConfigsFolder $ApplicationVolumesFolders.ConfigsFolderInHost `
                                -ApplicationSecretsFolder $ApplicationVolumesFolders.SecretsFolderInHost `
                                -FileName $FileName `
                                -ResultsFolder $ResultsFolder `
                                -ContainerInfo $ContainerInfo `
                                -KeepImage `
                                -KeepConfigs `
                                -KeepSecrets)
}