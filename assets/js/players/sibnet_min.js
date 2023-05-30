(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0}');
    document.adoptedStyleSheets = [sheet];

    window.addEventListener('DOMContentLoaded', () => {   
        window.addEventListener("flutterInAppWebViewPlatformReady", () => {
            setTimeout(() => {
                document.getElementsByClassName('vjs-big-play-button')[0].click();
                // Rest of the magic can be found in main.dart (androidShouldInterceptRequest section)
            }, 500);
        });
    }, false);
})();