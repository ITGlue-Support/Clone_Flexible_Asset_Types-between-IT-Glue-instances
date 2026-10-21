# ============================================
# Clone ALL Flexible Asset Types
# SOURCE IT Glue → TARGET IT Glue
# Author: Bart Jozwiak
# ============================================

Write-Host "=== Clone ALL Flexible Asset Types Between IT Glue Accounts ===" -ForegroundColor Cyan

# ================================
# PROMPTS
# ================================

$sourceApiKey = Read-Host "Enter SOURCE IT Glue API Key"
$targetApiKey = Read-Host "Enter TARGET IT Glue API Key"

# ================================
# HEADERS
# ================================

$sourceHeaders = @{
    "x-api-key"    = $sourceApiKey
    "Content-Type" = "application/vnd.api+json"
}

$targetHeaders = @{
    "x-api-key"    = $targetApiKey
    "Content-Type" = "application/vnd.api+json"
}

# Change if needed:
$baseUrl = "https://api.eu.itglue.com"

# ================================
# GET ALL SOURCE FATs
# ================================

Write-Host "`n--- Retrieving ALL Flexible Asset Types from SOURCE ---" -ForegroundColor Cyan

$allSourceFATs = @()
$page = 1

try {
    do {
        $url = "$baseUrl/flexible_asset_types?page[number]=$page&page[size]=100"
        $response = Invoke-RestMethod -Method GET -Uri $url -Headers $sourceHeaders

        if ($response.data) {
            $allSourceFATs += $response.data
        }

        $page++
    }
    while ($response.data.Count -gt 0)

    Write-Host " Found $($allSourceFATs.Count) Flexible Asset Types in source." -ForegroundColor Green
}
catch {
    Write-Host " Error retrieving FAT list from source." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit
}

if ($allSourceFATs.Count -eq 0) {
    Write-Host " No Flexible Asset Types found in source account." -ForegroundColor Yellow
    exit
}

# ================================
# GET ALL TARGET FAT NAMES
# ================================

Write-Host "`n--- Checking existing FATs in TARGET ---" -ForegroundColor Cyan

$targetFATNames = @()
$page = 1

try {
    do {
        $url = "$baseUrl/flexible_asset_types?page[number]=$page&page[size]=100"
        $response = Invoke-RestMethod -Method GET -Uri $url -Headers $targetHeaders

        if ($response.data) {
            $targetFATNames += $response.data.attributes.name
        }

        $page++
    }
    while ($response.data.Count -gt 0)
}
catch {
    Write-Host " Error retrieving FAT list from target." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit
}

# ================================
# CLONE LOOP
# ================================

$created = 0
$skipped = 0
$failed  = 0

foreach ($fat in $allSourceFATs) {

    $fatName = $fat.attributes.name
    $fatId   = $fat.id

    Write-Host "`nProcessing: $fatName" -ForegroundColor Yellow

    # Skip if exists
    if ($targetFATNames -contains $fatName) {
        Write-Host " Skipped (already exists in target)" -ForegroundColor DarkYellow
        $skipped++
        continue
    }

    try {
        # Get full FAT with fields
        $url = "$baseUrl/flexible_asset_types/$fatId/?include=flexible_asset_fields"
        $fatResponse = Invoke-RestMethod -Method GET -Uri $url -Headers $sourceHeaders

        $sourceType = $fatResponse.data.attributes
        $fields = $fatResponse.included |
            Where-Object { $_.type -eq "flexible-asset-fields" } |
            ForEach-Object { $_.attributes }

        if (-not $fields) {
            Write-Host " No fields found. Skipping." -ForegroundColor DarkYellow
            $skipped++
            continue
        }

        # Sanitize fields
        $cleanedFields = @()
        $order = 1

        foreach ($field in $fields) {

            $optionsSanitized = @()

            if ($field.options -and $field.options -is [System.Array]) {
                foreach ($opt in $field.options) {
                    if ($opt -is [string] -or $opt -is [int]) {
                        $optionsSanitized += $opt
                    }
                }
            }

            $fieldObj = @{
                type       = "flexible_asset_fields"
                attributes = @{
                    order           = $order
                    name            = $field.name
                    kind            = $field.kind
                    hint            = $field.hint
                    required        = $field.required
                    "use-for-title" = $field.'use-for-title'
                    "show-in-list"  = $field.'show-in-list'
                    options         = $optionsSanitized
                }
            }

            if ($field.'tag-type') {
                $fieldObj.attributes["tag-type"] = $field.'tag-type'
            }

            if ($field.'default-value') {
                $fieldObj.attributes["default-value"] = $field.'default-value'
            }

            $cleanedFields += $fieldObj
            $order++
        }

        # Prepare body
        $clone = @{
            data = @{
                type = "flexible_asset_types"
                attributes = @{
                    name        = $fatName
                    description = $sourceType.description
                }
                relationships = @{
                    "flexible-asset-fields" = @{
                        data = $cleanedFields
                    }
                }
            }
        }

        $body = $clone | ConvertTo-Json -Depth 10 -Compress

        # Create in target
        $postUrl = "$baseUrl/flexible_asset_types"
        $result = Invoke-RestMethod -Method POST -Uri $postUrl -Headers $targetHeaders -Body $body

        Write-Host " Created successfully (ID: $($result.data.id))" -ForegroundColor Green
        $created++
    }
    catch {
        Write-Host " Failed to create FAT." -ForegroundColor Red
        Write-Host $_.Exception.Message
        $failed++
    }
}

# ================================
# SUMMARY
# ================================

Write-Host "`n=== CLONE SUMMARY ===" -ForegroundColor Cyan
Write-Host " Created : $created" -ForegroundColor Green
Write-Host " Skipped : $skipped" -ForegroundColor Yellow
Write-Host " Failed  : $failed"  -ForegroundColor Red
Write-Host "`nDone."