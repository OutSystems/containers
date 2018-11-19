Param (
    [parameter(Mandatory=$true)][String]$HostingTechnology
)

$ErrorActionPreference = "Stop"

$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

if (-not $HostingTechnology) {
    throw "No Hosting Technology was specified!"
}

$SettingsForHostingTechnology = $(Join-Path -Path "$ExecutionPath" -ChildPath "$HostingTechnology/Settings.psm1")
$WrapperForHostingTechnology = $(Join-Path -Path "$ExecutionPath" -ChildPath "$HostingTechnology/Wrapper.psm1")

if ( (-not (Test-Path $SettingsForHostingTechnology)) -or (-not (Test-Path $WrapperForHostingTechnology)) ) {
    throw "[$HostingTechnology] not correctly configured. Check if the required files (Settings.psm1 and Wrapper.psm1) exist in path '$(Split-Path $SettingsForHostingTechnology -Parent)' and are implementing the correct method signatures."
}

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "GlobalSettings.psm1") -Force
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "Constants.psm1") -Force

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "../utils/Logger.psm1")
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "../utils/GeneralUtils.psm1") -Force
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "../utils/DeployUtils.psm1") -Force

# If $global:ArtefactsBasePath is not configured, default to execution path
if (-not $global:ArtefactsBasePath) {
    $ArtefactsBasePath = "$ExecutionPath/../"
} else {
    $ArtefactsBasePath = $global:ArtefactsBasePath
}

$global:ArtefactsBasePath = $(Join-Path -Path $ArtefactsBasePath -ChildPath "$($global:ArtefactsFolderName)/$HostingTechnology/")
$(New-Item -Force -Path $global:ArtefactsBasePath -ItemType Directory) 2>&1>$null
$global:ArtefactsBasePath = $(Resolve-Path $global:ArtefactsBasePath)

Import-Module $SettingsForHostingTechnology -Force
Import-Module $WrapperForHostingTechnology -Force

Function ContainerBuild {
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

    ExecOperation   -OperationName "ContainerBuild" `
                    -MarkerFile "PrepareDone" `
                    -Address $Address `
                    -ApplicationName $ApplicationName `
                    -ApplicationKey $ApplicationKey `
                    -OperationId $OperationId `
                    -TargetPath $TargetPath `
                    -ResultPath $ResultPath `
                    -ConfigPath $ConfigPath `
                    -AdditionalParameters $AdditionalParameters
}

Function ContainerRun {
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

    ExecOperation   -OperationName "ContainerRun" `
                    -MarkerFile "DeployDone" `
                    -Address $Address `
                    -ApplicationName $ApplicationName `
                    -ApplicationKey $ApplicationKey `
                    -OperationId $OperationId `
                    -TargetPath $TargetPath `
                    -ResultPath $ResultPath `
                    -ConfigPath $ConfigPath `
                    -AdditionalParameters $AdditionalParameters
}

Function ContainerRemove {
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

    ExecOperation   -OperationName "ContainerRemove" `
                    -MarkerFile "UndeployDone" `
                    -Address $Address `
                    -ApplicationName $ApplicationName `
                    -ApplicationKey $ApplicationKey `
                    -OperationId $OperationId `
                    -TargetPath $TargetPath `
                    -ResultPath $ResultPath `
                    -ConfigPath $ConfigPath `
                    -AdditionalParameters $AdditionalParameters
}

Function UpdateConfigurations {
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

    ExecOperation   -OperationName "UpdateConfigurations" `
                    -MarkerFile "UpdateConfigurations" `
                    -Address $Address `
                    -ApplicationName $ApplicationName `
                    -ApplicationKey $ApplicationKey `
                    -OperationId $OperationId `
                    -TargetPath $TargetPath `
                    -ResultPath $ResultPath `
                    -ConfigPath $ConfigPath `
                    -AdditionalParameters $AdditionalParameters
}

Function LogResultError {
    Param (
        [Parameter(Mandatory=$true)][String]$OperationName,
        [Parameter(Mandatory=$true)]$Result
    )

    if ($Result.Error) {
        WriteLog -Level "FATAL" -Message "Something went wrong when handling '$OperationName': $($Result.Error | Out-String)"
    }
}

