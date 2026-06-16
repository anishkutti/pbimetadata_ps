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

$baseUrl = "https://api.powerbi.com/v1.0/myorg/admin"

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
# HELPER FUNCTION: Retry Logic
# -----------------------------
function Invoke-WithRetry {
    param ($url)

    while ($true) {
        try {
            return Invoke-RestMethod -Headers $headers -Uri $url -Method Get
        }
        catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 429) {
                $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                if (-not $retryAfter) { $retryAfter = 10 }

                Write-Host "Rate limited. Waiting $retryAfter seconds..."
                Start-Sleep -Seconds $retryAfter
            }
            else {
                throw $_
            }
        }
    }
}

# -----------------------------
# STEP 1: Get Workspaces
# -----------------------------
$groups = Invoke-WithRetry "$baseUrl/groups?$top=5000"

$results = @()

# -----------------------------
# STEP 2: Loop with Throttle
# -----------------------------
foreach ($group in $groups.value) {

    Start-Sleep -Milliseconds 200  # proactive throttle

    $datasets = Invoke-WithRetry "$baseUrl/groups/$($group.id)/datasets"

    foreach ($dataset in $datasets.value) {

        Start-Sleep -Milliseconds 200

        $datasources = Invoke-WithRetry "$baseUrl/groups/$($group.id)/datasets/$($dataset.id)/datasources"

        foreach ($ds in $datasources.value) {
            if ($ds.datasourceType -like "*Teradata*") {
                $results += [PSCustomObject]@{
                    WorkspaceName = $group.name
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
$results | Export-Csv "Teradata_Datasets_Fallback.csv" -NoTypeInformation
Write-Host "Completed with throttling-safe execution."