/* CardPilot personal collector. Do not put tokens, mailbox content or card details in source. */
var CARDPILOT_MAIL = Object.freeze({
  VERSION: 1,
  PAGE_SIZE: 500,
  MAX_PACKAGE_BYTES: 5000000,
  MAX_ARCHIVE_BYTES: 45000000,
  MAX_NEW_PER_RUN: 500,
  MAX_SCAN_IDS: 20000,
  SOFT_RUNTIME_MS: 210000,
  INITIAL_DAYS: 30,
  OVERLAP_DAYS: 7,
  DAY_MS: 86400000
});

/** Run once from your own Apps Script editor, authorize, then deploy the web app. */
function setupCardPilot() {
  var properties = PropertiesService.getScriptProperties();
  if (!properties.getProperty('CARDPILOT_MAILBOX_ID')) {
    properties.setProperty('CARDPILOT_MAILBOX_ID', Utilities.getUuid());
  }
  if (!properties.getProperty('CARDPILOT_TOKEN')) rotateCardPilotToken();
  collectBankMail();
  ScriptApp.getProjectTriggers().filter(function (trigger) {
    return trigger.getHandlerFunction() === 'collectBankMail';
  }).forEach(function (trigger) { ScriptApp.deleteTrigger(trigger); });
  ScriptApp.newTrigger('collectBankMail').timeBased().inTimezone('Asia/Hong_Kong')
    .atHour(3).everyDays(1).create();
  return 'Ready. Copy CARDPILOT_TOKEN from project Script Properties directly into CardPilot.';
}

/** Invalidates the old device secret; this function never prints or returns it. */
function rotateCardPilotToken() {
  var token = [Utilities.getUuid(), Utilities.getUuid(), Utilities.getUuid()].join('').replace(/-/g, '');
  PropertiesService.getScriptProperties().setProperty('CARDPILOT_TOKEN', token);
  return 'Token rotated. Reconnect your devices using the new Script Property value.';
}

/** Read-only diagnostics. Logs fixed status codes only, never returned resource identifiers. */
function checkCardPilotServices() {
  var report = { checkedAt: new Date().toISOString(), scopes: {}, services: {} };
  [['gmailReadOnly', 'https://www.googleapis.com/auth/gmail.readonly'],
    ['driveFile', 'https://www.googleapis.com/auth/drive.file']].forEach(function (entry) {
    try {
      var info = ScriptApp.getAuthorizationInfo(ScriptApp.AuthMode.FULL, [entry[1]]);
      report.scopes[entry[0]] = info.getAuthorizationStatus() === ScriptApp.AuthorizationStatus.REQUIRED ? 'REQUIRED' : 'GRANTED';
    } catch (error) { report.scopes[entry[0]] = cardPilotFailureClass_(error); }
  });
  try {
    Gmail.Users.Messages.list('me', { maxResults: 1, includeSpamTrash: false, fields: 'messages(id)' });
    report.services.GMAIL_LIST = 'OK';
  } catch (error) { report.services.GMAIL_LIST = cardPilotFailureClass_(error); }
  try {
    Drive.Files.list({ pageSize: 1, fields: 'files(id)' });
    report.services.DRIVE_LIST = 'OK';
  } catch (error) { report.services.DRIVE_LIST = cardPilotFailureClass_(error); }
  Logger.log(JSON.stringify(report));
  return report;
}

