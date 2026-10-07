/* First-party same-origin read only. Credentials remain in the browser. */
(function(root){
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  function identity(value){
    const account=value?.account || value;
    const email=account?.email_address?.toLowerCase();
    const memberships=account?.memberships;
    if(typeof email!=='string'||email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||!Array.isArray(memberships)||memberships.length!==1)throw Error('identity-unavailable');
    const org=memberships[0]?.organization?.uuid;
    if(typeof org!=='string'||!uuid.test(org))throw Error('identity-unavailable');
    return {email,org:org.toLowerCase()};
  }
  async function read(fetcher, crypto){
    async function get(path){
      const response=await fetcher(path,{method:'GET',credentials:'same-origin',cache:'no-store',redirect:'error',headers:{Accept:'application/json'},signal:AbortSignal.timeout(10000)});
      if(!response.ok||!response.headers.get('content-type')?.includes('application/json'))throw Error('request-unavailable');
      const text=await response.text();if(text.length>1000000)throw Error('response-too-large');
      return JSON.parse(text);
    }
    const before=identity(await get('/api/account'));
    const payload=await get(`/api/organizations/${before.org}/usage?skip_spend=1`);
    const after=identity(await get('/api/account'));
    if(before.email!==after.email||before.org!==after.org)throw Error('account-changed');
    const rate_limits={};
    for(const name of ['five_hour','seven_day']){
      let w=payload[name];
      if(Array.isArray(payload.limits)){
        const values=payload.limits.filter(v=>v.kind===(name==='five_hour'?'session':'weekly_all'));
        if(values.length>1)throw Error('duplicate-window');
        w=values[0] ? {utilization:values[0].percent,resets_at:values[0].resets_at} : null;
      }
      if(w?.utilization==null)continue;
      if(typeof w.utilization!=='number'||!Number.isFinite(w.utilization)||w.utilization<0||w.utilization>100)throw Error('invalid-usage');
      const item={used_percentage:w.utilization};
      if(w.resets_at!=null){const date=Date.parse(w.resets_at);if(!Number.isFinite(date))throw Error('invalid-reset');item.resets_at=date/1000;}
      rate_limits[name]=item;
    }
    if(!Object.keys(rate_limits).length)throw Error('quota-unavailable');
    const hash=await crypto.subtle.digest('SHA-256',new TextEncoder().encode('claude-web-account\0'+before.email+'\0'+before.org));
    const fingerprint=[...new Uint8Array(hash)].map(n=>n.toString(16).padStart(2,'0')).join('');
    const [local,domain]=before.email.split('@');
    return {account:{fingerprint,displayName:(local[0]+'***@'+domain).slice(0,80)},usage:{rate_limits}};
  }
  const api={read};if(typeof module!=='undefined')module.exports=api;root.AChuUsage=api;
})(globalThis);
