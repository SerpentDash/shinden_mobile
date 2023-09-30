(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0}');
    document.adoptedStyleSheets = [sheet];

    window.addEventListener('DOMContentLoaded', async function() {   
        setTimeout(() => window.flutter_inappwebview.callHandler('open_in_browser', `https://9xbud.com/${location.href}`), 0);
    }, false);
})();