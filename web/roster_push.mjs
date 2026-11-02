const API='https://ahrkivleahrfvmmtujrh.supabase.co/functions/v1/roster-push';
const scope=()=>new URL('.',document.baseURI).href;
const ownerKey='roster-buddy-push-owner';
function supported() {
 const ios=/iPhone|iPad|iPod/.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent)&&navigator.maxTouchPoints>1);
 const installed=matchMedia('(display-mode: standalone)').matches || navigator.standalone===true;
 if(ios&&!installed) return {state:'install',message:'Open Roster Buddy from its Home Screen icon to enable iPhone/iPad notifications.'};
 if(!('serviceWorker' in navigator)||!('PushManager' in window)||!('Notification' in window))
   return {state:'unsupported',message:'This browser does not support Web Push. Use an up-to-date Home Screen app or supported browser.'};
 return null;
}
async function request(body,token) {
 const response=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify(body)});
 const data=await response.json();
 if(!response.ok) throw new Error(data.error || 'Notifications could not be configured.');
 return data;
}
export async function status(user) {
 const unavailable=supported(); if(unavailable) return unavailable;
 if(Notification.permission==='denied') return {state:'blocked',message:'Notifications are blocked. Allow them for Roster Buddy in your device notification settings.'};
 const registration=await navigator.serviceWorker.getRegistration(scope());
 const subscription=await registration?.pushManager.getSubscription();
 const enabled=subscription && Notification.permission==='granted' && localStorage.getItem(ownerKey)===user;
 return {state:enabled?'enabled':'available',message:enabled?'Enabled on this device. Updates can arrive while Roster Buddy is closed.':'Enable notifications for roster allocations, changes and annual-leave conflicts.'};
}
function bytes(value) {
 return Uint8Array.from(atob(value.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(value.length/4)*4,'=')),c=>c.charCodeAt(0));
}
export async function enable(token,user) {
 const unavailable=supported(); if(unavailable) throw new Error(unavailable.message);
 // Permission must be requested directly from the user's button tap.
 const permission=await Notification.requestPermission();
 if(permission!=='granted') throw new Error('Notification permission was not granted. You can allow it in device settings.');
 const response=await fetch(API); if(!response.ok) throw new Error('The push service could not be reached.');
 const config=await response.json();
 const registration=await navigator.serviceWorker.register(new URL('roster_push_sw.js',document.baseURI),{scope:scope(),updateViaCache:'none'});
 await navigator.serviceWorker.ready;
 let subscription=await registration.pushManager.getSubscription();
 if(subscription && localStorage.getItem(ownerKey)!==user) { await subscription.unsubscribe(); subscription=null; }
 const created=!subscription;
 subscription=subscription || await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:bytes(config.publicKey)});
 try {
   await request({action:'subscribe',subscription:subscription.toJSON()},token);
   localStorage.setItem(ownerKey,user);
 } catch(error) { if(created) await subscription.unsubscribe(); throw error; }
 return status(user);
}
export async function disable(token,user) {
 if(!('serviceWorker' in navigator)) return {state:'available',message:'Notifications are off on this device.'};
 const registration=await navigator.serviceWorker.getRegistration(scope());
 const subscription=await registration?.pushManager.getSubscription();
 if(subscription) {
   const endpoint=subscription.endpoint;
   await subscription.unsubscribe();
   if(token) { try {await request({action:'unsubscribe',endpoint},token);} catch {} }
 }
 localStorage.removeItem(ownerKey);
 return {state:'available',message:'Notifications are off on this device.'};
}
export async function test(token) {
 const registration=await navigator.serviceWorker.getRegistration(scope());
 const subscription=await registration?.pushManager.getSubscription();
 if(!subscription) throw new Error('Enable notifications first.');
 const result=await request({action:'test',endpoint:subscription.endpoint},token);
 if(!result.testSent) throw new Error('The test was queued but delivery has not been confirmed. Please retry shortly.');
 return {state:'enabled',message:'Test notification sent. Check your device notifications.'};
}
const wrap=fn=>(...args)=>fn(...args).then(JSON.stringify).catch(error=>JSON.stringify({error:error.message || 'Notifications could not be configured.'}));
window.rosterPushStatus=wrap(status);
window.rosterPushEnable=wrap(enable);
window.rosterPushDisable=wrap(disable);
window.rosterPushTest=wrap(test);
