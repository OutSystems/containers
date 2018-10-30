$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "GeneralUtils.psm1") -Force

Function CheckIfZipIsLikelyADockerBundle {
    param(
        [Parameter(mandatory=$true)][string]$DockerBundleFile
    )

    $status = $false

    if (Test-Path -Path $DockerBundleFile) {
        [Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') 2>&1>$null

        $BundleFile = Get-ChildItem $DockerBundleFile

        $status = [IO.Compression.ZipFile]::OpenRead($BundleFile.FullName).Entries.Fullname -contains "Dockerfile"
    } else {
        EchoAndLog "Bundle $DockerBundleFile not found. Maybe it was deleted?"
    }

    return $status
}

Function ContainerImageExists {
    param (
        [Parameter(Mandatory=$true)][string]$RepositoryName,
        [Parameter(Mandatory=$true)][string]$RepositoryTag
    )

    return $(docker image inspect $($RepositoryName + ":" + $RepositoryTag)) -ne "[]"
}

Function CleanUpSiteName {
    param (
        [Parameter(Mandatory=$true)][object]$ApplicationInfo
    )

    return $($ApplicationInfo.SiteName -replace ' ', '').ToLowerInvariant()
}

Function GetContainerImage {
    param (
        [Parameter(Mandatory=$true)][object]$ApplicationInfo
    )

    $SiteName = $(CleanUpSiteName -ApplicationInfo $ApplicationInfo)

    $Filters = "-f `"label=$($ApplicationInfo.ApplicationKey)`" -f `"label=$($ApplicationInfo.OperationID)`" -f `"label=$SiteName`""
    $DockerImageLsCmd = "& docker image ls $Filters 2>&1"
    $DockerImageLsInfo = Invoke-Expression $DockerImageLsCmd

    if (-not $DockerImageLsInfo -or $DockerImageLsInfo.Exception) {
        throw "Tried to do '$DockerImageLsCmd' got '$DockerImageLsInfo'."
    } else {
        # $DockerImageLsInfo.GetType().Name -ne "String" checks if the return is not the empty result: "REPOSITORY TAG IMAGE ID CREATED SIZE"
        if ($DockerImageLsInfo.Length -gt 1 -and $DockerImageLsInfo.GetType().Name -ne "String") {
            $ImageID = ($DockerImageLsInfo[1] -split "\s+")[0]
        }
    }

    if (-not $ImageID) {
        throw "No image was found with labels: '$($ApplicationInfo.ApplicationKey)' + '$($ApplicationInfo.OperationID)' + '$SiteName'."
    }

    return $ImageID
}

Function BuildContainerImage {
    param (
        [Parameter(Mandatory=$true)][object]$ApplicationInfo,
        [Parameter(Mandatory=$true)][string]$RepositoryName,
        [Parameter(Mandatory=$true)][string]$RepositoryTag,
        [Parameter(Mandatory=$true)][string]$DockerfilePath
    )

    $SiteName = $(CleanUpSiteName -ApplicationInfo $ApplicationInfo)

    $SetRepositoryTag = "${RepositoryName}:${RepositoryTag}"
    $SetLabels = "--label $($ApplicationInfo.ApplicationKey) --label $($ApplicationInfo.OperationID) --label $SiteName"
    $DockerBuildCmd = "& docker build -t $SetRepositoryTag $SetLabels $DockerfilePath 2>&1"
    $DockerBuildInfo = Invoke-Expression $DockerBuildCmd

    [string]$ImageID = $null

    if (-not $DockerBuildInfo -or $DockerBuildInfo.Exception) {
        throw "Tried to do '$DockerBuildCmd' got '$DockerBuildInfo'."
    } else {
        EchoAndLog "docker build: $($DockerBuildInfo -join "`r`n")"

        $SuccessMsgPrefix = "Successfully built "

        $SuccessMsg = $DockerBuildInfo | Where-Object { $_.StartsWith($SuccessMsgPrefix) }

        if ($SuccessMsg) {
            $ImageID = [string]$SuccessMsg.Replace($SuccessMsgPrefix, "")
        } else {
            throw "Something went wrong when building the container image '$($RepositoryName + ":" + $RepositoryTag)'!"
        }
    }

    return $ImageID
}

Function RunContainer {
    param (
        [Parameter(Mandatory=$true)][string]$ImageID,
        [Parameter(Mandatory=$true)][object]$ApplicationInfo,
        [Parameter(Mandatory=$true)][object]$ApplicationVolumesFolders
    )

    $SiteName = $(CleanUpSiteName -ApplicationInfo $ApplicationInfo)

    $SetVolumeConfigs = "-v $($ApplicationVolumesFolders.ConfigsFolderInHost):$($ApplicationVolumesFolders.ConfigsFolderInContainer):ro"
    $SetVolumeSecrets = "-v $($ApplicationVolumesFolders.SecretsFolderInHost):$($ApplicationVolumesFolders.SecretsFolderInContainer):ro"
    $SetLabels = "-l $($ApplicationInfo.ApplicationKey) -l $($ApplicationInfo.OperationID) -l $SiteName"

    $DockerRunCmd = "& docker run -dit $SetVolumeConfigs $SetVolumeSecrets $SetLabels $ImageID 2>&1"
    $DockerRunInfo = Invoke-Expression $DockerRunCmd

    [string]$ContainerID = $null

    if (-not $DockerRunInfo -or $DockerRunInfo.Exception) {
        throw "Tried to do '$DockerRunCmd', got '$DockerRunInfo'."
    } else {
        $ContainerID = [string]$DockerRunInfo
    }

    return $ContainerID
}

Function StartExistingContainer {
    param (
        [Parameter(Mandatory=$true)][string]$ContainerID
    )

    $(docker start $ContainerID)
}

Function GetContainerInfo {
    param (
        [Parameter(Mandatory=$true)][string]$ContainerID
    )

    [string]$InfoJSON = $(docker inspect $ContainerID)

    return $(ConvertFrom-Json $InfoJSON)
}

Function GetContainerID {
    param (
        [Parameter(Mandatory=$true)][object]$ApplicationInfo
    )

    $SiteName = $(CleanUpSiteName -ApplicationInfo $ApplicationInfo)

    $Filters = "-f `"label=$($ApplicationInfo.ApplicationKey)`" -f `"label=$($ApplicationInfo.OperationID)`" -f `"label=$SiteName`""
    $DockerContainerPSCmd = "& docker ps -a $Filters 2>&1"
    $DockerContainerPSInfo = Invoke-Expression $DockerContainerPSCmd

    if (-not $DockerContainerPSInfo -or $DockerContainerPSInfo.Exception) {
        throw "Tried to do '$DockerContainerPSCmd' got '$DockerContainerPSInfo'."
    } else {
        # $DockerImageLsInfo.GetType().Name -ne "String" checks if the return is not the empty result: "REPOSITORY TAG IMAGE ID CREATED SIZE"
        if ($DockerContainerPSInfo.Length -gt 1 -and $DockerContainerPSInfo.GetType().Name -ne "String") {
            $ContainerID = ($DockerContainerPSInfo[1] -split "\s+")[0]
        }
    }

    if (-not $ContainerID) {
        throw "No container was found with labels: '$($ApplicationInfo.ApplicationKey)' + '$($ApplicationInfo.OperationID)' + '$SiteName'."
    }

    return $ContainerID
}

Function GetRunningContainersForAppInSite {
    param (
        [Parameter(Mandatory=$true)][object]$ApplicationInfo
    )

    [string[]]$ContainerIDs = @()

    $SiteName = $(CleanUpSiteName -ApplicationInfo $ApplicationInfo)

    $RawFiltered = $(docker ps -f "label=$($ApplicationInfo.ApplicationKey)" -f "label=$SiteName") | Select-Object -Skip 1

    foreach ($Line in $RawFiltered) {
        $ContainerID = [regex]::split($Line, "\s\s+")[0]

        $ContainerIDs += $ContainerID
    }

    return [string[]]$ContainerIDs
}

Function StopContainers {
    param (
        [Parameter(Mandatory=$true)][string[]]$ContainerIDs
    )

    $SuccessfulStops = @()
    $FailedStop = $Null

    foreach ($ContainerID in $ContainerIDs) {
        $DockerRmCmd = "& docker stop $ContainerID 2>&1"
        $DockerRmInfo = Invoke-Expression $DockerRmCmd

        if (-not $DockerRmInfo -or $DockerRmInfo.Exception) {
            throw "Tried to do '$DockerRmCmd', got '$DockerRmInfo'."
        } else {
            if ([string]$DockerRmInfo -eq $ContainerID) {
                $SuccessfulStops += $ContainerID
            } else {
                $FailedStop = $ContainerID

                break
            }
        }
    }

    if ($ContainerIDs.Count -eq 0) {
        EchoAndLog "No containers to stop!"
    } else {
        $FailMsg = ""

        if ($FailedStop) {
            $FailMsg = "But couldn't stop container with ID '$ContainerID'. Aborting!"
        }

        EchoAndLog "Stopped containers: $([String]::Join(", ", $SuccessfulStops)). $FailMsg"
    }

    return ($ContainerIDs.Count -eq $SuccessfulStops.Count)
}

Function StopContainersForAppInSite {
    param (
        [Parameter(Mandatory=$true)][object]$ApplicationInfo
    )

    [string[]]$ContainerIDs = $(GetRunningContainersForAppInSite -ApplicationInfo $ApplicationInfo)

    if ($ContainerIDs) {
        $(StopContainers -ContainerIDs $ContainerIDs)
    }
}

Function ContainerExists {
    param (
        [Parameter(Mandatory=$true)][string]$ContainerID
    )

    $ContainerInfo = $(GetContainerInfo -ContainerID $ContainerID)

    return (-not $ContainerInfo) -and ($ContainerInfo -notcontains "Error: No such object: $ContainerID")
}

Function ContainerIsRunning {
    param (
        [Parameter(Mandatory=$true)][string]$ContainerID
    )

    $IsRunning = $(docker inspect --format="{{.State.Running}}" $ContainerID)

    return ($IsRunning -eq "true")
}

Function PurgeContainerImage {
    param (
        [Parameter(Mandatory=$true)][string]$ImageID
    )

    return ($(docker rmi -f $ImageID) -notcontains "No such image")
}

Function PurgeContainer {
    param (
        [Parameter(Mandatory=$true)][string]$ContainerID
    )

    return ($(docker rm -f $ContainerID) -eq $ContainerID)
}