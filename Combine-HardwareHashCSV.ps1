<#
.SYNOPSIS
    Combines multiple hardware hash CSV files into a single file for Windows Autopilot.

.DESCRIPTION
    This script safely combines multiple hardware hash CSV files into one consolidated file.
    It preserves the CSV structure, validates input files, and prevents corruption of original files.

    Features:
    - Validates CSV structure before combining
    - Preserves proper CSV formatting
    - Creates backup of existing output file
    - Handles duplicate entries
    - Supports custom encoding (UTF-8 with BOM by default for Autopilot)
    - Detailed logging and error handling

.PARAMETER SourcePath
    Path to the folder containing hardware hash CSV files to combine.
    Default: Current directory

.PARAMETER OutputFile
    Name or full path of the combined output CSV file.
    Default: Combined-HardwareHash.csv in the source path

.PARAMETER Recursive
    Search for CSV files recursively in subdirectories.

.PARAMETER RemoveDuplicates
    Remove duplicate entries based on Device Serial Number.

.PARAMETER CreateBackup
    Create a backup of the output file if it already exists.
    Default: $true

.EXAMPLE
    .\Combine-HardwareHashCSV.ps1
    Combines all CSV files in the current directory.

.EXAMPLE
    .\Combine-HardwareHashCSV.ps1 -SourcePath "C:\HardwareHashes" -OutputFile "Autopilot-All.csv"
    Combines all CSV files from specified path with custom output name.

.EXAMPLE
    .\Combine-HardwareHashCSV.ps1 -SourcePath "C:\HardwareHashes" -Recursive -RemoveDuplicates
    Recursively finds all CSV files and removes duplicates.

