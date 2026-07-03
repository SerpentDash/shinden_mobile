(function () {
  'use strict';

  const patterns = window.__shinden_capture_patterns || [];
  const matches = (url) =>
    patterns.length > 0 && patterns.some((pattern) => url.indexOf(pattern) !== -1);

  const emit = (payload) => {
    try {
      window.flutter_inappwebview.callHandler('shinden_capture', JSON.stringify(payload));
    } catch (_) {}
  };

  if (!window.__shinden_orig_fetch) {
    window.__shinden_orig_fetch = window.fetch.bind(window);
  }
  const origFetch = window.__shinden_orig_fetch;
  if (!origFetch) return;

  const hooked = function (input, init) {
    const url =
      typeof input === 'string'
        ? input
        : input && typeof input.url === 'string'
          ? input.url
          : '';

    return origFetch(input, init).then((response) => {
      if (!url || !matches(url)) return response;

      const responseUrl = response && response.url ? String(response.url) : url;
      response
        .clone()
        .text()
        .then((body) => {
          emit({ type: 'fetch_response', url: responseUrl, body: body });
        })
        .catch(function () {});

      return response;
    });
  };

  try {
    hooked.toString = function () {
      return origFetch.toString();
    };
  } catch (_) {}

  window.fetch = hooked;
})();
