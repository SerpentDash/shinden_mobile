(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0}');
    document.adoptedStyleSheets = [sheet];

    const acceptCookie = async (selector) => {
        while (selector) {
            selector?.click();
            await new Promise(requestAnimationFrame);
        }
        return true;
    };

    window.addEventListener('DOMContentLoaded', () => {   
        window.addEventListener("flutterInAppWebViewPlatformReady", () => {
            setTimeout(() => {
                document.getElementsByClassName('button_play')[0]?.click();
                setTimeout(() => {
                    acceptCookie(document.getElementsByClassName('np_DialogConsent-accept')[0]).then(() => 
                        document.getElementsByClassName('button_play')[0]?.click());
                    // Rest of the magic can be found in main.dart (androidShouldInterceptRequest section)
                }, 500);
            }, 500);
            // First click Play button to trigger cookie prompt
            // Click until cookie prompt disappear
            // Click Play button again to get request with .m3u8
        });
    }, false);
})();