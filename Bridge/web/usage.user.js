// ==UserScript==
// @name         A畜伴侣 · 网页额度连接
// @namespace    local.achu.companion
// @version      1.1.8.77
// @description  仅将 Claude 当前账户的遮蔽身份和订阅额度传给本机伴侣。
// @match        https://claude.ai/*
// @connect      127.0.0.1
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_getTab
// @grant        GM_saveTab
// @grant        GM_xmlhttpRequest
// @sandbox      DOM
// @noframes
// @run-at       document-idle
// @updateURL    http://127.0.0.1:__PORT__/module/usage.user.js
// @downloadURL  http://127.0.0.1:__PORT__/module/usage.user.js
// ==/UserScript==

(function () {
  'use strict';
  /*__USAGE_READER__*/
  const endpoint = 'http://127.0.0.1:__PORT__';
  const capability = '__CAPABILITY__';

  function createClient(runtime) {
    const {crypto, document, location} = runtime;
    const hex = bytes => [...bytes].map(n => n.toString(16).padStart(2, '0')).join('');
    const random = length => hex(crypto.getRandomValues(new Uint8Array(length)));
    let installID, installKey, tabID, epoch = '', sequence = 0, running = false;
    let challenge = '', bound = false, readBusy = false, readAgain = false, lastRead = 0;
    const documentID = random(16);
    const api = {
      async initialize() {
        installID = runtime.getValue('installID');
        installKey = runtime.getValue('installKey');
        if (!/^[a-f0-9]{32}$/.test(installID || '') || !/^[a-f0-9]{64}$/.test(installKey || '')) {
          installID = random(16); installKey = random(32);
          runtime.setValue('installID', installID); runtime.setValue('installKey', installKey);
        }
        if (!tabID) {
          const tab = await new Promise(resolve => runtime.getTab(resolve));
          tabID = /^[a-f0-9]{32}$/.test(tab.achuTab || '') ? tab.achuTab : random(16);
          runtime.saveTab({...tab, achuTab: tabID});
        }
      },
      packet(extra = {}) {
        const url = new URL(location.href); url.search = ''; url.hash = '';
        return {installID, tabID, documentID, url: url.href, focused: document.hasFocus(),
          visible: document.visibilityState === 'visible', epoch, sequence: ++sequence, ...extra};
      },
      async send(path, body, bootstrap = false) {
        const data = JSON.stringify(body), headers = {'Content-Type': 'application/json'};
        if (bootstrap) headers['X-AChu-Capability'] = capability;
        else {
          const keyBytes = new Uint8Array(installKey.match(/../g).map(n => parseInt(n, 16)));
          const key = await crypto.subtle.importKey('raw', keyBytes, {name: 'HMAC', hash: 'SHA-256'}, false, ['sign']);
          headers['X-AChu-Signature'] = hex(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(path + '\n' + data))));
        }
        return await new Promise((resolve, reject) => runtime.request({
          method: 'POST', url: endpoint + path, headers, data, timeout: 2000, anonymous: true,
          onload(response) {
            try {
              if (response.status < 200 || response.status >= 300) throw Error('transport-' + response.status);
              resolve(JSON.parse(response.responseText));
            } catch (error) { reject(error); }
          },
          ontimeout: () => reject(Error('transport-timeout')), onerror: () => reject(Error('transport-unavailable'))
        }));
      },
      async readQuota() {
        if (readBusy) { readAgain = true; return; }
        readBusy = true;
        const generation = epoch;
        try {
          const result = await globalThis.AChuUsage.read(runtime.fetch, crypto);
          if (generation === epoch) await api.send('/report', api.packet({status: 'ok', ...result}));
        } catch (error) {
          const status = error.message === 'account-changed' ? 'account-changed' : 'unavailable';
          if (generation === epoch) {
            try { await api.send('/report', api.packet({status})); } catch (_) { /* Next heartbeat retries. */ }
          }
        } finally {
          lastRead = Date.now(); readBusy = false;
          if (readAgain && bound) { readAgain = false; void api.readQuota(); }
        }
      },
      async step() {
        if (running) return;
        running = true;
        try {
          if (!epoch) {
            let hello;
            try { hello = await api.send('/hello', api.packet()); }
            catch (error) {
              if (!capability || !error.message.startsWith('transport-403')) throw error;
              hello = await api.send('/hello', api.packet(), true);
              epoch = hello.epoch;
              if (hello.challenge && document.hasFocus() && document.visibilityState === 'visible') {
                await api.send('/pair', api.packet({key: installKey, challenge: hello.challenge}), true);
              }
              // A candidate is not authorized until the companion closes its
              // uniqueness window. Retry without retaining an untrusted epoch.
              epoch = ''; return;
            }
            epoch = hello.epoch;
          }
          const response = await api.send('/poll', api.packet(challenge ? {challenge} : {}));
          challenge = response.challenge || ''; bound = response.bound === true;
          if (challenge && document.hasFocus() && document.visibilityState === 'visible') {
            const answer = await api.send('/poll', api.packet({challenge}));
            bound = answer.bound === true;
            if (answer.read) void api.readQuota();
          }
          if (bound && (response.read || Date.now() - lastRead >= 30000)) void api.readQuota();
        } catch (_) {
          epoch = ''; bound = false; challenge = '';
        } finally { running = false; }
      },
      async start() {
        await api.initialize();
        async function loop() {
          await api.step();
          setTimeout(loop, document.hasFocus() && document.visibilityState === 'visible' ? 100 : 1000);
        }
        void loop();
      }
    };
    return api;
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {createClient};
  else {
    const client = createClient({crypto, document, location, fetch: fetch.bind(globalThis),
      getValue: GM_getValue, setValue: GM_setValue, getTab: GM_getTab, saveTab: GM_saveTab, request: GM_xmlhttpRequest});
    void client.start();
  }
})();
