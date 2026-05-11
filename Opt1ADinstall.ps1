<#
.SYNOPSIS
    Install RSAT capabilities from FOD source as another user.

.AUTHOR
    Paul Coyle
#>

param(
    [switch]$DryRun,
    [switch]$AsUser
)

function Invoke-AsOtherUser {
    param(
        [switch]$AsUser
    )

    # Prevent infinite relaunch
    if ($AsUser) {
        return
    }

    if (-not $PSCommandPath) {
        Write-Host "ERROR: Script must be run from a saved .ps1 file." -ForegroundColor Red
        exit 1
    }

    # Prompt for credentials
    $cred = Get-Credential -Message 'Enter the account to run this script as (e.g. DOMAIN\User)'

    Write-Host "Starting script as $($cred.UserName)..." -ForegroundColor Yellow

    # Build argument list safely (fix for switch issue)
    $argList = @(
        "-NoExit"
        "-NoProfile"
        "-ExecutionPolicy Bypass"
        "-File `"$PSCommandPath`""
    )

    if ($DryRun) {
        $argList += "-DryRun"
    }

    $argList += "-AsUser"

    Start-Process powershell.exe `
        -ArgumentList ($argList -join " ") `
        -Credential $cred `
        -WorkingDirectory (Get-Location)

    exit
}

# Invoke relaunch if needed
Invoke-AsOtherUser -AsUser:$AsUser

# -------------------------------
# Script execution continues here
# -------------------------------

Write-Host "`n=== RSAT Capability Installer ===`n" -ForegroundColor Cyan
Write-Host "Running as: $env:USERNAME" -ForegroundColor Green
Write-Host "DryRun: $DryRun`n"

$ErrorActionPreference = 'Stop'

# Logging
$logPath = "C:\Temp\RSAT_install.log"
Start-Transcript -Path $logPath -Append

# FOD Source
$SourcePath = '\\4D000041\FOD20H2\'

# Validate UNC access
if (-not (Test-Path $SourcePath)) {
    Write-Host "WARNING: Cannot access $SourcePath" -ForegroundColor Yellow
    Write-Host "You may need to authenticate to the share in this session." -ForegroundColor Yellow
}

# RSAT Capabilities
$Capabilities = @(
    'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
    'Rsat.Dns.Tools~~~~0.0.1.0'
    'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
    'Rsat.DHCP.Tools~~~~0.0.1.0'
    'Rsat.FileServices.Tools~~~~0.0.1.0'
)

foreach ($Capability in $Capabilities) {

    Write-Host "Installing $Capability..." -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "  DryRun: Would install $Capability" -ForegroundColor Yellow
        continue
    }

    try {
        $Result = dism.exe /Online `
            /Add-Capability `
            /CapabilityName:$Capability `
            /Source:$SourcePath `
            /LimitAccess `
            /NoRestart 2>&1 | Out-String

        if ($Result -match "successfully") {
            Write-Host "  Installed successfully" -ForegroundColor Green
        }
        elseif ($Result -match "already installed") {
            Write-Host "  Already installed" -ForegroundColor Yellow
        }
        else {
            Write-Host "  Completed with warnings" -ForegroundColor Yellow
            Write-Host $Result
        }
    }
    catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nTask complete.`n" -ForegroundColor Cyan

Stop-Transcript

Read-Host "Press Enter to exit"