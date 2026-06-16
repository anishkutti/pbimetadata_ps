# =============================================================
# WARNING: DRAFT CODE
# THIS SCRIPT HAS NOT BEEN TESTED.
# DO NOT RUN IN PRODUCTION OR CUSTOMER-IMPACTING ENVIRONMENTS.
# =============================================================

# -----------------------------
# CONFIG
# -----------------------------
$tenantId     = "<tenant-id>"
$clientId     = "<client-id>"
$clientSecret = "<client-secret>"

# -----------------------------
# AUTH
# -----------------------------
$body = @{
    grant_type    = "client_credentials"
    scope         = "https://analysis.windows.net/powerbi/api/.default"
    client_id     = $clientId
    client_secret = $clientSecret
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -Body $body

$accessToken = $tokenResponse.access_token
$headers = @{
    Authorization = "Bearer $accessToken"
}

# -----------------------------
# STEP 1: Get Workspaces (Admin API)
# -----------------------------
$groupsUrl = "https://api.powerbi.com/v1.0/myorg/admin/groups?$top=5000"
$groups = (Invoke-RestMethod -Headers $headers -Uri $groupsUrl -Method Get).value

$workspaceIds = $groups.id

# -----------------------------
# STEP 2: Trigger Scan
# -----------------------------
$scanBody = @{
    workspaces = $workspaceIds
} | ConvertTo-Json -Depth 5

$scanResponse = Invoke-RestMethod `
    -Headers $headers `
    -Uri "https://api.powerbi.com/v1.0/myorg/admin/workspaces/scan" `
    -Method Post `
    -Body $scanBody `
    -ContentType "application/json"

$scanId = $scanResponse.id

Write-Host "Scan started: $scanId"

# -----------------------------
# STEP 3: Poll Scan Status
# -----------------------------
$statusUrl = "https://api.powerbi.com/v1.0/myorg/admin/workspaces/scanStatus/$scanId"

do {
    Start-Sleep -Seconds 10
    $status = Invoke-RestMethod -Headers $headers -Uri $statusUrl -Method Get
    Write-Host "Scan status: $($status.status)"
} while ($status.status -ne "Succeeded")

# -----------------------------
# STEP 4: Get Scan Results
# -----------------------------
$resultUrl = "https://api.powerbi.com/v1.0/myorg/admin/workspaces/scanResult/$scanId"
$result = Invoke-RestMethod -Headers $headers -Uri $resultUrl -Method Get

# -----------------------------
# STEP 5: Filter Teradata Usage
# -----------------------------
$teradataDatasets = @()

foreach ($workspace in $result.workspaces) {
    foreach ($dataset in $workspace.datasets) {
        foreach ($ds in $dataset.datasources) {
            if ($ds.datasourceType -like "*Teradata*") {
                $teradataDatasets += [PSCustomObject]@{
                    WorkspaceName = $workspace.name
                    DatasetName   = $dataset.name
                    Datasource    = $ds.datasourceType
                }
            }
        }
    }
}

# -----------------------------
# OUTPUT
# -----------------------------
$teradataDatasets | Export-Csv "Teradata_Datasets.csv" -NoTypeInformation
Write-Host "Teradata dataset inventory exported."