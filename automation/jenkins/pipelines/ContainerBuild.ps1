param(
    [Parameter(Mandatory=$true)][String]$SiteName,
    [Parameter(Mandatory=$true)][String]$ApplicationKey,
    [Parameter(Mandatory=$true)][String]$OperationID,
    [Parameter(Mandatory=$true)][String]$BundlesFolder,
    [Parameter(Mandatory=$true)][String]$UnzippedBundlesFolder,
    [Parameter(Mandatory=$true)][String]$ResultsFolder
)

$ScriptsPath = $(Join-Path -Path "$PSScriptRoot" -ChildPath "../scripts/")
Import-Module $(Join-Path -Path "$ScriptsPath" -ChildPath "ContainerUtils.psm1") -Force

$SourceIdentifier = "Jenkins"

HandlePrepareDeploy -SourceIdentifier $SourceIdentifier `
                    -SiteName $SiteName `
                    -ApplicationKey $ApplicationKey `
                    -OperationID $OperationID `
                    -BundlesFolder $BundlesFolder `
                    -UnzippedBundlesFolder $UnzippedBundlesFolder `
                    -ResultsFolder $ResultsFolder