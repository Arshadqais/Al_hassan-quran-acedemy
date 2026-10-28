// Cache only the public offline notice. Accounts, messages, Quran API responses,
// and classroom tokens are never cached by this service worker.
if (window.isSecureContext && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('academy-service-worker.js', {scope: './'})
      .catch(() => { /* The live website still works if installation is unavailable. */ });
  });
}
