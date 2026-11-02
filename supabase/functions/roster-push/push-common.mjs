export function endpointAllowed(value) {
  try {
    const u = new URL(value);
    const host = u.hostname.toLowerCase();
    return u.protocol === 'https:' && !u.username && !u.password && (!u.port || u.port === '443') &&
      (host === 'fcm.googleapis.com' || host === 'updates.push.services.mozilla.com' ||
       host === 'push.apple.com' || host.endsWith('.push.apple.com'));
  } catch { return false; }
}
export function subscriptionValid(s) {
  return s && typeof s.endpoint === 'string' && s.endpoint.length <= 4096 && endpointAllowed(s.endpoint) &&
    /^[A-Za-z0-9_-]{80,100}$/.test(s.keys?.p256dh || '') && /^[A-Za-z0-9_-]{20,30}$/.test(s.keys?.auth || '');
}
