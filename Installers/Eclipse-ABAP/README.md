# Eclipse IDE with SAP ABAP Development Tools (ADT) - PSADT Installer

PSADT-based installer for deploying Eclipse IDE with SAP ABAP Development Tools via Microsoft Intune or SCCM.

## Prerequisites

Download these files and place them in the `Files\` directory before packaging:

| File | Source | Notes |
|------|--------|-------|
| `eclipse-jee-2024-09-R-win32-x86_64.zip` | [eclipse.org/downloads](https://www.eclipse.org/downloads/packages/) | Eclipse IDE for Enterprise Java Developers 2024-09 (x64) |
| `OpenJDK21U-jdk_x64_windows_hotspot_21.0.9.msi` | [adoptium.net](https://adoptium.net/) | Eclipse Temurin JDK 21.0.9 LTS (MSI installer) |

> **Note:** Update the filenames in `Deploy-Application.ps1` variables `$eclipseZipFileName` and `$jdkMsiFileName` if your downloaded versions differ.

The ABAP Development Tools (ADT) plugin is downloaded and installed automatically from the SAP update site during installation. Network access to `https://tools.hana.ondemand.com/latest` is required at install time.

## Directory Structure

```
Eclipse-ABAP/
├── AppDeployToolkit/
│   ├── AppDeployToolkitConfig.xml        # PSADT configuration
│   └── AppDeployToolkitExtensions.ps1    # Custom helper functions
├── Files/
│   ├── (place Eclipse ZIP here)
│   └── (place JDK MSI here)
├── SupportFiles/
│   └── Detect-EclipseABAP.ps1           # Intune detection script
├── Deploy-Application.ps1                # Main PSADT deployment script
└── README.md
```

## What Gets Installed

1. **Eclipse Temurin JDK 21.0.9** - to `C:\Program Files\Eclipse Adoptium\jdk-21`
2. **Eclipse IDE for Enterprise Java** - to `C:\Program Files\Eclipse\eclipse-abap`
3. **SAP ABAP Development Tools (ADT)** - installed as Eclipse plugin via p2 director
4. **Start Menu & Desktop shortcuts** - pointing to Eclipse with default ABAP workspace
5. **Intune detection registry key** - at `HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP`

## Usage

### Silent Install (Intune / SCCM)

```powershell
powershell.exe -ExecutionPolicy Bypass -File Deploy-Application.ps1 -DeploymentType Install -DeployMode Silent
```

### Silent Uninstall

```powershell
powershell.exe -ExecutionPolicy Bypass -File Deploy-Application.ps1 -DeploymentType Uninstall -DeployMode Silent
```

### Repair (Re-install ADT plugin)

```powershell
powershell.exe -ExecutionPolicy Bypass -File Deploy-Application.ps1 -DeploymentType Repair -DeployMode Silent
```

### With Full PSADT Toolkit

If you have the full PSAppDeployToolkit, copy the toolkit files into the `AppDeployToolkit\` folder. The script will automatically detect and use them for UI prompts, logging, and other PSADT features.

## Intune Deployment Configuration

| Setting | Value |
|---------|-------|
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -File Deploy-Application.ps1 -DeploymentType Install -DeployMode Silent` |
| **Uninstall command** | `powershell.exe -ExecutionPolicy Bypass -File Deploy-Application.ps1 -DeploymentType Uninstall -DeployMode Silent` |
| **Detection rule** | Custom script: `SupportFiles\Detect-EclipseABAP.ps1` |
| **Install behavior** | System |
| **Return codes** | 0 = Success, 3010 = Soft reboot, 69001 = Eclipse ZIP missing, 69002 = JDK MSI missing, 69003 = Extraction failed |

## Customization

Key variables at the top of `Deploy-Application.ps1`:

- `$eclipseInstallDir` - Where Eclipse is installed
- `$eclipseWorkspace` - Default workspace path
- `$adtUpdateSite` - SAP ADT update site URL
- `$adtFeatures` - List of ADT feature IDs to install
- `$shortcutName` - Name for Start Menu / Desktop shortcuts
