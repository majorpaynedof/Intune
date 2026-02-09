<#
.SYNOPSIS
    PSAppDeployToolkit - Eclipse IDE with SAP ABAP Development Tools (ADT)
.DESCRIPTION
    Installs Eclipse IDE for Enterprise Java Developers and the SAP ABAP Development Tools (ADT) plugin.
    This script is designed for deployment via Microsoft Intune / SCCM using PSADT.

    Pre-requisites (place in the Files\ directory before deployment):
      - Eclipse IDE ZIP archive (e.g., eclipse-jee-2024-12-R-win32-x86_64.zip)
      - AdoptOpenJDK / Eclipse Temurin JDK MSI (e.g., OpenJDK17U-jdk_x64_windows_hotspot_17.0.x.msi)

    The ABAP Development Tools (ADT) plugin is installed automatically from the SAP update site
    after Eclipse is extracted.

.NOTES
    Toolkit Version:  3.9.3
    Application:      Eclipse IDE + SAP ABAP Development Tools (ADT)
    Author:           Intune Admin
    Date:             2026-02-09
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [String]$DeploymentType = 'Install',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [String]$DeployMode = 'Interactive',

    [Parameter(Mandatory = $false)]
    [switch]$AllowRebootPassThru = $false,

    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode = $false,

    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging = $false
)

