function notificationTarget(raw) {
 const fallback=new URL('?notifications=1',self.registration.scope).href;
 try {
   const target=new URL(raw || '?notifications=1',self.registration.scope);
   if(target.origin!==new URL(self.registration.scope).origin ||
      !target.pathname.startsWith(new URL(self.registration.scope).pathname)) return fallback;
   return target.href;
 } catch {return fallback;}
}
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',event=>{
 let data={}; try {data=event.data?.json() || {};} catch {}
 event.waitUntil(self.registration.showNotification(data.title || 'Roster Buddy update',{
   body:data.body || 'Open Roster Buddy to view your roster updates.',
   tag:data.tag || 'roster-update',
   icon:new URL('icons/Icon-192.png',self.registration.scope).href,
   badge:new URL('icons/Icon-192.png',self.registration.scope).href,
   data:{url:notificationTarget(data.url)},
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 const target=notificationTarget(event.notification.data?.url);
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async clients=>{
   const current=clients.find(c=>c.url.startsWith(self.registration.scope));
   if(current) {await current.navigate(target);return current.focus();}
   return self.clients.openWindow(target);
 }));
});
