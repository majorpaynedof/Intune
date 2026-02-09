<#
.SYNOPSIS
    Intune Win32 Detection Script for Eclipse IDE with ABAP Development Tools.
.DESCRIPTION
    This script is used as a custom detection rule in Microsoft Intune.
    It checks whether Eclipse with ABAP Development Tools is properly installed.

    Detection logic:
      1. Checks the Intune managed apps registry key.
      2. Verifies eclipse.exe exists at the expected installation path.
      3. Confirms at least one SAP ADT feature is present.

    If ALL checks pass, the script writes output to STDOUT (indicating detected).
    If any check fails, the script exits silently (indicating not detected).
.NOTES
    Usage in Intune:
      - Detection rule type: Custom detection script
      - Script file: Detect-EclipseABAP.ps1
      - Run as 32-bit: No
#>

$eclipseInstallDir = "$env:ProgramFiles\Eclipse\eclipse-abap"
$regPath = 'HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP'

try {
    # Check 1: Registry key exists
    if (-not (Test-Path $regPath)) {
        exit
    }

    # Check 2: Eclipse executable exists
    $eclipseExe = Join-Path $eclipseInstallDir 'eclipse.exe'
    if (-not (Test-Path -LiteralPath $eclipseExe -PathType Leaf)) {
        exit
    }

    # Check 3: ADT features directory contains SAP plugins
    $featuresDir = Join-Path $eclipseInstallDir 'features'
    if (Test-Path $featuresDir) {
        $adtFeatures = Get-ChildItem -Path $featuresDir -Directory -Filter 'com.sap.adt*' -ErrorAction SilentlyContinue
        if (-not $adtFeatures -or $adtFeatures.Count -eq 0) {
            exit
        }
    }
    else {
        exit
    }

    # All checks passed - output detection string
    $version = (Get-ItemProperty -Path $regPath -Name 'DisplayVersion' -ErrorAction SilentlyContinue).DisplayVersion
    Write-Output "Eclipse ABAP $version detected at $eclipseInstallDir"
}
catch {
    # Detection failed silently
    exit
}
