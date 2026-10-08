// Actual service process + actual HTTP + production script client, synthetic Claude only.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {webcrypto} = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const readline = require('node:readline');
const http = require('node:http');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const root = path.join(__dirname, '..');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'achu-web-simulation-'));
const events = [];
const child = spawn('/usr/bin/python3', [path.join(root, 'Bridge/web/service.py'), '--state-dir', directory, '--resources', path.join(root, 'Bridge')], {stdio: ['pipe', 'pipe', 'pipe']});
readline.createInterface({input: child.stdout}).on('line', line => events.push(JSON.parse(line)));
let stderr = ''; child.stderr.on('data', data => stderr += data.toString());
const command = value => child.stdin.write(JSON.stringify(value) + '\n');
async function waitFor(predicate) {
  for (let i = 0; i < 100; i++) { if (predicate()) return; await delay(20); }
  throw Error('Timed out: ' + stderr);
}
async function run() {
  await waitFor(() => events.some(e => e.kind === 'ready'));
  command({kind: 'setup', browser: 'com.google.Chrome'});
  await waitFor(() => events.some(e => e.kind === 'install'));
  const installURL = events.find(e => e.kind === 'install').url;
  const script = await new Promise((resolve, reject) => http.get(installURL, response => {
    let data = ''; response.on('data', part => data += part); response.on('end', () => resolve(data));
  }).on('error', reject));
  const url = new URL('https://claude.ai/chat/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  const store = new Map();
  let email = 'first@example.test', accountVersion = 0;
  const context = {module: {exports: {}}, URL, TextEncoder, Uint8Array, AbortSignal, crypto: webcrypto};
  vm.createContext(context); vm.runInContext(script, context);
  const runtime = {
    crypto: webcrypto, document: {hasFocus: () => true, visibilityState: 'visible'}, location: url,
    getValue: key => store.get(key), setValue: (key, value) => store.set(key, value),
    getTab: callback => callback(store.get('tab') || {}), saveTab: value => store.set('tab', value),
    fetch: async route => {
      const value = route === '/api/account' ? {email_address: email, memberships: [{organization: {uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'}}]} : {five_hour: {utilization: 10 + accountVersion}, seven_day: {utilization: 30}};
      return {ok: true, headers: {get: () => 'application/json'}, text: async () => JSON.stringify(value)};
    },
    request(options) {
      const request = http.request(options.url, {method: options.method, headers: options.headers}, response => {
        let data = ''; response.on('data', part => data += part);
        response.on('end', () => options.onload({status: response.statusCode, responseText: data}));
      });
      request.on('error', options.onerror); request.setTimeout(2000, () => {request.destroy(); options.ontimeout();});
      request.end(options.data);
    }
  };
  const client = context.module.exports.createClient(runtime);
  await client.initialize();
  command({kind: 'bind', url: url.href, browser: 'com.google.Chrome'});
  for (let i = 0; i < 12; i++) {await client.step(); await delay(80);}
  await waitFor(() => events.some(e => e.kind === 'usage'));
  const first = events.find(e => e.kind === 'usage');
  assert.equal(first.account.displayName, 'f***@example.test');
  assert.equal(first.usage.rate_limits.five_hour.used_percentage, 10);
  assert.ok(!JSON.stringify(events).includes('first@example.test'));
  email = 'second@example.test'; accountVersion = 1;
  command({kind: 'read'}); await delay(30); await client.step();
  await waitFor(() => events.filter(e => e.kind === 'usage').length === 2);
  const second = events.filter(e => e.kind === 'usage')[1];
  assert.notEqual(first.account.fingerprint, second.account.fingerprint);
  assert.equal(second.usage.rate_limits.five_hour.used_percentage, 11);
  const refreshed = context.module.exports.createClient(runtime);
  await refreshed.initialize(); await refreshed.step();
  command({kind: 'read'}); await delay(30); await refreshed.step();
  await waitFor(() => events.filter(e => e.kind === 'usage').length >= 3);
  command({kind: 'revoke'});
  await waitFor(() => events.some(e => e.kind === 'disconnected' && e.reason === 'revoked'));
  console.log('ManagedWebIntegration: actual process, pairing, quota, account switch, refresh and revoke passed');
}
run().catch(error => {console.error(error); process.exitCode = 1;}).finally(async () => {
  child.stdin.end(); await delay(700); if (!child.killed && child.exitCode === null) child.kill();
  fs.rmSync(directory, {recursive: true, force: true});
});