/** Read-only MIME-shape probe; never logs a message ID, header value or decoded content. */
function checkCardPilotMessageFormat() {
  var report = { checkedAt: new Date().toISOString(), stage: 'LIST_GMAIL', nodes: [] };
  try {
    var result = Gmail.Users.Messages.list('me', { maxResults: 20,
      q: 'newer_than:30d -in:spam -in:trash ' + cardPilotSenderQuery_() +
        ' {subject:"Transaction Notification" subject:"Online Transaction has been made on your Debit Card" subject:"滙豐信用卡交易通知"}' });
    var candidates = result.messages || [];
    for (var i = 0; i < candidates.length; i++) {
      report.stage = 'READ_GMAIL';
      var raw = Gmail.Users.Messages.get('me', candidates[i].id, { format: 'full' });
      var headers = raw.payload && raw.payload.headers || [];
      var from = headers.filter(function (header) { return String(header.name).toLowerCase() === 'from'; })[0];
      var subject = headers.filter(function (header) { return String(header.name).toLowerCase() === 'subject'; })[0];
      var bank = cardPilotBankRule_(cardPilotSender_(from && from.value));
      if (!bank || !bank.subject.test(String(subject && subject.value || '').trim().replace(/\s+/g, ' '))) continue;
      cardPilotMIMEShape_(raw.payload, report.nodes, 0);
      report.stage = 'MIME_DECODE';
      var text = cardPilotMIMEBody_(raw.payload);
      report.decodedLength = text.length;
      report.stage = 'TEXT_NORMALIZE';
      report.normalizedLength = cardPilotText_(text).length;
      report.stage = 'ENVELOPE_NORMALIZE';
      report.accepted = normalizeCardPilotMessage_(raw, 'diagnostic-mailbox') !== null;
      report.stage = 'COMPLETE';
      Logger.log(JSON.stringify(report));
      return report;
    }
    report.stage = 'NO_SUPPORTED_MESSAGE';
  } catch (error) {
    report.failureClass = cardPilotFailureClass_(error);
    report.stackFrames = cardPilotSafeStack_(error);
  }
  Logger.log(JSON.stringify(report));
  return report;
}

function cardPilotMIMEShape_(part, nodes, depth) {
  if (!part || nodes.length >= 30 || depth > 8) return;
  var data = part.body && part.body.data;
  var mime = String(part.mimeType || '');
  var allowed = ['text/plain', 'text/html', 'multipart/alternative', 'multipart/mixed', 'multipart/related'];
  nodes.push({ depth: depth, mimeType: allowed.indexOf(mime) >= 0 ? mime : 'other',
    dataType: typeof data, isArray: Array.isArray(data),
    dataLength: data && Number.isSafeInteger(data.length) ? data.length : 0,
    isAttachment: !!part.filename, hasAttachmentID: !!(part.body && part.body.attachmentId),
    base64Shape: typeof data !== 'string' ? 'not_string' : /^[A-Za-z0-9_\-]*={0,2}$/.test(data) ? 'web_safe' : /^[A-Za-z0-9+/]*={0,2}$/.test(data) ? 'standard' : 'other',
    padding: typeof data === 'string' && /=+$/.test(data) });
  (part.parts || []).forEach(function (child) { cardPilotMIMEShape_(child, nodes, depth + 1); });
}

function cardPilotSafeStack_(error) {
  return (String(error && error.stack || '').match(/\bCode(?:\.gs)?:\d+(?::\d+)?\b/g) || []).slice(0, 6);
}

/** Collects on Google servers. Does not mark read, label, forward or delete Gmail messages. */
function collectBankMail() {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) throw new Error('CARDPILOT_COLLECTION_BUSY');
  var properties = PropertiesService.getScriptProperties();
  var stage = 'SETUP';
  try {
    var started = Date.now();
    var mailboxID = properties.getProperty('CARDPILOT_MAILBOX_ID');
    if (!mailboxID) throw new Error('CARDPILOT_SETUP_REQUIRED');
    stage = 'READ_ARCHIVE';
    var archive = readCardPilotArchive_(properties, mailboxID);
    var last = Number(properties.getProperty('CARDPILOT_SCAN_CURSOR') || 0);
    var from = last > 0 ? last - CARDPILOT_MAIL.OVERLAP_DAYS * CARDPILOT_MAIL.DAY_MS
      : started - CARDPILOT_MAIL.INITIAL_DAYS * CARDPILOT_MAIL.DAY_MS;
    stage = 'LIST_GMAIL';
    var ids = listCardPilotMessageIDs_(from, started);
    var seen = Object.assign(Object.create(null), archive.inspectedIDs);
    archive.messages.forEach(function (message) { seen[message.id] = true; });
    var unknown = ids.filter(function (id) { return !seen[mailboxID + ':' + id]; });
    var processed = 0;
    var accepted = 0;
    for (var i = 0; i < unknown.length && processed < CARDPILOT_MAIL.MAX_NEW_PER_RUN; i++) {
      if (Date.now() - started >= CARDPILOT_MAIL.SOFT_RUNTIME_MS) break;
      stage = 'READ_GMAIL';
      var raw = Gmail.Users.Messages.get('me', unknown[i], { format: 'full' });
      stage = 'NORMALIZE_MAIL';
      var message = normalizeCardPilotMessage_(raw, mailboxID);
      // Rejected envelopes are remembered by ID only, never by body or financial fields.
      archive.inspectedIDs[mailboxID + ':' + unknown[i]] = true;
      if (message) { archive.messages.push(message); accepted++; }
      processed++;
    }
    var complete = processed === unknown.length;
    // Persist messages before advancing the Gmail window. Retrying a partial pass is idempotent.
    stage = 'WRITE_ARCHIVE';
    writeCardPilotArchive_(archive, properties);
    stage = 'COMMIT_CURSOR';
    if (complete) properties.setProperty('CARDPILOT_SCAN_CURSOR', String(started));
    stage = 'WRITE_STATUS';
    properties.setProperty('CARDPILOT_LAST_RESULT', JSON.stringify({
      collectedAt: new Date().toISOString(), accepted: accepted, inspected: processed,
      remaining: unknown.length - processed, complete: complete
    }));
    return { accepted: accepted, remaining: unknown.length - processed, complete: complete };
  } catch (error) {
    // Classify privately; service exception text can contain mailbox and resource identifiers.
    var failureClass = cardPilotFailureClass_(error);
    properties.setProperty('CARDPILOT_LAST_RESULT', JSON.stringify({
      failedAt: new Date().toISOString(), error: 'COLLECTION_FAILED', stage: stage, failureClass: failureClass,
      stackFrames: cardPilotSafeStack_(error)
    }));
    throw new Error('CARDPILOT_COLLECTION_FAILED_' + stage + '_' + failureClass + '_' + cardPilotSafeStack_(error).join('_'));
  } finally { lock.releaseLock(); }
}

