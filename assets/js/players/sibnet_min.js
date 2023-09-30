(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0}');
    document.adoptedStyleSheets = [sheet];

    window.addEventListener('DOMContentLoaded', () => {   
        setTimeout(() => window.flutter_inappwebview.callHandler('open_in_browser', `https://9xbud.com/${location.href}`), 0);
        return
        window.addEventListener("flutterInAppWebViewPlatformReady", () => {
            setTimeout(() => {
                
                document.getElementsByClassName('vjs-big-play-button')[0].click();
                // Rest of the magic can be found in main.dart (androidShouldInterceptRequest section)
            }, 500);
        });
    }, false);
})();