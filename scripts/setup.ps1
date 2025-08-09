#requires -version 5.0
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# === Start logging to ~/setup.log ===
$userHome = [Environment]::GetFolderPath("UserProfile")
$logFile = Join-Path $userHome "setup.log"
Start-Transcript -Path $logFile -Append | Out-Null

function Write-Log {
    param([string]$msg)
    Write-Output "[+] $msg"
}

function Ensure-Admin {
    Write-Log "Checking for administrator privileges..."
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "This script must be run as Administrator."
        exit 1
    }
}

function Install-Chocolatey {
    Write-Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    $chocoScript = "https://community.chocolatey.org/install.ps1"
    try {
        Invoke-Expression (Invoke-RestMethod $chocoScript)
        Write-Log "Chocolatey was installed successfully."
    } catch {
        Write-Error "Failed to install Chocolatey: $_"
        exit 1
    }
}

function Ensure-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Log "Chocolatey is already installed."
    } else {
        Install-Chocolatey
    }
}

function Ensure-Python {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        try {
            $versionOutput = & python --version 2>&1
            if ($versionOutput -match "Python (\d+)\.(\d+)\.(\d+)") {
                $major = [int]$matches[1]
                $minor = [int]$matches[2]
                if ($major -eq 3 -and $minor -ge 9) {
                    Write-Log "Python $major.$minor already installed."
                    return
                } else {
                    Write-Log "Installed Python is too old ($major.$minor). Installing Python 3.11..."
                }
            } else {
                Write-Log "Couldn't parse Python version. Reinstalling..."
            }
        } catch {
            Write-Log "Error while checking Python version. Reinstalling..."
        }
    } else {
        Write-Log "Python not found. Installing Python 3.11..."
    }

    choco install python3 --version=3.11.7 -y --no-progress
    if ($?) {
        Write-Log "Python 3.11 installed."
    } else {
        Write-Error "Failed to install Python."
        exit 1
    }
}

function Ensure-7zip {
    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        Write-Log "7-Zip is already installed."
    } else {
        Write-Log "Installing 7-Zip via Chocolatey..."
        choco install 7zip -y --no-progress
        if ($?) {
            Write-Log "7-Zip installed."
        } else {
            Write-Error "Failed to install 7-Zip."
            exit 1
        }
    }
}

function Ensure-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Log "Git is already installed."
    } else {
        Write-Log "Installing Git..."
        choco install git -y --no-progress
        if ($?) {
            Write-Log "Git installed."
        } else {
            Write-Error "Failed to install Git."
            exit 1
        }
    }
}

function Clone-Repos {
    $blessPath = Join-Path $userHome "bless"
    $dat2rulesPath = Join-Path $blessPath "dat2rules"

    if (-not (Test-Path $blessPath)) {
        Write-Log "Cloning bless repository into $blessPath..."
        git clone https://github.com/Barsux/bless.git $blessPath
    } else {
        Write-Log "bless directory already exists at $blessPath"
    }

    if (-not (Test-Path $dat2rulesPath)) {
        Write-Log "Cloning dat2rules into $dat2rulesPath..."
        git clone https://github.com/Barsux/dat2rules.git $dat2rulesPath
    } else {
        Write-Log "dat2rules directory already exists at $dat2rulesPath"
    }
}

function Setup-VenvAndInstallRequirements {
    $blessPath = Join-Path $userHome "bless"
    $venvPath = Join-Path $blessPath "venv"
    $requirementsPath = Join-Path $blessPath "dat2rules\requirements.txt"

    if (-not (Test-Path $venvPath)) {
        Write-Log "Creating virtual environment at $venvPath..."
        python -m venv $venvPath
    } else {
        Write-Log "Virtual environment already exists at $venvPath"
    }

    $activateScript = Join-Path $venvPath "Scripts\Activate.ps1"
    if (-not (Test-Path $activateScript)) {
        Write-Error "Could not find Activate.ps1 inside venv!"
        exit 1
    }

    Write-Log "Activating virtual environment..."
    & $activateScript

    if (Test-Path $requirementsPath) {
        Write-Log "Installing requirements from $requirementsPath..."
        & python -m pip install --upgrade pip *> $null
        & python -m pip install -r $requirementsPath *> $null
    } else {
        Write-Error "requirements.txt not found at $requirementsPath"
        exit 1
    }
}

function Download-MihomoZip {
    $blessPath = Join-Path $userHome "bless"
    $url = "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.12/mihomo-windows-amd64-v1.19.12.zip"
    $zipPath = Join-Path $blessPath "mihomo.zip"

    if (-not (Test-Path $zipPath)) {
        Write-Log "Downloading mihomo zip..."
        Invoke-WebRequest -Uri $url -OutFile $zipPath
    } else {
        Write-Log "mihomo.zip already exists, skipping download."
    }

    if (-not (Test-Path $zipPath) -or ((Get-Item $zipPath).Length -lt 1024)) {
        Write-Error "mihomo.zip is missing or too small. Validation failed."
        exit 1
    } else {
        Write-Log "mihomo.zip downloaded and validated."
    }
}

function Unpack-Mihomo {
    $blessPath = Join-Path $userHome "bless"
    $zipPath = Join-Path $blessPath "mihomo.zip"
    $originalExe = Join-Path $blessPath "mihomo-windows-amd64.exe"
    $targetExe = Join-Path $blessPath "mihomo.exe"

    if (-not (Test-Path $zipPath)) {
        Write-Error "mihomo.zip not found at $zipPath"
        exit 1
    }

    Write-Log "Unpacking mihomo.zip into $blessPath..."
    & 7z e $zipPath -o"$blessPath" -y *> $null

    if (Test-Path $originalExe) {
        Move-Item -Path $originalExe -Destination $targetExe -Force
        Remove-Item $zipPath -Force
        Write-Log "mihomo.exe unpacked and renamed from $($originalExe)"
    } else {
        Write-Error "Expected file 'mihomo-windows-amd64.exe' not found after unpacking."
        exit 1
    }
}