/** Maps untrusted exception text to a closed set of safe, actionable categories. */
function cardPilotFailureClass_(error) {
  var message = String(error && error.message || '');
  var known = [
    'CARDPILOT_SETUP_REQUIRED', 'CARDPILOT_SCAN_TOO_LARGE', 'CARDPILOT_MAIL_TOO_LARGE',
    'CARDPILOT_UNSUPPORTED_LONG_TEMPLATE', 'CARDPILOT_SUPPORTED_TEMPLATE_BODY_MISSING',
    'CARDPILOT_SUPPORTED_TEMPLATE_BODY_REQUIRES_ADAPTER', 'CARDPILOT_RECEIVED_DATE_INVALID',
    'CARDPILOT_MESSAGE_ID_INVALID', 'CARDPILOT_MIME_DATA_INVALID', 'CARDPILOT_BASE64_INVALID', 'CARDPILOT_PRIVATE_ARCHIVE_UNAVAILABLE',
    'CARDPILOT_PRIVATE_ARCHIVE_INVALID', 'CARDPILOT_ARCHIVE_CAPACITY'
  ];
  if (known.indexOf(message) !== -1) return message;
  if (/\b(?:Gmail|Drive) is not defined\b|not a function/i.test(message)) return 'ADVANCED_SERVICE_MISSING';
  if (/accessNotConfigured|service.?disabled|API.*(?:not.*enabled|disabled|not been used)|enable.*API/i.test(message)) return 'API_NOT_ENABLED';
  if (/insufficient.*scope|insufficientPermissions|required permissions|authorization is required|not have permission to call/i.test(message)) return 'OAUTH_SCOPE_MISSING';
  if (/quota|rate.?limit|too many times|daily limit|limit exceeded/i.test(message)) return 'QUOTA_LIMIT';
  if (/invalid credentials|unauthorized|\b401\b/i.test(message)) return 'UNAUTHORIZED';
  if (/forbidden|permission denied|access denied|\b403\b/i.test(message)) return 'FORBIDDEN';
  if (/not found|\b404\b/i.test(message)) return 'NOT_FOUND';
  if (/invalid (?:argument|value)|bad request|\b400\b/i.test(message)) return 'INVALID_REQUEST';
  if (/timeout|timed out|unavailable|internal error|\b50[0234]\b/i.test(message)) return 'SERVICE_UNAVAILABLE';
  if (error && error.name === 'SyntaxError') return 'INVALID_JSON';
  return 'UNCLASSIFIED_SERVICE_ERROR';
}

/** No query-string token or data-bearing GET route. */
function doGet() { return cardPilotJSON_({ error: 'POST_REQUIRED' }); }

