<#
.SYNOPSIS
    Deploy Taskpad locally using alternate credentials.

.NOTES
    Author : Paul Coyle
#>

param (
    [switch]$DryRun,
    [switch]$AsUser
)

function Invoke-AsOtherUser {
    param(
        [switch]$AsUser
    )

    if ($AsUser) {
        return
    }

    if (-not $PSCommandPath) {
        Write-Host "ERROR: Script must be run from a saved .ps1 file." -ForegroundColor Red
        exit 1
    }

    $cred = Get-Credential -Message 'Enter the account to run this script as (e.g. DOMAIN\User)'

    Write-Host "Starting script as $($cred.UserName)..." -ForegroundColor Yellow

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

# Relaunch as supplied user
Invoke-AsOtherUser -AsUser:$AsUser

Clear-Host
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "`n=== Taskpad Local Deployment ===" -ForegroundColor Cyan
Write-Host "Running as: $env:USERNAME" -ForegroundColor Green
Write-Host "DryRun: $DryRun`n"

# Paths
$sourceRoot = "\\rsnw-mrh-f02\NW05Groups\Operations Bridge\Taskpad-Local"
$localRoot  = "C:\Taskpad-Local"
$system32   = "$env:WINDIR\System32"
$publicDesk = "$env:PUBLIC\Desktop"

# --- Robust UNC Validation (NO PING) ---

$validPath = $false

while (-not $validPath) {

    if (Test-Path -Path $sourceRoot) {

        # Validate expected structure
        if (Test-Path (Join-Path $sourceRoot "Tools")) {
            $validPath = $true
        }
        else {
            Write-Host "ERROR: Source found, but expected 'Tools' folder is missing." -ForegroundColor Red
            $sourceRoot = Read-Host "Enter correct root path"
        }
    }
    else {
        Write-Host "ERROR: Cannot access '$sourceRoot'" -ForegroundColor Red
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host " - Incorrect path" -ForegroundColor Yellow
        Write-Host " - Permissions issue" -ForegroundColor Yellow
        Write-Host " - VPN / network not connected" -ForegroundColor Yellow

        $sourceRoot = Read-Host "Enter a valid source path"
    }

    if (-not $validPath -and [string]::IsNullOrWhiteSpace($sourceRoot)) {
        Write-Host "Operation cancelled by user." -ForegroundColor Red
        exit
    }
}

# Clean trailing slash
$sourceRoot = $sourceRoot.TrimEnd('\')

# Ensure ROBOCOPY.EXE
$roboSource = Join-Path $sourceRoot "Tools\ROBOCOPY.EXE"
$roboTarget = Join-Path $system32 "ROBOCOPY.EXE"

Write-Host "Checking ROBOCOPY.EXE..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "  DryRun: Would compare/copy ROBOCOPY.EXE" -ForegroundColor Yellow
}
else {
    if (-not (Test-Path $roboTarget) -or
        (Get-Item $roboSource).LastWriteTime -gt (Get-Item $roboTarget).LastWriteTime) {

        Copy-Item $roboSource $roboTarget -Force
        Write-Host "  ROBOCOPY.EXE updated." -ForegroundColor Green
    }
    else {
        Write-Host "  Already up to date." -ForegroundColor Yellow
    }
}

# Mirror Taskpad
Write-Host "`nMirroring Taskpad-Local..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "  DryRun: Would run robocopy $sourceRoot $localRoot /MIR" -ForegroundColor Yellow
}
else {
    robocopy $sourceRoot $localRoot /MIR /R:0 | Out-Null
    Write-Host "  Mirror complete." -ForegroundColor Green
}

# Update shortcut
Write-Host "`nUpdating Admin shortcut..." -ForegroundColor Cyan
$adminShortcut = Join-Path $publicDesk "Admin.lnk"

if ($DryRun) {
    Write-Host "  DryRun: Would replace Admin.lnk" -ForegroundColor Yellow
}
else {
    Remove-Item $adminShortcut -Force -ErrorAction SilentlyContinue
    robocopy "$sourceRoot\Admin" $publicDesk "Admin.lnk" /R:0 | Out-Null
    Write-Host "  Shortcut updated." -ForegroundColor Green
}

# Close Taskpad
Write-Host "`nClosing open Taskpad windows..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "  DryRun: Would stop Taskpad windows" -ForegroundColor Yellow
}
else {
    Get-Process |
        Where-Object { $_.MainWindowTitle -like 'Admin - Taskpad*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "  Taskpad windows closed." -ForegroundColor Green
}

# Launch Taskpad
Write-Host "`nLaunching Taskpad..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "  DryRun: Would launch $localRoot\Admin\Admin.msc" -ForegroundColor Yellow
}
else {
    Start-Process "$localRoot\Admin\Admin.msc"
    Write-Host "  Taskpad launched." -ForegroundColor Green
}

Write-Host "`nTask complete.`n" -ForegroundColor Cyan
Read-Host "Press Enter to exit"
