[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateLength(3, 3)]
    [string[]]$wo_category,

    [Parameter(Mandatory = $true)]
    [string]$wo_ip,

    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath 'MasterInventoryExports'),

    [string]$OutputFileNamePrefix = 'MasterInventory',

    [switch]$PassThru
)

function Convert-WideOrbitDateTime {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        if ($Value -match '^\d{14}$') {
            return [datetime]::ParseExact(
                $Value,
                'yyyyMMddHHmmss',
                [System.Globalization.CultureInfo]::InvariantCulture
            ).ToString('yyyy-MM-dd HH:mm:ss')
        }
    } catch {
        return $Value
    }

    return $Value
}

if (!(Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$uriSearchRadioStationContent = '{0}/ras/inventory' -f $wo_ip.TrimEnd('/')
$pulledAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$rows = New-Object 'System.Collections.Generic.List[object]'

foreach ($category in $wo_category) {
    $normalizedCategory = $category.ToUpperInvariant()
    Write-Verbose "Requesting media assets for category $normalizedCategory"

    $requestBody = '<?xml version="1.0" encoding="UTF-8"?><searchRadioStationContentRequest version="1"><clientId>clientId</clientId><authentication>admin</authentication><query>{0}/</query><start>0000</start><max>9999</max></searchRadioStationContentRequest>' -f $normalizedCategory

    $requestParams = @{
        Uri         = $uriSearchRadioStationContent
        Method      = 'Post'
        ContentType = 'text/xml'
        Body        = $requestBody
        ErrorAction = 'Stop'
    }

    if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('UseBasicParsing')) {
        $requestParams.UseBasicParsing = $true
    }

    $mediaAssetInfo = [xml]((Invoke-WebRequest @requestParams).Content)
    $cartObjects = @($mediaAssetInfo.searchRadioStationContentReply.cartObjects.cartObject)

    foreach ($cart in $cartObjects) {
        $lengthMilliseconds = $null
        if ($cart.length -match '^\d+$') {
            $lengthMilliseconds = [int64]$cart.length
        }

        $lengthSeconds = $null
        if ($null -ne $lengthMilliseconds) {
            $lengthSeconds = [math]::Round(($lengthMilliseconds / 1000), 3)
        }

        $mediaAsset = [string]::Format('{0}/{1}', $cart.category, $cart.cartName)
        $startDate = Convert-WideOrbitDateTime -Value $cart.startDateTime
        $endDate = Convert-WideOrbitDateTime -Value $cart.killDateTime

        $masterInventoryRow = [pscustomobject]@{
            Title           = $cart.desc1
            Artist          = $cart.desc2
            Trivia          = $cart.desc3
            MediaAsset      = $mediaAsset
            Category        = $cart.category
            Number          = $cart.cartName
            StartDateRaw    = $cart.startDateTime
            EndDateRaw      = $cart.killDateTime
            StartDate       = $startDate
            EndDate         = $endDate
            LengthMs        = $lengthMilliseconds
            LengthSeconds   = $lengthSeconds
            SourceTimestamp = $cart.timestamp
            PulledAtUtc     = $pulledAtUtc
        }

        $rows.Add($masterInventoryRow) | Out-Null
    }
}

if ($rows.Count -eq 0) {
    Write-Warning 'No rows returned from WideOrbit. No CSV file was created.'
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputPath = Join-Path -Path $OutputDirectory -ChildPath ('{0}-{1}.csv' -f $OutputFileNamePrefix, $timestamp)

$rows | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
Write-Output "Exported $($rows.Count) rows to $outputPath"

if ($PassThru) {
    $rows
}
