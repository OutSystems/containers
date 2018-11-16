$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

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

    $Result = NewWrapperResult

    try {
        
    } catch {
        $Result.Error = $_
    }

    return $Result
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

    $Result = NewWrapperResult

    try {

    } catch {
        $Result.Error = $_
    }

    $Result.SkipPing = $true
    return $Result
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

    $Result = NewWrapperResult

    try {

    } catch {
        $Result.Error = $_
    }

    return $Result
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

    $Result = NewWrapperResult

    try {

    } catch {
        $Result.Error = $_
    }

    return $Result
}
