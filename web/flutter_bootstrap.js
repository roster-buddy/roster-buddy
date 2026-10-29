{{flutter_js}}
{{flutter_build_config}}

// A release-specific filename bypasses older Flutter service-worker caches.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath === 'main.dart.js') {
    build.mainJsPath = 'main.__ROSTER_BUILD__.dart.js';
  }
}

async function startRosterBuddy() {
  if ('serviceWorker' in navigator) {
    try {
      const scope = new URL('.', document.baseURI).href;
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations
        .filter(registration => registration.scope === scope)
        .map(registration => registration.unregister()));
    } catch (error) {
      console.warn('Could not retire the old app worker', error);
    }
  }
  return _flutter.loader.load();
}
startRosterBuddy();
