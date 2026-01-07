# Hardware Hash CSV Combiner

A PowerShell script to safely combine multiple hardware hash CSV files into a single file for Windows Autopilot device registration.

## Overview

This script combines multiple hardware hash CSV files without corrupting the original or output files. It includes validation, backup capabilities, and duplicate removal options.

## Features

- **Safe Processing**: Validates CSV structure before combining
- **Automatic Backup**: Creates timestamped backups of existing output files
- **Duplicate Removal**: Optional removal of duplicate device entries
- **Detailed Reporting**: Automatically generates comprehensive processing reports
- **Empty File Detection**: Identifies and reports empty or header-only CSV files
- **Error Handling**: Robust error handling with detailed logging
- **Flexible Input**: Supports recursive directory scanning
- **Proper Encoding**: Uses UTF-8 with BOM encoding (required for Windows Autopilot)
- **Colored Output**: Easy-to-read console output with timestamps

## Requirements

- Windows PowerShell 5.1 or later
- PowerShell Core 7.x (cross-platform compatible)
- Read/Write permissions to source and destination folders

## Usage

### Basic Usage

Combine all CSV files in the current directory:

```powershell
.\Combine-HardwareHashCSV.ps1
```

### Specify Source Path

Combine CSV files from a specific directory:

```powershell
.\Combine-HardwareHashCSV.ps1 -SourcePath "C:\HardwareHashes"
```

### Custom Output File

Specify a custom output filename:

```powershell
.\Combine-HardwareHashCSV.ps1 -OutputFile "Autopilot-AllDevices.csv"
```

### Recursive Search

Search subdirectories for CSV files:

```powershell
.\Combine-HardwareHashCSV.ps1 -SourcePath "C:\HardwareHashes" -Recursive
```

### Remove Duplicates

Combine files and remove duplicate entries based on device serial number:

```powershell
.\Combine-HardwareHashCSV.ps1 -RemoveDuplicates
```

### Complete Example

```powershell
.\Combine-HardwareHashCSV.ps1 `
    -SourcePath "C:\DeviceHashes" `
    -OutputFile "Autopilot-Import.csv" `
    -Recursive `
    -RemoveDuplicates `
    -CreateBackup $true
```

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `SourcePath` | String | No | Current directory | Path to folder containing CSV files |
| `OutputFile` | String | No | Combined-HardwareHash.csv | Name or path of output file |
| `Recursive` | Switch | No | False | Search subdirectories recursively |
| `RemoveDuplicates` | Switch | No | False | Remove duplicate entries |
| `CreateBackup` | Boolean | No | True | Backup existing output file |
| `GenerateReport` | Boolean | No | True | Generate detailed processing report |

## CSV Format

The script expects hardware hash CSV files in the Windows Autopilot format:

```csv
Device Serial Number,Windows Product ID,Hardware Hash
123456789,XXXXX-XXXXX-XXXXX-XXXXX-XXXXX,BASE64_ENCODED_HASH_HERE
987654321,XXXXX-XXXXX-XXXXX-XXXXX-XXXXX,BASE64_ENCODED_HASH_HERE
```

### Supported Header Variations

- `Device Serial Number,Windows Product ID,Hardware Hash`
- `Device Serial Number,Windows Product Id,Hardware Hash`
- `Serial Number,Windows Product ID,Hardware Hash`

## How It Works

1. **Validation**: Checks all CSV files for proper hardware hash format
2. **Filtering**: Skips invalid or empty files
3. **Backup**: Creates timestamped backup if output file exists
4. **Combining**: Merges all valid CSV files into one
5. **Deduplication**: Optionally removes duplicate entries
6. **Export**: Writes combined data with proper UTF-8 BOM encoding
7. **Reporting**: Generates detailed processing report (optional)

## Automatic Reporting

The script automatically generates a comprehensive processing report (enabled by default) that includes:

### Report Contents

- **Summary Statistics**: Total files found, successfully combined, total records, output file size
- **Successfully Combined Files**: Lists each file with record count and file size
- **Empty Files (0 bytes)**: Files that are completely empty
- **Empty Data Files**: Files with header only, no data rows
- **Invalid Format Files**: Files that don't match expected hardware hash format
- **Validation Errors**: Files that failed validation checks
- **Processing Errors**: Files that encountered errors during processing

### Report Location

Reports are automatically saved as timestamped text files:
```
<OutputFile>.report_YYYYMMDD_HHMMSS.txt
```

Example:
```
Combined-HardwareHash.csv.report_20260107_143022.txt
```

### Sample Report

```
================================================================================
           Hardware Hash CSV Combine Report
================================================================================
Generated: 2026-01-07 14:30:22
Script Version: 1.0