Function StringifyParameters {
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
    
    $StringifiedAdditionalParameters = ""

    $StringifiedAdditionalParameters += "-Address '$Address' `` "
    $StringifiedAdditionalParameters += "-ApplicationName '$ApplicationName' `` "
    $StringifiedAdditionalParameters += "-ApplicationKey '$ApplicationKey' `` "
    $StringifiedAdditionalParameters += "-OperationId '$OperationId' `` "
    $StringifiedAdditionalParameters += "-TargetPath '$TargetPath' `` "
    $StringifiedAdditionalParameters += "-ResultPath '$ResultPath' `` "
    $StringifiedAdditionalParameters += "-ConfigPath '$ConfigPath' `` "

    foreach ($Key in $AdditionalParameters.Keys) { 
        $StringifiedAdditionalParameters += "-$Key '$($AdditionalParameters[$Key])' `` " 
    }

    return $StringifiedAdditionalParameters
}

Function ExecOperation {
    Param (
        [Parameter(Mandatory=$true)][String]$OperationName,
        [Parameter(Mandatory=$true)][String]$MarkerFile,
        [Parameter(Mandatory=$true)][String]$Address,
        [Parameter(Mandatory=$true)][String]$ApplicationName,
        [Parameter(Mandatory=$true)][String]$ApplicationKey,
        [Parameter(Mandatory=$true)][String]$OperationId,
        [Parameter(Mandatory=$true)][String]$TargetPath,
        [Parameter(Mandatory=$true)][String]$ResultPath,
        [Parameter(Mandatory=$true)][String]$ConfigPath,
        [Parameter(Mandatory=$true)][Hashtable]$AdditionalParameters
    )

    $Result = @{}

    try {
        $Address = $(ConvertIfFromBase64 -Text $Address)
        $ApplicationName = $(ConvertIfFromBase64 -Text $ApplicationName)
        $ApplicationKey = $(ConvertIfFromBase64 -Text $ApplicationKey)
        $OperationId = $(ConvertIfFromBase64 -Text $OperationId)
        $TargetPath = $(ConvertIfFromBase64 -Text $TargetPath)
        $ResultPath = $(ConvertIfFromBase64 -Text $ResultPath)
        $ConfigPath = $(ConvertIfFromBase64 -Text $ConfigPath)

        WriteLog "Starting [$OperationName] for app '$ApplicationName' ($($ApplicationKey)_$($OperationId))."

        $StringifiedAdditionalParameters = $(StringifyParameters    -Address $Address `
                                                                    -ApplicationName $ApplicationName `
                                                                    -ApplicationKey $ApplicationKey `
                                                                    -OperationId $OperationId `
                                                                    -TargetPath $TargetPath `
                                                                    -ResultPath $ResultPath `
                                                                    -ConfigPath $ConfigPath `
                                                                    -AdditionalParameters $AdditionalParameters)

        WriteLog -Level "DEBUG" -Message "Parameters: $StringifiedAdditionalParameters" -LogFile $LogFile

        # The functions for each of the operations will be defined in a given module's Wrapper.psm1
        $OperationResult = $(&"Wrapper_$OperationName"  -Address $Address `
                                                        -ApplicationName $ApplicationName `
                                                        -ApplicationKey $ApplicationKey `
                                                        -OperationId $OperationId `
                                                        -TargetPath $TargetPath `
                                                        -ResultPath $ResultPath `
                                                        -ConfigPath $ConfigPath `
                                                        -AdditionalParameters $AdditionalParameters)

        if ($OperationResult -and ($OperationResult.Error -or $OperationResult.SkipPing)) {
            $Result = $OperationResult
        } else {
            $Result.AdditionalInfo = "Everything went well. Check [ $($global:LogFilePath) ] for more info."
        }

    } catch {
        # If we hit his, we won't have a valid Result, let's initialize it
        $Result = NewWrapperResult
        $Result.Error = "Something went critically wrong: $_ : $($_.ScriptStackTrace)"

        throw $_
    } finally {
        # The functions to create marker files are defined in DeployUtils.psm1
        $(&"Create$($MarkerFile)File"   -ResultPath $ResultPath `
                                        -ApplicationKey $ApplicationKey `
                                        -OperationId $OperationId `
                                        -WrapperResult $Result)

        LogResultError  -OperationName $OperationName `
                        -Result $Result

        $Message = "[$OperationName] for app '$ApplicationName' ($($ApplicationKey)_$($OperationId)) finished"

        if (-not ($Result.Error)) {
            WriteLog "$Message successfully."
        } else {
            WriteLog "$Message unsuccessfully."
        }
    }
}
