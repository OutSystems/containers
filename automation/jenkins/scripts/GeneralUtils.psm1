$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "thirdparty\Logger.psm1") -Force

Function EchoAndLog([string]$Message) {
    $TimestampedMessage = "[$(Get-Date -Format o)]: $Message"

    WriteLogLine $TimestampedMessage
}

Function RemoveLastInstance {
    param(
        [Parameter(mandatory=$true)][string]$Of,
        [Parameter(mandatory=$true)][string]$In
    )

    return ($In -replace "(.*)$Of(.*)", "`$1`$2")
}

Function GetSubFolders([string]$path) {
    $SubFolders = @()

    foreach ($entry in (Get-ChildItem $path -Directory)) {
        $SubFolders += $entry.Name
    }

    return $SubFolders
}

Function IsZipFileValid {
    param(
        [Parameter(mandatory=$true)][string]$Filepath
    )

    $ZipFile = $Null

    try {
        [Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') 2>&1>$null
        $ZipFile = [IO.Compression.ZipFile]::OpenRead($Filepath)

        return $true
    } catch {
        return $false
    } finally {
        if ($ZipFile) {
            $ZipFile.Dispose()
        }
    }
}

Function GetHoldOfZipFile {
    param(
        [Parameter(mandatory=$true)][string]$SourceIdentifier,
        [Parameter(mandatory=$true)][string]$Filepath,
        [Parameter(mandatory=$true)][int]$Timeout,
        [switch]$ForciblyCloseHandlesOnLastTry=$false
    )

    EchoAndLog "'$SourceIdentifier': Trying to get a hold of '$Filepath'. Timeout is set to $Timeout seconds."

    $Start = Get-Date

    while ($true) {
        try {
            if (-not (Test-Path $Filepath)) {
                $Timeout = -5
                throw "'$Filepath' no longer exists."
            }

            $File = New-Object System.IO.FileInfo $Filepath

            $File.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None).Close()

            if (-not (IsZipFileValid -Filepath $Filepath)) {
                $Timeout = -5
                throw  "'$Filepath' is not a valid zip file."
            }

            EchoAndLog "'$SourceIdentifier': Successfully got a hold on '$Filepath'."

            break
        } catch {
            if ($Start.AddSeconds($Timeout) -lt $(Get-Date)) {
                if ($ForciblyCloseHandlesOnLastTry) {
                    EchoAndLog "'$SourceIdentifier': All else failed, will try to forcefully kill file handles on '$Filepath'."

                    $ForciblyCloseHandlesOnLastTry = $false

                    if (-not $(KillNetworkFileHandles -Filepath $Filepath)) {
                        EchoAndLog "'$SourceIdentifier': No network file handles found for '$Filepath'."

                        if (-not $(KillFileHandles -Filepath $Filepath)) {
                            EchoAndLog "'$SourceIdentifier': No local file handles found for '$Filepath'."
                        }
                    }
                } else {
                    throw "Unable to access '$Filepath'. Exception: $_"
                }
            }

            Start-Sleep -Seconds 5
        }
    }
}

Function IsNumeric {
    param(
        [Parameter(mandatory=$true)][string][AllowEmptyString()][AllowNull()]$Value
    )

    if (-not $Value) {
        return $false
    }

    return $Value -match '^[0-9]+$'
}

Function KillFileHandles {
    param(
        [Parameter(mandatory=$true)][string]$Filepath
    )

    $status = $false

    try {
        $HandleExeRelativePath = "thirdparty\Handle.exe"

        $HandleExePath = $(Join-Path -Path "$ExecutionPath" -ChildPath $HandleExeRelativePath)

        if (-not Test-Path $HandleExePath) {
            EchoAndLog "'$HandleExeRelativePath' not found, doing nothing."
            return $true
        }

        $handleListOutput = Invoke-Expression "$HandleExePath '$Filepath'"

        foreach ($listLine in $handleListOutput) {
            if ($listLine.contains("File") -and $listLine.contains("$Filepath")) {
                $split = $listLine -split "\s+"

                $HandlePID = $split[2]
                $HandleHex = $split[5]

                $handleKillOutput = Invoke-Expression "$HandleExePath -c $HandleHex -y -p $HandlePID"

                if ($handleKillOutput -like "*Handle closed.") {
                    EchoAndLog "Killed local file handle: '$($handleKillOutput -like "*$Filepath")'."
                    $status = $true
                } else {
                    EchoAndLog "Unable to close local file handle: '$handleKillOutput'."
                }
            }
        }
    } catch {
        throw "Critical failure on KillFileHandles: $_"
    }

    return $status
}

