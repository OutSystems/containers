$ExecutionPath = $ExecutionContext.SessionState.Module.ModuleBase

Import-Module WebAdministration
Import-Module $(Join-Path -Path "$ExecutionPath" -ChildPath "GeneralUtils.psm1") -Force

Function CreateSiteForWildcard {
    param(
        [Parameter(mandatory=$true)][string]$SiteFolder,
        [Parameter(mandatory=$true)][string]$SiteName
    )

    if (-not $(Get-WebSite -Name $SiteName)) {
        $Domain = (Get-WmiObject Win32_ComputerSystem).Domain
        $Hostname = $($(hostname) + "." + $Domain)

        Start-WebCommitDelay

        New-Item -Force -Path $SiteFolder -Type Directory

        $Site = "iis:\Sites\$SiteName"

        New-Item $Site -Bindings @{protocol="http";bindingInformation="*:80:$SiteName.$HostName"},@{protocol="https";bindingInformation="*:443:$SiteName.$HostName"} -physicalPath $SiteFolder -Force

        Stop-WebCommitDelay

        EchoAndLog "Created '$SiteName' website."

        Start-Website -Name $SiteName

        EchoAndLog "Started '$SiteName' website."

        Start-WebCommitDelay

        Set-WebConfiguration -Filter "/system.webServer/rewrite/allowedServerVariables" -Location "$SiteName" -Value (@{name="HTTP_X_FORWARDED_PROTO"})

        Stop-WebCommitDelay

        EchoAndLog "Added 'HTTP_X_FORWARDED_PROTO' allowed server variable to '$SiteName' website."

        # Just to force saving the web.config
        Start-WebCommitDelay

        Clear-WebConfiguration -PSPath $Site -Filter "system.webServer/rewrite/rules"

        Stop-WebCommitDelay
    } else {
        EchoAndLog "Website '$SiteName' already exists. Nothing was done."
    }
}

Function AddFallbackRewriteToSelfInboundRule {
    param(
        [Parameter(mandatory=$true)][string]$SiteName,
        [Parameter(mandatory=$true)][string]$OriginMachineFullyQualifiedName
    )

    $RuleName = "RewriteToSelf"

    $Site="iis:\sites\$SiteName"

    EchoAndLog "Creating URL Rewrite Inbound Rule to add rerouting back to original host ('$OriginMachineFullyQualifiedName') in '$SiteName' website."

    $FilterRewriteRules = "system.webServer/rewrite/rules"
    $FilterRoot = "$FilterRewriteRules/rule[@name='$RuleName']"

    Start-WebCommitDelay

    Clear-WebConfiguration -PSPath $Site -Filter $FilterRoot

    Stop-WebCommitDelay

    Start-WebCommitDelay

    Add-WebConfigurationProperty -PSPath $Site -Filter "$FilterRewriteRules" -Name "." -Value @{name=$RuleName; stopProcessing='True'}
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/match" -Name "url" -Value "(.*)"
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/action" -Name "type" -Value "Rewrite"
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/action" -Name "url" -Value "https://$OriginMachineFullyQualifiedName/{R:1}"

    Stop-WebCommitDelay
}

Function AddProxyHeaderInboundRule {
    param(
        [Parameter(mandatory=$true)][string]$SiteName,
        [Parameter(mandatory=$true)][ValidateSet('Https', 'Http')][string]$Proto,
        [Parameter(mandatory=$true)][string]$AtIndex
    )

    $RuleName = "AddProxyHeaders" + $Proto

    $Site="iis:\sites\$SiteName"

    EchoAndLog "Creating URL Rewrite Inbound Rule for '$Proto' offloading headers in '$SiteName' website."

    $FilterRewriteRules = "system.webServer/rewrite/rules"

    $FilterRoot = "$FilterRewriteRules/rule[@name='$RuleName']"

    Start-WebCommitDelay

    Clear-WebConfiguration -PSPath $Site -Filter $FilterRoot

    Stop-WebCommitDelay

    Start-WebCommitDelay

    $HttpsState = if ($Proto -eq "Https") { "ON" } else { "OFF" }
    Add-WebConfigurationProperty -PSPath $Site -Filter "$FilterRewriteRules" -Name "." -Value @{name=$RuleName; stopProcessing='False'} -AtIndex $AtIndex
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/match" -Name "url" -Value "(.*)"
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/action" -Name "type" -Value "None"
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/conditions" -Name "." -Value @{logicalGrouping="MatchAll";trackAllCaptures="false"}
    Set-WebConfiguration -PSPath $Site -Filter "$FilterRoot/conditions" -Value @{input="{HTTPS}";pattern=$HttpsState}
    Set-WebConfiguration -PSPath $Site -Filter "$FilterRoot/serverVariables" -Value (@{name="HTTP_X_FORWARDED_PROTO";value=$Proto.ToLowerInvariant()})

    Stop-WebCommitDelay
}