/** POST {token, after?}; one bounded page, with an append-only opaque cursor. */
function doPost(event) {
  try {
    var body = event && event.postData && event.postData.contents;
    if (typeof body !== 'string' || body.length > 4096) return cardPilotJSON_({ error: 'INVALID_REQUEST' });
    var request = JSON.parse(body);
    var properties = PropertiesService.getScriptProperties();
    var expected = properties.getProperty('CARDPILOT_TOKEN');
    if (!cardPilotTokenMatches_(request.token, expected)) return cardPilotJSON_({ error: 'UNAUTHORIZED' });
    var mailboxID = properties.getProperty('CARDPILOT_MAILBOX_ID');
    if (!mailboxID || !properties.getProperty('CARDPILOT_ARCHIVE_FILE_ID')) return cardPilotJSON_({ error: 'SETUP_REQUIRED' });
    var archive = readCardPilotArchive_(properties, mailboxID);
    return cardPilotJSON_(cardPilotPage_(archive, request.after));
  } catch (error) {
    if (error && error.message === 'CARDPILOT_INVALID_CURSOR') return cardPilotJSON_({ error: 'INVALID_CURSOR' });
    return cardPilotJSON_({ error: 'COLLECTOR_UNAVAILABLE' });
  }
}

function listCardPilotMessageIDs_(from, through) {
  var query = 'after:' + Math.floor(from / 1000) + ' before:' + (Math.floor(through / 1000) + 1) +
    ' -in:spam -in:trash ' + cardPilotSenderQuery_();
  var ids = [], seen = Object.create(null), page;
  do {
    var options = { q: query, maxResults: 500, includeSpamTrash: false };
    if (page) options.pageToken = page;
    var result = Gmail.Users.Messages.list('me', options);
    (result.messages || []).forEach(function (message) {
      if (!seen[message.id]) { seen[message.id] = true; ids.push(message.id); }
    });
    if (ids.length > CARDPILOT_MAIL.MAX_SCAN_IDS) throw new Error('CARDPILOT_SCAN_TOO_LARGE');
    page = result.nextPageToken;
  } while (page);
  return ids;
}

function cardPilotSenderQuery_() {
  return '{from:istatement@bochk.com from:lcccaut@hkbea.com ' +
    'from:onlineservicesnotification@hsbc.com.hk from:hsbc_cnp@notification.hsbc.com.hk}';
}

function normalizeCardPilotMessage_(raw, mailboxID) {
  var headers = raw && raw.payload && raw.payload.headers || [];
  var froms = headers.filter(function (header) { return String(header.name).toLowerCase() === 'from'; });
  if (froms.length !== 1) return null;
  var sender = cardPilotSender_(froms[0].value);
  var rule = cardPilotBankRule_(sender);
  if (!rule) return null;
  var subjectHeader = headers.filter(function (header) { return String(header.name).toLowerCase() === 'subject'; })[0];
  var subject = String(subjectHeader && subjectHeader.value || '').trim().replace(/\s+/g, ' ');
  if (!rule.subject.test(subject)) return null;
  // The top Gmail-added Authentication-Results wins. A lower forged pass cannot override its fail.
  var authentication = headers.filter(function (header) {
    return String(header.name).toLowerCase() === 'authentication-results' && /^\s*mx\.google\.com\s*;/i.test(header.value);
  })[0];
  var auth = String(authentication && authentication.value || '');
  var domain = /\bheader\.from\s*=\s*([^\s;]+)/i.exec(auth);
  if (!/\bdmarc\s*=\s*pass\b/i.test(auth) || !domain || domain[1].toLowerCase() !== rule.domain) return null;
  var text = cardPilotText_(cardPilotMIMEBody_(raw.payload));
  if (!text) throw new Error('CARDPILOT_SUPPORTED_TEMPLATE_BODY_MISSING');
  var received = Number(raw.internalDate);
  if (!Number.isFinite(received) || received <= 0 || received > Date.now() + 300000) throw new Error('CARDPILOT_RECEIVED_DATE_INVALID');
  if (!/^[a-zA-Z0-9_-]{1,200}$/.test(String(raw.id || ''))) throw new Error('CARDPILOT_MESSAGE_ID_INVALID');
  return { id: mailboxID + ':' + raw.id, sender: sender, subject: subject,
    receivedAt: new Date(received).toISOString(), body: text, authenticationResults: auth };
}

