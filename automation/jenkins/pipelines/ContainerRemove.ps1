param(
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

foreach ($Bundle in $(Get-ChildItem $BundlesFolder -Filter "*$ApplicationKey*")) {
    try {
        Write-Host "Deleting '$($Bundle.FullName)'..."

        Remove-Item $Bundle.FullName -Force

        $FileName = $(RemoveLastInstance -Of '.zip' -In $Bundle.Name)

        $SplitDeploymentInfo = $FileName -split "_"

        $LocalOperationID = $SplitDeploymentInfo[$SplitDeploymentInfo.Length-1]

        HandleContainerBundleDeletion   -SourceIdentifier $SourceIdentifier `
                                        -SiteName $SiteName `
                                        -ApplicationKey $ApplicationKey `
                                        -OperationID $LocalOperationID `
                                        -SubdomainsFolder $SubdomainsFolder `
                                        -UnzippedBundlesFolder $UnzippedBundlesFolder `
                                        -ConfigsFolder $ConfigsFolder `
                                        -SecretsFolder $SecretsFolder `
                                        -ResultsFolder $ResultsFolder
    } catch {
        Write-Host "Bundle deletion of '$($Bundle.FullName)' failed! Moving on... More info: $_"
    }
}

CreateUndeployDoneFile  -ResultsFolder $ResultsFolder `
                        -ApplicationKey $ApplicationKey `
                        -OperationID $OperationID