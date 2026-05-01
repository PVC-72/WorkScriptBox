Import-Module ActiveDirectory

$InputCsv  = "C:\Temp\EmailChange.csv"
$DryRunCsv = "C:\Temp\EmailChange_DryRun.csv"

$results = foreach ($row in (Import-Csv $InputCsv)) {

    $user    = Get-ADUser -Identity $row.UserSam -Properties Manager -ErrorAction SilentlyContinue
    $manager = Get-ADUser -Identity $row.ManagerSam -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        UserSam        = $row.UserSam
        ManagerSam     = $row.ManagerSam
        UserFound      = [bool]$user
        ManagerFound   = [bool]$manager
        CurrentManager = if ($user.Manager) { (Get-ADUser $user.Manager).SamAccountName } else { "" }
        NewManager     = if ($manager) { $manager.SamAccountName } else { "" }
        ChangeRequired = if ($user -and $manager -and ($user.Manager -ne $manager.DistinguishedName)) { $true } else { $false }
    }
}

$results | Export-Csv -NoTypeInformation -Path $DryRunCsv

Write-Host "Dry run complete. Review: $DryRunCsv" -ForegroundColor Cyan
