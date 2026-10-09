const test = require('node:test'); const assert = require('node:assert/strict');
const vm = require('node:vm'); const fs = require('node:fs'); const parser = require('../Bridge/chrome/parser.js');
function worker(saved=[]) {
  const listeners = {}, packets=[], badges=[], messages=[];
  const event = key => ({addListener(fn){listeners[key]=fn;}});
  const port = {onMessage:event('nativeMessage'),onDisconnect:event('disconnect'),postMessage(value){packets.push(value);}};
  const chrome = {runtime:{id:'ours',onMessage:event('message'),connectNative:()=>port}, storage:{session:{get:async()=>({achuTabs:saved}),set:async()=>{}}}, action:{onClicked:event('click'),setBadgeText:value=>badges.push(value)},tabs:{sendMessage:async(id,value)=>messages.push(value),onRemoved:event('remove')}};
  vm.runInNewContext(fs.readFileSync('Bridge/chrome/background.js','utf8'),{chrome,URL,AChuParser:parser,importScripts:()=>{}});
  return {listeners,packets,badges,messages};
}
const settle = ()=>new Promise(resolve=>setImmediate(resolve));
test('worker remains opt-in and rejects hostile or non-top-frame senders',async()=>{
  const w=worker(); const sender={id:'ours',tab:{id:2},frameId:0,url:'https://claude.ai/chat/mock'};
  const msg={type:'achu-observation',kind:'snapshot',url:sender.url,epoch:'one',sequence:0,messages:[],final:false};
  w.listeners.message(msg,sender); await settle(); assert.equal(w.packets.length,0);
  await w.listeners.click({id:2,url:sender.url});
  w.listeners.message(msg,{...sender,id:'hostile'});w.listeners.message(msg,{...sender,frameId:1});await settle();assert.equal(w.packets.length,0);
  w.listeners.message({...msg,readKey:true},sender);await settle();assert.equal(w.packets.length,1);assert.equal(w.packets[0].readKey,undefined);
  await w.listeners.click({id:2,url:sender.url});w.listeners.message(msg,sender);await settle();assert.equal(w.packets.length,1);
});
test('worker restores explicit session choice and requests full state after reload',async()=>{
  const w=worker([7]);w.listeners.message({type:'achu-ready'},{id:'ours',tab:{id:7},frameId:0,url:'https://claude.ai/chat/mock'});await settle();assert.equal(w.messages[0].type,'achu-enable');
  w.listeners.message({type:'achu-observation',kind:'snapshot',url:'https://claude.ai/chat/mock',epoch:'one',sequence:0,messages:[],final:false},{id:'ours',tab:{id:7},frameId:0,url:'https://claude.ai/chat/mock'});await settle();
  w.listeners.disconnect();assert.equal(w.badges.at(-1).text,'!');
});

test('worker forwards only a masked fingerprint account and can relay missing identity', async()=>{
  const w=worker([8]); const sender={id:'ours',tab:{id:8},frameId:0,url:'https://claude.ai/settings/usage'};
  const account={fingerprint:'a'.repeat(64),displayName:'f***@example.test',rawEmail:'never-forward'};
  const msg={type:'achu-observation',kind:'usage',url:sender.url,epoch:'usage-account',sequence:1,usage:{rate_limits:{}},account};
  w.listeners.message(msg,sender);await settle();
  assert.deepEqual(JSON.parse(JSON.stringify(w.packets[0].account)), {fingerprint:'a'.repeat(64),displayName:'f***@example.test'});
  w.listeners.message({...msg,sequence:2,account:null},sender);await settle();
  assert.equal(w.packets[1].account,undefined);
});
test('native refresh targets an opted-in tab once and rejects arbitrary controls',async()=>{
 const w=worker([8]);await settle();
 await w.listeners.click({id:9,url:'https://claude.ai/new'});
 const command={ok:true,requestUsage:'11111111-1111-4111-8111-111111111111',binding:'web-8'};
 w.listeners.nativeMessage(command);w.listeners.nativeMessage(command);await settle();
 assert.equal(w.messages.filter(m=>m.type==='achu-usage-refresh').length,1);
 w.listeners.nativeMessage({...command,binding:'web-10'});w.listeners.nativeMessage({...command,requestUsage:'arbitrary script'});await settle();
 assert.equal(w.messages.filter(m=>m.type==='achu-usage-refresh').length,1);
});
