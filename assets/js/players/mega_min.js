(function() {
    'use strict'; 

    window.addEventListener('DOMContentLoaded', function() {
        setTimeout(() => window.flutter_inappwebview.callHandler('open_in_browser', location.href), 0);
    }, false);
})();