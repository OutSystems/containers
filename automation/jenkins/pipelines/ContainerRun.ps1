param(
    [Parameter(Mandatory=$true)][String]$MachineFullyQualifiedName,
    [Parameter(Mandatory=$true)][String]$SiteName,
    [Parameter(Mandatory=$true)][String]$ApplicationKey,
    [Parameter(Mandatory=$true)][String]$OperationID,
    [Parameter(Mandatory=$true)][String]$BundlesFolder,
    [Parameter(Mandatory=$true)][AllowEmptyString()][String]$SubdomainsFolder,
    [Parameter(Mandatory=$true)][String]$UnzippedBundlesFolder,
    [Parameter(Mandatory=$true)][String]$ConfigsFolder,
    [Parameter(Mandatory=$true)][String]$SecretsFolder,
    [Parameter(Mandatory=$true)][String]$ResultsFolder
)

$ScriptsPath = $(Join-Path -Path "$PSScriptRoot" -ChildPath "../scripts/")
Import-Module $(Join-Path -Path "$ScriptsPath" -ChildPath "ContainerUtils.psm1") -Force

$SourceIdentifier = "Jenkins"

HandleDeploy    -SourceIdentifier $SourceIdentifier `
                -OriginMachineFullyQualifiedName $MachineFullyQualifiedName `
                -SiteName $SiteName `
                -ApplicationKey $ApplicationKey `
                -OperationID $OperationID `
                -SubdomainsFolder $SubdomainsFolder `
                -UnzippedBundlesFolder $UnzippedBundlesFolder `
                -ConfigsFolder $ConfigsFolder `
                -SecretsFolder $SecretsFolder `
                -ResultsFolder $ResultsFolder