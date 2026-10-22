const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// All fixtures are invented. No mailbox, Google account, token or network is used.
function fixture() {
  const properties = new Map([
    ['CARDPILOT_MAILBOX_ID', 'example-mailbox'],
    ['CARDPILOT_TOKEN', 'x'.repeat(96)]
  ]);
  let archive;
  let nextFile = 0;
  let uploads = 0;
  let listCalls = 0;
  const rawByID = new Map();
  let pages = [{ messages: [] }];
  let failUpload = false;
  let failGet = false;
  const prop = {
    getProperty: key => properties.get(key) || null,
    setProperty: (key, value) => { properties.set(key, String(value)); return prop; }
  };
  function blob(value) {
    const data = Buffer.isBuffer(value) || Array.isArray(value) ? Buffer.from(value) : Buffer.from(String(value), 'utf8');
    return { getBytes: () => [...data], getDataAsString: () => data.toString('utf8') };
  }
  const context = vm.createContext({
    Date, Number, JSON, Object, String, Array, Math, Error, Boolean,
    PropertiesService: { getScriptProperties: () => prop },
    LockService: { getScriptLock: () => ({ tryLock: () => true, releaseLock: () => {} }) },
    Utilities: {
      getUuid: () => 'invented-uuid-' + (++nextFile), newBlob: blob,
      base64DecodeWebSafe: value => [...Buffer.from(value, 'base64url')]
    },
    ScriptApp: { getOAuthToken: () => 'mock-oauth-never-real' },
    UrlFetchApp: { fetch: () => ({ getResponseCode: () => 200, getContentText: () => JSON.stringify(archive) }) },
    Gmail: { Users: { Messages: {
      list: (_, options) => { listCalls++; return pages[options.pageToken ? Number(options.pageToken) : 0]; },
      get: (_, id) => { if (failGet) throw new Error('mock secret should never escape'); return rawByID.get(id); }
    } } },
    Drive: { Files: {
      create: (_, data) => { if (failUpload) throw new Error('private upload failed'); archive = JSON.parse(data.getDataAsString()); uploads++; return { id: 'private-file' }; },
      update: (_, __, data) => { if (failUpload) throw new Error('private upload failed'); archive = JSON.parse(data.getDataAsString()); uploads++; return { id: 'private-file' }; }
    } },
    ContentService: {
      MimeType: { JSON: 'application/json' },
      createTextOutput: text => ({ text, setMimeType() { return this; } })
    }
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../cloud/apps-script/Code.gs'), 'utf8'), context);
  return {
    context, properties, rawByID,
    setPages(value) { pages = value; }, setFailUpload(value) { failUpload = value; }, setFailGet(value) { failGet = value; },
    archive: () => archive, uploads: () => uploads, listCalls: () => listCalls
  };
}

function mail(id = 'invented-1', overrides = {}) {
  const sender = overrides.sender || 'istatement@bochk.com';
  const domain = sender.split('@')[1];
  const body = overrides.body || '<html><style>fake css</style><body>Card Account Number Ending with: 9876<br>Transaction Date: 20/10<br>Merchant Name: EXAMPLE SHOP<br>Transaction Amount: HKD23.45<br>Any doubt call.</body></html>';
  return {
    id, threadId: 'one-thread-can-have-many-purchases', internalDate: String(new Date('2020-10-20T12:00:00+08:00').getTime()),
    payload: { mimeType: 'text/html', headers: [
      { name: 'From', value: 'Example <' + sender + '>' },
      { name: 'Subject', value: overrides.subject || '交易通知 (Transaction Notification)' },
      { name: 'Authentication-Results', value: overrides.auth || 'mx.google.com; dmarc=pass header.from=' + domain }
    ], body: { data: Buffer.from(body).toString('base64url') } }
  };
}

test('only exact authenticated bank transaction templates enter the feed', () => {
  const { context } = fixture();
  const valid = context.normalizeCardPilotMessage_(mail(), 'example-mailbox');
  assert.equal(valid.id, 'example-mailbox:invented-1');
  assert.match(valid.body, /EXAMPLE SHOP/);
  assert.doesNotMatch(valid.body, /fake css|Any doubt|<html>/);
  assert.equal(context.normalizeCardPilotMessage_(mail('spoof', { sender: 'istatement@bochk.com.attacker.example' }), 'example-mailbox'), null);
  assert.equal(context.normalizeCardPilotMessage_(mail('failed', { auth: 'mx.google.com; dmarc=fail header.from=bochk.com' }), 'example-mailbox'), null);
  assert.equal(context.normalizeCardPilotMessage_(mail('statement', { subject: 'BOC Credit Card e-Statement Alert' }), 'example-mailbox'), null);
  assert.equal(context.normalizeCardPilotMessage_(mail('transfer', { subject: '您的款項已發送給收款人' }), 'example-mailbox'), null);
  const forged = mail();
  forged.payload.headers[2].value = 'mx.google.com; dmarc=fail header.from=bochk.com';
  forged.payload.headers.push({ name: 'Authentication-Results', value: 'mx.google.com; dmarc=pass header.from=bochk.com' });
  assert.equal(context.normalizeCardPilotMessage_(forged, 'example-mailbox'), null);
});

test('BEA and HSBC keep observed fields without converting two messages in a thread into one', () => {
  const { context } = fixture();
  const bea = { sender: 'lcccaut@hkbea.com', subject: 'Contactless Payment Transaction Notification 非接觸式付款交易通知',
    body: 'your BEA Credit Card (last 4 digits 9876) has made a contactless payment transaction with HKD3.20 at EXAMPLE TRANSIT*on 2020/10/20. If in doubt' };
  const first = context.normalizeCardPilotMessage_(mail('bea-a', bea), 'example-mailbox');
  const second = context.normalizeCardPilotMessage_(mail('bea-b', bea), 'example-mailbox');
  assert.notEqual(first.id, second.id);
  assert.match(first.body, /EXAMPLE TRANSIT/);
  const hsbc = context.normalizeCardPilotMessage_(mail('hsbc-a', {
    sender: 'onlineservicesnotification@hsbc.com.hk',
    subject: 'Online Transaction has been made on your Debit Card 您的扣賬卡網上交易已完成',
    body: 'The online transaction has been successfully made on your HSBC Mastercard Debit Card number ending 9876.\nMerchant: EXAMPLE STORE Hong Kong HK\nTransaction currency and amount: HKD23.4\nTransaction date and time: 2020-10-20 20:11\nNeed more help?'
  }), 'example-mailbox');
  assert.match(hsbc.body, /2020-10-20 20:11/);
  assert.doesNotMatch(hsbc.body, /Need more help/);
});

test('real Apps Script decoded Byte arrays are not decoded again; REST Base64url remains supported', () => {
  const { context } = fixture();
  const raw = mail('advanced-byte-array', {
    body: 'Card Account Number Ending with: 9876\nTransaction Date: 20/10\nMerchant Name: EXAMPLE 香港\nTransaction Amount: HKD23.45'
  });
  const restData = raw.payload.body.data;
  const rest = context.normalizeCardPilotMessage_(raw, 'example-mailbox');
  const bytes = [...Buffer.from(restData, 'base64url')];
  raw.payload.body.data = bytes.map(value => value > 127 ? value - 256 : value);
  const advanced = context.normalizeCardPilotMessage_(raw, 'example-mailbox');
  assert.equal(advanced.body, rest.body);
  assert.match(advanced.body, /EXAMPLE 香港/);
  raw.payload.body.data = bytes;
  assert.equal(context.normalizeCardPilotMessage_(raw, 'example-mailbox').body, rest.body);
  for (const invalid of [[256], [-129], [1.1], ['1']]) {
    raw.payload.body.data = invalid;
    assert.throws(() => context.normalizeCardPilotMessage_(raw, 'example-mailbox'), /CARDPILOT_MIME_DATA_INVALID/);
  }
  raw.payload.body.data = new Array(1000001).fill(0);
  assert.throws(() => context.normalizeCardPilotMessage_(raw, 'example-mailbox'), /CARDPILOT_MAIL_TOO_LARGE/);
});

test('Gmail pagination and re-reading the same IDs are idempotent', () => {
  const f = fixture();
  f.rawByID.set('a', mail('a')); f.rawByID.set('b', mail('b'));
  f.setPages([{ messages: [{ id: 'a' }], nextPageToken: '1' }, { messages: [{ id: 'b' }, { id: 'a' }] }]);
  assert.equal(f.context.collectBankMail().accepted, 2);
  assert.equal(f.listCalls(), 2);
  assert.equal(f.archive().messages.length, 2);
  assert.ok(f.properties.get('CARDPILOT_SCAN_CURSOR'));
  assert.equal(f.context.collectBankMail().accepted, 0);
  assert.equal(f.archive().messages.length, 2);
});

test('private archive failures never advance the successful Gmail cursor', () => {
  const f = fixture();
  f.rawByID.set('a', mail('a')); f.setPages([{ messages: [{ id: 'a' }] }]);
  f.properties.set('CARDPILOT_SCAN_CURSOR', '1000');
  f.setFailUpload(true);
  assert.throws(() => f.context.collectBankMail(), /CARDPILOT_COLLECTION_FAILED/);
  assert.equal(f.properties.get('CARDPILOT_SCAN_CURSOR'), '1000');
  assert.equal(f.properties.get('CARDPILOT_ARCHIVE_FILE_ID'), undefined);
  assert.doesNotMatch(f.properties.get('CARDPILOT_LAST_RESULT'), /secret|EXAMPLE SHOP/);
  f.setFailUpload(false);
  assert.equal(f.context.collectBankMail().accepted, 1);
});

test('partial bounded collections retain backlog instead of skipping older messages', () => {
  const f = fixture();
  const ids = Array.from({ length: 501 }, (_, i) => 'm' + i);
  ids.forEach(id => f.rawByID.set(id, mail(id)));
  f.setPages([{ messages: ids.map(id => ({ id })) }]);
  const first = f.context.collectBankMail();
  assert.equal(first.accepted, 500); assert.equal(first.complete, false);
  assert.equal(f.properties.get('CARDPILOT_SCAN_CURSOR'), undefined);
  assert.equal(f.context.collectBankMail().accepted, 1);
  assert.equal(f.archive().messages.length, 501);
  assert.ok(f.properties.get('CARDPILOT_SCAN_CURSOR'));
});

test('authenticated append cursors preserve later arrivals and bound pages', () => {
  const f = fixture();
  const archive = { mailboxID: 'example-mailbox', messages: Array.from({ length: 501 }, (_, i) => ({ id: 'invented-' + i })) };
  const first = f.context.cardPilotPage_(archive);
  assert.equal(first.messages.length, 500);
  const second = f.context.cardPilotPage_(archive, first.nextCursor);
  assert.equal(second.messages.length, 1);
  assert.equal(f.context.cardPilotPage_(archive, second.nextCursor).nextCursor, null);
  archive.messages.push({ id: 'late-arrival-with-older-bank-date' });
  assert.equal(f.context.cardPilotPage_(archive, second.nextCursor).messages[0].id, 'late-arrival-with-older-bank-date');
  assert.throws(() => f.context.cardPilotPage_(archive, 'other-mailbox:500'), /INVALID_CURSOR/);
  assert.equal(JSON.parse(f.context.doGet().text).error, 'POST_REQUIRED');
  assert.equal(JSON.parse(f.context.doPost({ postData: { contents: JSON.stringify({ token: 'wrong' }) } }).text).error, 'UNAUTHORIZED');
  assert.equal(f.uploads(), 0);
});

test('rejected envelope identities are remembered without retaining their bodies', () => {
  const f = fixture();
  f.rawByID.set('marketing', mail('marketing', { subject: 'Promotion' }));
  f.setPages([{ messages: [{ id: 'marketing' }] }]);
  assert.equal(f.context.collectBankMail().accepted, 0);
  assert.equal(f.archive().messages.length, 0);
  f.setFailGet(true);
  assert.doesNotThrow(() => f.context.collectBankMail());
  assert.doesNotMatch(JSON.stringify(f.archive()), /EXAMPLE SHOP/);
});

test('an authenticated supported message with a missing body is not silently acknowledged', () => {
  const f = fixture();
  const broken = mail('broken-template');
  broken.payload.body = {};
  f.rawByID.set('broken-template', broken);
  f.setPages([{ messages: [{ id: 'broken-template' }] }]);
  f.properties.set('CARDPILOT_SCAN_CURSOR', '1000');
  assert.throws(() => f.context.collectBankMail(), /CARDPILOT_COLLECTION_FAILED/);
  assert.equal(f.properties.get('CARDPILOT_SCAN_CURSOR'), '1000');
  assert.equal(f.uploads(), 0);
});
