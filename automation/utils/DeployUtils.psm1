$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "Logger.psm1")
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "GeneralUtils.psm1") -Force

Function UnzipContainerBundle {
    Param (
        [Parameter(Mandatory=$true)][String]$BundleFilePath,
        [Parameter(Mandatory=$true)][String]$UnzipFolder,
        [bool]$Force
    )

    $FileName = $(Split-Path $BundleFilePath -leaf)

    try {
        if (-not (Test-Path $BundleFilePath)) {
            throw "File '$BundleFilePath' does not exist."
        }

        $Unzip = $True

        if ($(Test-Path $UnzipFolder)) {
            if (-not $BlockForce) {
                WriteLog -Level "DEBUG" -Message "'$FileName' already exists. Doing some checks..."

                if (-not $(FastCrossCheckFilesInFolderAndZip -FolderPath $UnzipFolder -ZipPath $BundleFilePath)) {
                    WriteLog -Level "DEBUG" -Message "'$FileName' zip bundle and unzipped bundle folder are not coherent. Deleting unzipped bundle folder."
                    Remove-Item -Path $UnzipFolder -Recurse -Force
                } else {
                    WriteLog -Level "DEBUG" -Message "'$FileName' Everything seems to be unchanged. Doing nothing."
                    $Unzip = $False
                }
            }
        }

        if ($Unzip) {
            WriteLog -Level "DEBUG" -Message "'$FileName' unzipped bundle folder doesn't exist. Unzipping..."

            $FolderName = $(Split-Path $UnzipFolder -Leaf)
            $TempPath = Join-Path -Path "C:\Windows\Temp" -ChildPath $FolderName

            Expand-Archive -Path $BundleFilePath -DestinationPath $TempPath

            Move-Item -Path $TempPath -Destination $UnzipFolder -Force

            if (Test-Path $TempPath) {
                Remove-Item -Path $TempPath -Recurse -Force 2>$null
            }

            WriteLog -Level "DEBUG" -Message "'$FileName' unzipped to '$UnzipFolder'."
        }
    } catch {
        throw "'$FileName' unzipping failed: $_"
    }
}

Function ConvertToCanonicalName {
    Param (
        [Parameter(Mandatory=$true)][String]$RepositoryName
    )

    $StringBuilder = New-Object System.Text.StringBuilder
    [System.Security.Cryptography.HashAlgorithm]::Create("SHA1").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($RepositoryName)) | ForEach-Object {
        [Void]$StringBuilder.Append($_.ToString("x2"))
    }
    return $StringBuilder.ToString().Substring(0, 8)
}

Function GetAppFullName {
    Param (
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId
    )

    return "$($ApplicationKey)_$($OperationId)"
}

Function GetAppInfo {
    Param (
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId, 
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$UnzippedBundlesPath 
    )

    $AppInfo = @{}

    $AppInfo.ApplicationKey = $ApplicationKey
    $AppInfo.OperationId = $OperationId
    $AppInfo.FullName = $(GetAppFullName -ApplicationKey $ApplicationKey -OperationId $OperationId)
    $AppInfo.BundleFilePath = Join-Path -Path $TargetPath -ChildPath "$($AppInfo.FullName).zip"
    $AppInfo.UnzippedBundlePath = Join-Path -Path $UnzippedBundlesPath -ChildPath $AppInfo.FullName

    $ModulesPath = $(Join-Path -Path $AppInfo.UnzippedBundlePath -ChildPath $global:ModulesFolderName)

    if (Test-Path $ModulesPath) {
        $AppInfo.ModuleNames = $(GetSubFolders $ModulesPath)
    } else {
        WriteLog -Level "DEBUG" -Message "The modules folder for app '$($AppInfo.FullName)' doesn't exist yet."
    }

    return $AppInfo
}

Function NewWrapperResult {
    $Result = @{}
    $Result.Error = $null
    $Result.SkipPing = $False
    
    return $Result
}

Function CreateMarkerFile {
    Param (
        [Parameter(Mandatory=$true)][String]$ResultPath,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$MarkerFileExtension,
        [Parameter(Mandatory=$true)][AllowNull()]$WrapperResult
    )

    if (-not $WrapperResult) {
        $WrapperResult = $(NewWrapperResult)
    }

    $FileName = "$($ApplicationKey)_$($OperationId)"

    WriteLog -Level "DEBUG" -Message "'$FileName' creating '$MarkerFileExtension' file..."

    if (-not (Test-Path $ResultPath)) {
        $ErrorMessage = "The result path '$ResultPath' is not accessible."
        
        WriteLog "$ErrorMessage"
        throw $ErrorMessage
    }

    $ResultsFilePath = $(Join-Path -Path $ResultPath -ChildPath $FileName)

    # Apparently Out-File does not create subfolders, so we need to go the other way round
    $(New-Item -Force -Path $($ResultsFilePath + $MarkerFileExtension)) 2>&1>$null
       
    if ($WrapperResult.Error) {
        $ErrorMessage = @{}
        $ErrorMessage.Error = @{}
        $ErrorMessage.Error.Message = "Container Automation: Check the log '$($global:LogFilePath)' for more info."
        $ContainerInfo = $ErrorMessage
    } else {
        $ContainerInfo = New-Object Object
    }

    if ($WrapperResult.AdditionalInfo) {
        $ContainerInfo = $WrapperResult.AdditionalInfo
    }

    if ($WrapperResult.SkipPing) {
        $ContainerInfo | Add-Member -Name "SkipPing" -Value "True" -MemberType NoteProperty
    }

    Out-File -Force -FilePath $($ResultsFilePath + $MarkerFileExtension) -InputObject $(ConvertTo-Json $ContainerInfo)

    WriteLog "'$FileName' info is available @ '$($ResultsFilePath + $MarkerFileExtension)'."
}

Function CreatePrepareDoneFile {
    Param (
        [Parameter(Mandatory=$true)][String]$ResultPath,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][AllowNull()]$WrapperResult
    )

    CreateMarkerFile -ResultPath $ResultPath `
                     -ApplicationKey $ApplicationKey `
                     -OperationId $OperationId `
                     -MarkerFileExtension $global:PrepareDone `
                     -WrapperResult $WrapperResult
}

Function CreateDeployDoneFile {
    Param (
        [Parameter(Mandatory=$true)][String]$ResultPath,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][AllowNull()]$WrapperResult
    )

    CreateMarkerFile    -ResultPath $ResultPath `
                        -ApplicationKey $ApplicationKey `
                        -OperationId $OperationId `
                        -MarkerFileExtension $global:DeployDone `
                        -WrapperResult $WrapperResult
}

Function CreateUndeployDoneFile {
    Param (
        [Parameter(Mandatory=$true)][String]$ResultPath,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][AllowNull()]$WrapperResult
    )

    CreateMarkerFile    -ResultPath $ResultPath `
                        -ApplicationKey $ApplicationKey `
                        -OperationId $OperationId `
                        -MarkerFileExtension $global:UndeployDone `
                        -WrapperResult $WrapperResult
}

Function CreateUpdateConfigurationsFile {
    Param (
        [Parameter(Mandatory=$true)][String]$ResultPath,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][AllowNull()]$WrapperResult
    )

    CreateMarkerFile    -ResultPath $ResultPath `
                        -ApplicationKey $ApplicationKey `
                        -OperationId $OperationId `
                        -MarkerFileExtension $global:ConfigsDone `
                        -WrapperResult $WrapperResult
}
