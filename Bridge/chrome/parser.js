/* Pure parsing shared by the content adapter and deterministic local tests. */
(function (root) {
  const validURL = value => {
    try { const url = new URL(value); return url.protocol === 'https:' && url.hostname === 'claude.ai' && !url.username && !url.password && (!url.port || url.port === '443'); }
    catch { return false; }
  };
  const usageLocation = value => {
    if (!validURL(value)) return false;
    const url = new URL(value);
    return /^\/settings\/usage\/?$/.test(url.pathname) || url.hash === '#settings/usage';
  };
  function accountEmail(menuText) {
    if (typeof menuText !== 'string' || menuText.length > 10000) return null;
    const values = [...new Set((menuText.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi) || []).map(email => email.toLowerCase()))];
    return values.length === 1 ? values[0] : null;
  }
  function messagesFromNodes(nodes) {
    return nodes.filter(node => ['assistant', 'user'].includes(node.author) && typeof node.text === 'string' && node.text.trim())
      .map((node, index) => ({ ordinal: index + 1, author: node.author, text: node.text, segment: Number.isInteger(node.segment) ? node.segment : 0, completed: node.completed === true, visible: node.visible === true }));
  }
  function usageFromLines(lines) {
    const rate_limits = {}; let window = null; let pendingReset = {};
    for (const raw of lines) {
      const line = raw.toLowerCase().trim();
      let nextWindow = window;
      if (['limit resets', 'usage credits', 'extra usage', '额度重置'].includes(line) || line.includes('usage by product')) nextWindow = null;
      else if (['current session', '当前会话', '本次会话', '5 小时', '5小时'].some(label => line.includes(label))) nextWindow = 'five_hour';
      else if (['this week', '本周'].includes(line) || ['all models', 'weekly limits', '所有模型', '每周'].some(label => line.includes(label))) nextWindow = 'seven_day';
      else if (line.includes('sonnet') || line.includes('opus')) nextWindow = null;
      if (nextWindow !== window) { window = nextWindow; pendingReset = {}; }
      if (window && /^(?:resets)\b|重置/i.test(raw.trim())) {
        const iso = raw.match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:[\d.Z+-]+/);
        pendingReset = iso && Number.isFinite(Date.parse(iso[0]))
          ? { resets_at: Date.parse(iso[0]) / 1000 } : { reset_description: raw.slice(0, 160) };
        if (rate_limits[window]) Object.assign(rate_limits[window], pendingReset);
        continue;
      }
      const match = raw.match(/([0-9]+(?:\.[0-9]+)?)\s*%\s*(?:used|已用|已使用)/i);
      if (window && match) {
        const used = Number(match[1]);
        if (used >= 0 && used <= 100 && !rate_limits[window]) rate_limits[window] = { used_percentage: used, ...pendingReset };
      }
    }
    return { rate_limits };
  }
  const api = { validURL, messagesFromNodes, usageFromLines, usageLocation, accountEmail };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.AChuParser = api;
})(globalThis);
