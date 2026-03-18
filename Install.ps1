param(
    [string]$InstallDirectory,
    [switch]$UsePersonalModules
)

$filelist = Write-Output `
    WideOrbit.psd1 `
    WideOrbit.psm1 `
    Export-MediaAssets.ps1 `
    Get-AllRadioStations.ps1 `
    Get-MediaAsset.ps1 `
    Get-ScheduleByDate.ps1 `
    Remove-CueAudio.ps1 `
    Remove-MediaAsset.ps1 `
    Search-RadioStationContent.ps1 `
    Sync-WOPurge.ps1 `
    Update-MediaAsset.ps1 `
    Update-CampaignSpots.ps1

if ('' -eq $InstallDirectory) {
    if ($UsePersonalModules) {
        $personalModules = Join-Path -Path ([System.Environment]::GetFolderPath('MyDocuments')) -ChildPath WindowsPowershell\Modules

        if(($env:PSModulePath -split ';') -notcontains $personalModules) {
            Write-Warning "personalModules is not in `$env:PSModulePath"
        }

        if(!(Test-Path $personalModules)) {
            Write-Warning "$personalModules does not exist."
        }

        $InstallDirectory = Join-Path -Path $personalModules -ChildPath WideOrbit
    } else {
        $InstallDirectory = Join-Path -Path $PSScriptRoot -ChildPath Modules\WideOrbit
    }
}

if (!(Test-Path $InstallDirectory)) {
    $null = mkdir $InstallDirectory
}

$wc = New-Object System.Net.WebClient
$filelist | ForEach-Object {
    $wc.DownloadFile("https://raw.github.com/areynolds77/wideorbit/master/$_","$InstallDirectory\$_")
}

$campaignSpotsScript = Join-Path -Path $InstallDirectory -ChildPath Update-CampaignSpots.ps1
if (Test-Path $campaignSpotsScript) {
    $exampleInvocation = "Update-CampaignSpots -wo_ip wideorbit -wo_csvfile 'C:\Powershell\WOImport\Campaign Spots Import 2018-09.csv' -Debug -WhatIf"
    $campaignSpotsContent = Get-Content -Path $campaignSpotsScript -Raw

    if ($campaignSpotsContent -match [regex]::Escape($exampleInvocation)) {
        $campaignSpotsContent = $campaignSpotsContent -replace [regex]::Escape($exampleInvocation), "# Example:`r`n# $exampleInvocation"
        Set-Content -Path $campaignSpotsScript -Value $campaignSpotsContent
    }
}

$exportMediaAssetsScript = Join-Path -Path $InstallDirectory -ChildPath Export-MediaAssets.ps1
if (Test-Path $exportMediaAssetsScript) {
    $oldWebRequestLine = '$MediaAssetInfoRet = [xml] (Invoke-WebRequest -Uri $URI_SearchRadioStationContent -Method Post -ContentType "text/xml" -Body $MediaAssetInfoBody)'
    $newWebRequestBlock = @'
            $requestParams = @{
                Uri         = $URI_SearchRadioStationContent
                Method      = 'Post'
                ContentType = 'text/xml'
                Body        = $MediaAssetInfoBody
            }

            if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('UseBasicParsing')) {
                $requestParams.UseBasicParsing = $true
            }

            $MediaAssetInfoRet = [xml]((Invoke-WebRequest @requestParams).Content)
'@
    $exportMediaAssetsContent = Get-Content -Path $exportMediaAssetsScript -Raw

    if ($exportMediaAssetsContent.Contains($oldWebRequestLine)) {
        $exportMediaAssetsContent = $exportMediaAssetsContent.Replace($oldWebRequestLine, $newWebRequestBlock.TrimEnd())
        Set-Content -Path $exportMediaAssetsScript -Value $exportMediaAssetsContent
    }
}

$getMediaAssetScript = Join-Path -Path $InstallDirectory -ChildPath Get-MediaAsset.ps1
if (Test-Path $getMediaAssetScript) {
    $oldGetMediaAssetLine = '$GMA_Reply = [xml](Invoke-WebRequest -Uri $wo_uri -Method POST -ContentType "text/xml" -Body $GMA_Body)'
    $newGetMediaAssetBlock = @'
        $requestParams = @{
            Uri         = $wo_uri
            Method      = 'POST'
            ContentType = 'text/xml'
            Body        = $GMA_Body
        }

        if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('UseBasicParsing')) {
            $requestParams.UseBasicParsing = $true
        }

        $GMA_Reply = [xml]((Invoke-WebRequest @requestParams).Content)
'@
    $getMediaAssetContent = Get-Content -Path $getMediaAssetScript -Raw

    if ($getMediaAssetContent.Contains($oldGetMediaAssetLine)) {
        $getMediaAssetContent = $getMediaAssetContent.Replace($oldGetMediaAssetLine, $newGetMediaAssetBlock.TrimEnd())
        Set-Content -Path $getMediaAssetScript -Value $getMediaAssetContent
    }
}

$moduleManifest = Join-Path -Path $InstallDirectory -ChildPath WideOrbit.psd1
if (Test-Path $moduleManifest) {
    Import-Module -Name $moduleManifest -Force -ErrorAction SilentlyContinue
}

Write-Output "Installed WideOrbit module to $InstallDirectory"
    
