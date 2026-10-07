const test=require('node:test'), assert=require('node:assert/strict');
const fs=require('node:fs');
test('web active acquisition module exists',()=>assert.ok(fs.existsSync('Bridge/chrome/usage.js'),'active web acquisition is absent'));
if(fs.existsSync('Bridge/chrome/usage.js')){
 const api=require('../Bridge/chrome/usage.js');
 const org='11111111-1111-4111-8111-111111111111';
 const identity=email=>({email_address:email,memberships:[{organization:{uuid:org}}]});
 const response=value=>({ok:true,status:200,headers:{get:()=> 'application/json'},text:async()=>JSON.stringify(value)});
 test('same-origin fetch checks account before and after, strips identity and spend',async()=>{
  const calls=[];let i=0;
  const value=await api.read(async(url,options)=>{calls.push({url,options});return response([identity('one@example.test'),{five_hour:{utilization:12,resets_at:'2026-10-08T12:00:00Z'},seven_day:{utilization:34},spend:99},identity('one@example.test')][i++]);},require('node:crypto').webcrypto);
  assert.equal(value.usage.rate_limits.five_hour.used_percentage,12);
  assert.equal(value.usage.rate_limits.seven_day.used_percentage,34);
  assert.match(value.account.fingerprint,/^[a-f0-9]{64}$/);
  assert.ok(!JSON.stringify(value).includes('one@example.test'));
  assert.ok(!JSON.stringify(value).includes('spend'));
  assert.ok(calls.every(c=>c.url.startsWith('/api/')&&c.options.credentials==='same-origin'&&c.options.redirect==='error'&&c.options.cache==='no-store'));
 });
 test('account changes, multiple organizations, failed responses and missing quota fail closed',async()=>{
  for(const values of [[identity('one@example.test'),{five_hour:{utilization:12}},identity('two@example.test')],
    [{...identity('one@example.test'),memberships:[]}],
    [identity('one@example.test'),{}],
    [identity('one@example.test'),{five_hour:{utilization:101}}]]){
    let i=0;await assert.rejects(()=>api.read(async()=>response(values[i++]),require('node:crypto').webcrypto));
  }
  await assert.rejects(()=>api.read(async()=>({ok:false,status:403}),require('node:crypto').webcrypto));
 });
 test('current limits payload keeps subscription windows and ignores product shares',async()=>{
   let i=0;const values=[identity('one@example.test'),{limits:[{kind:'session',percent:1,resets_at:'2026-10-08T12:00:00Z'},{kind:'weekly_all',percent:24},{kind:'product',percent:83}]},identity('one@example.test')];
   const result=await api.read(async()=>response(values[i++]),require('node:crypto').webcrypto);
   assert.equal(result.usage.rate_limits.five_hour.used_percentage,1);
   assert.equal(result.usage.rate_limits.seven_day.used_percentage,24);
 });
}
