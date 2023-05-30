(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0; pointer-events: none;} body {background: #181818}');
    document.adoptedStyleSheets = [sheet];

    window.addEventListener('load', function() {
        document.getElementById('method_free').click();
    }, false);

    
    window.addEventListener('flutterInAppWebViewPlatformReady', function() {
        setTimeout(() => window.flutter_inappwebview.callHandler('back_button'), 3000);
    });
})();