Function KillNetworkFileHandles {
    param(
        [Parameter(mandatory=$true)][string]$Filepath
    )

    $status = $false

    try {
        $results = net file

        if (-not ($results -like "There are no entries in the list.")) {
            foreach ($result in $results) {
                #Get id
                $id = $result.Split(" ")[0]

                if (IsNumeric -Value $id) {
                    $info = $(net file $id)

                    if ($info -like "*$Filepath*") {
                        #Close file
                        net file $id /close

                        EchoAndLog "Killed network file handle: '$($result)'."
                        $status = $true
                    }
                }
            }
        }
    } catch {
        throw "Critical failure on KillNetworkFileHandles: $_"
    }

    return $status
}

Function FastCompareContentsOfZipWithFolder([string]$zipPath, [string]$folderPath, [string]$basePath = $zipPath, $app = $(New-Object -COM 'Shell.Application'), [bool]$Result = $true) {
    foreach ($entry in $app.NameSpace($zipPath).Items()) {
        if ($entry.IsFolder) {

            $Result = $(FastCompareContentsOfZipWithFolder $entry.Path $folderPath $basePath $app $Result)

        } else {
            $fileInZipRelativePath = $($entry.Path -replace [regex]::escape($basePath), '')

            $fileInFolderPath = $(Join-Path -Path "$FolderPath" -ChildPath "$fileInZipRelativePath")

            if (-not $(Test-Path $fileInFolderPath)) {
                return $false;
            } else {
                $fileInFolder = $(Get-Item $fileInFolderPath)

                if (-not ($fileInFolder -is [System.IO.DirectoryInfo])) {
                    $fileInZip = $entry

                    if ($fileInFolder.Length -ne $fileInZip.Size) {
                        return $false
                    }
                }
            }
        }
    }

    return $Result
}

Function FastCompareContentsOfFolderWithZip([string]$folderPath, [string]$zipPath) {
    $app = New-Object -COM 'Shell.Application'

    foreach ($entry in $(Get-ChildItem $folderPath -Recurse)) {
        $fileInFolderRelativePath = $($entry.FullName -replace [regex]::escape($folderPath), '')

        $fileInZipPath = $(Join-Path -Path "$zipPath" -ChildPath "$fileInFolderRelativePath")

        try {
            $fileInZip = $app.NameSpace($fileInZipPath)
        } catch {
            # Trying to access files without an extension that are on the root of a zip file
            # [ something like $app.NameSpace('[whatever].zip\[file_without_extension]') ]
            # throws a 'The method or operation is not implemented.'
            # We do this to workaround the issue:

            $filesInRootOfZip = $app.NameSpace($zipPath).Items()

            foreach ($fileInRootOfZip in $filesInRootOfZip) {
                if ($fileInRootOfZip.Name -eq $fileInFolderRelativePath) {
                    $fileInZip = @{}
                    $fileInZip.Self = @{}

                    $fileInZip.Self.Size = $fileInRootOfZip.Size
                    $fileInZip.Self.IsFolder = $false

                    break;
                }
            }
        }

        if (-not $fileInZip) {
            return $false
        } else {
            $fileInFolder = $entry

            if (-not $fileInZip.Self.IsFolder) {
                if ($fileInFolder.Length -ne $fileInZip.Self.Size) {
                    return $false
                }
            }
        }
    }

    return $true
}

Function FastCrossCheckFilesInFolderAndZip {
    param (
        [Parameter(Mandatory=$true)][string]$FolderPath,
        [Parameter(Mandatory=$true)][string]$ZipPath
    )

    return $(FastCompareContentsOfFolderWithZip $FolderPath $ZipPath) -and $(FastCompareContentsOfZipWithFolder $ZipPath $FolderPath)
}

Function RetryWithReturnValue {
    param (
        [Parameter(Mandatory=$true)][int16]$NRetries,
        [Parameter(Mandatory=$true)][string]$ExceptionMessage,
        [Parameter(Mandatory=$true)][Scriptblock]$Action,
        $ArgumentList
    )

    $InnerExceptionMessage = $null

    for ($i = 0; $i -lt $NRetries; $i++) {
        try {
            $Result = $Action.Invoke($ArgumentList)

            if ($Result) {
                return $Result
            } else {
                throw "Result was null with no exception thrown. Does the ScriptBlock have a return value?"
            }
        } catch {
            If (-not $InnerExceptionMessage) {
                $InnerExceptionMessage = $_
            }
        }
    }

    if ($InnerExceptionMessage) {
        throw "$ExceptionMessage First error (of $NRetries retries): $InnerExceptionMessage."
    } else {
        throw "$ExceptionMessage"
    }
}