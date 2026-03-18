[CmdletBinding()]
param(
    [string]$WoIp = $env:WO_SERVER_IP,

    [ValidateLength(3, 3)]
    [string[]]$Categories,

    [string]$WebhookUrl = $env:WO_MASTER_WEBHOOK_URL,

    [string]$WebhookToken = $env:WO_MASTER_WEBHOOK_TOKEN,

    [string]$SheetName = $(if ([string]::IsNullOrWhiteSpace($env:WO_MASTER_SHEET_NAME)) { 'Inventory' } else { $env:WO_MASTER_SHEET_NAME }),

    [ValidateSet('upsert', 'replace')]
    [string]$WriteMode = $(if ([string]::IsNullOrWhiteSpace($env:WO_MASTER_WRITE_MODE)) { 'upsert' } else { $env:WO_MASTER_WRITE_MODE }),

    [ValidateRange(1, 5000)]
    [int]$BatchSize = 500,

    [ValidateRange(0, 10)]
    [int]$MaxRetries = 3,

    [switch]$EnableCsv,

    [string]$OutputDirectory,

    [string]$LogDirectory
)

$setupRoot = Split-Path -Path $PSCommandPath -Parent
$repoRoot = Split-Path -Path $setupRoot -Parent
$exportScript = Join-Path -Path $repoRoot -ChildPath 'Export-MediaAssetsToMasterInventory.ps1'

if (!(Test-Path -Path $exportScript)) {
    throw "Could not find exporter script at '$exportScript'."
}

if (!$PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $repoRoot -ChildPath 'MasterInventoryExports'
}

if (!$PSBoundParameters.ContainsKey('LogDirectory')) {
    $LogDirectory = Join-Path -Path $repoRoot -ChildPath 'Logs'
}

if (!(Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

if (!$PSBoundParameters.ContainsKey('Categories') -or $Categories.Count -eq 0) {
    if ([string]::IsNullOrWhiteSpace($env:WO_CATEGORIES)) {
        $Categories = @('COM')
    } else {
        $Categories = $env:WO_CATEGORIES.Split(',') |
            ForEach-Object { $_.Trim().ToUpperInvariant() } |
            Where-Object { $_ } |
            Select-Object -Unique
    }
}

$missing = New-Object 'System.Collections.Generic.List[string]'
if ([string]::IsNullOrWhiteSpace($WoIp)) {
    $missing.Add('WoIp or WO_SERVER_IP') | Out-Null
}
if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    $missing.Add('WebhookUrl or WO_MASTER_WEBHOOK_URL') | Out-Null
}
if ([string]::IsNullOrWhiteSpace($WebhookToken)) {
    $missing.Add('WebhookToken or WO_MASTER_WEBHOOK_TOKEN') | Out-Null
}
if ($missing.Count -gt 0) {
    throw ("Missing required configuration: " + ($missing -join ', '))
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path -Path $LogDirectory -ChildPath ("MasterInventorySync-{0}.log" -f $timestamp)

$transcriptStarted = $false
try {
    Start-Transcript -Path $logPath -Append | Out-Null
    $transcriptStarted = $true

    $invokeParams = @{
        wo_ip             = $WoIp
        wo_category       = $Categories
        OutputDirectory   = $OutputDirectory
        WebhookUrl        = $WebhookUrl
        WebhookToken      = $WebhookToken
        WebhookSheetName  = $SheetName
        WebhookWriteMode  = $WriteMode
        WebhookBatchSize  = $BatchSize
        WebhookMaxRetries = $MaxRetries
    }

    if (!$EnableCsv) {
        $invokeParams.DisableCsv = $true
    }

    if ($PSBoundParameters.ContainsKey('Verbose')) {
        $invokeParams.Verbose = $true
    }

    Write-Output "Starting sync for categories: $($Categories -join ', ')"
    Write-Output "Using exporter: $exportScript"

    & $exportScript @invokeParams
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }

    Write-Output "Sync log written to $logPath"
}
