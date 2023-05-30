(function() {
    'use strict'; 

    // Watch list 2.0
    function animeWatchList() {
        // create new button (for anime watch list)
        let btn = document.createElement('button');
        btn.classList.add('btnWL')
        btn.innerHTML = "<i class='fa fa-list-ul'></i>";
        document.querySelector('.top-bar--user').append(btn);

        btn.onclick = async () => {
            let target = document.getElementById('la');
            btn.classList.toggle('active');

            // Click list button to hide watch list
            if(!btn.classList.contains('active')) {
                target.classList.remove('show');
                document.body.classList.remove('block_scroll');
                window.flutter_inappwebview.callHandler('reload');
                window.onhashchange = null;
                
                // TODO: FIX THIS BS..
                // Simple throttling, prevents spamming / multiple fetch requests
                setTimeout(() => btn.removeAttribute('disabled'), 1000);
                btn.setAttribute('disabled', '');
                return;
            }

            // Get watch list and parse to DOM Document
            await fetch('https://shinden.pl/api/user/to-watch', {headers: {'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'}})
            .then(res => res.text())
            .then(text => {
                let output = new DOMParser().parseFromString(text, "text/html");

                // Fix class names conventions to prevent css naming issues
                output.querySelector('.l-container-primary').className = 'container';
                output.querySelector('.l-main-contantainer').className = 'contantainer';

                // Remove useless scripts and styles
                output.querySelectorAll('script').forEach(el => el.remove());
                output.querySelectorAll('style').forEach(el => el.remove());

                // Show imgs in high res
                const images = output.getElementsByTagName("img");
                for(let j=0; j < images.length; j++)
                    images[j].src = images[j].src.replace("36x48", "225x350");

                // Add border
                let border = document.createElement('div');
                border.innerHTML = "<div class='border-inner'></div>";
                border.classList.add('border-outer');
                output.getElementsByClassName('api-iframe')[0].prepend(border);
                
                // Prepare for sorting and add episode counters
                const sortContidions = ['Film', 'Specjalny'];
                
                let counter = document.createElement('a');
                counter.classList.add('counter');
                let counterValue = 0;

                const media_items = output.getElementsByClassName('media-item');
                
                [...media_items].forEach(item => {
                    if(item.classList.contains('open-in-full-page')) return;
                    let episode_list = item.getElementsByClassName('episode-list')[0];

                    counterValue = episode_list.firstElementChild.title.match(/\d+/g).length; // count numbers occurrence in string

                    item.dataset.sort = counterValue + (sortContidions.some(el => item.getElementsByClassName('info-line')[0].innerText.includes(el)) ? 10000 : 0);
                    counter.innerText = counterValue;

                    item.append(counter.cloneNode(true));
                    
                    item.children[0].href = episode_list.children[1].href;
                    item.children[1].innerText = item.children[1].title;
                });

                // Sort list
                let parent = output.getElementsByClassName('wait-to-attention')[0];
                [...media_items].sort((a, b) => 
                    parseInt(a.dataset.sort) - parseInt(b.dataset.sort) || a.innerText.toLowerCase().localeCompare(b.innerText.toLowerCase())
                ).forEach(item => parent.appendChild(item));

                // Add space between 'Seriale' and 'Filmy'
                let firstFilm = [...media_items].find(el => el.dataset.sort >= 10000); // find first Film element
                if (firstFilm) {
                    let spacing = document.createElement('hr');
                    spacing.classList.add('spacing');
                    parent.insertBefore(spacing, firstFilm);
                }

                // TODO: CHECK THIS IF ITS ACTUALLY NEEDED
                // Insert new list
                [...output.body.children].forEach(el => target.appendChild(el));
                
                // Prevent scrolling background and show list
                document.body.classList.add('block_scroll');
                target.style.display = 'block';
                setTimeout(() => target.classList.add('show'), 100); // this will smoothly start opacity transition

                // End 'opacity' transition then disable list element
                target.addEventListener('transitionend', () => {
                    if(!target.classList.contains('show')) {
                        target.style.display = 'none';
                        target.innerHTML = "";
                    }
                });

                setTimeout(() => {
                    // Prevent accidental reloading in flutter app
                    window.flutter_inappwebview.callHandler('noReload');
                        
                    // Let user use back button in flutter app to close list
                    location.hash = 'list';
                    setTimeout(() => window.onhashchange = () => btn.click(), 0);
                }, 0);
            }).catch(error => {
                btn.classList.remove('active');
                console.log(error);
                return;
            });
        }
    }
    
    // Nowosci
    function slideResize() {
        var items = document.getElementsByClassName("slide");
        for(var i = 0; i < items.length; i++){
            var temp = items[i].style.backgroundImage;
            items[i].style.backgroundImage = temp.slice(0, -6) + 'h' + temp.slice(-6);
            items[i].getElementsByTagName('section')[0].innerText = items[i].getElementsByTagName('section')[0]?.innerText.trim();
        };
    }

    // Ostatnie sezony
    function seasonTitle() {
        var items = document.getElementsByClassName("img media-title-cover season-tile");
        for (var i = 0; i < items.length; i++)
        if (!items[i].style.backgroundImage.includes("placeholder"))
            items[i].style.backgroundImage = items[i].style.backgroundImage.replace("225x350", "genuine");
    }

    // Okladka tytulu
    function titleCover() {
        var item = document.getElementsByClassName("title-cover")[0].getElementsByTagName("img")[0];
        item.src = item.parentElement.href;
    }

    // Postacie / VA
    function charactersImages() {
        var items = document.getElementsByClassName("ch-st-item");
        for(var i=0; i < items.length; i++) {
            var item = items[i].getElementsByTagName("span");
            for(var j=0; j < item.length; j++) {
                var temp = item[j].getElementsByClassName("img")[0].getElementsByTagName("img")[0];
                temp.src = temp.src.replace("36x48", "225x350");
                temp.parentNode.style.pointerEvents = "none";
            }
        };
    };

    // Obsada Anime
    function castImages() {
        var items = document.getElementsByClassName("person-character-item");
        for(var i=0; i < items.length; i++) {
            var temp = items[i].getElementsByClassName("person person-one")[0].getElementsByClassName("character")[0];
            temp.src = temp.src.replace("36x48", "225x350");
            temp.style.pointerEvents = "none";
        };
    };

    // Lista POWIAZANE SERIE
    function relatedSeriesImages() {
        var items = document.getElementsByClassName("relation_t2t");
        items[0].parentNode.classList.remove("box-scrollable-x");
        for(var i = 0; i < items.length; i++) {
            var temp = items[i].getElementsByTagName("img")[0];
            temp.src = temp.src.replace("100x100", "225x350");
        };
    };

    // Lista REKOMENDACJE
    function recommendationsImages() {
        var items = document.getElementsByClassName("page-content page-anime-recommendations")[0].getElementsByClassName("media media-item");
        for(var i=0; i < items.length; i++) {
            var temp = items[i].getElementsByTagName("img")[0];
            temp.src = temp.src.replace("100x100", "225x350");
        };
    };

    // Lista Anime / Manga
    function animeMangaImages() {
        var items = document.getElementsByClassName("anime-list")[0].getElementsByTagName("article")[0].getElementsByClassName("div-row");
        for(var i=0; i < items.length; i++) {
            var temp = items[i].getElementsByTagName("a")[0];
            temp.style.backgroundImage = temp.style.backgroundImage.replace("100x100", "genuine");
        };
    };

    // Fix User account button behaviour
    function topButtonEvent() {
        // remove old event by replacing old element with clone without events
        let old_element = document.getElementsByClassName('top-button top-button--user')[0];
        let new_element = old_element.cloneNode(true);
        old_element.parentNode.replaceChild(new_element, old_element);
        
        // setup topbar (disable old functionality)
        let target = document.getElementsByClassName('top-bar--nav-user')[0];
        target.classList.remove('active');
        target.style.display = 'none';

        // add new working event
        new_element.onclick = () => 
            target.style.display == 'none' ? target.style.display = 'block' : target.style.display = 'none';
    }

    // Fix bad img urls on main page
    function fixBadImg() {
        const toChange = {
          'unknownh': 'unknown',
          'hjpeg': 'jpeg',
          'h.png': '.png',
          'h.jpg': '.jpg',
        };
      
        document.querySelectorAll('.newSlider .slide').forEach(slide => {
            Object.entries(toChange).forEach(([search, replace]) => {
                if (slide.style.backgroundImage.includes(search)) {
                    slide.style.backgroundImage = slide.style.backgroundImage.replace(search, replace);
                }
            });
        });
      }

    function hideEmptyNameTranslations() {
        let parent = document.querySelector('.episode-other-titles');
        let tbody = parent.querySelector('tbody');
        if(tbody.childElementCount === 0) parent.classList.add('hide');
    }

    function resizableCoocreate() {
        let parent = document.querySelector('.title-coocreate');
        parent.children[0].style.border = 'white 1px solid';
        parent.children[0].style.borderRadius = '25px';
        parent.children[0].onclick = () => parent.children[1].classList.toggle('hide');
        parent.children[1].classList.add('hide');
    }

    // add shortcut to easilly set chapter as watched
    function addWwatchedButtonShortcut() {
        let clone = document.querySelector('[data-by="1"]').cloneNode(true);
        clone.classList.remove("button");
        clone.onclick = function() { this.style.pointerEvents = 'none'; this.style.filter = 'brightness(.5)' }
        document.getElementsByClassName('pull-right')[0].prepend(clone);
    }

    // Sort table with videos (by video provider name and by date)
    function sortTable() {
        const parent = document.querySelector('.data-view-table-strips.data-view-table-big.data-view-hover:not(.data-view-table-episodes) tbody');
        const t = (tr, i) => tr.cells[i].textContent.trim().toLowerCase();
        
        [...parent.querySelectorAll('tr')]
            .sort((a, b) => t(a, 0)?.localeCompare(t(b, 0)) || t(b, 4)?.localeCompare(t(a, 4)))
            .forEach(tr => parent.append(tr));
    }

    function fixSearchModal() {
        // Block scroll when clicked on search toggle button
        document.getElementsByClassName('search-toggle')[0].addEventListener("click", () => {
            document.body.classList.add('block_scroll');
            window.flutter_inappwebview.callHandler('noReload'); // prevent accidental reload on swipe down
        });

        // hide modal when clicked outside of modal body 
        let modal = document.getElementsByClassName('search-modal')[0];
        modal.children[0].children[0].remove(); // remove close button
        modal.onclick = (event) => {
            if(event.target.className == 'search-modal active') {
                modal.classList.remove('active');
                document.body.classList.remove('block_scroll');
                window.flutter_inappwebview.callHandler('reload');
            }
        }
    }

    // fix displayed amount of items on smaller screens 
    function reloadOWL() {
        window.onload = () => {
            $('.current-season-tiles').trigger("destroy.owl.carousel");
            $('.owl-carousel').owlCarousel({ items: 3, loop: true, autoplay: true});
        }
    }

    /* 
    function changeImagesSizes(parent, container, before) {
        var images = parent;
        for(var i=0; i < images.length; i++){
            var temp = images[i].getElementsByTagName(container)[0];
            container == "a" ? temp.style.backgroundImage = temp.style.backgroundImage.replace(before, "225x350") : temp.src = temp.src.replace(before, "225x350");
        };
    } */

    // Run corresponding function when certain element exists in DOM
    let items = {
        '.top-bar--user': animeWatchList,
        '.top-button--user': topButtonEvent,
        '.slide': slideResize,
        '.img media-title-cover season-tile': seasonTitle,
        '.episode-other-titles tbody': hideEmptyNameTranslations,
        '.current-season-tiles': reloadOWL,
        '.search-modal': fixSearchModal,
        '.title-cover': titleCover,
        '.ch-st-list': charactersImages,
        '.person-character-item': castImages,
        '.relation_t2t': relatedSeriesImages,
        '.page-anime-recommendations': recommendationsImages,
        '.div-row': animeMangaImages,
        '.newSlider': fixBadImg,
        '.data-view-table-strips:not(.data-view-table-episodes)': sortTable,
        '.title-coocreate': resizableCoocreate,
        '[data-by="1"]':addWwatchedButtonShortcut
    };

    Object.entries(items).forEach(([selector, callback]) => {
        waitForElement(selector).then(() => setTimeout(callback, 0));
    });

    function waitForElement(selector) {
        return new Promise(resolve => {
            new MutationObserver((mutations, observer) => {
                if (document.readyState === "complete") observer.disconnect();
                mutations
                    .flatMap(mutation => [...mutation.addedNodes])
                    .filter(node => node.matches && node.matches(selector))
                    .forEach(target => {
                        resolve(target);
                        observer.disconnect();
                    });
            }).observe(document, { childList: true, subtree: true });
        });
    }
})();