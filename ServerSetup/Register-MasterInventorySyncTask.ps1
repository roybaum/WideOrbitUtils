[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TaskName = 'WideOrbit-MasterInventory-Sync',

    [ValidateRange(5, 1440)]
    [int]$IntervalMinutes = 60,

    [datetime]$StartAt = (Get-Date).AddMinutes(5),

    [string]$ScriptPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-MasterInventorySync.ps1'),

    [ValidateSet('SYSTEM', 'CurrentUser')]
    [string]$RunAs = 'SYSTEM',

    [switch]$RunImmediately
)

if (!(Test-Path -Path $ScriptPath)) {
    throw "Could not find sync launcher script at '$ScriptPath'."
}

$powershellExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
$actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $actionArgs
$trigger = New-ScheduledTaskTrigger -Once -At $StartAt -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

if ($RunAs -eq 'SYSTEM') {
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
} else {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType S4U -RunLevel Highest
}

if ($PSCmdlet.ShouldProcess($TaskName, 'Register scheduled sync task')) {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Output "Registered scheduled task '$TaskName'."
    Write-Output "Schedule: every $IntervalMinutes minute(s), starting at $StartAt"
    Write-Output "RunAs: $RunAs"
}

if ($RunImmediately -and $PSCmdlet.ShouldProcess($TaskName, 'Start scheduled task now')) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Output "Started task '$TaskName'."
}
