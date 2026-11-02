import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import webPush from 'npm:web-push@3.6.7';
import { subscriptionValid, endpointAllowed } from './push-common.mjs';

const project = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const db = createClient(project, serviceKey, {auth: {persistSession:false, autoRefreshToken:false}});
const subject = 'https://roster-buddy.github.io/roster-buddy/';
const allowedOrigin = 'https://roster-buddy.github.io';
const headers = {
 'Access-Control-Allow-Origin': allowedOrigin,
 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-roster-dispatch-token',
 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
 'Content-Type':'application/json', 'Cache-Control':'no-store',
};
function reply(value: unknown, status=200) { return new Response(JSON.stringify(value), {status,headers}); }
function equalSecret(a: string,b: string) {
 if (!a || a.length !== b.length) return false;
 let difference=0; for(let i=0;i<a.length;i++) difference|=a.charCodeAt(i)^b.charCodeAt(i);
 return difference===0;
}
async function config() {
 const {data,error}=await db.rpc('roster_push_config');
 if(error || !data?.vapid?.publicKey || !data?.vapid?.privateKey || !data?.dispatch) throw new Error('Push configuration unavailable');
 return data;
}
async function sendPending(cfg: any) {
 const {data,error}=await db.rpc('claim_roster_push_deliveries');
 if(error) throw new Error('Could not claim notifications');
 let sent=0, failed=0;
 const items=data || [];
 for(let offset=0;offset<items.length;offset+=5) {
  await Promise.all(items.slice(offset,offset+5).map(async item => {
   try {
     if(!endpointAllowed(item.subscription?.endpoint)) throw new Error('Invalid push endpoint');
     await webPush.sendNotification(item.subscription, JSON.stringify({
       title:item.title, body:item.body, tag:'roster-'+item.event_id,
       url:'?notifications=1',
     }), {TTL:3600,urgency:'high',timeout:10000,vapidDetails:{
       subject,publicKey:cfg.vapid.publicKey,privateKey:cfg.vapid.privateKey,
     }});
     const result = await db.from('roster_push_deliveries').update({status:'sent',sent_at:new Date().toISOString(),last_error:null}).in('id',item.delivery_ids);
     if(result.error) throw new Error('Could not record delivery');
     sent++;
   } catch(error: any) {
     if(error?.statusCode===404 || error?.statusCode===410) {
       await db.from('roster_push_subscriptions').delete().eq('id',item.subscription_id);
     } else {
       await db.from('roster_push_deliveries').update({
         status:item.attempts>=5?'failed':'pending',
         next_attempt_at:new Date(Date.now()+Math.min(3600,60*(2**item.attempts))*1000).toISOString(),
         last_error:error?.statusCode ? 'Push provider HTTP '+error.statusCode : 'Push delivery failed',
       }).eq('id',item.delivery_id);
     }
     failed++;
   }
  }));
 }
 return {sent,failed,claimed:(data || []).length};
}
Deno.serve(async req => {
 if(req.method==='OPTIONS') return new Response('ok',{headers});
 const origin=req.headers.get('origin');
 if(origin && origin!==allowedOrigin) return reply({error:'Origin not allowed'},403);
 try {
   const cfg=await config();
   if(req.method==='GET') return reply({publicKey:cfg.vapid.publicKey,ready:true});
   if(req.method!=='POST') return reply({error:'Method not allowed'},405);
   const contentLength=Number(req.headers.get('content-length') || 0);
   if(contentLength>12000) return reply({error:'Request too large'},413);
   const body=await req.json();
   const isDispatcher=equalSecret(req.headers.get('x-roster-dispatch-token') || '',cfg.dispatch);
   if(body.action==='dispatch' || body.action==='selftest') {
     if(!isDispatcher) return reply({error:'Not authorized'},401);
     if(body.action==='selftest') {
       const sample=webPush.generateVAPIDKeys();
       const bytes=crypto.getRandomValues(new Uint8Array(16));
       const auth=btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
       const details=webPush.generateRequestDetails({endpoint:'https://web.push.apple.com/test',
         keys:{p256dh:sample.publicKey,auth}},
         JSON.stringify({title:'Encryption check'}),{vapidDetails:{subject,publicKey:cfg.vapid.publicKey,privateKey:cfg.vapid.privateKey},TTL:60});
       return reply({encryptionReady:details.body.length>20});
     }
     return reply(await sendPending(cfg));
   }
   const jwt=(req.headers.get('authorization') || '').replace(/^Bearer\s+/i,'');
   const {data:authData,error:authError}=await db.auth.getUser(jwt);
   if(authError || !authData.user) return reply({error:'Please sign in again'},401);
   const user=authData.user;
   if(body.action==='subscribe') {
     if(!subscriptionValid(body.subscription)) return reply({error:'Invalid subscription'},400);
     const endpoint=body.subscription.endpoint;
     const existing=await db.from('roster_push_subscriptions').select('id,user_id').eq('endpoint',endpoint).maybeSingle();
     if(existing.error) throw new Error('Subscription lookup failed');
     if(existing.data && existing.data.user_id!==user.id) return reply({error:'Disable notifications on this device, then enable them again for this account.'},409);
     const count=await db.from('roster_push_subscriptions').select('id',{count:'exact',head:true}).eq('user_id',user.id);
     if(!existing.data && (count.count || 0)>=10) return reply({error:'Ten devices are already subscribed. Disable an old device first.'},400);
     const result=await db.from('roster_push_subscriptions').upsert({
       user_id:user.id,endpoint,subscription:body.subscription,updated_at:new Date().toISOString(),
     },{onConflict:'endpoint'});
     if(result.error) throw new Error('Subscription save failed');
     return reply({subscribed:true});
   }
   if(body.action==='unsubscribe') {
     if(typeof body.endpoint==='string') {
       const result=await db.from('roster_push_subscriptions').delete().eq('user_id',user.id).eq('endpoint',body.endpoint);
       if(result.error) throw new Error('Subscription removal failed');
     }
     return reply({unsubscribed:true});
   }
   if(body.action==='test') {
     const subscriptions=await db.from('roster_push_subscriptions').select('id').eq('user_id',user.id).eq('endpoint',body.endpoint || '');
     if(subscriptions.error || !subscriptions.data?.length) return reply({error:'Enable notifications on this device first'},400);
     const recent=await db.from('roster_push_events').select('id',{head:true,count:'exact'}).eq('user_id',user.id)
       .eq('kind','test').gte('created_at',new Date(Date.now()-60000).toISOString());
     if((recent.count || 0)>=3) return reply({error:'Wait a minute before testing again'},429);
     const event=await db.from('roster_push_events').insert({
       user_id:user.id,kind:'test',title:'Roster Buddy test notification',
       body:'Push notifications are working. Open Roster Buddy to view your updates.',
       event_key:'test|'+crypto.randomUUID(),
     }).select('id').single();
     if(event.error) throw new Error('Test notification failed');
     // Queue this test only to the device that requested it.
     const delivery=await db.from('roster_push_deliveries').insert({event_id:event.data.id,subscription_id:subscriptions.data[0].id});
     if(delivery.error) throw new Error('Test delivery failed');
     await sendPending(cfg);
     const verified=await db.from('roster_push_deliveries').select('status').eq('event_id',event.data.id).eq('subscription_id',subscriptions.data[0].id).maybeSingle();
     return reply({queued:true,testSent:verified.data?.status==='sent'});
   }
   return reply({error:'Unknown action'},400);
 } catch {
   return reply({error:'Push service could not complete this request. Please retry.'},500);
 }
});
