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
        'default'
    ]; // 'streamsb', 'hqq'

    // Providers allowed to use Seal app
    const sealAllowlist = ['lulustream'];

    function overrideButtons(source) {
        const key = source.split(/_Storage\.basic = '/)[1].split("';")[0];
        let elements = document.getElementsByClassName("ep-buttons");
        let clone, data;

        // template for dropdown
        // The Seal button will be added conditionally per-provider below.
        let dropdown = document.createElement('div');
        dropdown.classList.add('dropdown');
        dropdown.innerHTML = `
            <a class="button">Wybierz<i class='fa fa-chevron-down'></i></a><div class="dropdown-content">
            <a class='button'>Pokaż</a></div>`;

        // clone template and assign correct values / events
        for (let i = 1; i < elements.length; i++) {
            clone = elements[i].firstChild.cloneNode(true);
            elements[i].replaceChild(clone, elements[i].firstChild);
            let data = clone.getAttribute("data-episode");

            let providerName = elements[i].parentElement.firstElementChild.innerText.toLowerCase();

            // Determine whether this provider is allowed to use Seal
            const showSeal = sealAllowlist.some(v => providerName.includes(v));

            if (showSeal) {
                // For Seal-allowed providers show ONLY 'Pokaż' and 'Seal'
                let _dropdown = document.createElement('div');
                _dropdown.classList.add('dropdown');
                _dropdown.innerHTML = `
                    <a class="button">Wybierz<i class='fa fa-chevron-down'></i></a><div class="dropdown-content">
                    <a class='button'>Pokaż</a><a class='button'>Seal</a></div>`;

                clone.after(_dropdown);
                clone.remove();

                _dropdown.children[0].onclick = (e) => e.target.nextSibling.classList.add('show');
                const buttons = _dropdown.children[1].children;
                // Pokaż
                if (buttons[0]) buttons[0].onclick = () => handleClick(i, data, '', buttons[0].innerText);
                // Seal
                if (buttons[1]) buttons[1].onclick = () => handleClick(i, data, 'seal', buttons[1].innerText);
            } else if (providers.some(provider => providerName == provider)) {
                // For supported providers, build dropdown with stream/download/show
                let _dropdown = document.createElement('div');
                _dropdown.classList.add('dropdown');

                let inner = `
                    <a class="button">Wybierz<i class='fa fa-chevron-down'></i></a><div class="dropdown-content">
                    <a class='button'>Stream</a><a class='button'>Pobierz</a><a class='button'>Pokaż</a></div>`;

                _dropdown.innerHTML = inner;

                clone.after(_dropdown);
                clone.remove();

                _dropdown.children[0].onclick = (e) => e.target.nextSibling.classList.add('show');
                const buttons = _dropdown.children[1].children;
                // Stream
                if (buttons[0]) buttons[0].onclick = () => handleClick(i, data, 'stream', buttons[0].innerText);
                // Download
                if (buttons[1]) buttons[1].onclick = () => handleClick(i, data, 'download', buttons[1].innerText);
                // Show
                if (buttons[2]) buttons[2].onclick = () => handleClick(i, data, '', buttons[2].innerText);
            } else {
                // For unsupported providers, show minimal dropdown (Pokaż)
                let _dropdown = dropdown.cloneNode(true);

                clone.after(_dropdown);
                clone.remove();

                _dropdown.children[0].onclick = (e) => e.target.nextSibling.classList.add('show');
                const buttons = _dropdown.children[1].children;
                // Pokaż
                if (buttons[0]) buttons[0].onclick = () => handleClick(i, data, '', buttons[0].innerText);
            }
        };

        // Set correct onclick to button
        const handleClick = (i, data, mode, buttonText) => {
            let btn = elements[i].querySelector('.button');
            selectButton(btn);
            getPlayer(data);
            btn.innerText = buttonText;
            current_mode = mode;
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