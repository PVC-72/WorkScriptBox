######Not connecting to ex managgement shell


##############################################
# EDIT THESE TWO LINES ONLY
##############################################
$Sam = "CSalter3"                                  # AD username
$ExternalAddress = "charles.salter@gtrailway.com"  # External SMTP address
##############################################

<#
   Mail-enable an AD User in Exchange On-Prem
   Auto-loads Exchange CMDLETs (snap-in or remoting)
#>

# ----------------------------
# Load AD module
# ----------------------------
Import-Module ActiveDirectory -ErrorAction Stop

# ----------------------------
# Load Exchange cmdlets
# ----------------------------
function Load-ExchangeCmdlets {

    Write-Host "Loading Exchange cmdlets..." -ForegroundColor Cyan

    # 1. Try snap-ins (2010/2013/2016/2019)
    $snapins = @(
        "Microsoft.Exchange.Management.PowerShell.SnapIn",
        "Microsoft.Exchange.Management.PowerShell.E2016",
        "Microsoft.Exchange.Management.PowerShell.E2013",
        "Microsoft.Exchange.Management.PowerShell.E2010"
    )

    foreach ($snap in $snapins) {
        try {
            Add-PSSnapin $snap -ErrorAction Stop
            if (Get-Command Get-Recipient -ErrorAction SilentlyContinue) {
                Write-Host "Loaded Exchange snap-in: $snap" -ForegroundColor Green
                return
            }
        } catch { }
    }

    # 2. Try implicit remoting (local Exchange server PowerShell virtual directory)
    $EndPoints = @(
        "http://localhost/PowerShell/",
        "https://localhost/PowerShell/"
    )

    foreach ($ep in $EndPoints) {
        try {
            Write-Host "Trying remoting: $ep" -ForegroundColor DarkYellow
            $so = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
            $session = New-PSSession -ConfigurationName Microsoft.Exchange `
                                     -ConnectionUri $ep `
                                     -Authentication Kerberos `
                                     -SessionOption $so `
                                     -ErrorAction Stop
            Import-PSSession $session -DisableNameChecking -AllowClobber | Out-Null
            
            if (Get-Command Get-Recipient -ErrorAction SilentlyContinue) {
                Write-Host "Imported Exchange cmdlets via remoting." -ForegroundColor Green
                return
            }
        } catch { }
    }

    throw "Could not load Exchange cmdlets. You may need to run on an Exchange server."
}

Load-ExchangeCmdlets

# ----------------------------
# Validate AD user
# ----------------------------
$adUser = Get-ADUser -Identity $Sam -Properties DisplayName -ErrorAction Stop

# ----------------------------
# Check if already mailbox-enabled
# ----------------------------
$recip = Get-Recipient -Identity $Sam -ErrorAction SilentlyContinue
if ($recip -and $recip.RecipientType -eq "UserMailbox") {
    throw "User already has a mailbox — cannot enable as MailUser."
}

# ----------------------------
# Enable or update MailUser
# ----------------------------
$mu = Get-MailUser -Identity $Sam -ErrorAction SilentlyContinue

if (-not $mu) {
    Write-Host "Creating MailUser..." -ForegroundColor Cyan
    Enable-MailUser -Identity $Sam -ExternalEmailAddress $ExternalAddress -ErrorAction Stop
    Start-Sleep 3
} else {
    Write-Host "MailUser exists — updating..." -ForegroundColor Yellow
    if ($mu.ExternalEmailAddress -ne $ExternalAddress) {
        Set-MailUser -Identity $Sam -ExternalEmailAddress $ExternalAddress
    }
}

# Refresh object
$mu = Get-MailUser -Identity $Sam

# ----------------------------
# Prefix Display Name
# ----------------------------
$newName = "EXT-$($adUser.DisplayName)"

if ($mu.DisplayName -notlike "EXT-*") {
    Write-Host "Updating DisplayName to: $newName" -ForegroundColor Green
    Set-MailUser -Identity $Sam -DisplayName $newName
}

# ----------------------------
# Ensure GAL visibility
# ----------------------------
Set-MailUser -Identity $Sam -HiddenFromAddressListsEnabled:$false

# ----------------------------
# DONE
# ----------------------------
Write-Host "`nFinal MailUser State:" -ForegroundColor Cyan
Get-MailUser -Identity $Sam | Format-List