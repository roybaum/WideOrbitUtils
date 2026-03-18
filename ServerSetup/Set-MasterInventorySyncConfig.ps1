[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$WoIp,

    [Parameter(Mandatory = $true)]
    [string]$WebhookUrl,

    [Parameter(Mandatory = $true)]
    [string]$WebhookToken,

    [ValidateLength(3, 3)]
    [string[]]$Categories = @('COM'),

    [string]$SheetName = 'Inventory',

    [ValidateSet('upsert', 'replace')]
    [string]$WriteMode = 'upsert',

    [ValidateSet('User', 'Machine')]
    [string]$Scope = 'User'
)

$values = [ordered]@{
    WO_SERVER_IP            = $WoIp
    WO_CATEGORIES           = ($Categories | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique) -join ','
    WO_MASTER_WEBHOOK_URL   = $WebhookUrl
    WO_MASTER_WEBHOOK_TOKEN = $WebhookToken
    WO_MASTER_SHEET_NAME    = $SheetName
    WO_MASTER_WRITE_MODE    = $WriteMode
}

foreach ($name in $values.Keys) {
    $value = $values[$name]

    if ($PSCmdlet.ShouldProcess("Environment:$name", "Set $Scope scope value")) {
        try {
            [System.Environment]::SetEnvironmentVariable($name, $value, $Scope)
            Set-Item -Path "Env:$name" -Value $value
        } catch {
            throw "Failed setting $name at $Scope scope: $($_.Exception.Message)"
        }
    }
}

$maskedToken = if ($WebhookToken.Length -ge 8) {
    "{0}...{1}" -f $WebhookToken.Substring(0, 4), $WebhookToken.Substring($WebhookToken.Length - 4)
} else {
    '****'
}

Write-Output "Saved sync configuration to $Scope environment scope."
Write-Output "WO_SERVER_IP=$($values.WO_SERVER_IP)"
Write-Output "WO_CATEGORIES=$($values.WO_CATEGORIES)"
Write-Output "WO_MASTER_WEBHOOK_URL=$($values.WO_MASTER_WEBHOOK_URL)"
Write-Output "WO_MASTER_WEBHOOK_TOKEN=$maskedToken"
Write-Output "WO_MASTER_SHEET_NAME=$($values.WO_MASTER_SHEET_NAME)"
Write-Output "WO_MASTER_WRITE_MODE=$($values.WO_MASTER_WRITE_MODE)"