Try {
    ## Set the script execution policy for this process
    Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    [String]$appVendor       = 'Eclipse Foundation / SAP'
    [String]$appName         = 'Eclipse IDE with ABAP Development Tools'
    [String]$appVersion      = '2024-12'
    [String]$appArch         = 'x64'
    [String]$appLang         = 'EN'
    [String]$appRevision     = '01'
    [String]$appScriptVersion = '1.0.0'
    [String]$appScriptDate   = '2026-02-09'
    [String]$appScriptAuthor = 'Intune Admin'

    ##*===============================================
    ##* APPLICATION CONFIGURATION
    ##*===============================================

    # Installation paths
    [String]$eclipseInstallDir  = "$env:ProgramFiles\Eclipse\eclipse-abap"
    [String]$eclipseWorkspace   = "$env:PUBLIC\Documents\Eclipse-ABAP-Workspace"
    [String]$jdkInstallDir      = "$env:ProgramFiles\Eclipse Adoptium\jdk-17"

    # Source file names (must exist in Files\ directory)
    [String]$eclipseZipFileName = 'eclipse-jee-2024-12-R-win32-x86_64.zip'
    [String]$jdkMsiFileName     = 'OpenJDK17U-jdk_x64_windows_hotspot_17.0.13.11.msi'

    # SAP ABAP Development Tools update site URL
    [String]$adtUpdateSite      = 'https://tools.hana.ondemand.com/latest'

    # ADT feature IDs to install
    [String[]]$adtFeatures = @(
        'com.sap.adt.tools.abap.feature.feature.group',
        'com.sap.adt.tools.abap.core.feature.feature.group',
        'com.sap.adt.tools.hana.devedition.feature.feature.group'
    )

    # Shortcut configuration
    [String]$shortcutName = 'Eclipse ABAP'

    ##*===============================================
    ##* PSADT TOOLKIT INITIALIZATION
    ##*===============================================

    ## Dot source the required App Deploy Toolkit Functions
    ## NOTE: In a full PSADT package you would dot-source AppDeployToolkitMain.ps1 here.
    ##       For Intune Win32 deployment, this script can run standalone with the helper
    ##       functions below.

    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $toolkitMainScript = Join-Path $scriptDirectory 'AppDeployToolkit\AppDeployToolkitMain.ps1'

    If (Test-Path -LiteralPath $toolkitMainScript -PathType 'Leaf') {
        . $toolkitMainScript -DisableLogging:$DisableLogging
    }
    Else {
        ## Standalone mode - define minimal helper functions for Intune deployment
        Write-Host "Running in standalone mode (PSADT toolkit not found). Using built-in functions."

        $dirFiles = Join-Path $scriptDirectory 'Files'

        function Show-InstallationWelcome { param([String]$CloseApps, [switch]$CloseAppsCountdown, [int]$PersistPrompt) }
        function Show-InstallationProgress { param([String]$StatusMessage) Write-Host $StatusMessage }
        function Show-InstallationRestartPrompt { Write-Host "A restart may be required." }
        function Show-BalloonTip { param([String]$BalloonTipText, [String]$BalloonTipTitle) Write-Host "$BalloonTipTitle : $BalloonTipText" }

        function Execute-MSI {
            param(
                [String]$Action = 'Install',
                [String]$Path,
                [String]$Transform = '',
                [String]$Parameters = '',
                [switch]$PassThru
            )
            $msiPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $dirFiles $Path }
            $logPath = Join-Path $env:TEMP ("msi_" + [System.IO.Path]::GetFileNameWithoutExtension($Path) + ".log")

            if ($Action -eq 'Install') {
                $args = "/i `"$msiPath`" /qn /norestart /l*v `"$logPath`" $Parameters"
            }
            elseif ($Action -eq 'Uninstall') {
                $args = "/x `"$msiPath`" /qn /norestart /l*v `"$logPath`" $Parameters"
            }
            Write-Host "Running: msiexec.exe $args"
            $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
            return $process.ExitCode
        }

        function Remove-MSIApplications {
            param([String]$Name)
            $products = Get-WmiObject -Class Win32_Product -Filter "Name LIKE '%$Name%'" -ErrorAction SilentlyContinue
            foreach ($product in $products) {
                Write-Host "Uninstalling: $($product.Name)"
                $product.Uninstall() | Out-Null
            }
        }

        function New-Shortcut {
            param(
                [String]$Path,
                [String]$TargetPath,
                [String]$Arguments = '',
                [String]$IconLocation = '',
                [String]$Description = '',
                [String]$WorkingDirectory = ''
            )
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($Path)
            $shortcut.TargetPath = $TargetPath
            if ($Arguments) { $shortcut.Arguments = $Arguments }
            if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
            if ($Description) { $shortcut.Description = $Description }
            if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
            $shortcut.Save()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }

    ##*===============================================
    ##* HELPER FUNCTIONS
    ##*===============================================

    function Install-EclipsePlugin {
        <#
        .SYNOPSIS
            Installs an Eclipse plugin from an update site using the p2 director.
        #>
        param(
            [Parameter(Mandatory)]
            [String]$EclipsePath,

            [Parameter(Mandatory)]
            [String]$Repository,

            [Parameter(Mandatory)]
            [String[]]$InstallIUs
        )

        $eclipseExe = Join-Path $EclipsePath 'eclipse.exe'
        $iuList = $InstallIUs -join ','

        $arguments = @(
            '-application', 'org.eclipse.equinox.p2.director',
            '-repository', $Repository,
            '-installIU', $iuList,
            '-destination', $EclipsePath,
            '-nosplash'
        )

        Write-Host "Installing Eclipse plugins from: $Repository"
        Write-Host "Features: $iuList"

        $process = Start-Process -FilePath $eclipseExe -ArgumentList $arguments `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\eclipse_p2_stdout.log" `
            -RedirectStandardError "$env:TEMP\eclipse_p2_stderr.log"

        if ($process.ExitCode -ne 0) {
            Write-Warning "Eclipse p2 director returned exit code: $($process.ExitCode)"
            if (Test-Path "$env:TEMP\eclipse_p2_stderr.log") {
                $stderr = Get-Content "$env:TEMP\eclipse_p2_stderr.log" -Raw
                if ($stderr) { Write-Warning "STDERR: $stderr" }
            }
        }
        else {
            Write-Host "Eclipse plugins installed successfully."
        }

        return $process.ExitCode
    }

    function Test-EclipseInstalled {
        <#
        .SYNOPSIS
            Checks if Eclipse is installed at the expected location.
        #>
        $eclipseExe = Join-Path $eclipseInstallDir 'eclipse.exe'
        return (Test-Path -LiteralPath $eclipseExe -PathType 'Leaf')
    }

    ##*===============================================
    ##* PRE-INSTALLATION
    ##*===============================================
    If ($DeploymentType -ieq 'Install') {

        ## Show Welcome Message, close Eclipse if running, allow up to 3 deferrals
        Show-InstallationWelcome -CloseApps 'eclipse' -CloseAppsCountdown -PersistPrompt 0

        Show-InstallationProgress -StatusMessage "Preparing to install Eclipse IDE with ABAP Development Tools..."

        ## Validate source files exist
        $eclipseZipPath = Join-Path $dirFiles $eclipseZipFileName
        $jdkMsiPath     = Join-Path $dirFiles $jdkMsiFileName

        if (-not (Test-Path -LiteralPath $eclipseZipPath)) {
            Write-Warning "Eclipse ZIP not found at: $eclipseZipPath"
            Write-Warning "Please place '$eclipseZipFileName' in the Files\ directory."
            Exit 69001
        }

        if (-not (Test-Path -LiteralPath $jdkMsiPath)) {
            Write-Warning "JDK MSI not found at: $jdkMsiPath"
            Write-Warning "Please place '$jdkMsiFileName' in the Files\ directory."
            Exit 69002
        }

    ##*===============================================
    ##* INSTALLATION
    ##*===============================================

        ## ---- Step 1: Install JDK (Eclipse Temurin / AdoptOpenJDK 17) ----
        Show-InstallationProgress -StatusMessage "Installing Eclipse Temurin JDK 17..."
        Write-Host "--- Step 1/4: Installing JDK ---"

        $jdkExitCode = Execute-MSI -Action 'Install' -Path $jdkMsiFileName -Parameters "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome INSTALLDIR=`"$jdkInstallDir`""

        if ($jdkExitCode -ne 0 -and $jdkExitCode -ne 3010) {
            Write-Warning "JDK installation failed with exit code: $jdkExitCode"
            Exit $jdkExitCode
        }

        # Refresh PATH so eclipse.exe can find java
        $env:JAVA_HOME = $jdkInstallDir
        $env:PATH = "$jdkInstallDir\bin;$env:PATH"

        ## ---- Step 2: Extract Eclipse IDE ----
        Show-InstallationProgress -StatusMessage "Extracting Eclipse IDE..."
        Write-Host "--- Step 2/4: Extracting Eclipse IDE ---"

        # Create the parent install directory
        $eclipseParent = Split-Path $eclipseInstallDir -Parent
        if (-not (Test-Path $eclipseParent)) {
            New-Item -Path $eclipseParent -ItemType Directory -Force | Out-Null
        }

        # Remove previous installation if present
        if (Test-Path $eclipseInstallDir) {
            Write-Host "Removing previous Eclipse installation at: $eclipseInstallDir"
            Remove-Item -Path $eclipseInstallDir -Recurse -Force
        }

        # Extract Eclipse ZIP to a temporary location, then rename
        $tempExtract = Join-Path $env:TEMP "eclipse_extract_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host "Extracting to temporary location: $tempExtract"
        Expand-Archive -Path $eclipseZipPath -DestinationPath $tempExtract -Force

        # The ZIP typically contains a root 'eclipse' folder
        $extractedEclipse = Join-Path $tempExtract 'eclipse'
        if (Test-Path $extractedEclipse) {
            Move-Item -Path $extractedEclipse -Destination $eclipseInstallDir -Force
        }
        else {
            # If there's no sub-folder, move contents directly
            Move-Item -Path $tempExtract -Destination $eclipseInstallDir -Force
        }

        # Cleanup temp extraction
        if (Test-Path $tempExtract) {
            Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Verify extraction
        if (-not (Test-EclipseInstalled)) {
            Write-Warning "Eclipse extraction failed - eclipse.exe not found in $eclipseInstallDir"
            Exit 69003
        }

        Write-Host "Eclipse IDE extracted successfully to: $eclipseInstallDir"

        ## ---- Step 3: Configure eclipse.ini for JDK ----
        Show-InstallationProgress -StatusMessage "Configuring Eclipse to use installed JDK..."
        Write-Host "--- Step 3/4: Configuring eclipse.ini ---"

        $eclipseIniPath = Join-Path $eclipseInstallDir 'eclipse.ini'
        if (Test-Path $eclipseIniPath) {
            $iniContent = Get-Content $eclipseIniPath -Raw

            # Add -vm parameter pointing to the installed JDK if not already present
            if ($iniContent -notmatch '-vm') {
                $javaExe = Join-Path $jdkInstallDir 'bin\javaw.exe'
                $vmBlock = "-vm`r`n$javaExe`r`n"

                # Insert -vm before -vmargs
                $iniContent = $iniContent -replace '(-vmargs)', "$vmBlock`$1"
                Set-Content -Path $eclipseIniPath -Value $iniContent -Encoding UTF8 -Force
                Write-Host "eclipse.ini updated with JDK path: $javaExe"
            }

            # Increase default memory allocation for ABAP workloads
            $iniContent = Get-Content $eclipseIniPath -Raw
            $iniContent = $iniContent -replace '-Xms\d+m', '-Xms512m'
            $iniContent = $iniContent -replace '-Xmx\d+m', '-Xmx2048m'
            Set-Content -Path $eclipseIniPath -Value $iniContent -Encoding UTF8 -Force
            Write-Host "eclipse.ini memory settings updated (Xms=512m, Xmx=2048m)"
        }

        ## ---- Step 4: Install SAP ABAP Development Tools (ADT) via p2 Director ----
        Show-InstallationProgress -StatusMessage "Installing SAP ABAP Development Tools (ADT) plugin..."
        Write-Host "--- Step 4/4: Installing ABAP Development Tools ---"

        $adtExitCode = Install-EclipsePlugin -EclipsePath $eclipseInstallDir `
            -Repository $adtUpdateSite `
            -InstallIUs $adtFeatures

        if ($adtExitCode -ne 0) {
            Write-Warning "ADT plugin installation returned exit code: $adtExitCode"
            Write-Warning "ADT may need to be installed manually via Eclipse Marketplace."
            # Non-fatal - Eclipse is still usable, ADT can be added later
        }

    ##*===============================================
    ##* POST-INSTALLATION
    ##*===============================================

        Show-InstallationProgress -StatusMessage "Finalizing installation..."

        ## Create default workspace directory
        if (-not (Test-Path $eclipseWorkspace)) {
            New-Item -Path $eclipseWorkspace -ItemType Directory -Force | Out-Null
            Write-Host "Created default workspace: $eclipseWorkspace"
        }

        ## Create Start Menu shortcut
        $startMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        $shortcutPath  = Join-Path $startMenuPath "$shortcutName.lnk"
        $eclipseExe    = Join-Path $eclipseInstallDir 'eclipse.exe'

        New-Shortcut -Path $shortcutPath `
            -TargetPath $eclipseExe `
            -Arguments "-data `"$eclipseWorkspace`"" `
            -IconLocation "$eclipseExe,0" `
            -Description 'Eclipse IDE with SAP ABAP Development Tools' `
            -WorkingDirectory $eclipseInstallDir

        Write-Host "Start Menu shortcut created: $shortcutPath"

        ## Create Desktop shortcut
        $desktopShortcut = Join-Path "$env:PUBLIC\Desktop" "$shortcutName.lnk"
        New-Shortcut -Path $desktopShortcut `
            -TargetPath $eclipseExe `
            -Arguments "-data `"$eclipseWorkspace`"" `
            -IconLocation "$eclipseExe,0" `
            -Description 'Eclipse IDE with SAP ABAP Development Tools' `
            -WorkingDirectory $eclipseInstallDir

        Write-Host "Desktop shortcut created: $desktopShortcut"

        ## Write Intune detection registry key
        $regPath = 'HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP'
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'DisplayName'    -Value $appName    -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'DisplayVersion' -Value $appVersion -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'InstallDate'    -Value (Get-Date -Format 'yyyy-MM-dd') -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'InstallPath'    -Value $eclipseInstallDir -PropertyType String -Force | Out-Null
        Write-Host "Intune detection registry key created at: $regPath"

        Show-InstallationProgress -StatusMessage "Installation complete!"
        Write-Host "=== Eclipse IDE with ABAP Development Tools installed successfully ==="
    }

    ##*===============================================
    ##* UNINSTALLATION
    ##*===============================================
    ElseIf ($DeploymentType -ieq 'Uninstall') {

        Show-InstallationWelcome -CloseApps 'eclipse' -CloseAppsCountdown -PersistPrompt 0
        Show-InstallationProgress -StatusMessage "Uninstalling Eclipse IDE with ABAP Development Tools..."

        ## Remove Eclipse installation directory
        if (Test-Path $eclipseInstallDir) {
            Write-Host "Removing Eclipse installation: $eclipseInstallDir"
            Remove-Item -Path $eclipseInstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        ## Remove the parent Eclipse folder if empty
        $eclipseParent = Split-Path $eclipseInstallDir -Parent
        if ((Test-Path $eclipseParent) -and -not (Get-ChildItem $eclipseParent -Force)) {
            Remove-Item -Path $eclipseParent -Force -ErrorAction SilentlyContinue
        }

        ## Remove shortcuts
        $startMenuShortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$shortcutName.lnk"
        $desktopShortcut   = "$env:PUBLIC\Desktop\$shortcutName.lnk"

        if (Test-Path $startMenuShortcut) { Remove-Item $startMenuShortcut -Force }
        if (Test-Path $desktopShortcut)   { Remove-Item $desktopShortcut -Force }

        ## Uninstall JDK (optional - comment out if JDK is shared with other apps)
        Write-Host "Uninstalling Eclipse Temurin JDK..."
        Execute-MSI -Action 'Uninstall' -Path $jdkMsiFileName

        ## Remove Intune detection registry key
        $regPath = 'HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP'
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force
            Write-Host "Intune detection registry key removed."
        }

        ## Remove workspace (optional - uncomment to clean workspace on uninstall)
        # if (Test-Path $eclipseWorkspace) {
        #     Remove-Item -Path $eclipseWorkspace -Recurse -Force
        # }

        Write-Host "=== Eclipse IDE with ABAP Development Tools uninstalled ==="
    }

    ##*===============================================
    ##* REPAIR
    ##*===============================================
    ElseIf ($DeploymentType -ieq 'Repair') {
        Show-InstallationProgress -StatusMessage "Repairing Eclipse ABAP installation..."

        ## Re-run ADT plugin installation
        if (Test-EclipseInstalled) {
            $adtExitCode = Install-EclipsePlugin -EclipsePath $eclipseInstallDir `
                -Repository $adtUpdateSite `
                -InstallIUs $adtFeatures

            Write-Host "Repair complete. ADT plugin reinstallation exit code: $adtExitCode"
        }
        else {
            Write-Warning "Eclipse not found. Run a full install instead of repair."
            Exit 69010
        }
    }
}
Catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    Exit 69999
}
