[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateLength(3, 3)]
    [string[]]$wo_category,

    [Parameter(Mandatory = $true)]
    [string]$wo_ip,

    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath 'MasterInventoryExports'),

    [string]$OutputFileNamePrefix = 'MasterInventory',

    [string]$WebhookUrl,

    [string]$WebhookToken,

    [ValidateSet('upsert', 'replace')]
    [string]$WebhookWriteMode = 'upsert',

    [string]$WebhookSheetName = 'Inventory',

    [ValidateRange(1, 5000)]
    [int]$WebhookBatchSize = 500,

    [ValidateRange(0, 10)]
    [int]$WebhookMaxRetries = 3,

    [switch]$DisableCsv,

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

function Invoke-MasterInventoryWebhookBatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string]$SheetName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('upsert', 'replace')]
        [string]$WriteMode,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [int]$BatchNumber,

        [Parameter(Mandatory = $true)]
        [int]$BatchCount,

        [Parameter(Mandatory = $true)]
        [int]$MaxRetries
    )

    $payload = [ordered]@{
        token        = $Token
        sheetName    = $SheetName
        writeMode    = $WriteMode
        keyFields    = @('Category', 'Number')
        runId        = $RunId
        batchNumber  = $BatchNumber
        batchCount   = $BatchCount
        isFirstBatch = ($BatchNumber -eq 1)
        isLastBatch  = ($BatchNumber -eq $BatchCount)
        rows         = $Rows
    }

    $jsonBody = $payload | ConvertTo-Json -Depth 8 -Compress

    $requestParams = @{
        Uri         = $Url
        Method      = 'Post'
        ContentType = 'application/json; charset=utf-8'
        Body        = $jsonBody
        ErrorAction = 'Stop'
    }

    if ((Get-Command Invoke-RestMethod).Parameters.ContainsKey('UseBasicParsing')) {
        $requestParams.UseBasicParsing = $true
    }

    for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
        try {
            return Invoke-RestMethod @requestParams
        } catch {
            if ($attempt -gt $MaxRetries) {
                throw
            }

            $delaySeconds = [int][math]::Pow(2, $attempt)
            Write-Warning "Webhook batch $BatchNumber attempt $attempt failed: $($_.Exception.Message). Retrying in $delaySeconds second(s)."
            Start-Sleep -Seconds $delaySeconds
        }
    }
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

if (!$DisableCsv) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outputPath = Join-Path -Path $OutputDirectory -ChildPath ('{0}-{1}.csv' -f $OutputFileNamePrefix, $timestamp)

    $rows | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported $($rows.Count) rows to $outputPath"
}

$resolvedWebhookUrl = $WebhookUrl
if ([string]::IsNullOrWhiteSpace($resolvedWebhookUrl)) {
    $resolvedWebhookUrl = $env:WO_MASTER_WEBHOOK_URL
}

$resolvedWebhookToken = $WebhookToken
if ([string]::IsNullOrWhiteSpace($resolvedWebhookToken)) {
    $resolvedWebhookToken = $env:WO_MASTER_WEBHOOK_TOKEN
}

if (![string]::IsNullOrWhiteSpace($resolvedWebhookUrl)) {
    if ([string]::IsNullOrWhiteSpace($resolvedWebhookToken)) {
        throw 'Webhook URL is set but webhook token is missing. Set -WebhookToken or WO_MASTER_WEBHOOK_TOKEN.'
    }

    $runId = [guid]::NewGuid().Guid
    $batchCount = [int][math]::Ceiling($rows.Count / [double]$WebhookBatchSize)

    for ($batchNumber = 1; $batchNumber -le $batchCount; $batchNumber++) {
        $startIndex = ($batchNumber - 1) * $WebhookBatchSize
        $endIndex = [Math]::Min(($startIndex + $WebhookBatchSize - 1), ($rows.Count - 1))

        if ($startIndex -eq $endIndex) {
            $batchRows = @($rows[$startIndex])
        } else {
            $batchRows = @($rows[$startIndex..$endIndex])
        }

        Write-Verbose "Posting webhook batch $batchNumber/$batchCount with $($batchRows.Count) row(s)"

        $response = Invoke-MasterInventoryWebhookBatch `
            -Url $resolvedWebhookUrl `
            -Token $resolvedWebhookToken `
            -Rows $batchRows `
            -SheetName $WebhookSheetName `
            -WriteMode $WebhookWriteMode `
            -RunId $runId `
            -BatchNumber $batchNumber `
            -BatchCount $batchCount `
            -MaxRetries $WebhookMaxRetries

        if ($null -ne $response) {
            try {
                $responseText = $response | ConvertTo-Json -Depth 6 -Compress
                Write-Verbose ("Webhook response batch {0}: {1}" -f $batchNumber, $responseText)
            } catch {
                Write-Verbose "Webhook response batch $batchNumber received."
            }
        }
    }

    Write-Output "Pushed $($rows.Count) rows to webhook in $batchCount batch(es)."
}

if ($PassThru) {
    $rows
}
