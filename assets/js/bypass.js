(function () {
    'use strict';

    if (window.__shinden_bypass) return;
    window.__shinden_bypass = true;

    function initBypass() {
        if (document.querySelector('.ep-buttons .dropdown')) return;

        overrideButtons(document.documentElement.textContent);
        container = document.getElementsByClassName("player-online box")[0];
    }

    if (document.querySelector('.player-navigator-section')) {
        setTimeout(initBypass, 0);
    } else {
        new MutationObserver(function () {
            if (document.readyState === "complete") this.disconnect();
            if (document.querySelector('.player-navigator-section')) {
                this.disconnect();
                setTimeout(initBypass, 0);
            }
        }).observe(document, { childList: true, subtree: true });
    }

    document.addEventListener('click', closeMenus);

    function closeMenus() {
        document.querySelectorAll('.dropdown-content.show').forEach(el => el.classList.remove('show'));
        document.querySelectorAll('.download-group.open').forEach(g => g.classList.remove('open'));
    }

    async function getReq(url, callback = null) {
        await fetch(url, { credentials: 'include' }).then(async r => callback && callback(await r.text()));
    }

    // Names of providers on website
    const providers = [
        'cda',
        'gdrive',
        'sibnet',
        'streamtape',
        'mp4upload',
        'dailymotion',
        'supervideo',
        'dood',
        'vk',
        'okru',
        'yourupload',
        'aparat',
        'mega', // maybe will check in future
        'lycoriscafe',
        'pixeldrain',
        'rumble',
        'streamwish',
        'filemoon',
        'vidhide',
        'savefiles',
        'streamhls',
        'bigwarp',
        'default',
        'streamup'
    ]; // 'streamsb', 'hqq'

    function overrideButtons(source) {
        const key = source.split(/_Storage\.basic = '/)[1].split("';")[0];
        const elements = document.getElementsByClassName("ep-buttons");

        const handleClick = (i, data, mode, buttonText) => {
            const btn = elements[i].querySelector('.button');
            selectButton(btn);
            getPlayer(data);
            btn.innerText = buttonText;
            current_mode = mode;
        };

        const getPlayer = (d) => {
            const data = JSON.parse(d);
            getReq(`https://api4.shinden.pl/xhr/${data.online_id}/player_load?auth=${key}`);
            countdown([data, key], 5);
        };

        const createDropdown = (innerHtml) => {
            const dropdown = document.createElement('div');
            dropdown.classList.add('dropdown');
            dropdown.innerHTML =
                `<a class="button">Wybierz<i class='fa fa-chevron-down'></i></a>` +
                `<div class="dropdown-content">${innerHtml}</div>`;
            dropdown.addEventListener('click', e => e.stopPropagation());

            const menu = dropdown.children[1];
            dropdown.children[0].onclick = () => {
                const wasOpen = menu.classList.contains('show');
                closeMenus();
                if (!wasOpen) menu.classList.add('show');
            };

            const group = menu.querySelector('.download-group');
            if (group) {
                group.querySelector('[data-toggle="download"]').onclick = () => {
                    group.classList.toggle('open');
                };
            }
            return dropdown;
        };

        for (let i = 1; i < elements.length; i++) {
            const clone = elements[i].firstChild.cloneNode(true);
            elements[i].replaceChild(clone, elements[i].firstChild);
            const data = clone.getAttribute("data-episode");
            const providerName = elements[i].parentElement.firstElementChild.innerText.toLowerCase();

            let newElement;
            if (providers.some(provider => providerName === provider)) {
                newElement = createDropdown(
                    `<a class="button" data-mode="stream">Stream</a>` +
                    `<div class="download-group">` +
                    `<a class="button" data-toggle="download">Pobierz<i class='fa fa-chevron-down'></i></a>` +
                    `<div class="download-submenu">` +
                    `<a class="button" data-mode="download">W aplikacji</a>` +
                    `<a class="button" data-mode="seal">Seal</a>` +
                    `</div></div>` +
                    `<a class="button" data-mode="">Pokaż</a>`
                );
                newElement.querySelectorAll('[data-mode]').forEach(btn => {
                    btn.onclick = () => handleClick(i, data, btn.dataset.mode, btn.innerText);
                });
            } else {
                newElement = createDropdown(`<a class="button">Seal</a><a class="button">Pokaż</a>`);
                const buttons = newElement.children[1].children;
                buttons[0].onclick = () => handleClick(i, data, 'seal', buttons[0].innerText);
                buttons[1].onclick = () => handleClick(i, data, '', buttons[1].innerText);
            }

            clone.after(newElement);
            clone.remove();
        }
    }

    function selectButton(btn) {
        btn?.classList.add('selected');
        document.querySelectorAll('.button.selected').forEach(el => {
            el.innerHTML = (el.dataset.old != null ? 'Pokaż' : "Wybierz <i class='fa fa-chevron-down'></i>");
            if (el != btn) el.classList.remove('selected');
        });
        closeMenus();
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
    async function replace(player) {
        let playerDOM = new DOMParser().parseFromString(player, 'text/html');
        let link = playerDOM.getElementsByTagName('iframe')[0] || playerDOM.querySelector('.button-player');
        link = link.src || link.href;
        console.log(link);

        if (current_mode === '') {
            window.flutter_inappwebview.callHandler('open_browser', link);
        } else {
            window.flutter_inappwebview.callHandler('handle_link', link, current_mode);
        }

        setTimeout(() => {
            selectButton(null);
            container.innerHTML = "";
        }, 1000);
    }
})();
