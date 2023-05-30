(function() {
    'use strict'; 

    // const sheet = new CSSStyleSheet();
    // sheet.replaceSync('html {opacity: 0; background: black; pointer-events: none}');
    // document.adoptedStyleSheets = [sheet];

    window.addEventListener('load', async function() {
        setTimeout(() => {
            let link = document.querySelector('.group[href][rel]').href;
            console.log(link);
            let title = link.split('Name=')[1];
            window.flutter_inappwebview.callHandler('download/stream', link, title);
        }, 5000);
    }, false);
})();