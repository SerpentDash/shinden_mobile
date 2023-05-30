(function() {
    'use strict'; 

    let css = `
        .footer {zoom: 2; left: 3%}
        .button-players { filter: invert(.9); zoom: 2; left: 3%; right: 3%; }
        :fullscreen .button-players { filter: invert(.9) opacity(.5); zoom: 1 }
        .pb-vid-click {display: flex; align-items: center; justify-content: space-between;}
        .rewind {height: 8vmin; visibility: hidden; border-radius: 50px; pointer-events: none; position: absolute;}
        .rewind-l {left: 4vw; box-shadow: rgb(20 20 20 / 40%) -6vmin 0px 0px 8vmin, rgb(20 20 20 / 40%) 0px 0px 0px 8vmin inset; transform: rotateZ(180deg); }
        :fullscreen .rewind-l { left: 9vw; box-shadow: rgb(20 20 20 / 40%) -9vmin 0px 0px 12vmin, rgb(20 20 20 / 40%) 0px 0px 0px 4vmin inset }
        .rewind-r {right: 4vw; box-shadow: rgb(20 20 20 / 40%) -6vmin 0px 0px 8vmin, rgb(20 20 20 / 40%) 0px 0px 0px 8vmin inset; }
        :fullscreen .rewind-r {right: 9vw; box-shadow: rgb(20 20 20 / 40%) -8vmin 0px 0px 12vmin, rgb(20 20 20 / 40%) 0px 0px 0px 4vmin inset }
        .rewind-t {font-size: 2.5vmin; color: white; position: absolute; visibility: hidden; pointer-events: none;}
        :fullscreen .rewind-t {font-size: 3vmin;}
        .pb-ad-pause-plt-show {display:none;}
        .pb-play-ico {pointer-events: none;}
    `;

    const sheet = new CSSStyleSheet();
    sheet.replaceSync(css);
    document.adoptedStyleSheets = [sheet];

    localStorage.setItem('cda-player-volume', '{"volume":"100.00","muted":false}')

    // new double click variables for move forward / backward
    let rewind_img = document.createElement('img');
    let rewind_text = document.createElement('a');

    let video, buttons;

    let clickTimeout = null;
    let doubleClickTimeout = null;

    let buttonsHideTimer = 2000;

    window.addEventListener('DOMContentLoaded', function() {    
        setTimeout(() => {
            document.querySelector('[data-quality]:last-child a')?.click(); // set max quality
            document.querySelector('.pb-settings-click')?.click(); // hide quality menu

            video = document.querySelector('video');
        }, 100); 

        buttons = document.querySelector('.button-players'); // show / hide bottom bar
        buttons.style.display = 'block';

        const fontAwesome = document.createElement('link');
        fontAwesome.rel = 'stylesheet';
        fontAwesome.href = 'https://maxcdn.bootstrapcdn.com/font-awesome/4.4.0/css/font-awesome.min.css';
        document.head.append(fontAwesome);

        AddDownloadButton();
        AddStreamButton();       

        // remove old events from pb-vid-click element
        let old_vid_click = document.querySelector('.pb-vid-click');
        let vid_click = old_vid_click.cloneNode(false);
        old_vid_click.parentNode.replaceChild(vid_click, old_vid_click);

        // FIX Play / Pause from bottom bar
        //document.getElementsByClassName('pb-play')[0].onclick = (e) => {}

        // setup new elements
        rewind_img.src = '//scdn.cda.pl/v001/img/player/r-c-rewind-icon-r.png';
        rewind_img.classList = 'rewind rewind-r'
        rewind_text.classList = 'rewind-t';

        vid_click.appendChild(rewind_img);
        vid_click.appendChild(rewind_text);
        
        vid_click.onclick = (e) => ClickHandler(e);
        
        vid_click.ondblclick = (e) => {
            if(!doubleClick) { // prevents multiple calls from onclick and ondbclick at the same time
                doubleClick = true;
                DoubleClickHandler(e);
            }
        }

        buttons.onclick = (e) => ClickHandlerOnPanel(e);
    }, false);
    
    function ClickHandler(e) {
        clearTimeout(clickTimeout); // prevents stacking timeouts
        setTimeout(() => { // make sure player is not double clicking right now
            if(!doubleClick) {
                if(document.fullscreenElement != null)
                    clickTimeout = setTimeout(() => buttons.style.display = 'none', buttonsHideTimer);
                if(buttons.style.display == 'block') {
                    video.paused ? video.play() : video.pause();
                    if(video.paused) clearTimeout(clickTimeout);
                    return;
                }
                buttons.style.display == 'none' ? buttons.style.display = 'block' : buttons.style.display = 'none';
            }
        }, 250);
        if(doubleClick)  DoubleClickHandler(e);
    }

    function ClickHandlerOnPanel(e) {
        clearTimeout(clickTimeout); // prevents stacking timeouts
        setTimeout(() => {
            if(!doubleClick && document.fullscreenElement != null)
                clickTimeout = setTimeout(() => buttons.style.display = 'none', buttonsHideTimer);
        }, 250);
    }

    // TODO: Combine img and text to div with background-image css

    let rewind_value_l = 0, rewind_value_r = 0;
    let doubleClick = false;
    function DoubleClickHandler(e) {
        clearTimeout(clickTimeout);

        rewind_img.style.visibility = 'unset';
        rewind_text.style.visibility = 'unset';
        if (0.66 * window.innerWidth < e.offsetX) {
            rewind_value_r+=5; rewind_value_l=0;
            rewind_img.classList.replace('rewind-l', 'rewind-r');
            document.fullscreenElement != null ? rewind_text.style.right = '30vmin' : rewind_text.style.right = '12vmin' ;
            rewind_text.style.removeProperty('left');
            rewind_text.innerText = `${rewind_value_r} sekund`;
        } else if (e.offsetX < 0.33 * window.innerWidth) {
            rewind_value_l+=5; rewind_value_r=0;
            rewind_img.classList.replace('rewind-r', 'rewind-l');
            document.fullscreenElement != null ? rewind_text.style.left = '30vmin' : rewind_text.style.left = '12vmin' ;
            rewind_text.style.removeProperty('right');
            rewind_text.innerText = `${rewind_value_l} sekund`;
        } else {
            rewind_value_r=0; rewind_value_l=0;
            rewind_img.style.visibility = 'hidden';
            rewind_text.style.visibility = 'hidden';
        }
        
        clearTimeout(doubleClickTimeout);
        doubleClickTimeout = setTimeout (() => {
            if (0.66 * window.innerWidth < e.offsetX)
                video.currentTime = video.currentTime + rewind_value_r;
            else if (e.offsetX < 0.33 * window.innerWidth)
                video.currentTime = (video.currentTime - rewind_value_l) < 0 ? 0 : (video.currentTime - rewind_value_l);
            
            rewind_value_l = rewind_value_r = 0;
            doubleClick = false;
            rewind_img.style.visibility = 'hidden';
            rewind_text.style.visibility = 'hidden';

            if(document.fullscreenElement != null)
                clickTimeout = setTimeout(() => buttons.style.display = 'none', buttonsHideTimer);
        }, 700);
    }

    // TODO: Cleanup...
    function AddDownloadButton() {
        let btn = document.createElement("a");
        btn.classList = 'fa fa-arrow-circle-down';
        //btn.text = '\u2913'; // icon
        btn.onclick = () => {
            let quality = document.querySelector('.pb-quality-txt').innerText;
            let title = video.ownerDocument.title
            let toRemove = ["[1080]", "[1080p]", "1080", "[", "]", "  "]; // TODO:  add more illegal characters?
            for(var i = 0; i < toRemove.length; i++)
                title = title.replace(toRemove[i], '');
            title = title.replace(/[|&;:$%@"<>+,]/g, "");
            title = title.trim();
                
            window.flutter_inappwebview.callHandler('download', video.src, `${title} (${quality})`);
        }
        btn.setAttribute("style", 'font-size: 70px; color: white; padding: 10px 10px; opacity: .5; position: absolute; z-index: 10; top: 0; right: 0; line-height: .8;');
        (document.URL.match("www.cda.pl") ? document.getElementsByClassName("wplayer")[0] : document.body).appendChild(btn);
    }

    function AddStreamButton() {
        let btn = document.createElement("a");
        btn.classList = 'fa fa-play-circle';
        //btn.text = '\u229A'; // icon
        btn.onclick = () => {          
            let quality = document.querySelector('.pb-quality-txt').innerText;
            let title = video.ownerDocument.title
            let toRemove = ["[1080]", "[1080p]", "1080", "[", "]", "  "]; // TODO:  add more illegal characters?
            for(var i = 0; i < toRemove.length; i++)
                title = title.replace(toRemove[i], '');
            title = title.replace(/[|&;:$%@"<>+,]/g, "");
            title = title.trim();
            
            video.pause();
            window.flutter_inappwebview.callHandler('stream', video.src, `${title} (${quality})`);
        }
        btn.setAttribute("style", 'font-size: 70px; color: white; padding: 10px 10px; opacity: .5; position: absolute; z-index: 10; top: 80px; right: 0; line-height: .8;');
        (document.URL.match("www.cda.pl") ? document.getElementsByClassName("wplayer")[0] : document.body).appendChild(btn);
    }

    window.onbeforeunload = () => {
        video.pause();
        video.ended = true;
        video.blur();
    }
})();