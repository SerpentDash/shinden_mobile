(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0}');
    document.adoptedStyleSheets = [sheet];

    window.addEventListener('DOMContentLoaded', async function() {   
        setTimeout(() => window.flutter_inappwebview.callHandler('open_in_browser', `https://9xbud.com/${location.href}`), 0);
        return
        let json = JSON.parse(document.querySelector('[data-options]').dataset.options);
        //console.log(JSON.parse(json.flashvars.metadata));

        let xml = new DOMParser().parseFromString(JSON.parse(json.flashvars.metadata).metadataEmbedded, "application/xml");
        let urls = xml.querySelectorAll('BaseURL');
        let m3u8;
        console.log(urls[urls.length-1].innerHTML.replace(/&amp;/g, "&"));
        fetch(urls[urls.length-1].innerHTML.replace(/&amp;/g, "&")).then((response) => console.log(response.url));
        
        setTimeout(() => document.getElementsByClassName('vid_play')[0].click(), 500);
        window.addEventListener("flutterInAppWebViewPlatformReady", async function(event) {
            //await fetch(JSON.parse(json.flashvars.metadata).hlsManifestUrl).then(response => response.text()).then((response) => m3u8 = response);
            //console.log(JSON.parse(json.flashvars.metadata).hlsManifestUrl);
            //console.log(m3u8);
            console.log('AAAAA');
            //setTimeout(() => window.flutter_inappwebview.callHandler('stream', urls[urls.length-1].innerHTML.replace(/&amp;/g, "&"), ''), 4000);
            
        });
    }, false);
})();