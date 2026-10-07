/* Opt-in, top-frame only. No reading Cookie/OAuth, debugger, or page navigation. */
(() => {
  if (typeof chrome === 'undefined' || !chrome.runtime || window !== window.top) return;
  let enabled = false, epoch = crypto.randomUUID(), sequence = 0, lastURL = '', lastSnapshot = '', lastSent = 0, timer;
  let captureBusy = false, usageEpoch = crypto.randomUUID(), usageSequence = 0, lastAccountKey, lastUsage = '', lastUsageSent = 0;
  let forceUsage = true, lastUsageAttempt = 0, activation = 0, usageBusy = false, lastCompletedUsage = '';
  const cleanURL = () => { const url = new URL(location.href); url.search = ''; url.hash = ''; return url.href; };
  function plainText(element) {
    const copy = element.cloneNode(true);
    copy.querySelectorAll('button, [role="button"], [data-testid*="tool"], [aria-label="Tool output"], [data-is-thinking="true"]').forEach(node => node.remove());
    function render(node) {
      if (node.nodeType === Node.TEXT_NODE) return node.textContent;
      if (node.nodeType !== Node.ELEMENT_NODE) return '';
      if (node.tagName === 'PRE') {
        const code = node.querySelector('code');
        const text = (code || node).textContent;
        const fence = '`'.repeat(Math.max(3, ...[...text.matchAll(/`+/g)].map(match => match[0].length + 1)));
        const language = code?.className.match(/language-([a-zA-Z0-9_-]+)/)?.[1] || '';
        return '\n\n' + fence + language + '\n' + text + (text.endsWith('\n') ? '' : '\n') + fence + '\n\n';
      }
      if (node.tagName === 'CODE') {
        const text = node.textContent;
        const fence = '`'.repeat(Math.max(1, ...[...text.matchAll(/`+/g)].map(match => match[0].length + 1)));
        return fence + text + fence;
      }
      if (node.tagName === 'BR') return '\n';
      const text = [...node.childNodes].map(render).join('');
      if (['P','DIV','SECTION','UL','OL','BLOCKQUOTE','H1','H2','H3','H4','TABLE','TR'].includes(node.tagName)) return text + '\n\n';
      if (node.tagName === 'LI') return '- ' + text + '\n';
      return text;
    }
    return render(copy).trim();
  }
  async function usageCapture(url) {
    if (usageBusy || (!forceUsage && Date.now() - lastUsageAttempt < 60000)) return;
    usageBusy = true;
    try {
    forceUsage = false; lastUsageAttempt = Date.now();
    const startedActivation = activation;
    let account, usage = {rate_limits:{}};
    try { const result = await AChuUsage.read(fetch.bind(window), crypto); account = result.account; usage = result.usage; }
    catch { /* Missing identity, quota, request failure and account changes all clear old values. */ }
    if (!enabled || activation !== startedActivation || cleanURL() !== url) return;
    const key = account?.fingerprint || 'unverified';
    if (key !== lastAccountKey) { lastAccountKey = key; usageEpoch = crypto.randomUUID(); usageSequence = 0; lastUsage = ''; }
    const signature = JSON.stringify({usage, account});
    if (signature === lastUsage && Date.now() - lastUsageSent < 5000) return;
    lastUsage = signature; lastUsageSent = Date.now();
    chrome.runtime.sendMessage({type:'achu-observation', kind:'usage', epoch:usageEpoch, sequence:usageSequence++, url, usage, account}).catch(() => {});
    } finally { usageBusy = false; }
  }
  async function capture() {
    if (captureBusy) return;
    captureBusy = true;
    try { await captureCurrent(); } finally { captureBusy = false; }
  }
  async function captureCurrent() {
    if (!enabled || !AChuParser.validURL(location.href)) return;
    const url = cleanURL();
    if (lastURL !== url) { lastURL = url; epoch = crypto.randomUUID(); sequence = 0; lastSnapshot = ''; }
    void usageCapture(url);
    if (!enabled || cleanURL() !== url || AChuParser.usageLocation(location.href)) return;
    const nodes = [...document.querySelectorAll('[data-message-author-role], [data-testid="assistant-message"], [data-testid="user-message"]')]
      .filter(node => !node.parentElement?.closest('[data-message-author-role], [data-testid="assistant-message"], [data-testid="user-message"]'));
    const generating = Boolean(document.querySelector('button[aria-label="Stop response"], button[aria-label="Stop generating"], button[aria-label="停止回复"]'));
    const messages = AChuParser.messagesFromNodes(nodes.map(node => ({
      author: node.getAttribute('data-message-author-role') || (node.getAttribute('data-testid') === 'assistant-message' ? 'assistant' : 'user'),
      text: plainText(node),
      segment: Number(node.getAttribute('data-segment') || '0'),
      visible: (() => { const r = node.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight; })(),
      completed: node.getAttribute('data-is-streaming') === 'false' || (!generating && Boolean(node.querySelector('button[aria-label="Copy"], button[aria-label="Copy response"], button[aria-label="复制"]')))
    }))).slice(-16);
    const snapshot = JSON.stringify(messages);
    const completedSignature = JSON.stringify(messages.filter(m => m.author === 'assistant' && m.completed).map(m => [m.ordinal, m.segment, m.text]));
    if (completedSignature !== lastCompletedUsage) {
      lastCompletedUsage = completedSignature;
      if (completedSignature !== '[]') forceUsage = true;
    }
    if (snapshot === lastSnapshot && Date.now() - lastSent < 5000) return;
    lastSnapshot = snapshot; lastSent = Date.now();
    chrome.runtime.sendMessage({ type: 'achu-observation', kind: 'snapshot', epoch, sequence: sequence++, url, messages, final: !generating && messages.length > 0 && messages.at(-1).completed });
  }
  const schedule = () => { clearTimeout(timer); timer = setTimeout(capture, 150); };
  chrome.runtime.onMessage.addListener(message => {
    if (message.type === 'achu-enable' || message.type === 'achu-resync') { activation++; enabled = true; lastSnapshot = ''; forceUsage = true; capture(); }
    if (message.type === 'achu-usage-refresh' && enabled) { forceUsage = true; capture(); }
    if (message.type === 'achu-disable') { activation++; enabled = false; clearTimeout(timer); }
  });
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['data-is-streaming'] });
  setInterval(() => { if (enabled) capture(); }, 1000);
  addEventListener('scroll', schedule, {capture: true, passive: true});
  chrome.runtime.sendMessage({type:'achu-ready'}).catch(() => {});
})();
