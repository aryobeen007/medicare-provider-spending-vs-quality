# =============================================================================
# Download CMS datasets for the Medicare Provider Spending vs. Quality project
# =============================================================================
# Downloads four CMS source files to the local Downloads folder:
#   1. Medicare Physician & Other Practitioners (MUP-PHY) - 2023 vintage
#   2. Hospital General Information
#   3. Complications and Deaths - Hospital
#   4. Unplanned Hospital Visits - Hospital
#   5. HCAHPS - Hospital (patient experience)
#
# The MUP-PHY file uses a stable direct URL since it's a fixed historical
# release. The four Provider Data Catalog files use rotating URLs, so we
# query the metastore API to get the current download URL for each.
#
# Usage:
#   .\download_cms_datasets.ps1
#
# The files land in $env:USERPROFILE\Downloads\ by default.
# =============================================================================

# --- Configuration ---------------------------------------------------------

$DownloadDir = "$env:USERPROFILE\Downloads"

# MUP-PHY has a stable URL (fixed historical release)
$MupPhyUrl = "https://data.cms.gov/sites/default/files/2025-04/e3f823f8-db5b-4cc7-ba04-e7ae92b99757/MUP_PHY_R25_P05_V20_D23_Prov_Svc.csv"
$MupPhyFilename = "MUP_PHY_R25_P05_V20_D23_Prov_Svc.csv"

# Provider Data Catalog datasets (rotating URLs, fetched via metastore API)
$ProviderDataDatasets = @{
    "Hospital_General_Information"          = "xubh-q36u"
    "Complications_and_Deaths-Hospital"     = "ynj2-r877"
    "Unplanned_Hospital_Visits-Hospital"    = "632h-zaca"
    "HCAHPS-Hospital"                       = "dgck-syfz"
}

$MetastoreApiBase = "https://data.cms.gov/provider-data/api/1/metastore/schemas/dataset/items"

# --- Download MUP-PHY ------------------------------------------------------

Write-Host "Downloading MUP-PHY 2023 (large file, ~2.85 GB)..." -ForegroundColor Cyan
$mupPhyOut = Join-Path $DownloadDir $MupPhyFilename
Invoke-WebRequest -Uri $MupPhyUrl -OutFile $mupPhyOut
Write-Host "  Saved to $mupPhyOut" -ForegroundColor Green

# --- Download Provider Data Catalog files ---------------------------------

foreach ($name in $ProviderDataDatasets.Keys) {
    $datasetId = $ProviderDataDatasets[$name]
    Write-Host "Fetching metastore URL for $name ($datasetId)..." -ForegroundColor Cyan

    try {
        $response = Invoke-RestMethod -Uri "$MetastoreApiBase/$datasetId"
        $url = $response.distribution[0].downloadURL
        $outFile = Join-Path $DownloadDir "$name.csv"

        Write-Host "  Downloading from $url" -ForegroundColor Gray
        Invoke-WebRequest -Uri $url -OutFile $outFile
        Write-Host "  Saved to $outFile" -ForegroundColor Green
    }
    catch {
        Write-Host "  FAILED for ${name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Summary ---------------------------------------------------------------

Write-Host ""
Write-Host "Downloaded files:" -ForegroundColor Cyan
$expectedFiles = @($MupPhyFilename) + @($ProviderDataDatasets.Keys | ForEach-Object { "$_.csv" })
foreach ($f in $expectedFiles) {
    $path = Join-Path $DownloadDir $f
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        $sizeMB = [math]::Round($size / 1MB, 2)
        Write-Host "  [OK]  $f  ($sizeMB MB)"
    } else {
        Write-Host "  [MISSING]  $f" -ForegroundColor Red
    }
}
