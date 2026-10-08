const assert = require('node:assert/strict');
const {webcrypto} = require('node:crypto');
const path = require('node:path');
const fs = require('node:fs');
const vm = require('node:vm');
const template = fs.readFileSync(path.join(__dirname, '../Bridge/web/usage.user.js'), 'utf8');
const library = fs.readFileSync(path.join(__dirname, '../Bridge/chrome/usage.js'), 'utf8');
let count = 0;
async function run() {
  const store = new Map(), requests = [], endpoints = [];
  const document = {hasFocus: () => true, visibilityState: 'visible'};
  const location = new URL('https://claude.ai/chat/test');
  let email = 'alpha@example.test', readCount = 0, accountSwitch = false;
  const context = {
    module: {exports: {}}, TextEncoder, Uint8Array, URL, AbortSignal, crypto: webcrypto,
    fetch: async (url, options) => {
      endpoints.push({url, options});
      const value = url === '/api/account' ? {email_address: (accountSwitch && ++readCount % 2 === 0) ? 'other@example.test' : email,
        memberships: [{organization: {uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'}}]} : {five_hour: {utilization: 7, resets_at: '2030-01-01T00:00:00Z'}, seven_day: {utilization: 23}};
      return {ok: true, headers: {get: () => 'application/json'}, text: async () => JSON.stringify(value)};
    }
  };
  vm.createContext(context);
  vm.runInContext(template.replaceAll('__PORT__', '12345').replace('__CAPABILITY__', 'bootstrap').replace('/*__USAGE_READER__*/', library), context);
  const client = context.module.exports.createClient({
    crypto: webcrypto, document, location, fetch: context.fetch,
    getValue: (key) => store.get(key), setValue: (key, value) => store.set(key, value),
    getTab: (callback) => callback({}), saveTab: (value) => store.set('tab', value),
    request: (options) => {
      requests.push(options);
      options.onload({status: 200, responseText: JSON.stringify({epoch: 'current-app', bound: false, read: false})});
    }
  });
  await client.initialize();
  assert.match(store.get('installKey'), /^[a-f0-9]{64}$/); count++;
  assert.match(store.get('installID'), /^[a-f0-9]{32}$/); count++;
  const identity = store.get('installID');
  await client.initialize();
  assert.equal(store.get('installID'), identity); count++;
  await client.step();
  assert.ok(requests.every(r => !r.headers.Cookie && !r.cookie)); count++;
  assert.ok(requests.some(r => r.headers['X-AChu-Signature'])); count++;
  requests.length = 0;
  await client.readQuota();
  const report = requests.find(r => r.url.endsWith('/report'));
  const body = JSON.parse(report.data);
  assert.equal(body.status, 'ok'); count++;
  assert.equal(body.account.displayName, 'a***@example.test'); count++;
  assert.equal(body.usage.rate_limits.five_hour.used_percentage, 7); count++;
  assert.ok(!report.data.includes(email)); count++;
  assert.ok(!Object.keys(body).some(k => /cookie|session|text|message/i.test(k))); count++;
  assert.ok(endpoints.every(e => e.options.credentials === 'same-origin')); count++;
  accountSwitch = true; readCount = 0; requests.length = 0;
  await client.readQuota();
  const failed = JSON.parse(requests.find(r => r.url.endsWith('/report')).data);
  assert.equal(failed.status, 'account-changed'); count++;
  assert.ok(!failed.account && !failed.usage); count++;
  document.hasFocus = () => false;
  assert.equal(client.packet().focused, false); count++;
  console.log(`ManagedWebModule: ${count} checks passed`);
}
run().catch(error => {console.error(error); process.exitCode = 1;});