Function AddURLRewriteInboundRule {
    param(
        [Parameter(mandatory=$true)][string]$SiteName,
        [Parameter(mandatory=$true)][string]$TargetHostName,
        [Parameter(mandatory=$true)][string]$ModuleName
    )

    $MatchString = $ModuleName
    $RuleName = $ModuleName

    $Site="iis:\sites\$SiteName"

    EchoAndLog "Creating URL Rewrite Inbound Rule for '$MatchString' in '$SiteName' website."

    $FilterRewriteRules = "system.webServer/rewrite/rules"
    $FilterRoot = "$FilterRewriteRules/rule[@name='$RuleName']"

    Start-WebCommitDelay

    Clear-WebConfiguration -PSPath $Site -Filter $FilterRoot

    Stop-WebCommitDelay

    Start-WebCommitDelay

    Add-WebConfigurationProperty -PSPath $Site -Filter "$FilterRewriteRules" -Name "." -Value @{name=$RuleName;patternSyntax='Regular Expressions';stopProcessing='True'}
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/match" -Name "url" -Value "^$MatchString/(.*)"
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/conditions" -Name "logicalGrouping" -Value "MatchAny"
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/action" -Name "type" -Value "Rewrite"
    Set-WebConfigurationProperty -PSPath $Site -Filter "$FilterRoot/action" -Name "url" -Value "http://${TargetHostName}/$ModuleName/{R:1}"

    Stop-WebCommitDelay
}

Function RemoveURLRewriteInboundRule {
    param(
        [Parameter(mandatory=$true)][string]$SiteName,
        [Parameter(mandatory=$true)][string]$RuleName
    )

    EchoAndLog "Removing URL Rewrite Inbound Rule with name '$RuleName' from '$SiteName' website."

    $Site = "iis:\sites\$SiteName"

    $FilterRoot = "system.webServer/rewrite/rules/rule[@name='$RuleName']"

    Start-WebCommitDelay

    Clear-WebConfiguration -PSPath $Site -Filter $FilterRoot

    Stop-WebCommitDelay
}

Function GetURLRewriteInboundRule {
    param(
        [Parameter(mandatory=$true)][string]$SiteName,
        [Parameter(mandatory=$true)][string]$RuleName
    )

    $Site = "iis:\sites\$SiteName"

    $FilterRoot = "system.webServer/rewrite/rules/rule[@name='$RuleName']"

    Get-WebConfigurationProperty -PSPath $Site -Filter $FilterRoot -Name "."
}

Function CheckIfRewriteRulesCanBeRemoved {
    param(
        [Parameter(mandatory=$true)][ApplicationInfo]$ApplicationInfo,
        [Parameter(mandatory=$true)][string]$TargetHostName,
        [Parameter(mandatory=$true)][string[]]$ModuleNames
    )

    foreach ($ModuleName in $ModuleNames) {
        $RewriteURL = $(GetURLRewriteInboundRule -SiteName $ApplicationInfo.SiteName -RuleName $ModuleName)

        if ($RewriteURL -and $RewriteURL.action.url.Contains("http://$TargetHostName/")) {
            continue
        } else {
            return $false
        }
    }

    return $true
}

Function AddReroutingRules {
    param(        
        [Parameter(mandatory=$true)][object]$ApplicationInfo,
        [Parameter(mandatory=$true)][string]$OriginMachineFullyQualifiedName,
        [Parameter(mandatory=$true)][string]$TargetHostName,
        [Parameter(mandatory=$true)][string[]]$ModuleNames
    )

    if ($ApplicationInfo.SiteName -ne "Default Web Site") {
        CreateSiteForWildcard   -SiteFolder $ApplicationInfo.ParentFolder `
                                -SiteName $ApplicationInfo.SiteName
    } else {
        EchoAndLog "Pointing to 'Default Web Site'. No specific website was created."
    }

    AddProxyHeaderInboundRule -SiteName $ApplicationInfo.SiteName -Proto "Https" -AtIndex 0
    AddProxyHeaderInboundRule -SiteName $ApplicationInfo.SiteName -Proto "Http" -AtIndex 1

    foreach ($ModuleName in $ModuleNames) {
        AddURLRewriteInboundRule    -SiteName $ApplicationInfo.SiteName `
                                    -TargetHostName $TargetHostName `
                                    -ModuleName $ModuleName
    }

    AddFallbackRewriteToSelfInboundRule -SiteName $ApplicationInfo.SiteName `
                                        -OriginMachineFullyQualifiedName $OriginMachineFullyQualifiedName
}

Function RemoveReroutingRules {
    param(
        [Parameter(mandatory=$true)][object]$ApplicationInfo,
        [Parameter(mandatory=$true)][string[]]$ModuleNames
    )

    RemoveURLRewriteInboundRule -SiteName $ApplicationInfo.SiteName `
                                -RuleName "AddProxyHeadersHttps"

    RemoveURLRewriteInboundRule -SiteName $ApplicationInfo.SiteName `
                                -RuleName "AddProxyHeadersHttp"

    foreach ($ModuleName in $ModuleNames) {
        $RuleName = $ModuleName

        RemoveURLRewriteInboundRule -SiteName $ApplicationInfo.SiteName `
                                    -RuleName $RuleName
    }
}