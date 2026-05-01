Import-Module ActiveDirectory

$DryRunCsv = "C:\Temp\EmailChange_DryRun.csv.csv"

$rows = Import-Csv $DryRunCsv

foreach ($row in $rows) {

    if ($row.UserFound -eq "True" -and
        $row.ManagerFound -eq "True" -and
        $row.ChangeRequired -eq "True") {

        $user    = Get-ADUser -Identity $row.UserSam
        $manager = Get-ADUser -Identity $row.ManagerSam

        Set-ADUser -Identity $user -Manager $manager.DistinguishedName

        Write-Host "Updated: $($row.UserSam) → $($row.ManagerSam)" -ForegroundColor Green
    }
    else {
        Write-Host "Skipped: $($row.UserSam)" -ForegroundColor Yellow
    }
}
