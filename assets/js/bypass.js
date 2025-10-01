(function () {
    'use strict';

    new MutationObserver(function () {
        if (document.readyState === "complete") this.disconnect();

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

    // Providers allowed to use Seal app
    const sealAllowlist = ['lulustream'];

    function overrideButtons(source) {
        const key = source.split(/_Storage\.basic = '/)[1].split("';")[0];
        const elements = document.getElementsByClassName("ep-buttons");

        // Set correct onclick to button
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

        // Helper to create dropdown with specified buttons
        const createDropdown = (buttonTexts) => {
            const dropdown = document.createElement('div');
            dropdown.classList.add('dropdown');
            const content = buttonTexts.map(text => `<a class='button'>${text}</a>`).join('');
            dropdown.innerHTML = `<a class="button">Wybierz<i class='fa fa-chevron-down'></i></a><div class="dropdown-content">${content}</div>`;
            dropdown.children[0].onclick = (e) => e.target.nextSibling.classList.add('show');
            return dropdown;
        };

        // clone template and assign correct values / events
        for (let i = 1; i < elements.length; i++) {
            const clone = elements[i].firstChild.cloneNode(true);
            elements[i].replaceChild(clone, elements[i].firstChild);
            const data = clone.getAttribute("data-episode");
            const providerName = elements[i].parentElement.firstElementChild.innerText.toLowerCase();

            // Determine whether this provider is allowed to use Seal
            const showSeal = sealAllowlist.some(v => providerName.includes(v));

            let newElement;
            if (showSeal) {
                // For Seal-allowed providers show ONLY 'Pokaż' and 'Seal'
                newElement = createDropdown(['Pokaż', 'Seal']);
                const buttons = newElement.children[1].children;
                buttons[0].onclick = () => handleClick(i, data, '', buttons[0].innerText);
                buttons[1].onclick = () => handleClick(i, data, 'seal', buttons[1].innerText);
            } else if (providers.some(provider => providerName === provider)) {
                // For supported providers, build dropdown with stream/download/show
                newElement = createDropdown(['Stream', 'Pobierz', 'Pokaż']);
                const buttons = newElement.children[1].children;
                buttons[0].onclick = () => handleClick(i, data, 'stream', buttons[0].innerText);
                buttons[1].onclick = () => handleClick(i, data, 'download', buttons[1].innerText);
                buttons[2].onclick = () => handleClick(i, data, '', buttons[2].innerText);
            } else {
                // For unsupported providers, show default 'Pokaż' button (will open external browser app)
                newElement = document.createElement('a');
                newElement.innerText = 'Pokaż';
                newElement.classList.add('button');
                newElement.dataset.old = '';
                newElement.onclick = () => {
                    selectButton(newElement);
                    getPlayer(data);
                };
            }

            clone.after(newElement);
            clone.remove();
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

        // Handle link based on mode - empty mode opens system browser
        if (current_mode === '') {
            window.flutter_inappwebview.callHandler('open_browser', link);
        } else if (current_mode === 'seal') {
            // Special mode for Seal app
            window.flutter_inappwebview.callHandler('handle_link', link, 'seal');
        } else {
            window.flutter_inappwebview.callHandler('handle_link', link, current_mode);
        }
        
        // Clean up UI
        setTimeout(() => {
            selectButton(null);
            container.innerHTML = "";
        }, 1000);
    }
})();