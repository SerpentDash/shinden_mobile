(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0; background: black; pointer-events: none}');
    document.adoptedStyleSheets = [sheet];

    window.addEventListener('load', async function() {
        if(/[drive|docs].google.com\/file/.test(location.href)) {
            let error = document.querySelector('.errorMessage'); 
            if(error != null) {
                setTimeout(() => {
                    window.flutter_inappwebview.callHandler('back_button');
                    alert('Video does not exist!\nChoose other player.'); 
                }, 250);
                return;
            }

            let gdf_id= /\/file\/d\/([^\/]+)/i.exec(location.href);
            let direct = location.protocol+'//'+location.hostname+'/uc?id='+gdf_id[1]+'&confirm=t&export=download';
            let title = document.querySelector('[itemprop=name]').content;
            window.flutter_inappwebview.callHandler('download/stream', direct, `${title}`);
        }
    }, false);
})();