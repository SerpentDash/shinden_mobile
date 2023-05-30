(function() {
    'use strict'; 

    window.addEventListener('flutterInAppWebViewPlatformReady', function() {
        window.flutter_inappwebview.callHandler('open_in_browser', document.querySelector('.btn-success').href);
    });
})();