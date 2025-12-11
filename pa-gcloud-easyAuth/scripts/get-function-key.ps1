# Get Function Key for authLevel: function workaround

$FUNCTION_APP = "pa-gcloud15-api-14sxir"
$RESOURCE_GROUP = "pa-gcloud15-rg"

Write-Host "=== Getting Function Key ===" -ForegroundColor Cyan

# Try multiple methods to get the function key

# Method 1: Direct Azure CLI
Write-Host "Method 1: Trying Azure CLI..." -ForegroundColor Yellow
$key = az functionapp function keys list --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --function-name function_app --query "default" -o tsv 2>&1

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($key) -and $key -notmatch "ERROR") {
    Write-Host "✓ Function Key: $key" -ForegroundColor Green
    Write-Host "`nAdd this to your frontend environment variables:" -ForegroundColor Cyan
    Write-Host "VITE_FUNCTION_KEY=$key" -ForegroundColor Yellow
    exit 0
}

# Method 2: REST API
Write-Host "`nMethod 2: Trying REST API..." -ForegroundColor Yellow
$subscriptionId = az account show --query id -o tsv
$accessToken = az account get-access-token --query accessToken -o tsv

$keyUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP/functions/function_app/keys/default?api-version=2022-03-01"
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

try {
    $keyResponse = Invoke-RestMethod -Uri $keyUrl -Headers $headers -Method Get
    if ($keyResponse.properties.value) {
        $key = $keyResponse.properties.value
        Write-Host "✓ Function Key: $key" -ForegroundColor Green
        Write-Host "`nAdd this to your frontend environment variables:" -ForegroundColor Cyan
        Write-Host "VITE_FUNCTION_KEY=$key" -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Host "✗ REST API failed: $_" -ForegroundColor Red
}

# Method 3: List all keys
Write-Host "`nMethod 3: Listing all function keys..." -ForegroundColor Yellow
$allKeys = az functionapp function keys list --name $FUNCTION_APP --resource-group $RESOURCE_GROUP --function-name function_app -o json 2>&1 | ConvertFrom-Json

if ($allKeys -and $allKeys.PSObject.Properties.Count -gt 0) {
    Write-Host "Available keys:" -ForegroundColor Cyan
    $allKeys.PSObject.Properties | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor Yellow
    }
    $key = $allKeys.PSObject.Properties[0].Value
    Write-Host "`nUsing first key: $key" -ForegroundColor Green
    Write-Host "`nAdd this to your frontend environment variables:" -ForegroundColor Cyan
    Write-Host "VITE_FUNCTION_KEY=$key" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n✗ Could not get function key automatically" -ForegroundColor Red
Write-Host "`nMANUAL STEPS:" -ForegroundColor Yellow
Write-Host "1. Go to Azure Portal" -ForegroundColor White
Write-Host "2. Function App: $FUNCTION_APP" -ForegroundColor White
Write-Host "3. Functions -> function_app -> Function Keys" -ForegroundColor White
Write-Host "4. Copy the 'default' key value" -ForegroundColor White
Write-Host "5. Add it as VITE_FUNCTION_KEY in frontend app settings" -ForegroundColor White