function cardPilotBankRule_(sender) {
  switch (sender) {
    case 'istatement@bochk.com':
      return { domain: 'bochk.com', subject: /^(?:交易通知\s*[（(]\s*Transaction Notification\s*[）)]|Transaction Notification)$/i };
    case 'lcccaut@hkbea.com':
      return { domain: 'hkbea.com', subject: /^Contactless Payment Transaction Notification(?:\s+非接觸式付款交易通知)?$/i };
    case 'onlineservicesnotification@hsbc.com.hk':
      return { domain: 'hsbc.com.hk', subject: /^Online Transaction has been made on your Debit Card(?:\s+您的扣賬卡網上交易已完成)?$/i };
    case 'hsbc_cnp@notification.hsbc.com.hk':
      // Gmail authenticates this subdomain sender against HSBC's parent domain.
      return { domain: 'hsbc.com.hk', subject: /^HSBC Credit Card Transaction Notification(?:\s*(?:\/\s*)?滙豐信用卡交易通知)?$/i };
    default: return null;
  }
}

function cardPilotSender_(value) {
  var text = String(value || '').trim();
  var angle = /<([^<>\s]+@[^<>\s]+)>\s*$/.exec(text);
  if (angle) return angle[1].toLowerCase();
  return /^[^<>\s,@]+@[^<>\s,@]+$/.test(text) ? text.toLowerCase() : '';
}

function cardPilotMIMEBody_(part) {
  if (!part || part.filename) return '';
  if (part.body && part.body.attachmentId && /^text\/(plain|html)$/i.test(part.mimeType || '')) {
    throw new Error('CARDPILOT_SUPPORTED_TEMPLATE_BODY_REQUIRES_ADAPTER');
  }
  var children = part.parts || [];
  var plain = children.filter(function (child) { return child.mimeType === 'text/plain' && !child.filename; });
  if (plain.length) return cardPilotMIMEBody_(plain[0]);
  if (part.body && part.body.data && /^text\/(plain|html)$/i.test(part.mimeType || '')) {
    var bytes = cardPilotBodyBytes_(part.body.data);
    return Utilities.newBlob(bytes).getDataAsString('UTF-8');
  }
  return children.map(cardPilotMIMEBody_).filter(Boolean).join('\n');
}

function cardPilotBodyBytes_(data) {
  // Advanced Gmail returns decoded Byte[]; the REST JSON representation uses Base64url.
  if (Array.isArray(data)) {
    if (data.length > 1000000) throw new Error('CARDPILOT_MAIL_TOO_LARGE');
    return data.map(function (value) {
      if (!Number.isInteger(value) || value < -128 || value > 255) throw new Error('CARDPILOT_MIME_DATA_INVALID');
      return value > 127 ? value - 256 : value;
    });
  }
  if (typeof data !== 'string') throw new Error('CARDPILOT_MIME_DATA_INVALID');
  var encoded = data.replace(/\s/g, '');
  if (encoded.length > 1333336) throw new Error('CARDPILOT_MAIL_TOO_LARGE');
  if (!/^[A-Za-z0-9+/_-]*={0,2}$/.test(encoded)) throw new Error('CARDPILOT_BASE64_INVALID');
  encoded = encoded.replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
  if (encoded.length % 4 === 1) throw new Error('CARDPILOT_BASE64_INVALID');
  encoded += '='.repeat((4 - encoded.length % 4) % 4);
  var bytes = Utilities.base64DecodeWebSafe(encoded);
  if (bytes.length > 1000000) throw new Error('CARDPILOT_MAIL_TOO_LARGE');
  return bytes;
}

