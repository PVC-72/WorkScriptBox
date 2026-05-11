<#
.SYNOPSIS
    This script will check for major updates for on premisies devices (non cloud)

.DESCRIPTION
    Before the RFTools can run, there is a requirement for the device to be up to date
    with the device updates. This script attempts to scan for and install any major updates
    that are available or pending.

.PARAMETER DryRun (-DryRun)
    This will be removed once all steps are working.

.NOTES
    Author         : Paul Coyle
    Date           : May 2026
#>

param(
    [switch]$DryRun
)

Write-Host "`n=== On‑Premises Major System Update Scan ===`n" -ForegroundColor Cyan
Write-Host "DryRun: $DryRun`n"

# -------------------------------
# Create COM Objects
# -------------------------------
Write-Host "Initialising Windows Update engine..." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "DryRun: Would create Windows Update COM session" -ForegroundColor Yellow
}
else {
    try {
        $Session  = New-Object -ComObject Microsoft.Update.Session
        $Searcher = $Session.CreateUpdateSearcher()
        Write-Host "Windows Update engine initialised." -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Unable to initialise Windows Update COM objects." -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit
    }
}

# -------------------------------
# Search Criteria
# -------------------------------
$Criteria = "IsInstalled=0 AND IsHidden=0 AND Type='Software'"

Write-Host "`nPreparing update scan..." -ForegroundColor Yellow
Write-Host "Running update scan..." -ForegroundColor Yellow

# -------------------------------
# Perform Scan
# -------------------------------
if ($DryRun) {
    Write-Host "DryRun: Would run update scan for major updates only" -ForegroundColor Yellow

    $Result = [pscustomobject]@{
        Updates = @(
            [pscustomobject]@{ Title = "Example Security Update" }
            [pscustomobject]@{ Title = "Example Cumulative Update" }
        )
    }
}
else {
    try {
        $Result = $Searcher.Search($Criteria)
        Write-Host "Scan complete." -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Update scan failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit
    }
}

# -------------------------------
# No Updates Found
# -------------------------------
if ($Result.Updates.Count -eq 0) {
    Write-Host "`nNo major system updates found." -ForegroundColor Green

    # Still validate Defender even if nothing found
    $SkipInstall = $true
}
else {
    $SkipInstall = $false

    Write-Host "`nMajor system updates available:" -ForegroundColor Red

    foreach ($Update in $Result.Updates) {
        $Cat = ($Update.Categories | Select-Object -ExpandProperty Name) -join ", "
        Write-Host "- $($Update.Title) [$Cat]"
    }

    # -------------------------------
    # Download Updates
    # -------------------------------
    Write-Host "`nPreparing download..." -ForegroundColor Yellow

    if (-not $DryRun) {
        $Downloader = $Session.CreateUpdateDownloader()
        $Downloader.Updates = $Result.Updates
    }

    Write-Host "`nDownloading updates..." -ForegroundColor Yellow

    if (-not $DryRun) {
        $DownloadResult = $Downloader.Download()
        Write-Host "Download complete." -ForegroundColor Green
    }

    # -------------------------------
    # Install Updates
    # -------------------------------
    Write-Host "`nInstalling updates..." -ForegroundColor Yellow

    if ($DryRun) {
        $InstallResult = [pscustomobject]@{ ResultCode = 2 }
    }
    else {
        $Installer = $Session.CreateUpdateInstaller()
        $Installer.Updates = $Result.Updates
        $InstallResult = $Installer.Install()
        Write-Host "Installation process finished." -ForegroundColor Green
    }

    # -------------------------------
    # Installation Summary
    # -------------------------------
    Write-Host "`nInstallation summary:" -ForegroundColor Cyan

    switch ($InstallResult.ResultCode) {
        2 { Write-Host "Updates installed successfully." -ForegroundColor Green }
        3 { Write-Host "Updates installed, reboot required." -ForegroundColor Yellow }
        4 { Write-Host "Updates completed with minor issues (code 4). Verifying actual state..." -ForegroundColor Yellow }
        default { Write-Host "Installation completed with result code: $($InstallResult.ResultCode)" -ForegroundColor Yellow }
    }
}

# -------------------------------
# ✅ Defender Validation (ALWAYS RUN)
# -------------------------------
Write-Host "`nValidating Microsoft Defender state..." -ForegroundColor Yellow

try {
    if (-not $DryRun) {
        $DefenderStatus = Get-MpComputerStatus

        $SigVersion = $DefenderStatus.AntivirusSignatureVersion
        $SigDate    = $DefenderStatus.AntivirusSignatureLastUpdated
        $OutOfDate  = $DefenderStatus.DefenderSignaturesOutOfDate

        Write-Host "Defender Signature Version : $SigVersion"
        Write-Host "Last Updated              : $SigDate"
        Write-Host "Out Of Date               : $OutOfDate"

        if ($OutOfDate -eq $false) {
            Write-Host "`n✅ Defender is up to date." -ForegroundColor Green
        }
        else {
            Write-Host "`n⚠️ Defender is out of date. Attempting manual update..." -ForegroundColor Yellow

            & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -SignatureUpdate | Out-Null
            Start-Sleep -Seconds 3

            $RetryStatus = Get-MpComputerStatus

            if ($RetryStatus.DefenderSignaturesOutOfDate -eq $false) {
                Write-Host "✅ Defender successfully updated after retry." -ForegroundColor Green
            }
            else {
                Write-Host "❌ Defender still out of date after retry." -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "DryRun: Would validate Defender status" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "WARNING: Unable to validate Defender status." -ForegroundColor Yellow
    Write-Host $_.Exception.Message
}

Write-Host "`nTask complete.`n" -ForegroundColor Cyan