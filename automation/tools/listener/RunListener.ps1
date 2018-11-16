Param (
    $Port
)

[Console]::OutputEncoding = New-Object -typename System.Text.UTF8Encoding

$ExecutionPath = $PSScriptRoot

Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "AutomationHookListener.psm1") -Force

if (-not $Port) {
    $Port = 8080
}

AutomationHookListener -Port $Port
