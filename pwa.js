(() => {
  if (!('serviceWorker' in navigator) || location.protocol === 'file:') return;
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./service-worker.js').catch(error => console.error('Falha ao ativar suporte offline:', error));
  });
})();