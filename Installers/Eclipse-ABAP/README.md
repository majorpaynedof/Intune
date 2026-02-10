# Eclipse IDE for Java Developers with SAP ABAP Development Tools (ADT) - PSADT Installer

PSADT-based installer that automates the documented manual build guide for deploying Eclipse IDE for Java Developers with SAP ABAP Development Tools via Microsoft Intune or SCCM.

## Prerequisites

Download these files and place them in the `Files\` directory before packaging:

| File | Source | Notes |
|------|--------|-------|
| `eclipse-java-2024-09-R-win32-x86_64.zip` | [eclipse.org/downloads](https://www.eclipse.org/downloads/packages/) | Eclipse IDE for Java Developers 2024-09 (x64) |
| `OpenJDK21U-jdk_x64_windows_hotspot_21.0.9.msi` | [adoptium.net](https://adoptium.net/) | Eclipse Temurin JDK 21.0.9 LTS (MSI installer) |

Both files are also available on the SCCM share at:
`\\gaatlnetappcifs\sccm$\Applications\Eclipse 2024 and JDK 21.09 for ABAP`

The ABAP Development Tools (ADT) plugin is downloaded and installed automatically from the SAP update site during installation. Network access to `http://tools.hana.ondemand.com/latest` is required at install time.

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

This script replicates the manual build guide steps silently:

1. **Removes existing JRE/JDK** - cleans up any prior Java installations (Oracle, Temurin, Corretto, etc.)
2. **Eclipse Temurin JDK 21.0.9** - to `C:\Program Files\Eclipse Adoptium\jdk-21`
3. **Eclipse IDE for Java Developers 2024-09** - to `C:\Users\Public\Eclipse\java-latest-released\eclipse`
4. **SAP ABAP Development Tools (ADT)** - installed as Eclipse plugin via p2 director
5. **Shortcuts** - "Eclipse IDE for Java" on Public Desktop and Start Menu (available to all users)
6. **Intune detection registry key** - at `HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP`

### Path Layout (matches build guide)

```
C:\Users\Public\Eclipse\                          # Root / Workspace
└── java-latest-released\
    └── eclipse\                                   # Eclipse install dir
        ├── eclipse.exe
        ├── eclipse.ini (configured for JDK 21)
        ├── features\
        │   └── com.sap.adt.*                      # ADT features
        └── plugins\
            └── com.sap.adt.*                      # ADT plugins
```

## Usage

### Silent Install (Intune / SCCM)

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File Deploy-Application.ps1 -DeploymentType Install -DeployMode Silent
```

### Silent Uninstall

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File Deploy-Application.ps1 -DeploymentType Uninstall -DeployMode Silent
```

### Repair (Re-install ADT plugin)

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File Deploy-Application.ps1 -DeploymentType Repair -DeployMode Silent
```

### With Full PSADT Toolkit

If you have the full PSAppDeployToolkit, copy the toolkit files into the `AppDeployToolkit\` folder. The script will automatically detect and use them for UI prompts, logging, and other PSADT features.

## Intune Deployment Configuration

| Setting | Value |
|---------|-------|
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File Deploy-Application.ps1 -DeploymentType Install -DeployMode Silent` |
| **Uninstall command** | `powershell.exe -ExecutionPolicy Bypass -NoProfile -File Deploy-Application.ps1 -DeploymentType Uninstall -DeployMode Silent` |
| **Detection rule** | Custom script: `SupportFiles\Detect-EclipseABAP.ps1` |
| **Install behavior** | System |
| **Return codes** | 0 = Success, 3010 = Soft reboot, 69001 = Eclipse ZIP missing, 69002 = JDK MSI missing, 69003 = Extraction failed |

## Logging

Install logs are written to `C:\ProgramData\Eclipse-ABAP-Install\` with timestamped filenames for troubleshooting.

## Customization

Key variables at the top of `Deploy-Application.ps1`:

- `$eclipseRootDir` - Eclipse root directory (`C:\Users\Public\Eclipse`)
- `$eclipseInstallDir` - Where eclipse.exe lives (`C:\Users\Public\Eclipse\java-latest-released\eclipse`)
- `$eclipseWorkspace` - Default workspace path (`C:\Users\Public\Eclipse`)
- `$adtUpdateSite` - SAP ADT update site URL
- `$adtFeatures` - List of ADT feature IDs to install
- `$shortcutName` - Name for Start Menu / Desktop shortcuts (`Eclipse IDE for Java`)
