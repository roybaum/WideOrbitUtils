const TOKEN_PROPERTY_KEY = 'MASTER_WEBHOOK_TOKEN';
const DEFAULT_SHEET_NAME = 'Inventory';
const DEFAULT_KEY_FIELDS = ['Category', 'Number'];

function doGet() {
  return jsonResponse({
    ok: true,
    message: 'Master Inventory webhook is running.'
  });
}

function doPost(e) {
  try {
    const payload = parsePayload(e);
    authorizeRequest(payload);

    const rows = Array.isArray(payload.rows) ? payload.rows : [];
    if (rows.length === 0) {
      return jsonResponse({ ok: true, processedRows: 0, skippedRows: 0, message: 'No rows in payload.' });
    }

    const sheetName = String(payload.sheetName || DEFAULT_SHEET_NAME);
    const writeMode = String(payload.writeMode || 'upsert').toLowerCase();
    const keyFields = Array.isArray(payload.keyFields) && payload.keyFields.length > 0
      ? payload.keyFields
      : DEFAULT_KEY_FIELDS;

    if (writeMode !== 'upsert' && writeMode !== 'replace') {
      throw new Error('Unsupported writeMode. Use upsert or replace.');
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = ss.getSheetByName(sheetName) || ss.insertSheet(sheetName);

    let result;
    if (writeMode === 'replace') {
      result = applyReplace(sheet, rows, payload);
    } else {
      result = applyUpsert(sheet, rows, keyFields);
    }

    return jsonResponse({
      ok: true,
      sheetName: sheetName,
      writeMode: writeMode,
      batchNumber: payload.batchNumber || null,
      batchCount: payload.batchCount || null,
      runId: payload.runId || null,
      processedRows: result.processedRows,
      skippedRows: result.skippedRows
    });
  } catch (err) {
    return jsonResponse({ ok: false, error: err.message }, 400);
  }
}

function setWebhookToken(token) {
  if (!token || String(token).trim() === '') {
    throw new Error('Token cannot be empty.');
  }

  PropertiesService.getScriptProperties().setProperty(TOKEN_PROPERTY_KEY, String(token).trim());
  return 'Webhook token saved.';
}

function parsePayload(e) {
  if (!e || !e.postData || !e.postData.contents) {
    throw new Error('Missing JSON request body.');
  }

  try {
    return JSON.parse(e.postData.contents);
  } catch (err) {
    throw new Error('Invalid JSON body.');
  }
}

function authorizeRequest(payload) {
  const expectedToken = PropertiesService.getScriptProperties().getProperty(TOKEN_PROPERTY_KEY);
  if (!expectedToken) {
    throw new Error('Webhook token is not configured in Script Properties.');
  }

  const actualToken = payload && payload.token ? String(payload.token) : '';
  if (actualToken !== expectedToken) {
    throw new Error('Unauthorized request token.');
  }
}

function applyReplace(sheet, rows, payload) {
  const incomingHeaders = collectHeaders(rows);
  const values = rowsToValues(rows, incomingHeaders);
  const isFirstBatch = payload.isFirstBatch === true;

  if (isFirstBatch) {
    sheet.clearContents();
    sheet.getRange(1, 1, 1, incomingHeaders.length).setValues([incomingHeaders]);
    if (values.length > 0) {
      sheet.getRange(2, 1, values.length, incomingHeaders.length).setValues(values);
    }
    sheet.setFrozenRows(1);
    return { processedRows: rows.length, skippedRows: 0 };
  }

  const existingHeaders = getSheetHeaders(sheet);
  let headers = existingHeaders;
  if (headers.length === 0) {
    headers = incomingHeaders;
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
  }

  const alignedValues = rowsToValues(rows, headers);
  const startRow = Math.max(2, sheet.getLastRow() + 1);
  sheet.getRange(startRow, 1, alignedValues.length, headers.length).setValues(alignedValues);

  return { processedRows: rows.length, skippedRows: 0 };
}

function applyUpsert(sheet, rows, keyFields) {
  const existingData = sheet.getDataRange().getValues();
  const existingHeaders = existingData.length > 0 ? existingData[0] : [];
  const incomingHeaders = collectHeaders(rows);
  const headers = unionHeaders(existingHeaders, incomingHeaders);

  if (headers.length === 0) {
    throw new Error('No headers available for upsert operation.');
  }

  const recordsByKey = {};
  const orderedKeys = [];

  let startRow = 1;
  if (existingData.length > 0) {
    startRow = 2;
  }

  for (let i = startRow - 1; i < existingData.length; i++) {
    const record = rowToObject(existingData[i], existingHeaders);
    const key = buildKey(record, keyFields);
    if (!key) {
      continue;
    }

    if (!recordsByKey[key]) {
      orderedKeys.push(key);
    }
    recordsByKey[key] = record;
  }

  let skippedRows = 0;
  for (let i = 0; i < rows.length; i++) {
    const incoming = rows[i];
    const key = buildKey(incoming, keyFields);
    if (!key) {
      skippedRows++;
      continue;
    }

    if (!recordsByKey[key]) {
      orderedKeys.push(key);
      recordsByKey[key] = {};
    }

    recordsByKey[key] = Object.assign({}, recordsByKey[key], incoming);
  }

  const outputValues = [];
  outputValues.push(headers);
  for (let i = 0; i < orderedKeys.length; i++) {
    const key = orderedKeys[i];
    outputValues.push(objectToRow(recordsByKey[key], headers));
  }

  sheet.clearContents();
  sheet.getRange(1, 1, outputValues.length, headers.length).setValues(outputValues);
  sheet.setFrozenRows(1);

  return { processedRows: rows.length - skippedRows, skippedRows: skippedRows };
}

function collectHeaders(rows) {
  const seen = {};
  const headers = [];

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i] || {};
    const keys = Object.keys(row);
    for (let k = 0; k < keys.length; k++) {
      const key = keys[k];
      if (!seen[key]) {
        seen[key] = true;
        headers.push(key);
      }
    }
  }

  return headers;
}

