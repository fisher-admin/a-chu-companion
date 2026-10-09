importScripts('parser.js');
// Session storage survives worker suspension, but never enables a page by default.
const enabledTabs = new Set();
const restored = chrome.storage.session.get('achuTabs').then(value => {
  for (const id of value.achuTabs || []) if (Number.isInteger(id)) enabledTabs.add(id);
});
const persist = () => chrome.storage.session.set({achuTabs:[...enabledTabs]});
let port = null;
const usageRequests = new Map();
function connect() {
  if (port) return port;
  const next = chrome.runtime.connectNative('local.achu.companion'); port = next;
  next.onDisconnect.addListener(() => {
    if (port === next) port = null;
    for (const id of enabledTabs) chrome.action.setBadgeText({tabId:id,text:'!'});
  });
  next.onMessage.addListener(message => {
    if (message.ok === true && typeof message.requestUsage === 'string' && /^[A-Fa-f0-9-]{36}$/.test(message.requestUsage) && /^web-[0-9]+$/.test(message.binding || '')) {
      const id = Number(message.binding.slice(4));
      if (enabledTabs.has(id) && usageRequests.get(id) !== message.requestUsage) {
        usageRequests.set(id, message.requestUsage);
        void chrome.tabs.sendMessage(id, {type:'achu-usage-refresh'}).catch(() => {});
      }
    }
    for (const id of enabledTabs) chrome.action.setBadgeText({tabId:id,text:message.ok === true ? 'ON' : '?'});
  });
  return next;
}
chrome.action.onClicked.addListener(async tab => {
  await restored;
  if (!tab.id || !AChuParser.validURL(tab.url || '')) return;
  const wasEnabled = enabledTabs.has(tab.id);
  if (wasEnabled) enabledTabs.delete(tab.id); else enabledTabs.add(tab.id);
  if (!wasEnabled) connect();
  await persist();
  try { await chrome.tabs.sendMessage(tab.id, {type:wasEnabled ? 'achu-disable' : 'achu-enable'}); }
  catch { enabledTabs.delete(tab.id); await persist(); }
  chrome.action.setBadgeText({tabId:tab.id,text:enabledTabs.has(tab.id) ? 'ON' : ''});
});
chrome.runtime.onMessage.addListener((message, sender) => {
  void restored.then(async () => {
    if (sender.id !== chrome.runtime.id || !sender.tab?.id || sender.frameId !== 0 || !enabledTabs.has(sender.tab.id) || !AChuParser.validURL(sender.url || '')) return;
    if (message.type === 'achu-ready') {
      await chrome.tabs.sendMessage(sender.tab.id,{type:'achu-enable'}).catch(() => {}); return;
    }
    if (message.type !== 'achu-observation' || !['snapshot','usage'].includes(message.kind) || !AChuParser.validURL(message.url)) return;
    const url = new URL(sender.url); url.search = ''; url.hash = '';
    if (url.href !== message.url) return;
    const value = {version:1,kind:message.kind,binding:`web-${sender.tab.id}`,epoch:message.epoch,sequence:message.sequence,url:url.href};
    if (message.kind === 'snapshot') { value.messages = message.messages; value.final = message.final; }
    else {
      value.usage = message.usage;
      const account = message.account;
      if (account && /^[a-f0-9]{64}$/.test(account.fingerprint) && typeof account.displayName === 'string' && account.displayName.length <= 80) {
        value.account = {fingerprint:account.fingerprint, displayName:account.displayName};
      }
    }
    try { connect().postMessage(value); } catch { port = null; chrome.action.setBadgeText({tabId:sender.tab.id,text:'!'}); }
  });
});
chrome.tabs.onRemoved.addListener(id => { enabledTabs.delete(id); usageRequests.delete(id); void persist(); });
