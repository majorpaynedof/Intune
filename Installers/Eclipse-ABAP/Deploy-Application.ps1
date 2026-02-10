<#
.SYNOPSIS
    PSAppDeployToolkit - Eclipse IDE for Java Developers with SAP ABAP Development Tools (ADT)
.DESCRIPTION
    Automates the manual installation procedure for Eclipse IDE for Java Developers
    with SAP ABAP Development Tools, matching the documented build guide.

    This script replicates the following manual steps silently:
      1. Remove any existing JRE/JDK installations
      2. Install Eclipse Temurin JDK 21.0.9
      3. Extract Eclipse IDE for Java Developers 2024-09
      4. Configure eclipse.ini to use JDK 21
      5. Install ABAP Development Tools via p2 director
      6. Create shortcuts on Public Desktop and Start Menu

    Pre-requisites (place in the Files\ directory before deployment):
      - eclipse-java-2024-09-R-win32-x86_64.zip
      - OpenJDK21U-jdk_x64_windows_hotspot_21.0.9.msi

    Source files available on the SCCM share at:
      \\gaatlnetappcifs\sccm$\Applications\Eclipse 2024 and JDK 21.09 for ABAP

.NOTES
    Toolkit Version:  3.9.3
    Application:      Eclipse IDE for Java Developers + SAP ABAP Development Tools (ADT)
    Author:           Intune Admin
    Date:             2026-02-10
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [String]$DeploymentType = 'Install',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [String]$DeployMode = 'Silent',

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

    ## Start transcript for Intune Management Extension logging
    $logDir = Join-Path $env:ProgramData 'Eclipse-ABAP-Install'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $transcriptPath = Join-Path $logDir "Deploy-EclipseABAP_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $transcriptPath -Force -ErrorAction SilentlyContinue

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    [String]$appVendor       = 'Eclipse Foundation / SAP'
    [String]$appName         = 'Eclipse IDE for Java Developers with ABAP Development Tools'
    [String]$appVersion      = '2024-09'
    [String]$appArch         = 'x64'
    [String]$appLang         = 'EN'
    [String]$appRevision     = '01'
    [String]$appScriptVersion = '2.0.0'
    [String]$appScriptDate   = '2026-02-10'
    [String]$appScriptAuthor = 'Intune Admin'

    ##*===============================================
    ##* APPLICATION CONFIGURATION
    ##* Paths match the documented manual build guide:
    ##*   Eclipse root:  C:\Users\Public\Eclipse
    ##*   Eclipse exe:   C:\Users\Public\Eclipse\java-latest-released\eclipse\eclipse.exe
    ##*   Workspace:     C:\Users\Public\Eclipse
    ##*===============================================

    # Installation paths - matches article: C:\Users\Public\Eclipse\java-latest-released\eclipse
    [String]$eclipseRootDir     = "$env:PUBLIC\Eclipse"
    [String]$eclipseInstallDir  = "$env:PUBLIC\Eclipse\java-latest-released\eclipse"
    [String]$eclipseWorkspace   = "$env:PUBLIC\Eclipse"
    [String]$jdkInstallDir      = "$env:ProgramFiles\Eclipse Adoptium\jdk-21"

    # Source file names (must exist in Files\ directory)
    # Available at: \\gaatlnetappcifs\sccm$\Applications\Eclipse 2024 and JDK 21.09 for ABAP
    [String]$eclipseZipFileName = 'eclipse-java-2024-09-R-win32-x86_64.zip'
    [String]$jdkMsiFileName     = 'OpenJDK21U-jdk_x64_windows_hotspot_21.0.9.msi'

    # SAP ABAP Development Tools update site URL (article uses http://)
    [String]$adtUpdateSite      = 'http://tools.hana.ondemand.com/latest'

    # ADT feature IDs to install (matches "ABAP Development Tools" from the article)
    [String[]]$adtFeatures = @(
        'com.sap.adt.tools.abap.feature.feature.group',
        'com.sap.adt.tools.abap.core.feature.feature.group',
        'com.sap.adt.tools.hana.devedition.feature.feature.group'
    )

    # Shortcut configuration - matches article: "Eclipse IDE for Java"
    [String]$shortcutName = 'Eclipse IDE for Java'

    ##*===============================================
    ##* PSADT TOOLKIT INITIALIZATION
    ##*===============================================

    ## Use $PSScriptRoot for reliable path resolution under Intune SYSTEM context
    $scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
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
                $msiArgs = "/i `"$msiPath`" /qn /norestart /l*v `"$logPath`" $Parameters"
            }
            elseif ($Action -eq 'Uninstall') {
                $msiArgs = "/x `"$msiPath`" /qn /norestart /l*v `"$logPath`" $Parameters"
            }
            Write-Host "Running: msiexec.exe $msiArgs"
            $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
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

    function Remove-ExistingJava {
        <#
        .SYNOPSIS
            Removes any existing JRE or JDK installations.
            Per the build guide: "Remove any other JRE or JDK that is installed before installation."
        #>
        Write-Host "Searching for existing Java installations to remove..."

        # Remove via registry uninstall keys (covers MSI and non-MSI installs)
        $uninstallPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $javaProducts = foreach ($path in $uninstallPaths) {
            Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -and (
                        $_.DisplayName -match 'Java\s+\d' -or
                        $_.DisplayName -match 'Java\(TM\)' -or
                        $_.DisplayName -match 'JDK\s' -or
                        $_.DisplayName -match 'JRE\s' -or
                        $_.DisplayName -match 'Eclipse Temurin' -or
                        $_.DisplayName -match 'AdoptOpenJDK' -or
                        $_.DisplayName -match 'Amazon Corretto' -or
                        $_.DisplayName -match 'OpenJDK' -or
                        $_.DisplayName -match 'Oracle JDK'
                    )
                }
        }

        if (-not $javaProducts) {
            Write-Host "No existing Java installations found."
            return
        }

        foreach ($product in $javaProducts) {
            Write-Host "Removing: $($product.DisplayName) ($($product.DisplayVersion))"
            $uninstallString = $product.UninstallString

            if ($product.PSChildName -match '^\{.*\}$') {
                # MSI product - uninstall via msiexec
                $msiGuid = $product.PSChildName
                $uninstallProcess = Start-Process -FilePath 'msiexec.exe' `
                    -ArgumentList "/x `"$msiGuid`" /qn /norestart" `
                    -Wait -PassThru
                Write-Host "  MSI uninstall exit code: $($uninstallProcess.ExitCode)"
            }
            elseif ($uninstallString) {
                # EXE-based uninstall
                if ($product.QuietUninstallString) {
                    $quietCmd = $product.QuietUninstallString
                }
                else {
                    $quietCmd = "$uninstallString /s"
                }
                Write-Host "  Running: $quietCmd"
                Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $quietCmd" -Wait -NoNewWindow
            }
        }

        Write-Host "Existing Java removal complete."
    }

    function Install-EclipsePlugin {
        <#
        .SYNOPSIS
            Installs an Eclipse plugin from an update site using the p2 director.
            Replicates: Help > Install New Software > http://tools.hana.ondemand.com/latest
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

        # Create a temp p2 data directory so the SYSTEM account doesn't fail
        # trying to write to C:\Windows\system32\config\systemprofile
        $p2DataDir = Join-Path $env:TEMP "eclipse_p2_data_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -Path $p2DataDir -ItemType Directory -Force | Out-Null

        $arguments = @(
            '-application', 'org.eclipse.equinox.p2.director',
            '-repository', $Repository,
            '-installIU', $iuList,
            '-destination', $EclipsePath,
            '-data', $p2DataDir,
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

        # Clean up temp p2 data directory
        if (Test-Path $p2DataDir) {
            Remove-Item -Path $p2DataDir -Recurse -Force -ErrorAction SilentlyContinue
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

        ## Show Welcome Message, close Eclipse if running
        Show-InstallationWelcome -CloseApps 'eclipse' -CloseAppsCountdown -PersistPrompt 0

        Show-InstallationProgress -StatusMessage "Preparing to install Eclipse IDE for Java Developers with ABAP Development Tools..."

        ## Validate source files exist
        $eclipseZipPath = Join-Path $dirFiles $eclipseZipFileName
        $jdkMsiPath     = Join-Path $dirFiles $jdkMsiFileName

        if (-not (Test-Path -LiteralPath $eclipseZipPath)) {
            Write-Warning "Eclipse ZIP not found at: $eclipseZipPath"
            Write-Warning "Please place '$eclipseZipFileName' in the Files\ directory."
            Write-Warning "Source: \\gaatlnetappcifs\sccm`$\Applications\Eclipse 2024 and JDK 21.09 for ABAP"
            Stop-Transcript -ErrorAction SilentlyContinue
            Exit 69001
        }

        if (-not (Test-Path -LiteralPath $jdkMsiPath)) {
            Write-Warning "JDK MSI not found at: $jdkMsiPath"
            Write-Warning "Please place '$jdkMsiFileName' in the Files\ directory."
            Write-Warning "Source: \\gaatlnetappcifs\sccm`$\Applications\Eclipse 2024 and JDK 21.09 for ABAP"
            Stop-Transcript -ErrorAction SilentlyContinue
            Exit 69002
        }

    ##*===============================================
    ##* INSTALLATION
    ##*===============================================

        ## ---- Step 1: Remove existing JRE/JDK ----
        ## Per build guide: "Remove any other JRE or JDK that is installed before installation."
        Show-InstallationProgress -StatusMessage "Removing existing Java installations..."
        Write-Host "--- Step 1/5: Removing existing JRE/JDK ---"

        Remove-ExistingJava

        ## ---- Step 2: Install JDK (Eclipse Temurin 21.0.9) ----
        Show-InstallationProgress -StatusMessage "Installing Eclipse Temurin JDK 21.0.9..."
        Write-Host "--- Step 2/5: Installing JDK 21.0.9 ---"

        $jdkExitCode = Execute-MSI -Action 'Install' -Path $jdkMsiFileName -Parameters "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome INSTALLDIR=`"$jdkInstallDir`""

        if ($jdkExitCode -ne 0 -and $jdkExitCode -ne 3010) {
            Write-Warning "JDK installation failed with exit code: $jdkExitCode"
            Stop-Transcript -ErrorAction SilentlyContinue
            Exit $jdkExitCode
        }

        # Refresh PATH so eclipse.exe can find java
        $env:JAVA_HOME = $jdkInstallDir
        $env:PATH = "$jdkInstallDir\bin;$env:PATH"

        ## ---- Step 3: Extract Eclipse IDE for Java Developers ----
        ## Replicates the Eclipse Installer "Advanced Mode" workflow:
        ##   - Bundle pool at C:\Users\Public\Eclipse
        ##   - Root install folder: C:\Users\Public\Eclipse
        ##   - Installation folder name: java-latest-released
        ##   - Final path: C:\Users\Public\Eclipse\java-latest-released\eclipse
        Show-InstallationProgress -StatusMessage "Extracting Eclipse IDE for Java Developers 2024-09..."
        Write-Host "--- Step 3/5: Extracting Eclipse IDE ---"

        # Create the root Eclipse directory at C:\Users\Public\Eclipse
        if (-not (Test-Path $eclipseRootDir)) {
            New-Item -Path $eclipseRootDir -ItemType Directory -Force | Out-Null
        }

        # Create the java-latest-released parent directory
        $eclipseProductDir = Split-Path $eclipseInstallDir -Parent
        if (-not (Test-Path $eclipseProductDir)) {
            New-Item -Path $eclipseProductDir -ItemType Directory -Force | Out-Null
        }

        # Remove previous installation if present
        if (Test-Path $eclipseInstallDir) {
            Write-Host "Removing previous Eclipse installation at: $eclipseInstallDir"
            Remove-Item -Path $eclipseInstallDir -Recurse -Force
        }

        # Extract Eclipse ZIP to a temporary location, then move into place
        $tempExtract = Join-Path $env:TEMP "eclipse_extract_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host "Extracting to temporary location: $tempExtract"
        Expand-Archive -Path $eclipseZipPath -DestinationPath $tempExtract -Force

        # The ZIP contains a root 'eclipse' folder - move it to the target path
        $extractedEclipse = Join-Path $tempExtract 'eclipse'
        if (Test-Path $extractedEclipse) {
            Move-Item -Path $extractedEclipse -Destination $eclipseInstallDir -Force
        }
        else {
            Move-Item -Path $tempExtract -Destination $eclipseInstallDir -Force
        }

        # Cleanup temp extraction
        if (Test-Path $tempExtract) {
            Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Verify extraction
        if (-not (Test-EclipseInstalled)) {
            Write-Warning "Eclipse extraction failed - eclipse.exe not found in $eclipseInstallDir"
            Stop-Transcript -ErrorAction SilentlyContinue
            Exit 69003
        }

        Write-Host "Eclipse IDE extracted successfully to: $eclipseInstallDir"

        ## ---- Step 4: Configure eclipse.ini for JDK 21 ----
        Show-InstallationProgress -StatusMessage "Configuring Eclipse to use JDK 21.0.9..."
        Write-Host "--- Step 4/5: Configuring eclipse.ini ---"

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

        ## ---- Step 5: Install SAP ABAP Development Tools (ADT) via p2 Director ----
        ## Replicates: Help > Install New Software > http://tools.hana.ondemand.com/latest
        ##             Check "ABAP Development Tools" > Next > Accept license > Finish
        Show-InstallationProgress -StatusMessage "Installing SAP ABAP Development Tools (ADT) plugin..."
        Write-Host "--- Step 5/5: Installing ABAP Development Tools ---"

        $adtExitCode = Install-EclipsePlugin -EclipsePath $eclipseInstallDir `
            -Repository $adtUpdateSite `
            -InstallIUs $adtFeatures

        if ($adtExitCode -ne 0) {
            Write-Warning "ADT plugin installation returned exit code: $adtExitCode"
            Write-Warning "ADT may need to be installed manually via Help > Install New Software."
            # Non-fatal - Eclipse is still usable, ADT can be added later
        }

    ##*===============================================
    ##* POST-INSTALLATION
    ##*===============================================

        Show-InstallationProgress -StatusMessage "Finalizing installation..."

        ## Create Desktop shortcut at C:\Users\Public\Desktop (Public Desktop)
        ## Per article: Right-click eclipse > Send To > Desktop, rename to "Eclipse IDE for Java",
        ##              then move to C:\Users\Public\Public Desktop
        $eclipseExe = Join-Path $eclipseInstallDir 'eclipse.exe'
        $desktopShortcut = Join-Path "$env:PUBLIC\Desktop" "$shortcutName.lnk"

        New-Shortcut -Path $desktopShortcut `
            -TargetPath $eclipseExe `
            -Arguments "-data `"$eclipseWorkspace`"" `
            -IconLocation "$eclipseExe,0" `
            -Description 'Eclipse IDE for Java Developers with SAP ABAP Development Tools' `
            -WorkingDirectory $eclipseInstallDir

        Write-Host "Public Desktop shortcut created: $desktopShortcut"

        ## Create Start Menu shortcut at C:\ProgramData\Microsoft\Windows\Start Menu\Programs
        ## Per article: Copy shortcut to Start Menu Programs for all users
        $startMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        $shortcutPath  = Join-Path $startMenuPath "$shortcutName.lnk"

        New-Shortcut -Path $shortcutPath `
            -TargetPath $eclipseExe `
            -Arguments "-data `"$eclipseWorkspace`"" `
            -IconLocation "$eclipseExe,0" `
            -Description 'Eclipse IDE for Java Developers with SAP ABAP Development Tools' `
            -WorkingDirectory $eclipseInstallDir

        Write-Host "Start Menu shortcut created: $shortcutPath"

        ## Write Intune detection registry key
        $regPath = 'HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP'
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'DisplayName'    -Value $appName    -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'DisplayVersion' -Value $appVersion -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'InstallDate'    -Value (Get-Date -Format 'yyyy-MM-dd') -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name 'InstallPath'    -Value $eclipseInstallDir -PropertyType String -Force | Out-Null
        Write-Host "Intune detection registry key created at: $regPath"

        Show-InstallationProgress -StatusMessage "Installation complete!"
        Write-Host "=== Eclipse IDE for Java Developers with ABAP Development Tools installed successfully ==="
        Write-Host "Eclipse location: $eclipseInstallDir"
        Write-Host "Workspace: $eclipseWorkspace"
        Stop-Transcript -ErrorAction SilentlyContinue
        Exit 0
    }

    ##*===============================================
    ##* UNINSTALLATION
    ##*===============================================
    ElseIf ($DeploymentType -ieq 'Uninstall') {

        Show-InstallationWelcome -CloseApps 'eclipse' -CloseAppsCountdown -PersistPrompt 0
        Show-InstallationProgress -StatusMessage "Uninstalling Eclipse IDE for Java Developers with ABAP Development Tools..."

        ## Remove Eclipse root directory (C:\Users\Public\Eclipse and everything underneath)
        if (Test-Path $eclipseRootDir) {
            Write-Host "Removing Eclipse installation: $eclipseRootDir"
            Remove-Item -Path $eclipseRootDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        ## Remove shortcuts
        $startMenuShortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$shortcutName.lnk"
        $desktopShortcut   = "$env:PUBLIC\Desktop\$shortcutName.lnk"

        if (Test-Path $startMenuShortcut) { Remove-Item $startMenuShortcut -Force }
        if (Test-Path $desktopShortcut)   { Remove-Item $desktopShortcut -Force }

        ## Uninstall JDK (comment out if JDK is shared with other apps)
        Write-Host "Uninstalling Eclipse Temurin JDK 21.0.9..."
        Execute-MSI -Action 'Uninstall' -Path $jdkMsiFileName

        ## Remove Intune detection registry key
        $regPath = 'HKLM:\SOFTWARE\IntuneManagedApps\Eclipse-ABAP'
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force
            Write-Host "Intune detection registry key removed."
        }

        Write-Host "=== Eclipse IDE for Java Developers with ABAP Development Tools uninstalled ==="
        Stop-Transcript -ErrorAction SilentlyContinue
        Exit 0
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
            Write-Warning "Eclipse not found at $eclipseInstallDir. Run a full install instead of repair."
            Stop-Transcript -ErrorAction SilentlyContinue
            Exit 69010
        }
        Stop-Transcript -ErrorAction SilentlyContinue
        Exit 0
    }
}
Catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    Stop-Transcript -ErrorAction SilentlyContinue
    Exit 69999
}
