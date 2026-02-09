<#
.SYNOPSIS
    PSAppDeployToolkit Extensions - Eclipse ABAP Installer
.DESCRIPTION
    Custom extension functions for the Eclipse ABAP deployment.
    These functions extend the base PSADT toolkit with Eclipse-specific capabilities.
.NOTES
    This file is dot-sourced by the main Deploy-Application.ps1 script.
#>

##*===============================================
##* EXTENSION FUNCTIONS
##*===============================================

function Test-JavaInstalled {
    <#
    .SYNOPSIS
        Checks if a compatible Java runtime is installed and accessible.
    .OUTPUTS
        [PSCustomObject] with properties: Installed (bool), Version (string), Path (string)
    #>
    [CmdletBinding()]
    Param()

    $result = [PSCustomObject]@{
        Installed = $false
        Version   = ''
        Path      = ''
    }

    # Check JAVA_HOME first
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
        $result.Path = "$env:JAVA_HOME\bin\java.exe"
    }
    else {
        # Search PATH
        $javaCmd = Get-Command 'java.exe' -ErrorAction SilentlyContinue
        if ($javaCmd) {
            $result.Path = $javaCmd.Source
        }
    }

    if ($result.Path) {
        try {
            $versionOutput = & $result.Path -version 2>&1 | Select-Object -First 1
            if ($versionOutput -match '(\d+[\.\d+]*)') {
                $result.Version = $Matches[1]
                $result.Installed = $true
            }
        }
        catch {
            Write-Warning "Found java at $($result.Path) but unable to determine version."
        }
    }

    return $result
}

function Get-EclipseInstalledPlugins {
    <#
    .SYNOPSIS
        Returns a list of installed Eclipse plugins/features.
    .PARAMETER EclipsePath
        Path to the Eclipse installation directory.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [String]$EclipsePath
    )

    $featuresDir = Join-Path $EclipsePath 'features'
    if (-not (Test-Path $featuresDir)) {
        Write-Warning "Features directory not found: $featuresDir"
        return @()
    }

    $features = Get-ChildItem -Path $featuresDir -Directory | ForEach-Object {
        $parts = $_.Name -split '_', 2
        [PSCustomObject]@{
            FeatureId = $parts[0]
            Version   = if ($parts.Count -gt 1) { $parts[1] } else { 'unknown' }
            FullName  = $_.Name
        }
    }

    return $features
}

function Test-ADTPluginInstalled {
    <#
    .SYNOPSIS
        Checks if SAP ABAP Development Tools are installed in the Eclipse instance.
    .PARAMETER EclipsePath
        Path to the Eclipse installation directory.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [String]$EclipsePath
    )

    $plugins = Get-EclipseInstalledPlugins -EclipsePath $EclipsePath
    $adtInstalled = $plugins | Where-Object { $_.FeatureId -like 'com.sap.adt*' }

    if ($adtInstalled) {
        Write-Host "SAP ADT plugins found: $($adtInstalled.Count) feature(s)"
        $adtInstalled | ForEach-Object { Write-Host "  - $($_.FeatureId) v$($_.Version)" }
        return $true
    }

    return $false
}

function Set-EclipseIniProperty {
    <#
    .SYNOPSIS
        Sets or updates a property in eclipse.ini.
    .PARAMETER IniPath
        Full path to eclipse.ini.
    .PARAMETER Property
        The property name (e.g., '-Xmx').
    .PARAMETER Value
        The value to set (e.g., '2048m').
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [String]$IniPath,

        [Parameter(Mandatory)]
        [String]$Property,

        [Parameter(Mandatory)]
        [String]$Value
    )

    if (-not (Test-Path $IniPath)) {
        Write-Warning "eclipse.ini not found at: $IniPath"
        return
    }

    $content = Get-Content $IniPath
    $pattern = [regex]::Escape($Property) + '\S*'
    $replacement = "$Property$Value"

    $found = $false
    $newContent = $content | ForEach-Object {
        if ($_ -match $pattern) {
            $found = $true
            $replacement
        }
        else {
            $_
        }
    }

    if (-not $found) {
        # Add before -vmargs if the property doesn't exist
        $newContent = @()
        foreach ($line in $content) {
            if ($line -eq '-vmargs' -and -not $found) {
                $newContent += $replacement
                $found = $true
            }
            $newContent += $line
        }
    }

    Set-Content -Path $IniPath -Value $newContent -Encoding UTF8
    Write-Host "eclipse.ini updated: $Property$Value"
}