function getSheetHeaders(sheet) {
  if (sheet.getLastRow() < 1 || sheet.getLastColumn() < 1) {
    return [];
  }

  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  return headers.filter(function (h) { return String(h).trim() !== ''; });
}

function unionHeaders(existingHeaders, incomingHeaders) {
  const seen = {};
  const headers = [];

  existingHeaders.forEach(function (header) {
    const key = String(header);
    if (key && !seen[key]) {
      seen[key] = true;
      headers.push(key);
    }
  });

  incomingHeaders.forEach(function (header) {
    const key = String(header);
    if (key && !seen[key]) {
      seen[key] = true;
      headers.push(key);
    }
  });

  return headers;
}

function buildKey(record, keyFields) {
  const parts = [];
  for (let i = 0; i < keyFields.length; i++) {
    const field = keyFields[i];
    const value = record && record[field] !== undefined && record[field] !== null ? String(record[field]).trim() : '';
    parts.push(value);
  }

  const key = parts.join('|');
  return key.replace(/\|/g, '') === '' ? '' : key;
}

function rowToObject(values, headers) {
  const obj = {};
  for (let i = 0; i < headers.length; i++) {
    obj[headers[i]] = values[i];
  }
  return obj;
}

function objectToRow(obj, headers) {
  return headers.map(function (header) {
    return obj[header] !== undefined ? obj[header] : '';
  });
}

function rowsToValues(rows, headers) {
  return rows.map(function (row) {
    return headers.map(function (header) {
      return row[header] !== undefined ? row[header] : '';
    });
  });
}

function jsonResponse(payload, statusCode) {
  const output = ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);

  if (statusCode && output.setResponseCode) {
    output.setResponseCode(statusCode);
  }

  return output;
}
