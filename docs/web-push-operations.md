# Roster Buddy Web Push

Notifications are opt-in per device/account. In the Home Screen web app open the bell,
then Device notifications → Enable notifications → Allow → Send test notification.

Completed processed Base/10D/7D/48HR uploads enqueue matching allocations/changes.
Working amendment rows on recorded leave enqueue investigation alerts without editing leave.
The dispatcher runs every minute; retries use leases/backoff and expired endpoints are removed.
One upload is batched per device to avoid a notification for every date in a Base Roster.

Deployment:
- Edge Function: roster-push (JWT gateway disabled; the handler validates signed-in users with getUser,
  and dispatch/self-test requests require the Vault-backed dispatcher token).
- Runtime dependencies pinned in index.ts.
- Private Vault secrets: roster_push_vapid (JSON publicKey/privateKey), roster_push_dispatch.
  Never put private keys in GitHub, the app bundle or logs. Do not regenerate VAPID on redeploy.
- Only service_role can execute the config/claim RPCs. Browser responses include the public key only.
- Cron: roster-push-dispatch invokes the authenticated dispatcher every minute.
- Worker: web/roster_push_sw.js. Bootstrap preserves this worker while retiring legacy Flutter workers.
- Signing out unsubscribes the current browser device before clearing the session.

Verification:
- node --test browser-scanner/push.test.mjs
- Flutter analysis/tests and Chromium/WebKit scanner checks run before web deployment.
- Server rollback tests exercise suffix matching, allocation, duplicate suppression and leave preservation.
- Authenticated dispatcher self-test verifies actual Deno web-push encryption.
- Real lock-screen delivery requires the user to grant permission and run the test on their device.
