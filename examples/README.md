# Examples

This folder contains sample hardware hash CSV files for testing the `Combine-HardwareHashCSV.ps1` script.

## Sample Files

The `sample-hardware-hashes` folder contains three CSV files with sample hardware hash data:

- **Device1.csv**: 2 device records
- **Device2.csv**: 2 device records
- **Device3.csv**: 2 device records (includes 1 duplicate from Device1.csv)

Total: 6 records (5 unique devices after deduplication)

## Testing the Script

### Basic Combination

Navigate to the sample directory and run:

```powershell
# From the root Intune directory
cd examples/sample-hardware-hashes
../../Combine-HardwareHashCSV.ps1
```

This will create `Combined-HardwareHash.csv` with all 6 records.

### With Duplicate Removal

```powershell
../../Combine-HardwareHashCSV.ps1 -RemoveDuplicates
```

This will create a combined file with only 5 unique records (duplicate serial number SN123456789 removed).

### From Parent Directory

```powershell
# From the root Intune directory
.\Combine-HardwareHashCSV.ps1 -SourcePath ".\examples\sample-hardware-hashes"
```

### With All Options

```powershell
.\Combine-HardwareHashCSV.ps1 `
    -SourcePath ".\examples\sample-hardware-hashes" `
    -OutputFile ".\examples\Test-Combined.csv" `
    -RemoveDuplicates `
    -CreateBackup $true
```

## Expected Results

When combining all three sample files:

- **Without deduplication**: 6 total records
- **With deduplication**: 5 unique records
- **Duplicate**: Device SN123456789 appears in both Device1.csv and Device3.csv

## Sample Data Notes

The sample CSV files use:
- Fictional serial numbers (SN#########)
- Sample Windows Product IDs
- Base64-encoded sample data (not real hardware hashes)

For real hardware hash collection, use the `Get-WindowsAutoPilotInfo.ps1` script from Microsoft.
