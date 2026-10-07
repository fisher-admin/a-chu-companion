const test = require('node:test');
const assert = require('node:assert/strict');
const { validURL, messagesFromNodes, usageFromLines } = require('../Bridge/chrome/parser.js');
test('only Claude HTTPS pages are admitted', () => {
  assert.equal(validURL('https://claude.ai/chat/test'), true);
  for (const url of ['https://evil.example', 'https://claude.ai.evil.example', 'http://claude.ai/chat/test', 'https://user@claude.ai/chat/test']) assert.equal(validURL(url), false);
});
test('formal messages retain code, exclude tool states and do not invent completion', () => {
  const nodes = [{text:'Formal first\n```js\nlet x=1;\n```',author:'assistant',completed:false}, {text:'Running tool',author:'tool'}, {text:'user prompt',author:'user'}];
  const result = messagesFromNodes(nodes);
  assert.equal(result.length, 2);
  assert.equal(result[0].text, nodes[0].text);
  assert.equal(result[0].completed, false);
});
test('usage includes independent known windows and ignores remaining/spend', () => {
  const usage = usageFromLines(['Current session','12% used','All models','34% used']);
  assert.equal(usage.rate_limits.five_hour.used_percentage, 12);
  assert.equal(usage.rate_limits.seven_day.used_percentage, 34);
  assert.deepEqual(usageFromLines(['Current session','12% remaining']).rate_limits, {});
});
test('current Usage headings retain resets before percentages and stop at product shares', () => {
  const usage = usageFromLines(['Current session','Resets at 5:00 AM','12% used',
    'This week','Resets Friday 2:00 PM','34% used','Limit resets',
    'Full reset','5-hour reset','This week’s usage by product','Claude Code','15% used']);
  assert.deepEqual(usage.rate_limits, {
    five_hour: {used_percentage:12, reset_description:'Resets at 5:00 AM'},
    seven_day: {used_percentage:34, reset_description:'Resets Friday 2:00 PM'}
  });
  assert.deepEqual(usageFromLines(['This week’s usage by product','Claude Code','15% used']).rate_limits, {});
});

test('quota location follows current Settings route and identity requires one unique menu email', () => {
  assert.equal(typeof require('../Bridge/chrome/parser.js').usageLocation, 'function');
  const { usageLocation, accountEmail } = require('../Bridge/chrome/parser.js');
  assert.equal(usageLocation('https://claude.ai/new#settings/usage'), true);
  assert.equal(usageLocation('https://claude.ai/settings/usage'), true);
  assert.equal(usageLocation('https://evil.example/new#settings/usage'), false);
  assert.equal(usageLocation('https://claude.ai/new#settings/account'), false);
  assert.equal(accountEmail('Account FIRST@example.test Settings Log out'), 'first@example.test');
  assert.equal(accountEmail('Fisher Pro Settings Log out'), null);
  assert.equal(accountEmail('first@example.test second@example.test'), null);
});
