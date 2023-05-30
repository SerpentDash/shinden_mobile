(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0; background: black}');
    document.adoptedStyleSheets = [sheet];
    // Rest of the magic can be found in main.dart (androidShouldInterceptRequest section)
})();