document.addEventListener('DOMContentLoaded', () => {
  if (typeof HSStaticMethods !== 'undefined') {
    HSStaticMethods.autoInit();
  }
});

document.body.addEventListener('htmx:afterSwap', () => {
  if (typeof HSStaticMethods !== 'undefined') {
    HSStaticMethods.autoInit();
  }
});
