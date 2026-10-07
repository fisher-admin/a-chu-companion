const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { chromium } = require(process.env.ACHU_PLAYWRIGHT_MODULE || 'playwright');
(async () => {
  const browser = await chromium.launch({headless:true, executablePath: process.env.ACHU_CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  try {
    const context = await browser.newContext();
    let intercepted = 0;
    await context.route('**/*', async route => {
      intercepted++;
      const url=new URL(route.request().url());
      if(url.pathname==='/api/account'){
        await new Promise(resolve=>setTimeout(resolve,400));
        return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({email_address:'synthetic@example.test',memberships:[{organization:{uuid:'11111111-1111-4111-8111-111111111111'}}]})});
      }
      if(url.pathname.endsWith('/usage'))return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({five_hour:{utilization:12},seven_day:{utilization:34}})});
      return route.fulfill({status:200, contentType:'text/html', body: '<!DOCTYPE html><meta charset="utf-8"><article data-testid="assistant-message"><p>First formal paragraph.</p><pre><code class="language-javascript">let preserved = "😀";</code></pre><div data-testid="tool-output">RUNNING_TOOL_NOT_BODY</div><button aria-label="Copy">TOOLTIP_NOT_BODY</button></article>'});
    });
    const page = await context.newPage();
    await page.goto('https://claude.ai/chat/synthetic-intercepted-fixture');
    await page.evaluate(() => { globalThis.captured = []; globalThis.chrome = {runtime:{onMessage:{addListener(callback){globalThis.bridgeListener=callback;}},sendMessage(value){captured.push(value);return Promise.resolve({});}}}; });
    await page.addScriptTag({path:path.resolve('Bridge/chrome/parser.js')});
    await page.addScriptTag({path:path.resolve('Bridge/chrome/usage.js')});
    await page.addScriptTag({path:path.resolve('Bridge/chrome/content.js')});
    assert.equal(await page.evaluate(() => captured.filter(value=>value.kind).length), 0, 'adapter must remain opt-in');
    await page.evaluate(() => bridgeListener({type:'achu-enable'}));
    const value = await page.evaluate(() => captured.find(value=>value.kind==='snapshot'));
    assert.equal(await page.evaluate(()=>captured.filter(v=>v.kind==='usage').length),0,'reply capture must not await slow quota networking');
    assert.equal(value.messages.length, 1);
    assert.ok(value.messages[0].text.includes('```javascript\nlet preserved = "😀";\n```'), 'code block structure must be preserved');
    assert.ok(!value.messages[0].text.includes('RUNNING_TOOL_NOT_BODY') && !value.messages[0].text.includes('TOOLTIP_NOT_BODY'));
    await page.waitForFunction(()=>captured.some(v=>v.kind==='usage'&&v.account&&v.usage.rate_limits.five_hour?.used_percentage===12));
    assert.ok(!JSON.stringify(await page.evaluate(()=>captured)).includes('synthetic@example.test'));
    await page.evaluate(() => document.querySelector('p').textContent = 'Updated formal paragraph.');
    await page.waitForFunction(() => captured.some(value=>value.messages?.[0]?.text.includes('Updated formal paragraph.')));
    const previousEpoch = await page.evaluate(() => captured.find(value=>value.kind==='snapshot').epoch);
    await page.evaluate(() => { history.pushState({}, '', '/chat/second-synthetic'); bridgeListener({type:'achu-resync'}); });
    const navigated = await page.evaluate(() => captured.filter(value=>value.kind==='snapshot').at(-1));
    assert.notEqual(navigated.epoch, previousEpoch); assert.equal(navigated.sequence,0);
    await page.evaluate(() => { document.body.style.height='2500px'; document.querySelector('article').style.marginTop='1800px'; bridgeListener({type:'achu-resync'}); });
    assert.equal(await page.evaluate(() => captured.filter(value=>value.kind==='snapshot').at(-1).messages[0].visible), false);
    const beforeStop = await page.evaluate(() => captured.length);
    await page.evaluate(() => { bridgeListener({type:'achu-disable'}); document.querySelector('p').textContent = 'Disabled change'; });
    await page.waitForTimeout(300);
    assert.equal(await page.evaluate(() => captured.length), beforeStop);
    await page.evaluate(() => { document.body.style.height='auto'; document.body.style.padding='24px'; document.querySelector('article').style.marginTop='0'; });
    fs.mkdirSync('output/playwright', {recursive:true});
    await page.screenshot({path:'output/playwright/bridge-synthetic.png'});
    assert.ok(intercepted >= 1, 'every page and account request was intercepted; no real Claude request');
    console.log('PASS: isolated browser DOM, opt-in, code, tool filtering, updates, navigation, viewport history and stop; all network intercepted');
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode=1; });
