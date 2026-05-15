# --- CONFIGURATION & CREDENTIALS ---
$InstanceURL = "https://nwrprod.service-now.com"
$GroupID     = "d232de84db3e9410a6247a76f3961959" # ITHD_ADMIN
$LocalPath   = "C:\temp\SNReports"
$OutputFile  = Join-Path $LocalPath "RemovableMedia_Report.csv"

# Credentials
$SNUser = ""
$SNPass = ""

if ($SNUser -eq "YOUR_USERNAME") {
    Write-Host "ERROR: Please update credentials." -ForegroundColor Red
    return
}


# --- AUTH (FIXED) ---
$AuthString = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $SNUser, $SNPass))
)

$Headers = @{
    'Authorization' = "Basic $AuthString"
    'Accept'        = 'application/json'
}




# --- QUERY ---
$query = "assignment_group=$GroupID^stateIN1,2^request_item.cat_item.name=Amend My Removable Device Access"

$uri = "$InstanceURL/api/now/table/sc_task?sysparm_query=$query&sysparm_limit=1000&sysparm_display_value=all"

# --- GET TASKS ---
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get
}
catch {
    Write-Host "❌ Failed to retrieve tasks" -ForegroundColor Red
    Write-Host $_
    return
}

Write-Host "Records returned: $($response.result.Count)"

$results = @()

# --- PROCESS TASKS ---
foreach ($task in $response.result) {

    $ritmSysId = $task.request_item.value

    $varValue = $null

    try {
        # --- GET VARIABLES FOR RITM ---
        $varUri = "$InstanceURL/api/now/table/sc_item_option_mtom?sysparm_query=request_item=$ritmSysId&sysparm_display_value=all"
        $varResponse = Invoke-RestMethod -Uri $varUri -Headers $Headers -Method Get

        foreach ($var in $varResponse.result) {

            # ✅ MATCH CORRECT VARIABLE USING SYS_ID
            if ($var.item_option_new -eq $targetVarId) {

                # ✅ CORRECT FIELD FOR VALUE
                if ($var.value) {
                    $varValue = $var.value
                } else {
                    $varValue = "NO VALUE"
                }

                break
            }
        }

        if (-not $varValue) {
            $varValue = "NOT FOUND"
        }

        # ✅ RESOLVE VALUE TO FRIENDLY TEXT
        if ($varValue -and $varValue -notin @("NOT FOUND","ERROR","NO VALUE")) {

            $choiceQuery = "value=$varValue"
            $choiceUri = "$InstanceURL/api/now/table/question_choice?sysparm_query=$choiceQuery&sysparm_fields=text,value"

            try {
                $choiceResponse = Invoke-RestMethod -Uri $choiceUri -Headers $Headers -Method Get

                if ($choiceResponse.result.Count -gt 0) {
                    $varValue = $choiceResponse.result[0].text
                }
            }
            catch {
                $varValue = "LOOKUP ERROR"
            }
        }

    }
    catch {
        $varValue = "ERROR"
    }

    # --- STATE FRIENDLY NAME ---
    $stateText = switch ([string]$task.state.value) {
        "1" { "Open" }
        "2" { "Work In Progress" }
        default { $task.state.display_value }
    }

    # --- BUILD RESULT ---
    $results += [PSCustomObject]@{
        TaskNumber        = $task.number.display_value
        RITMNumber        = $task.request_item.display_value
        AssignmentGroup   = $task.assignment_group.display_value
        State             = $stateText
        CatalogItem       = "Amend My Removable Device Access"
        DoYouHaveNewAsset = $varValue
    }
}

# --- ENSURE OUTPUT DIRECTORY EXISTS ---
if (!(Test-Path $LocalPath)) {
    New-Item -ItemType Directory -Path $LocalPath | Out-Null
}

# --- ENSURE HEADERS EVEN IF NO DATA ---
if ($results.Count -eq 0) {
    Write-Host "⚠️ No records found — creating empty report with headers"

    $results = @(
        [PSCustomObject]@{
            TaskNumber        = $null
            RITMNumber        = $null
            AssignmentGroup   = $null
            State             = $null
            CatalogItem       = $null
            DoYouHaveNewAsset = $null
        }
    )
}

# --- EXPORT ---
$results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "✅ Export complete: $OutputFile"
