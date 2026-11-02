import test from 'node:test';
import assert from 'node:assert/strict';
import { endpointAllowed, subscriptionValid } from '../supabase/functions/roster-push/push-common.mjs';

test('push delivery accepts only known HTTPS push providers',()=>{
 for(const url of ['https://web.push.apple.com/token','https://fcm.googleapis.com/fcm/send/token','https://updates.push.services.mozilla.com/wpush/v2/token']) assert.equal(endpointAllowed(url),true);
 for(const url of ['http://web.push.apple.com/token','https://web.push.apple.com.evil.test/token','http://127.0.0.1/','https://user@web.push.apple.com/token','https://web.push.apple.com:8443/token']) assert.equal(endpointAllowed(url),false);
 assert.equal(subscriptionValid({endpoint:'https://web.push.apple.com/token',keys:{p256dh:'A'.repeat(87),auth:'B'.repeat(22)}}),true);
 assert.equal(subscriptionValid({endpoint:'https://web.push.apple.com/token',keys:{p256dh:'bad',auth:'bad'}}),false);
});

test('permission starts from the tap, saved subscriptions are account-bound, and disabling removes them',async()=>{
 const events=[], values=new Map();
 let active=null;
 const subscription={endpoint:'https://web.push.apple.com/test',toJSON(){return {endpoint:this.endpoint,keys:{p256dh:'A'.repeat(87),auth:'B'.repeat(22)}};},async unsubscribe(){events.push('unsubscribe');active=null;return true;}};
 const registration={pushManager:{async getSubscription(){return active;},async subscribe(){events.push('subscribe');active=subscription;return subscription;}}};
 globalThis.window={PushManager:{}};
 globalThis.document={baseURI:'https://roster-buddy.github.io/roster-buddy/'};
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{userAgent:'Desktop',maxTouchPoints:0,serviceWorker:{
   async getRegistration(){return registration;},async register(){events.push('register');return registration;},ready:Promise.resolve(registration),
 }}});
 globalThis.matchMedia=()=>({matches:true});
 globalThis.localStorage={getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};
 globalThis.Notification={permission:'default',async requestPermission(){events.push('permission');this.permission='granted';return 'granted';}};
 window.Notification=globalThis.Notification;
 globalThis.fetch=async (url,options)=>{
   if(!options) {events.push('config');return {ok:true,async json(){return {publicKey:Buffer.alloc(65,4).toString('base64url')};}};}
   const body=JSON.parse(options.body);
   events.push(body.action);assert.equal(options.headers.Authorization,'Bearer session-token');
   return {ok:true,async json(){return {};}}
 };
 const api=await import('../web/roster_push.mjs');
 const enabled=await api.enable('session-token','driver-a');
 assert.equal(events[0],'permission');
 assert.equal(enabled.state,'enabled');
 assert.equal((await api.status('driver-b')).state,'available');
 await api.disable('session-token','driver-a');
 assert.equal(active,null);
 assert.equal((await api.status('driver-a')).state,'available');
 assert.ok(events.includes('unsubscribe'));
 navigator.userAgent='iPhone';globalThis.matchMedia=()=>({matches:false});
 assert.equal((await api.status('driver-a')).state,'install');
});
