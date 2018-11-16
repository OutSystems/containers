<# 
To debug using Visual Code:
    Use Open Folder to load the project
    Set (in this file) the $HostingTechnology you want to debug
    Call the function you want to debug
    Set up breakpoints as needed
    Start Debugging! (press F5)
#>

# select the Hosting Technology: needs to exist the implementation in /modules/{HostingTechnology}
$HostingTechnology = "DockerEEPlusIIS"

Import-Module C:/jenkins/modules/HostingTechnologyModuleLoader.psm1 -Force -ArgumentList $HostingTechnology

$SiteName = "testing"
$PlatformServerFQMN = "your.machine"

# Call here any of the four main operations: ContainerBuild, ContainerRun, UpdateConfigurations and ContainerRemove
ContainerBuild  -Address "testing" `
                -ApplicationName "testapp" `
                -ApplicationKey "" `
                -OperationId "" `
                -TargetPath "" `
                -ResultPath "" `
                -ConfigPath "" `
                -AdditionalParameters @{ "SiteName"="$SiteName" ; "PlatformServerFQMN"="$PlatformServerFQMN" }