function Copy-WintunDll {
    $blessPath = Join-Path $userHome "bless"
    $sourceDll = Join-Path $blessPath "misc\tte.dll"
    $targetDll = Join-Path $blessPath "wintun.dll"

    if (-not (Test-Path $sourceDll)) {
        Write-Error "Source DLL not found: $sourceDll"
        exit 1
    }

    Copy-Item -Path $sourceDll -Destination $targetDll -Force
    Write-Log "Copied wintun.dll from misc/tte.dll"

    if (-not (Test-Path $targetDll) -or ((Get-Item $targetDll).Length -lt 100 * 1024)) {
        Write-Error "wintun.dll copy failed or file too small. Validation failed."
        exit 1
    } else {
        Write-Log "wintun.dll successfully copied and validated."
    }
}



function Create-BlessKeyAndPrompt {
    $blessPath = Join-Path $userHome "bless"
    $keyFile = Join-Path $blessPath "bless.key"

    if (-not (Test-Path $keyFile)) {
        Write-Log "Creating empty bless.key file at $keyFile..."
        New-Item -Path $keyFile -ItemType File -Force | Out-Null
    } else {
        Write-Log "bless.key already exists at $keyFile"
    }

    Write-Output ""
    Write-Output "=== ACTION REQUIRED ==="
    Write-Output "Please paste your VLESS key into the following file:"
    Write-Output "`n$keyFile`n"
    Read-Host "Press Enter after you've saved the key"
}

function Run-VlessParser {
    $blessPath = Join-Path $userHome "bless"
    $parserScript = Join-Path $blessPath "scripts\vless_parser.py"
    $keyFile = Join-Path $blessPath "bless.key"
    $outputConfig = Join-Path $blessPath "config.yaml"

    if (-not (Test-Path $parserScript)) {
        Write-Error "vless_parser.py not found at $parserScript"
        exit 1
    }

    if (-not (Test-Path $keyFile)) {
        Write-Error "bless.key not found at $keyFile"
        exit 1
    }

    Write-Log "Running vless_parser.py..."
    & python $parserScript --vless-file $keyFile --output-file $outputConfig
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Error "vless_parser.py failed with exit code $exitCode"
        exit 1
    } else {
        Write-Log "vless_parser.py completed successfully. Output: $outputConfig"
    }
}

function Copy-VlgTemplate {
    $src = Join-Path $userHome "bless\templates\vlg_config.json"
    $dst = Join-Path $userHome "bless\dat2rules\vlg_config.json"

    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Log "vlg_config.json copied to dat2rules"
    } else {
        Write-Error "Template vlg_config.json not found at $src"
        exit 1
    }
}

function Update-RulesPathInVlgConfig {
    $script = Join-Path $userHome "bless\scripts\set_rules_path.py"
    Write-Log "Updating rules_filepath in vlg_config.json..."
    & python $script
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to update vlg_config.json"
        exit 1
    }
}

function Create-LauncherScript {
    $blessPath = Join-Path $userHome "bless"
    $batPath = Join-Path $blessPath "run_bless.bat"
    $iconPath = Join-Path $blessPath "misc\icon.ico"
    $shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "bless.lnk"

    Write-Log "Creating run_bless.bat..."

    $batContent = @"
@echo off
cd /d "$blessPath"
call venv\Scripts\activate.bat
python dat2rules\dat2rules.py dat2rules\vlg_config.json
if errorlevel 1 (
    echo dat2rules.py failed. Exiting.
    exit /b 1
)
mihomo.exe -f config.yaml
"@

    Set-Content -Path $batPath -Value $batContent -Encoding ASCII
    Write-Log "Batch launcher created: $batPath"

    Write-Log "Creating shortcut on Desktop..."
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $batPath
    $shortcut.WorkingDirectory = $blessPath
    if (Test-Path $iconPath) {
        $shortcut.IconLocation = $iconPath
    }
    $shortcut.WindowStyle = 1
    $shortcut.Description = "Launch bless (admin)"
    $shortcut.Save()

    # Set to run as administrator (via shortcut .lnk file metadata hack)
    $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

    Write-Log "Shortcut created: $shortcutPath"
}

function Offer-Autostart {
    $answer = Read-Host "Do you want to add bless to Windows startup? (y/n)"
    if ($answer -eq "y") {
        $startupPath = Join-Path ([Environment]::GetFolderPath("Startup")) "bless.lnk"
        $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "bless.lnk"

        if (Test-Path $desktopShortcut) {
            Copy-Item -Path $desktopShortcut -Destination $startupPath -Force
            Write-Log "bless added to autostart."
        } else {
            Write-Error "Shortcut not found on Desktop. Cannot add to autostart."
        }
    } else {
        Write-Log "User skipped autostart."
    }
}



# ---- MAIN ----

Ensure-Admin
Write-Log "Starting environment setup..."
Ensure-Chocolatey
Ensure-Python
Ensure-7zip
Ensure-Git
Clone-Repos
Setup-VenvAndInstallRequirements
Download-MihomoZip
Unpack-Mihomo
Copy-WintunDll
Create-BlessKeyAndPrompt
Run-VlessParser
Copy-VlgTemplate
Update-RulesPathInVlgConfig
Create-LauncherScript
Offer-Autostart
Write-Log "Setup complete."

# === Stop logging ===
Stop-Transcript | Out-Null
