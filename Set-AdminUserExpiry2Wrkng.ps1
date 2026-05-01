<#
Set AD User Expiry Only
Now includes:
- STEP 1 Standard User check
- Elevation once only
- Auto-reload without re-elevating
#>

param(
    [switch]$Reinvoked,
    [switch]$Elevate
)

# ---------------------------------------------------------
#   RUN-AS-ANOTHER-USER / ELEVATION HANDLER
# ---------------------------------------------------------
function Invoke-AsOtherUser {
    param([switch]$Elevate)

    $cred = Get-Credential -Message 'Enter the account to run this script as (e.g. DOMAIN\User)'

    if (-not $Elevate) {
        Start-Process PowerShell.exe -Credential $cred -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "-Reinvoked"
        )
        Start-Sleep 1
        exit
    }

    try {
        $taskName = "RunAsOtherUser_" + ([guid]::NewGuid())
        $psArgs   = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Reinvoked"
        $start    = (Get-Date).AddMinutes(1).ToString('HH:mm')

        $bstr     = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)
        $plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)

        schtasks /Create /TN $taskName /TR "powershell.exe $psArgs" /SC ONCE /ST $start /RL HIGHEST /RU $cred.UserName /RP $plainPwd /F | Out-Null
        schtasks /Run /TN $taskName | Out-Null
        Start-Sleep 3
        schtasks /Delete /TN $taskName /F | Out-Null

        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $plainPwd = $null
    }
    catch {
        Write-Host "[ERROR] Failed to run as other user (elevated): $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        exit
    }
}

# Reinvoke once only
if (-not $Reinvoked) {
    Invoke-AsOtherUser -Elevate:$Elevate
}

# ---------------------------------------------------------
#   IMPORT AD MODULE
# ---------------------------------------------------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] Unable to load ActiveDirectory module." -ForegroundColor Red
    pause
    exit
}

Write-Host "=== Set AD User Expiry ===" -ForegroundColor Cyan
Write-Host "Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Yellow


# ====================================================================
#   STEP 1 — STANDARD USER (CHECK ONLY)
# ====================================================================
$StandardUser = Read-Host "Enter Standard Account Username"
if ([string]::IsNullOrWhiteSpace($StandardUser)) {
    Write-Host "[ERROR] Standard Account Username is required." -ForegroundColor Red
    pause
    goto ReloadScript
}

try {
    $StandardUserObj = Get-ADUser -Identity $StandardUser -Properties AccountExpirationDate -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] User '$StandardUser' does not exist." -ForegroundColor Red
    pause
    goto ReloadScript
}

Write-Host "User found: $($StandardUserObj.Name) [$($StandardUserObj.SamAccountName)]" -ForegroundColor Green
Write-Host "DN: $($StandardUserObj.DistinguishedName)" -ForegroundColor DarkGreen

if ($StandardUserObj.AccountExpirationDate) {
    $CurrentExpiry = $StandardUserObj.AccountExpirationDate.ToString("dd/MM/yyyy HH:mm")
} else {
    $CurrentExpiry = "Not Set To Expire"
}

Write-Host "Current Expiry: $CurrentExpiry" -ForegroundColor Cyan


# ====================================================================
#   INPUTS FOR EXPIRY CHANGE
# ====================================================================
$SamAccountName = Read-Host "Enter sAMAccountName for expiry change"
if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
    Write-Host "[ERROR] sAMAccountName is required." -ForegroundColor Red
    pause
    goto ReloadScript
}

$ExpireChoice = Read-Host "Set account to expire? (None / Date / 6months)"
if ([string]::IsNullOrWhiteSpace($ExpireChoice)) {
    Write-Host "[ERROR] Expiry choice is required." -ForegroundColor Red
    pause
    goto ReloadScript
}

# Validate target user
try {
    $User = Get-ADUser -Identity $SamAccountName -Properties AccountExpirationDate -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] User '$SamAccountName' not found." -ForegroundColor Red
    pause
    goto ReloadScript
}

Write-Host "User found: $($User.Name) [$($User.SamAccountName)]" -ForegroundColor Green
Write-Host "DN: $($User.DistinguishedName)" -ForegroundColor DarkGreen


# ====================================================================
#   DETERMINE EXPIRY
# ====================================================================
$AccountExpirationDate = $null

switch -Regex ($ExpireChoice.ToLower()) {

    "none" {
        $AccountExpirationDate = $null
    }

    "date" {
        $DateInput = Read-Host "Enter expiration date (dd/MM/yyyy)"
        try {
            $AccountExpirationDate = [datetime]::ParseExact($DateInput,"dd/MM/yyyy",[System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            Write-Host "[ERROR] Invalid date format." -ForegroundColor Red
            pause
            goto ReloadScript
        }
    }

    "6months" {
        $AccountExpirationDate = (Get-Date).AddMonths(6)
    }

    default {
        Write-Host "[ERROR] Invalid option." -ForegroundColor Red
        pause
        goto ReloadScript
    }
}

# ====================================================================
#   APPLY EXPIRY
# ====================================================================
try {
    Set-ADUser -Identity $User.DistinguishedName -AccountExpirationDate $AccountExpirationDate -ErrorAction Stop
    
    $Verify = Get-ADUser -Identity $User.DistinguishedName -Properties AccountExpirationDate
    $Effective = if ($Verify.AccountExpirationDate) {
        $Verify.AccountExpirationDate.ToString("dd/MM/yyyy HH:mm")
    } else {
        "None (does not expire)"
    }

    Write-Host "[SUCCESS] Updated expiry for '$SamAccountName'." -ForegroundColor Green
    Write-Host "Effective Expiry: $Effective" -ForegroundColor Cyan
}
catch {
    Write-Host "[ERROR] Failed to update expiry: $($_.Exception.Message)" -ForegroundColor Red
}

# ====================================================================
#   RELOAD WITHOUT RE-ELEVATING
# ====================================================================
:ReloadScript
Write-Host ""
Write-Host "Press Enter to reload or type X to exit..." -ForegroundColor Yellow
$choice = Read-Host

if ($choice -eq "x") {
    exit
}

Write-Host "`nReloading script..." -ForegroundColor Cyan
Start-Sleep 1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`"$PSCommandPath`"" -Reinvoked

exit