SUMMARY
========================================
Total CSV Files Found: 10
Successfully Combined: 8
Total Records in Output: 156
Output File: C:\HardwareHashes\Combined-HardwareHash.csv
Output File Size: 245.67 KB

PROCESSING STATISTICS
========================================
Valid Files Processed: 8
Empty Files (0 bytes): 1
Empty Data Files (header only): 1
Invalid Format Files: 0
Files with Validation Errors: 0
Files with Processing Errors: 0

SUCCESSFULLY COMBINED FILES (8)
========================================
  [OK] Device1.csv
       Records: 25
       Size: 32.15 KB
       Path: C:\HardwareHashes\Device1.csv
  ...

EMPTY FILES - 0 BYTES (1)
========================================
  [SKIP] EmptyFile.csv
         Reason: File is empty (0 bytes)
         Path: C:\HardwareHashes\EmptyFile.csv

EMPTY DATA FILES - HEADER ONLY (1)
========================================
  [SKIP] NoData.csv
         Reason: File contains only header, no data rows
         Path: C:\HardwareHashes\NoData.csv
```

### Disabling Reports

To disable automatic report generation:

```powershell
.\Combine-HardwareHashCSV.ps1 -GenerateReport $false
```

## Safety Features

### No Corruption

- Original files are never modified
- Read-only operations on source files
- Validation before processing
- Proper CSV parsing and export

### Backup Protection

- Automatic backup of existing output file
- Timestamped backup files (e.g., `Combined-HardwareHash.csv.backup_20260107_143022`)
- Backup created before any write operations

### Error Handling

- Validates file structure before combining
- Continues processing if individual files fail
- Detailed error messages with timestamps
- Exit codes for automation (0 = success, 1 = error)

## Example Output

```
[2026-01-07 14:30:15] [INFO] Starting Hardware Hash CSV Combine Process
[2026-01-07 14:30:15] [INFO] =========================================
[2026-01-07 14:30:15] [INFO] Source Path: C:\HardwareHashes
[2026-01-07 14:30:15] [INFO] Output File: C:\HardwareHashes\Combined-HardwareHash.csv
[2026-01-07 14:30:15] [INFO] Found 5 CSV file(s) to process
[2026-01-07 14:30:15] [INFO] Validating CSV files...
[2026-01-07 14:30:15] [SUCCESS]   Valid: Device1.csv
[2026-01-07 14:30:15] [SUCCESS]   Valid: Device2.csv
[2026-01-07 14:30:15] [SUCCESS] 5 valid file(s) will be combined
[2026-01-07 14:30:15] [INFO] Combining CSV files...
[2026-01-07 14:30:16] [SUCCESS]   Added 10 record(s) from Device1.csv
[2026-01-07 14:30:16] [INFO] Total records collected: 50
[2026-01-07 14:30:16] [INFO] Writing combined CSV file...
[2026-01-07 14:30:16] [INFO] =========================================
[2026-01-07 14:30:16] [SUCCESS] SUCCESS: Combined CSV file created!
[2026-01-07 14:30:16] [SUCCESS] Output File: C:\HardwareHashes\Combined-HardwareHash.csv
[2026-01-07 14:30:16] [SUCCESS] Total Records: 50
[2026-01-07 14:30:16] [SUCCESS] File Size: 245.67 KB
[2026-01-07 14:30:16] [SUCCESS] Files Combined: 5
[2026-01-07 14:30:16] [INFO] =========================================
```

## Troubleshooting

### "No CSV files found"

- Verify the source path is correct
- Check that CSV files exist in the directory
- Use `-Recursive` switch to search subdirectories

### "File does not have expected hardware hash CSV format"

- Ensure CSV files have proper headers
- Check that files are not corrupted
- Verify files contain hardware hash data

### Permission Errors

- Run PowerShell as Administrator if needed
- Check read permissions on source folder
- Verify write permissions on destination folder

## Use Cases

- Combining hardware hashes from multiple technicians
- Consolidating device inventories before Autopilot import
- Merging departmental hardware hash collections
- Creating master device lists for bulk enrollment

## Importing to Windows Autopilot

After combining your CSV files, import to Windows Autopilot:

### Option 1: Microsoft Intune Admin Center

1. Navigate to **Devices** > **Windows** > **Windows enrollment** > **Devices**
2. Click **Import**
3. Select your combined CSV file
4. Click **Import**

### Option 2: PowerShell

```powershell
Install-Module -Name Microsoft.Graph.Intune
Connect-MSGraph
Import-AutopilotCSV -csvFile "Combined-HardwareHash.csv"
```

## Contributing

Feel free to submit issues, feature requests, or pull requests.

## License

This script is provided as-is for use with Windows Autopilot hardware hash management.
