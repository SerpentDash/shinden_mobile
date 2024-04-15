(function () {
    'use strict';

    new MutationObserver(function () {
        if (document.readyState === "complete") this.disconnect();
        // TODO: Test this.
        // Get next element to make sure our target (previous element) is fully loaded
        if (document.querySelector('.player-navigator-section')) {
            this.disconnect();
            setTimeout(() => overrideButtons(document.documentElement.textContent), 0);
            container = document.getElementsByClassName("player-online box")[0];
        }
    }).observe(document, { childList: true, subtree: true });

    async function getReq(url, callback = null) {
        await fetch(url, { credentials: 'include' }).then(async r => callback && callback(await r.text()));
    }

    const providers = [
        { name: 'cda', handler: 'open_cda' },
        { name: 'gdrive', handler: 'open_gdrive' },
        { name: 'drive.google', handler: 'open_gdrive' },
        { name: 'sibnet', handler: 'open_sibnet' },
        { name: 'streamtape', handler: 'open_streamtape' },
        { name: 'mp4upload', handler: 'open_mp4upload' },
        { name: 'dailymotion', handler: 'open_dailymotion' },
        { name: 'supervideo', handler: 'open_supervideo' },
        { name: 'dood', handler: 'open_dood' },
        { name: 'vk', handler: 'open_vk' },
        { name: 'okru', handler: 'open_okru' },
        { name: 'yourupload', handler: 'open_yourupload' },
        { name: 'aparat', handler: 'open_aparat' }, // aka wolfstream
        { name: 'default', handler: 'open_default' }, // aka filemoon
        { name: 'mega', handler: 'open_in_browser' },
    ]; // 'streamsb', 'hqq'

    function overrideButtons(source) {
        const key = source.split(/_Storage\.basic = '/)[1].split("';")[0];
        let elements = document.getElementsByClassName("ep-buttons");
        let clone, data;

        // template for dropdown
        let dropdown = document.createElement('div');
        dropdown.classList.add('dropdown');
        dropdown.innerHTML = `
            <a class="button">Wybierz<i class='fa fa-chevron-down'></i></a><div class="dropdown-content">
            <a class='button'>Stream</a><a class='button'>Pobierz</a></div>`;

        // clone template and assign correct values / events
        for (let i = 1; i < elements.length; i++) {
            clone = elements[i].firstChild.cloneNode(true);
            elements[i].replaceChild(clone, elements[i].firstChild);
            let data = clone.getAttribute("data-episode");

            let providerName = elements[i].parentElement.firstElementChild.innerText.toLowerCase();

            if (providers.some(provider => provider.name === providerName)) {
                let _dropdown = dropdown.cloneNode(true);
                clone.after(_dropdown);
                clone.remove();

                _dropdown.children[0].onclick = (e) => e.target.nextSibling.classList.add('show');
                _dropdown.children[1].children[0].onclick = () => handleClick(i, data, 'stream', _dropdown.children[1].children[0].innerText);
                _dropdown.children[1].children[1].onclick = () => handleClick(i, data, 'download', _dropdown.children[1].children[1].innerText);

                switch (providerName) {
                    /* case 'supervideo': // only stream
                        _dropdown.children[1].children[1].remove();
                        break; */
                    case 'mega': // open in official mega app (or browser)
                        _dropdown.children[1].children[1].innerText = 'Mega APP';
                    case 'mp4upload': // only download
                    case 'yourupload':
                    case 'dood':
                        _dropdown.children[1].children[0].remove();

                        _dropdown.children[1].children[0].onclick = () => handleClick(i, data, 'download', _dropdown.children[1].children[0].innerText);
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
                    selectButton(normalBtn);
                    getPlayer(data);
                }
                clone.after(normalBtn);
                clone.remove();
            }
        };

        // Set correct onclick to button
        const handleClick = (i, data, mode, buttonText) => {
            let btn = elements[i].querySelector('.button');
            selectButton(btn);
            getPlayer(data);
            btn.innerText = buttonText;
            window.flutter_inappwebview.callHandler('mode_set', (current_mode = mode));
        };

        function getPlayer(d) {
            data = JSON.parse(d);
            getReq(`https://api4.shinden.pl/xhr/${data.online_id}/player_load?auth=${key}`);
            countdown([data, key], 5);
        }
    }

    // select new button, hide old selected buttons
    function selectButton(btn) {
        //window.flutter_inappwebview.callHandler('mode_clear');
        btn?.classList.add('selected');
        document.querySelectorAll('.button.selected').forEach(el => {
            el.innerHTML = (el.dataset.old != null ? 'Pokaż' : "Wybierz <i class='fa fa-chevron-down'></i>");
            if (el != btn) el.classList.remove('selected');
            el.nextSibling.classList.remove('show');
        });
    }

    let container, timer;
    function countdown(array, time) {
        clearInterval(timer); // clear timer to prevent multiple requests when user change source
        container.innerHTML = `<h2 class='countdown'>${time > 0 ? `Odliczanie: ${time}` : "Ładowanie playera"}</h2>`;
        if (time <= 0) {
            getReq(`https://api4.shinden.pl/xhr/${array[0].online_id}/player_show?auth=${array[1]}&width=${document.body.offsetWidth}`, replace);
            return;
        }
        timer = setInterval(() => countdown(array, --time), 1000);
    }

    let current_mode = '';
    // Set player with small changes
    async function replace(player) {
        // Get link to video
        let playerDOM = new DOMParser().parseFromString(player, 'text/html');
        let link = playerDOM.getElementsByTagName('iframe')[0] || playerDOM.querySelector('.button-player');
        link = link.src || link.href;
        console.log(link);

        // Fix link
        if (link.includes('mp4upload')) link = link.replace("embed-", "");
        if (link.includes('yourupload')) link = link.replace("embed", "watch");

        // Pass url to supported handlers
        if (current_mode != '') {
            for (const provider of providers) {
                if (link.includes(provider.name)) {
                    window.flutter_inappwebview.callHandler(provider.handler, link);
                    setTimeout(() => {
                        selectButton(null);
                        container.innerHTML = "";
                    }, 1000);
                    return;
                }
            }
        }

        location.assign(link);
    }
})();