# Master Inventory Webhook Setup

## 1) Google Apps Script Web App

1. Open your target spreadsheet.
2. Go to Extensions -> Apps Script.
3. Replace your script with the contents of GoogleAppsScript-MasterInventoryWebhook.js.
4. Save the project.
5. Run setWebhookToken once from the Apps Script editor with your token value.
6. Deploy -> New deployment -> Web app.
7. Set:
   - Execute as: Me
   - Who has access: Anyone with the link
8. Copy the deployment URL.

## 2) PowerShell Usage

The exporter now supports direct webhook posting with batching and retries.

Example command:

```powershell
.\Export-MediaAssetsToMasterInventory.ps1 `
  -wo_ip 192.168.144.21 `
  -wo_category COM `
  -WebhookUrl "PASTE_WEBHOOK_URL_HERE" `
  -WebhookToken "PASTE_WEBHOOK_TOKEN_HERE" `
  -WebhookSheetName "Inventory" `
  -WebhookWriteMode upsert `
  -WebhookBatchSize 500 `
  -WebhookMaxRetries 3 `
  -Verbose
```

You can also use environment variables instead of command-line secrets:

```powershell
$env:WO_MASTER_WEBHOOK_URL = "PASTE_WEBHOOK_URL_HERE"
$env:WO_MASTER_WEBHOOK_TOKEN = "PASTE_WEBHOOK_TOKEN_HERE"
.\Export-MediaAssetsToMasterInventory.ps1 -wo_ip 192.168.144.21 -wo_category COM -WebhookSheetName "Inventory" -WebhookWriteMode upsert -Verbose
```

## 3) Payload Contract

The exporter sends JSON batches with these fields:

- token
- sheetName
- writeMode (upsert or replace)
- keyFields (defaults to Category + Number)
- runId
- batchNumber
- batchCount
- isFirstBatch
- isLastBatch
- rows (array of mapped inventory records)

## 4) Notes

- CSV export remains enabled by default.
- Use -DisableCsv if you only want webhook push.
- Replace mode clears the sheet on the first batch of a run.
- Upsert mode updates existing rows by key and appends new ones.
