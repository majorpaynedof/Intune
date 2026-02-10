<#
.SYNOPSIS
    Intune Win32 Detection Script for Eclipse IDE for Java Developers with ABAP Development Tools.
.DESCRIPTION
    This script is used as a custom detection rule in Microsoft Intune.
    It checks whether Eclipse with ABAP Development Tools is properly installed
    at the location matching the documented build guide.

    Detection logic:
      1. Checks the Intune managed apps registry key exists and version matches.
      2. Verifies eclipse.exe exists at C:\Users\Public\Eclipse\java-latest-released\eclipse.
      3. Confirms at least one SAP ADT feature is present.

    If ALL checks pass, the script writes output to STDOUT (indicating detected).
    If any check fails, the script exits silently (indicating not detected).
.NOTES
    Usage in Intune:
      - Detection rule type: Custom detection script
      - Script file: Detect-EclipseABAP.ps1
      - Run script as 32-bit process: No
      - Enforce script signature check: No (unless signed)
#>

# Must match the values in Deploy-Application.ps1
$expectedVersion   = '2024-09'
$eclipseInstallDir = "$env:PUBLIC\Eclipse\java-latest-released\eclipse"
$regPath           = 'HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP'

try {
    # Check 1: Registry key exists with expected version
    if (-not (Test-Path $regPath)) {
        exit
    }

    $regProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if (-not $regProps -or $regProps.DisplayVersion -ne $expectedVersion) {
        exit
    }

    # Check 2: Eclipse executable exists at the documented path
    $eclipseExe = Join-Path $eclipseInstallDir 'eclipse.exe'
    if (-not (Test-Path -LiteralPath $eclipseExe -PathType Leaf)) {
        exit
    }

    # Check 3: ADT features directory contains SAP plugins
    $featuresDir = Join-Path $eclipseInstallDir 'features'
    if (-not (Test-Path $featuresDir)) {
        exit
    }

    $adtFeatures = Get-ChildItem -Path $featuresDir -Directory -Filter 'com.sap.adt*' -ErrorAction SilentlyContinue
    if (-not $adtFeatures -or $adtFeatures.Count -eq 0) {
        exit
    }

    # All checks passed - write to STDOUT so Intune marks as "Detected"
    Write-Output "Eclipse ABAP $expectedVersion detected at $eclipseInstallDir with $($adtFeatures.Count) ADT feature(s)"
}
catch {
    # Detection failed silently - Intune treats no STDOUT as "Not detected"
    exit
}
