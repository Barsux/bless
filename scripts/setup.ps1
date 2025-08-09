#requires -version 5.0
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'  # Превращаем ошибки в исключения

# Локальный Bypass на время работы скрипта
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch {}

# === Start logging to ~/setup.log ===
$userHome = [Environment]::GetFolderPath("UserProfile")
$logFile = Join-Path $userHome "setup.log"
try { Start-Transcript -Path $logFile -Append | Out-Null } catch {}

function Write-Log {
    param([string]$msg)
    Write-Output "[+] $msg"
}

function Ensure-Admin {
    Write-Log "Checking for administrator privileges..."
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "This script must be run as Administrator."
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
        throw "Failed to install Chocolatey: $($_.Exception.Message)"
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
    Write-Log "Checking Python..."
    $targetMajor = 3
    $targetMinorMin = 11
    $needInstall = $true

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        try {
            $v = & python --version 2>&1
            if ($v -match "Python (\d+)\.(\d+)\.(\d+)") {
                $maj = [int]$matches[1]; $min = [int]$matches[2]
                if ($maj -eq $targetMajor -and $min -ge $targetMinorMin) {
                    Write-Log "Python $maj.$min already installed."
                    $needInstall = $false
                } else {
                    Write-Log "Python $maj.$min is too old. Need $targetMajor.$targetMinorMin+"
                }
            } else {
                Write-Log "Cannot parse Python version. Will reinstall."
            }
        } catch {
            Write-Log "Version check failed. Will reinstall."
        }
    } else {
        Write-Log "Python not found. Will install $targetMajor.$targetMinorMin+"
    }

    if (-not $needInstall) { return }

    # 1) WinGet
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Log "Installing Python via WinGet (Python.Python.3.11)..."
        $p = Start-Process -FilePath "winget" -ArgumentList @(
            "install","-e","--id","Python.Python.3.11",
            "--scope","machine",
            "--accept-package-agreements","--accept-source-agreements"
        ) -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0) {
            Write-Log "Python installed via WinGet."
            return
        } else {
            Write-Log "WinGet install failed with code $($p.ExitCode). Fallback to Chocolatey..."
        }
    } else {
        Write-Log "WinGet not found. Fallback to Chocolatey..."
    }

    # 2) Chocolatey — ставим не 'python3', а конкретную ветку 'python311'
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Log "Installing python311 via Chocolatey..."
        choco install python311 -y --no-progress
        if ($LASTEXITCODE -eq 0 -or $?) {
            Write-Log "Python installed via Chocolatey."
            return
        } else {
            Write-Log "Chocolatey install failed. Fallback to official installer..."
        }
    }

    # 3) Официальный инсталлер (тихо)
    $ver = "3.11.9"
    $url = "https://www.python.org/ftp/python/$ver/python-$ver-amd64.exe"
    $dst = Join-Path $env:TEMP "python-$ver-amd64.exe"
    Write-Log "Downloading official Python installer $url ..."
    Invoke-WebRequest -Uri $url -OutFile $dst

    # Проверка подписи (не блокируем установку при Warning)
    $sig = Get-AuthenticodeSignature -FilePath $dst
    if ($sig.Status -ne 'Valid') {
        Write-Log "Warning: installer signature status = $($sig.Status). Continuing..."
    }

    $args = "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=0"
    $proc = Start-Process -FilePath $dst -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Official installer failed with exit code $($proc.ExitCode)."
    }

    # Обновим PATH текущей сессии
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    $v2 = & python --version 2>&1
    Write-Log "Python installed. Detected: $v2"
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
            throw "Failed to install 7-Zip."
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
            throw "Failed to install Git."
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
        throw "Could not find Activate.ps1 inside venv!"
    }

    Write-Log "Activating virtual environment..."
    & $activateScript

    if (Test-Path $requirementsPath) {
        Write-Log "Installing requirements from $requirementsPath..."
        & python -m pip install --upgrade pip *> $null
        & python -m pip install -r $requirementsPath *> $null
    } else {
        throw "requirements.txt not found at $requirementsPath"
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
        throw "mihomo.zip is missing or too small. Validation failed."
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
        throw "mihomo.zip not found at $zipPath"
    }

    Write-Log "Unpacking mihomo.zip into $blessPath..."
    & 7z e $zipPath -o"$blessPath" -y *> $null

    if (Test-Path $originalExe) {
        Move-Item -Path $originalExe -Destination $targetExe -Force
        Remove-Item $zipPath -Force
        Write-Log "mihomo.exe unpacked and renamed from $($originalExe)"
    } else {
        throw "Expected file 'mihomo-windows-amd64.exe' not found after unpacking."
    }
}

function Copy-WintunDll {
    $blessPath = Join-Path $userHome "bless"
    $sourceDll = Join-Path $blessPath "misc\tte.dll"
    $targetDll = Join-Path $blessPath "wintun.dll"

    if (-not (Test-Path $sourceDll)) {
        throw "Source DLL not found: $sourceDll"
    }

    Copy-Item -Path $sourceDll -Destination $targetDll -Force
    Write-Log "Copied wintun.dll from misc/tte.dll"

    if (-not (Test-Path $targetDll) -or ((Get-Item $targetDll).Length -lt 100 * 1024)) {
        throw "wintun.dll copy failed or file too small. Validation failed."
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
        throw "vless_parser.py not found at $parserScript"
    }

    if (-not (Test-Path $keyFile)) {
        throw "bless.key not found at $keyFile"
    }

    Write-Log "Running vless_parser.py..."
    & python $parserScript --vless-file $keyFile --output-file $outputConfig
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "vless_parser.py failed with exit code $exitCode"
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
        throw "Template vlg_config.json not found at $src"
    }
}

function Update-RulesPathInVlgConfig {
    $script = Join-Path $userHome "bless\scripts\set_rules_path.py"
    Write-Log "Updating rules_filepath in vlg_config.json..."
    & python $script
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update vlg_config.json"
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
$hadError = $false
try {
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
}
catch {
    $hadError = $true
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    if ($hadError) {
        Write-Host "`nSetup finished with errors. See log: $logFile" -ForegroundColor Red
    } else {
        Write-Host "`nSetup completed successfully. Log: $logFile" -ForegroundColor Green
    }
    Read-Host "Press Enter to exit"
}