function cardPilotText_(body) {
  var text = String(body || '')
    .replace(/<(script|style|head)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<\s*br\s*\/?\s*>|<\/\s*(?:p|div|tr|td|li|table)\s*>/gi, '\n')
    .replace(/<[^>]*>/g, '')
    .replace(/&(?:nbsp|#160);/gi, ' ')
    .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"').replace(/&apos;|&#39;/gi, "'")
    .replace(/&#(x[0-9a-f]+|[0-9]+);/gi, function (_, value) {
      var code = value[0].toLowerCase() === 'x' ? parseInt(value.slice(1), 16) : Number(value);
      return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : '';
    })
    .replace(/[\t\r ]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  // Keep the evidence, not promotional footers, duplicated translations or message links.
  var patterns = [
    /(Credit card number\s*:?\s*Ending with\s+\d{4}\s+Merchant\s*:?\s*[\s\S]*?\s+Date\s*:?\s*\d{1,2}\s+[A-Za-z]{3,9}(?:\s+\d{4})?\s+Amount\s*:?\s*[A-Z]{3}\s*[\d,]+(?:\.\d{1,2})?)(?=\s*(?:\n|$))/i,
    /(Card Account Number Ending with:[\s\S]*?Transaction Amount:[^\n]+)(?:\n|$)/i,
    /(your BEA Credit Card\s*\(last 4 digits[\s\S]*?\bon\s+\d{4}\/\d{2}\/\d{2}\.?)/i,
    /(The online transaction has been successfully made[\s\S]*?Transaction date and time:\s*\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})/i
  ];
  for (var i = 0; i < patterns.length; i++) {
    var match = patterns[i].exec(text);
    if (match) { text = match[1]; break; }
  }
  if (text.length > 12000) throw new Error('CARDPILOT_UNSUPPORTED_LONG_TEMPLATE');
  return text;
}

function readCardPilotArchive_(properties, mailboxID) {
  var fileID = properties.getProperty('CARDPILOT_ARCHIVE_FILE_ID');
  if (!fileID) return { stateVersion: 1, mailboxID: mailboxID, messages: [], inspectedIDs: {} };
  var response = UrlFetchApp.fetch('https://www.googleapis.com/drive/v3/files/' + encodeURIComponent(fileID) + '?alt=media', {
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() }, muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) throw new Error('CARDPILOT_PRIVATE_ARCHIVE_UNAVAILABLE');
  var archive = JSON.parse(response.getContentText());
  if (archive.stateVersion !== 1 || archive.mailboxID !== mailboxID || !Array.isArray(archive.messages)) {
    throw new Error('CARDPILOT_PRIVATE_ARCHIVE_INVALID');
  }
  archive.inspectedIDs = archive.inspectedIDs || {};
  // Rejected IDs suppress repeated reads, while no rejected body is retained.
  archive.messages.forEach(function (message) { archive.inspectedIDs[message.id] = true; });
  return archive;
}

function writeCardPilotArchive_(archive, properties) {
  var json = JSON.stringify(archive);
  var blob = Utilities.newBlob(json, 'application/json', 'CardPilot bank mail.json');
  if (blob.getBytes().length > CARDPILOT_MAIL.MAX_ARCHIVE_BYTES) throw new Error('CARDPILOT_ARCHIVE_CAPACITY');
  var fileID = properties.getProperty('CARDPILOT_ARCHIVE_FILE_ID');
  if (fileID) Drive.Files.update({}, fileID, blob, { fields: 'id' });
  else {
    var file = Drive.Files.create({ name: 'CardPilot bank mail.json', mimeType: 'application/json',
      appProperties: { cardpilot: 'bank-mail-v1' } }, blob, { fields: 'id' });
    properties.setProperty('CARDPILOT_ARCHIVE_FILE_ID', file.id);
  }
}

function cardPilotPage_(archive, after) {
  var offset = 0;
  if (after !== undefined && after !== null && after !== '') {
    var prefix = archive.mailboxID + ':';
    if (typeof after !== 'string' || after.indexOf(prefix) !== 0 || !/^\d{1,10}$/.test(after.slice(prefix.length))) {
      throw new Error('CARDPILOT_INVALID_CURSOR');
    }
    offset = Number(after.slice(prefix.length));
    if (!Number.isSafeInteger(offset) || offset < 0 || offset > archive.messages.length) throw new Error('CARDPILOT_INVALID_CURSOR');
  }
  var messages = archive.messages.slice(offset, offset + CARDPILOT_MAIL.PAGE_SIZE);
  var result = { schemaVersion: 1, messages: messages,
    nextCursor: messages.length ? archive.mailboxID + ':' + (offset + messages.length) : null };
  while (messages.length && Utilities.newBlob(JSON.stringify(result)).getBytes().length > CARDPILOT_MAIL.MAX_PACKAGE_BYTES) {
    messages.pop(); result.nextCursor = messages.length ? archive.mailboxID + ':' + (offset + messages.length) : null;
  }
  if (!messages.length && offset < archive.messages.length) throw new Error('CARDPILOT_MESSAGE_EXCEEDS_PAGE');
  return result;
}

function cardPilotTokenMatches_(candidate, expected) {
  if (typeof candidate !== 'string' || typeof expected !== 'string' || expected.length < 64 || candidate.length !== expected.length) return false;
  var mismatch = 0;
  for (var i = 0; i < expected.length; i++) mismatch |= candidate.charCodeAt(i) ^ expected.charCodeAt(i);
  return mismatch === 0;
}

function cardPilotJSON_(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}
