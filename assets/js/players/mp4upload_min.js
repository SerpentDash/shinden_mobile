(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0; pointer-events: none;} body {background: #181818}');
    document.adoptedStyleSheets = [sheet];

    window.addEventListener('DOMContentLoaded', function() {
        setTimeout(() => window.flutter_inappwebview.callHandler('open_in_browser', `https://9xbud.com/${location.href}`), 0);
    }, false);

   /*  window.addEventListener('load', function() {
        alert(location.href)
        setTimeout(() => window.flutter_inappwebview.callHandler('open_in_browser', location.href), 0);
        return
        document.getElementById('method_free')?.click();

        const title = document.querySelector(".name h4").textContent.replaceAll(' ', "%20")
        const url = document.documentElement.textContent.split('src: "')[1].split('"')[0]

        if(title != null && url != null)
            window.flutter_inappwebview.callHandler('download/stream', url, `${title}`);
        
        new Promise((resolve) => setTimeout(resolve, 1000)).then(() => {
            url = $('video')[0].src;
            console.log("url", url)
        });
    }, false); */
})();