(function() {
    'use strict'; 

    const sheet = new CSSStyleSheet();
    sheet.replaceSync('html {opacity: 0; pointer-events: none}');
    document.adoptedStyleSheets = [sheet];
    
    let video, fallback;

    window.addEventListener('load', async function() {   
        video = document.querySelector('video');
        if(!video) {
            setTimeout(() => {
                window.flutter_inappwebview.callHandler('back_button');
                alert('Video does not exist!\nChoose other player.'); 
            }, 250);
            return; 
        } 
        
        // Stream after player switch to better quality
        new MutationObserver(Stream).observe(video, { attributes: true, attributeFilter: ['src'] });
        
        // Click HTML button to set the highest quality
        document.querySelector('[data-quality]:last-child a').click();
        
        // Use fallback when there is no better quality to choose 
        fallback = setTimeout(Stream, 5000);
    }, false);
    
    function Stream() {
        clearTimeout(fallback);
        let quality = document.querySelector('.pb-quality-txt').innerText;
        let title = video.ownerDocument.title;
        window.flutter_inappwebview.callHandler('download/stream', video.src, `${title} (${quality}).mp4`);    
    }
})();