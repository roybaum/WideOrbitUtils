# Run Master Inventory Sync On WideOrbit Server

This setup runs the sync directly from the WideOrbit Central Server and posts inventory to your Google Sheet webhook.

## 1) Copy Project To Server

Copy the full project folder to a stable path on the server, for example:

- C:/WideOrbitUtils

## 2) Set Server Configuration

Open PowerShell as Administrator (recommended) and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Set-Location C:\WideOrbitUtils

.\ServerSetup\Set-MasterInventorySyncConfig.ps1 `
  -WoIp 192.168.144.21 `
  -WebhookUrl "https://script.google.com/a/macros/connmedia.com/s/AKfycbxUAcXt5SvtF75Sv5NvJ2ly2BMUpR5MUMYxI7T3jlTGWyJ8bGkEuunGL-Lp31uqLO-B/exec" `
  -WebhookToken "REPLACE_WITH_YOUR_TOKEN" `
  -Categories COM `
  -SheetName Inventory `
  -WriteMode upsert `
  -Scope Machine
```

Notes:

- Use `-Scope User` if you do not want machine-wide environment variables.
- `-Scope Machine` usually requires elevated permissions.

## 3) Test Manual Run On Server

```powershell
Set-Location C:\WideOrbitUtils
.\ServerSetup\Invoke-MasterInventorySync.ps1 -Verbose
```

Expected output includes:

- `Pushed <n> rows to webhook in <m> batch(es).`
- `Sync log written to ...\Logs\MasterInventorySync-*.log`

## 4) Register Scheduled Task (Hourly)

```powershell
Set-Location C:\WideOrbitUtils
.\ServerSetup\Register-MasterInventorySyncTask.ps1 `
  -TaskName "WideOrbit-MasterInventory-Sync" `
  -IntervalMinutes 60 `
  -RunAs SYSTEM `
  -RunImmediately
```

## 5) Verify Task

```powershell
Get-ScheduledTask -TaskName "WideOrbit-MasterInventory-Sync" | Get-ScheduledTaskInfo
```

You can also review logs under:

- C:/WideOrbitUtils/Logs

## 6) Manual Trigger Anytime

```powershell
Start-ScheduledTask -TaskName "WideOrbit-MasterInventory-Sync"
```
