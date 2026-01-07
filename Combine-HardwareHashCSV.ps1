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

.PARAMETER GenerateReport
    Automatically generate a detailed processing report.
    Default: $true

.EXAMPLE
    .\Combine-HardwareHashCSV.ps1
    Combines all CSV files in the current directory and generates a report.

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
    [bool]$CreateBackup = $true,

    [Parameter(Mandatory = $false)]
    [bool]$GenerateReport = $true
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

    $result = @{
        IsValid = $false
        Status = ""
        RecordCount = 0
        Reason = ""
    }

    try {
        # Check if file is empty (0 bytes)
        $fileSize = (Get-Item $FilePath).Length
        if ($fileSize -eq 0) {
            Write-ColorOutput "File is empty (0 bytes): $FilePath" -Type "Warning"
            $result.Status = "Empty"
            $result.Reason = "File is empty (0 bytes)"
            return $result
        }

        # Read file content
        $content = Get-Content -Path $FilePath

        # Check if file only has header (no data rows)
        if ($content.Count -le 1) {
            Write-ColorOutput "File has no data rows: $FilePath" -Type "Warning"
            $result.Status = "EmptyData"
            $result.Reason = "File contains only header, no data rows"
            return $result
        }

        # Read first line to check header
        $firstLine = $content[0]

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
            $result.Status = "InvalidFormat"
            $result.Reason = "File does not have expected hardware hash CSV format"
            return $result
        }

        # File is valid - count data rows (excluding header)
        $result.IsValid = $true
        $result.Status = "Valid"
        $result.RecordCount = $content.Count - 1
        $result.Reason = "Valid hardware hash CSV"
        return $result
    }
    catch {
        Write-ColorOutput "Error validating file $FilePath : $_" -Type "Error"
        $result.Status = "Error"
        $result.Reason = "Error validating file: $_"
        return $result
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

    # Validate all CSV files and track results for reporting
    Write-ColorOutput "Validating CSV files..." -Type "Info"
    $validFiles = @()
    $reportData = @{
        SuccessfulFiles = [System.Collections.ArrayList]::new()
        EmptyFiles = [System.Collections.ArrayList]::new()
        EmptyDataFiles = [System.Collections.ArrayList]::new()
        InvalidFormatFiles = [System.Collections.ArrayList]::new()
        ErrorFiles = [System.Collections.ArrayList]::new()
        ProcessingErrors = [System.Collections.ArrayList]::new()
    }

    foreach ($file in $csvFiles) {
        Write-ColorOutput "Checking: $($file.Name)" -Type "Info"
        $validationResult = Test-HardwareHashCSV -FilePath $file.FullName

        if ($validationResult.IsValid) {
            $validFiles += $file
            Write-ColorOutput "  Valid: $($file.Name) - $($validationResult.RecordCount) record(s)" -Type "Success"
        }
        else {
            # Track different types of issues for reporting
            $fileInfo = [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                Reason = $validationResult.Reason
            }

            switch ($validationResult.Status) {
                "Empty" { [void]$reportData.EmptyFiles.Add($fileInfo) }
                "EmptyData" { [void]$reportData.EmptyDataFiles.Add($fileInfo) }
                "InvalidFormat" { [void]$reportData.InvalidFormatFiles.Add($fileInfo) }
                "Error" { [void]$reportData.ErrorFiles.Add($fileInfo) }
            }

            Write-ColorOutput "  Skipped: $($file.Name) - $($validationResult.Reason)" -Type "Warning"
        }
    }

    if ($validFiles.Count -eq 0) {
        Write-ColorOutput "No valid hardware hash CSV files found." -Type "Error"

        # Generate report even on failure
        if ($GenerateReport) {
            $reportPath = "$outputPath.report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            $reportContent = "Hardware Hash CSV Combine Report - FAILED`n"
            $reportContent += "=" * 70 + "`n"
            $reportContent += "No valid CSV files found to combine.`n`n"
            $reportContent += "Empty Files (0 bytes): $($reportData.EmptyFiles.Count)`n"
            $reportContent += "Empty Data Files (header only): $($reportData.EmptyDataFiles.Count)`n"
            $reportContent += "Invalid Format Files: $($reportData.InvalidFormatFiles.Count)`n"
            $reportContent += "Files with Errors: $($reportData.ErrorFiles.Count)`n"
            $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
            Write-ColorOutput "Report saved to: $reportPath" -Type "Info"
        }

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

            # Import CSV content (force array to handle single-row CSVs)
            $csvContent = @(Import-Csv -Path $file.FullName -Encoding UTF8)

            Write-ColorOutput "  DEBUG: Imported $($csvContent.Count) records from $($file.Name)" -Type "Info"

            # Store header from first valid file
            if ($null -eq $header -and $csvContent.Count -gt 0) {
                $header = $csvContent[0].PSObject.Properties.Name
            }

            # Add each record individually (not as array) to avoid nesting
            foreach ($record in $csvContent) {
                $allData += $record
            }
            Write-ColorOutput "  DEBUG: Total records in collection now: $($allData.Count)" -Type "Info"
            $processedCount++

            # Track successful file processing for report
            $successInfo = [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                RecordCount = $csvContent.Count
                FileSize = [math]::Round((Get-Item $file.FullName).Length / 1KB, 2)
            }
            [void]$reportData.SuccessfulFiles.Add($successInfo)

            Write-ColorOutput "  Added $($csvContent.Count) record(s) from $($file.Name)" -Type "Success"
        }
        catch {
            Write-ColorOutput "Error processing $($file.Name): $_" -Type "Error"

            # Track processing error for report
            $errorInfo = [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                Error = $_.Exception.Message
            }
            [void]$reportData.ProcessingErrors.Add($errorInfo)

            # Continue processing other files
        }
    }

    if ($allData.Count -eq 0) {
        Write-ColorOutput "No data records found to combine." -Type "Error"
        exit 1
    }

    Write-ColorOutput "Total records collected: $($allData.Count)" -Type "Info"
    Write-ColorOutput "DEBUG: Inspecting collected data..." -Type "Info"
    Write-ColorOutput "DEBUG: First item type: $($allData[0].GetType().FullName)" -Type "Info"
    Write-ColorOutput "DEBUG: First item serial: $($allData[0].'Device Serial Number')" -Type "Info"
    if ($allData.Count -gt 1) {
        Write-ColorOutput "DEBUG: Second item serial: $($allData[1].'Device Serial Number')" -Type "Info"
        Write-ColorOutput "DEBUG: Last item serial: $($allData[-1].'Device Serial Number')" -Type "Info"
    }

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
    Write-ColorOutput "DEBUG: About to export $($allData.Count) total records" -Type "Info"
    Write-ColorOutput "DEBUG: Data type: $($allData.GetType().FullName)" -Type "Info"

    # Export the array directly
    $allData | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Force

    # Verify the file was written correctly
    Write-ColorOutput "DEBUG: Verifying output file..." -Type "Info"
    $verifyContent = @(Import-Csv -Path $outputPath)
    Write-ColorOutput "DEBUG: Output file contains $($verifyContent.Count) records" -Type "Info"

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

        # Generate detailed processing report
        if ($GenerateReport) {
            $reportPath = "$outputPath.report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            Write-ColorOutput "Generating processing report..." -Type "Info"

            $reportContent = @"
================================================================================
           Hardware Hash CSV Combine Report
================================================================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Script Version: 1.0

SUMMARY
========================================
Total CSV Files Found: $($csvFiles.Count)
Successfully Combined: $($reportData.SuccessfulFiles.Count)
Total Records in Output: $($allData.Count)
Output File: $outputPath
Output File Size: $([math]::Round($outputSize / 1KB, 2)) KB

PROCESSING STATISTICS
========================================
Valid Files Processed: $($reportData.SuccessfulFiles.Count)
Empty Files (0 bytes): $($reportData.EmptyFiles.Count)
Empty Data Files (header only): $($reportData.EmptyDataFiles.Count)
Invalid Format Files: $($reportData.InvalidFormatFiles.Count)
Files with Validation Errors: $($reportData.ErrorFiles.Count)
Files with Processing Errors: $($reportData.ProcessingErrors.Count)

"@

            # Add successfully combined files section
            if ($reportData.SuccessfulFiles.Count -gt 0) {
                $reportContent += @"
SUCCESSFULLY COMBINED FILES ($($reportData.SuccessfulFiles.Count))
========================================
"@
                foreach ($file in $reportData.SuccessfulFiles) {
                    $reportContent += "`n  [OK] $($file.FileName)`n"
                    $reportContent += "       Records: $($file.RecordCount)`n"
                    $reportContent += "       Size: $($file.FileSize) KB`n"
                    $reportContent += "       Path: $($file.FilePath)`n"
                }
                $reportContent += "`n"
            }

            # Add empty files section
            if ($reportData.EmptyFiles.Count -gt 0) {
                $reportContent += @"
EMPTY FILES - 0 BYTES ($($reportData.EmptyFiles.Count))
========================================
"@
                foreach ($file in $reportData.EmptyFiles) {
                    $reportContent += "`n  [SKIP] $($file.FileName)`n"
                    $reportContent += "         Reason: $($file.Reason)`n"
                    $reportContent += "         Path: $($file.FilePath)`n"
                }
                $reportContent += "`n"
            }

            # Add empty data files section
            if ($reportData.EmptyDataFiles.Count -gt 0) {
                $reportContent += @"
EMPTY DATA FILES - HEADER ONLY ($($reportData.EmptyDataFiles.Count))
========================================
"@
                foreach ($file in $reportData.EmptyDataFiles) {
                    $reportContent += "`n  [SKIP] $($file.FileName)`n"
                    $reportContent += "         Reason: $($file.Reason)`n"
                    $reportContent += "         Path: $($file.FilePath)`n"
                }
                $reportContent += "`n"
            }

            # Add invalid format files section
            if ($reportData.InvalidFormatFiles.Count -gt 0) {
                $reportContent += @"
INVALID FORMAT FILES ($($reportData.InvalidFormatFiles.Count))
========================================
"@
                foreach ($file in $reportData.InvalidFormatFiles) {
                    $reportContent += "`n  [SKIP] $($file.FileName)`n"
                    $reportContent += "         Reason: $($file.Reason)`n"
                    $reportContent += "         Path: $($file.FilePath)`n"
                }
                $reportContent += "`n"
            }

            # Add validation error files section
            if ($reportData.ErrorFiles.Count -gt 0) {
                $reportContent += @"
FILES WITH VALIDATION ERRORS ($($reportData.ErrorFiles.Count))
========================================
"@
                foreach ($file in $reportData.ErrorFiles) {
                    $reportContent += "`n  [SKIP] $($file.FileName)`n"
                    $reportContent += "         Reason: $($file.Reason)`n"
                    $reportContent += "         Path: $($file.FilePath)`n"
                }
                $reportContent += "`n"
            }

            # Add processing error files section
            if ($reportData.ProcessingErrors.Count -gt 0) {
                $reportContent += @"
FILES WITH PROCESSING ERRORS ($($reportData.ProcessingErrors.Count))
========================================
"@
                foreach ($file in $reportData.ProcessingErrors) {
                    $reportContent += "`n  [ERROR] $($file.FileName)`n"
                    $reportContent += "          Error: $($file.Error)`n"
                    $reportContent += "          Path: $($file.FilePath)`n"
                }
                $reportContent += "`n"
            }

            # Add duplicate removal section if applicable
            if ($RemoveDuplicates) {
                $reportContent += @"
DUPLICATE REMOVAL
========================================
Duplicate removal was enabled.
Original record count before deduplication: (see processing log)
Final unique record count: $($allData.Count)

"@
            }

            $reportContent += @"
================================================================================
End of Report
================================================================================
"@

            # Save report to file
            $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
            Write-ColorOutput "Report saved to: $reportPath" -Type "Success"
        }
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
