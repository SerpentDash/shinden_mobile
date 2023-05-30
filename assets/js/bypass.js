(function() {
    'use strict'; 

    // Auto click button to show info after user ends watching video (easier access to stats of series)
    window.onload = () => {
        if(localStorage.getItem('show_info') == 'true') {
            setTimeout(() => {
                window.scrollTo({ top: 0, behavior: 'smooth' });
                document.getElementsByClassName('info-aside-button-slide-open')[0].click();
                localStorage.removeItem('show_info');
            }, 0)
        }
    }
  
    // Override buttons with new events when website is loaded
    document.onreadystatechange = async () => {
        if (document.readyState === 'interactive') {
            overrideButtons(document.documentElement.textContent);
            container = document.getElementsByClassName("player-online box")[0];
        }
    };    

    async function getReq(url, callback = null) {
        await fetch(url, {credentials: 'include'}).then(async r => callback && callback(await r.text()));
    }

    const handledSites = [
        'cda', 
        'sibnet', 
        'streamtape', 
        'dailymotion',
        'gdrive', 
        'drive.google', 
        'mp4upload', 
        'mega', 
        'yourupload'
    ]//, 'streamsb', 'hqq', 'okru'];
    
    function overrideButtons(source) {
        const key = source.match(/_Storage\.basic =  \'.*\'/)[0].substring(19).slice(0, -1);
        let elements = document.getElementsByClassName("ep-buttons");
        let clone, data;

        // template for dropdown
        let dropdown = document.createElement('div');
        dropdown.classList.add('dropdown');
        dropdown.innerHTML = `
            <a class="button">Wybierz<i class='fa fa-chevron-down'></i></a><div class="dropdown-content">
            <a class='button'>Pokaż</a><a class='button'>Stream</a><a class='button'>Pobierz</a></div>`;

        // clone template and assign correct values / events
        for (let i = 1; i < elements.length; i++) {
            clone = elements[i].firstChild.cloneNode(true);
            elements[i].replaceChild(clone, elements[i].firstChild);
            let data = clone.getAttribute("data-episode");
            
            if(handledSites.includes(elements[i].parentElement.firstElementChild.innerText.toLowerCase())) {               
                let _dropdown = dropdown.cloneNode(true);
                clone.after(_dropdown);
                clone.remove();
                               
                _dropdown.children[0].onclick = (e) => e.target.nextSibling.classList.add('show');
                _dropdown.children[1].children[0].onclick = () => handleClick(i, data, '', _dropdown.children[1].children[0].innerText);
                _dropdown.children[1].children[1].onclick = () => handleClick(i, data, 'stream', _dropdown.children[1].children[1].innerText);
                _dropdown.children[1].children[2].onclick = () => handleClick(i, data, 'download', _dropdown.children[1].children[2].innerText);

                switch(elements[i].parentElement.firstElementChild.innerText.toLowerCase()) {
                    case 'dailymotion': // only stream
                        _dropdown.children[1].children[2].remove();
                        break;
                    case 'yourupload': // only open external browser
                    case 'mega': 
                        _dropdown.children[1].children[1].remove();
                        _dropdown.children[1].children[1].innerText = elements[i].parentElement.firstElementChild.innerText.toLowerCase() == 'mega' ? 'MegaAPP' : 'External Browser';
                        _dropdown.children[1].children[1].onclick = () => handleClick(i, data, 'download', _dropdown.children[1].children[1].innerText);
                        break;
                    default:
                        break;
                }
            } else {
                let normalBtn = document.createElement('a');
                normalBtn.innerText = 'Pokaż';
                normalBtn.classList.add('button');
                normalBtn.dataset.old = '';
                normalBtn.onclick = () => {
                    setUI(normalBtn);
                    getPlayer(data);
                }
                clone.after(normalBtn);
                clone.remove();
            }            
        };

        // Set correct onclick to button
        const handleClick = (i, data, mode, buttonText) => {
            let btn = elements[i].querySelector('.button');
            setUI(btn);
            getPlayer(data);
            btn.innerText = buttonText;
            if(mode) window.flutter_inappwebview.callHandler('mode_set', mode);
        };

        function getPlayer(d) {
            data = JSON.parse(d); // e.target.getAttribute("data-episode");
            getReq(`https://api4.shinden.pl/xhr/${data.online_id}/player_load?auth=${key}`);
            countdown([data, key], 5);
        }

        // select new button, hide old selected buttons
        function setUI(btn) {
            window.flutter_inappwebview.callHandler('mode_clear');
            btn.classList.add('selected');
            document.querySelectorAll('.button.selected').forEach(el => {
                el.innerHTML = (el.dataset.old != null ? 'Pokaż' : "Wybierz <i class='fa fa-chevron-down'></i>");
                if(el != btn) el.classList.remove('selected');
                el.nextSibling.classList.remove('show');
            });
            clearTimeout(timer); // prevents unnecessary requests when user change source
            container.innerHTML = ''; // clear countdown container
        }
    }

    let container, timer = null;
    function countdown(array, time) {
        container.innerHTML = `<h2 class='countdown'>${time > 0 ? `Odliczanie: ${time}`: "Ładowanie playera"}</h2>`;
        if(time <= 0) {
            clearTimeout(timer);
            getReq(`https://api4.shinden.pl/xhr/${array[0].online_id}/player_show?auth=${array[1]}&width=${document.body.offsetWidth}`, replace);
            return;
        }
        timer = setInterval(() => countdown(array, --time), 1000);
    }

    // Set player with small changes
    async function replace(player) {
        // Get link to video
        let playerDOM = new DOMParser().parseFromString(player, 'text/html');
        let link = playerDOM.getElementsByTagName('iframe')[0] || playerDOM.querySelector('.button-player');
        link = link.src || link.href;
        //console.log(link); 
        
        // Open this link
        localStorage.setItem('show_info', 'true');
        if(link.includes('mp4upload')) link = link.replace("embed-", "");
        if(link.includes('yourupload')) link = link.replace("embed", "watch");
        location.assign(link);

        // if(handledSites.find(el => link.includes(el))) {
        //     return;
        // }
        
        // container.innerHTML = player;

        // let iframe = container.getElementsByTagName("iframe")[0];
        // iframe.setAttribute("style", 'width: 100%; height: 100%; aspect-ratio: 12/8; border: none !important; display: block; margin: 0 auto;');
        
        // // fix wrong scale after fullscreen exit
        // document.querySelector('meta[name="viewport"]').content = 'initial-scale=1, maximum-scale=1, minimum-scale=1, width=device-width';
    }
})();