.NOTES
    Author: Claude
    Date: 2026-01-07
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourcePath = ".",

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "Combined-HardwareHash.csv",

    [Parameter(Mandatory = $false)]
    [switch]$Recursive,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveDuplicates,

    [Parameter(Mandatory = $false)]
    [bool]$CreateBackup = $true
)

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Type) {
        "Success" { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
        "Error"   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        "Warning" { Write-Host "[$timestamp] [WARNING] $Message" -ForegroundColor Yellow }
        default   { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
    }
}

# Function to validate hardware hash CSV structure
function Test-HardwareHashCSV {
    param(
        [string]$FilePath
    )

    try {
        # Check if file is empty
        if ((Get-Item $FilePath).Length -eq 0) {
            Write-ColorOutput "File is empty: $FilePath" -Type "Warning"
            return $false
        }

        # Read first line to check header
        $firstLine = Get-Content -Path $FilePath -TotalCount 1

        # Expected headers for hardware hash CSV (Windows Autopilot format)
        $expectedHeaders = @(
            "Device Serial Number,Windows Product ID,Hardware Hash",
            "Device Serial Number,Windows Product Id,Hardware Hash",  # Alternative casing
            "Serial Number,Windows Product ID,Hardware Hash"
        )

        $isValid = $false
        foreach ($header in $expectedHeaders) {
            if ($firstLine -like "*$($header.Split(',')[0])*" -and
                $firstLine -like "*Hardware Hash*") {
                $isValid = $true
                break
            }
        }

        if (-not $isValid) {
            Write-ColorOutput "File does not have expected hardware hash CSV format: $FilePath" -Type "Warning"
            return $false
        }

        return $true
    }
    catch {
        Write-ColorOutput "Error validating file $FilePath : $_" -Type "Error"
        return $false
    }
}

# Main script execution
try {
    Write-ColorOutput "Starting Hardware Hash CSV Combine Process" -Type "Info"
    Write-ColorOutput "=========================================" -Type "Info"

    # Resolve and validate source path
    $sourcePath = Resolve-Path -Path $SourcePath -ErrorAction Stop
    Write-ColorOutput "Source Path: $sourcePath" -Type "Info"

    # Determine output file path
    if ([System.IO.Path]::IsPathRooted($OutputFile)) {
        $outputPath = $OutputFile
    }
    else {
        $outputPath = Join-Path -Path $sourcePath -ChildPath $OutputFile
    }

    Write-ColorOutput "Output File: $outputPath" -Type "Info"

    # Get all CSV files from source path
    $searchParams = @{
        Path    = $sourcePath
        Filter  = "*.csv"
        File    = $true
    }

    if ($Recursive) {
        $searchParams.Add("Recurse", $true)
    }

    $csvFiles = Get-ChildItem @searchParams | Where-Object {
        $_.FullName -ne $outputPath  # Exclude output file if it exists
    }

    if ($csvFiles.Count -eq 0) {
        Write-ColorOutput "No CSV files found in the specified path." -Type "Warning"
        exit 1
    }

    Write-ColorOutput "Found $($csvFiles.Count) CSV file(s) to process" -Type "Info"

    # Validate all CSV files
    Write-ColorOutput "Validating CSV files..." -Type "Info"
    $validFiles = @()

    foreach ($file in $csvFiles) {
        Write-ColorOutput "Checking: $($file.Name)" -Type "Info"
        if (Test-HardwareHashCSV -FilePath $file.FullName) {
            $validFiles += $file
            Write-ColorOutput "  Valid: $($file.Name)" -Type "Success"
        }
        else {
            Write-ColorOutput "  Skipped: $($file.Name)" -Type "Warning"
        }
    }

    if ($validFiles.Count -eq 0) {
        Write-ColorOutput "No valid hardware hash CSV files found." -Type "Error"
        exit 1
    }

    Write-ColorOutput "$($validFiles.Count) valid file(s) will be combined" -Type "Success"

    # Create backup if output file exists
    if ($CreateBackup -and (Test-Path $outputPath)) {
        $backupPath = "$outputPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-ColorOutput "Creating backup: $backupPath" -Type "Info"
        Copy-Item -Path $outputPath -Destination $backupPath -Force
        Write-ColorOutput "Backup created successfully" -Type "Success"
    }

    # Combine CSV files
    Write-ColorOutput "Combining CSV files..." -Type "Info"
    $allData = @()
    $header = $null
    $processedCount = 0

    foreach ($file in $validFiles) {
        try {
            Write-ColorOutput "Processing: $($file.Name)" -Type "Info"

            # Import CSV content
            $csvContent = Import-Csv -Path $file.FullName -Encoding UTF8

            # Store header from first valid file
            if ($null -eq $header -and $csvContent.Count -gt 0) {
                $header = $csvContent[0].PSObject.Properties.Name
            }

            # Add data to collection
            $allData += $csvContent
            $processedCount++

            Write-ColorOutput "  Added $($csvContent.Count) record(s) from $($file.Name)" -Type "Success"
        }
        catch {
            Write-ColorOutput "Error processing $($file.Name): $_" -Type "Error"
            # Continue processing other files
        }
    }

    if ($allData.Count -eq 0) {
        Write-ColorOutput "No data records found to combine." -Type "Error"
        exit 1
    }

    Write-ColorOutput "Total records collected: $($allData.Count)" -Type "Info"

    # Remove duplicates if requested
    if ($RemoveDuplicates) {
        Write-ColorOutput "Removing duplicate entries..." -Type "Info"
        $originalCount = $allData.Count

        # Get the property name for serial number (could be "Device Serial Number" or "Serial Number")
        $serialNumberProperty = $allData[0].PSObject.Properties.Name | Where-Object {
            $_ -like "*Serial*Number*"
        } | Select-Object -First 1

        if ($serialNumberProperty) {
            $allData = $allData | Sort-Object -Property $serialNumberProperty -Unique
            $removedCount = $originalCount - $allData.Count
            Write-ColorOutput "Removed $removedCount duplicate(s), $($allData.Count) unique record(s) remain" -Type "Success"
        }
        else {
            Write-ColorOutput "Could not identify serial number column for duplicate removal" -Type "Warning"
        }
    }

    # Export combined data to new CSV file
    Write-ColorOutput "Writing combined CSV file..." -Type "Info"

    # Use UTF8 with BOM encoding (required for Windows Autopilot)
    $utf8BOM = New-Object System.Text.UTF8Encoding $true
    $allData | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

    # Verify output file was created successfully
    if (Test-Path $outputPath) {
        $outputSize = (Get-Item $outputPath).Length
        Write-ColorOutput "=========================================" -Type "Info"
        Write-ColorOutput "SUCCESS: Combined CSV file created!" -Type "Success"
        Write-ColorOutput "Output File: $outputPath" -Type "Success"
        Write-ColorOutput "Total Records: $($allData.Count)" -Type "Success"
        Write-ColorOutput "File Size: $([math]::Round($outputSize / 1KB, 2)) KB" -Type "Success"
        Write-ColorOutput "Files Combined: $processedCount" -Type "Success"
        Write-ColorOutput "=========================================" -Type "Info"
    }
    else {
        throw "Output file was not created successfully"
    }
}
catch {
    Write-ColorOutput "=========================================" -Type "Error"
    Write-ColorOutput "FATAL ERROR: $($_.Exception.Message)" -Type "Error"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
    Write-ColorOutput "=========================================" -Type "Error"
    exit 1
}
