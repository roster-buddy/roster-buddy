self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',event=>{
 let data={}; try {data=event.data?.json() || {};} catch {}
 event.waitUntil(self.registration.showNotification(data.title || 'Roster Buddy update',{
   body:data.body || 'Open Roster Buddy to view your roster updates.',
   tag:data.tag || 'roster-update',
   icon:new URL('icons/Icon-192.png',self.registration.scope).href,
   badge:new URL('icons/Icon-192.png',self.registration.scope).href,
   data:{url:'?notifications=1'},
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 const target=new URL('?notifications=1',self.registration.scope).href;
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async clients=>{
   const current=clients.find(c=>c.url.startsWith(self.registration.scope));
   if(current) {await current.navigate(target);return current.focus();}
   return self.clients.openWindow(target);
 }));
});
