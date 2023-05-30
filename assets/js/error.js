setTimeout(() => {
    // Overview: small UI changes to error page + auto check for internet connection then reload
    const sheet = new CSSStyleSheet();
    sheet.replaceSync('body {color: white} h2 {margin-top: 35px} img {display: none}');
    document.adoptedStyleSheets = [sheet];
    
    setInterval(() => navigator.onLine && location.reload(), 3000);
}, 0);