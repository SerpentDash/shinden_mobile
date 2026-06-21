import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:android_intent_plus/android_intent.dart';

import 'download_kit.dart';
import 'video_server.dart';
import 'webview_debug.dart';

String css = "";
List<String> hosts = [];

final urlWhiteList = [
  "shinden",
  "gravatar",
  "imgur",
  "discordapp",
  "gstatic",
  "googleapis",
  "cloudflare",
  "jsdelivr",
  "spolecznosci",
  "youtube",
  "ckeditor",
  "google.com/recaptcha"
];

String tempUrl = "";
String tempRequest = "";

// add styling and features only to shinden.pl
bool injectable(String url) =>
    url.contains('shinden.pl') && !url.contains('shinden.pl/animelist');

String cssInjectionSource() => """
(function(){
  if(location.hostname.indexOf('shinden.pl')===-1||location.pathname.indexOf('/animelist')!==-1)return;
  var s=new CSSStyleSheet();s.replaceSync(window.atob('$css'));document.adoptedStyleSheets=[s];
})();
""";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ByteData bytes = await rootBundle.load('assets/css/main.css');
  css = base64Encode(Uint8List.view(bytes.buffer));

  String hostFile = await rootBundle.loadString('assets/host.txt');
  LineSplitter.split(hostFile).forEach((line) => hosts.add(line));

  if (defaultTargetPlatform == TargetPlatform.android) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = kDebugMode;
    await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  }

  runApp(MaterialApp(
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xff181818),
          secondary: const Color(0xff252525),
        ),
        useMaterial3: true,
      ),
      home: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final GlobalKey webViewKey = GlobalKey();

  InAppWebViewController? webViewController;
  InAppWebViewSettings settings = InAppWebViewSettings(
    javaScriptCanOpenWindowsAutomatically: false,
    useShouldInterceptRequest: true,
    transparentBackground: true,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    supportZoom: false,
    useOnRenderProcessGone: true,
    useShouldInterceptFetchRequest: true,
  );

  PullToRefreshController? pullToRefreshController;

  // Get url from share intent
  late StreamSubscription _textIntent;

  // Allow users to copy links to clipboard
  // By default, webview won't show context menu on long pressing link elements
  late ContextMenu contextMenu = ContextMenu(
    onCreateContextMenu: (hitTestResult) async {
      if (hitTestResult.type != InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE) return;

      final snackBar = SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(hitTestResult.extra!)),
            SnackBarAction(
              label: 'Copy to clipboard',
              backgroundColor: const Color(0xFF404040),
              onPressed: () => Clipboard.setData(
                ClipboardData(text: hitTestResult.extra!),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    },
  );

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: Colors.white, backgroundColor: Colors.black),
      onRefresh: () async => webViewController?.reload(),
    );

    // Opening shared url from outside the app while the app is in the memory
    _textIntent = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isEmpty) return;
        String sharedValue = value.first.path;
        if (!sharedValue.contains("shinden.pl")) return;
        webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(sharedValue)));
      },
    );
  }

  @override
  void dispose() {
    _textIntent.cancel();
    VideoServer().stop();
    super.dispose();
  }

  Future<void> injectCss(InAppWebViewController controller, String url) async {
    if (!injectable(url)) return;
    await controller.evaluateJavascript(source: cssInjectionSource());
  }

  Future<void> injectJs(InAppWebViewController controller, String url, {bool retry = false}) async {
    if (!injectable(url)) return;

    if (retry) {
      final done = await controller.evaluateJavascript(source: 'window.__shinden_main === true');
      if (done == true || done == 'true') return;
    } else {
      // Guard preventing multiple injections of the same file
      await controller.evaluateJavascript(source: 'window.__shinden_main = false; window.__shinden_bypass = false;');
    }

    await controller.injectJavascriptFileFromAsset(assetFilePath: 'assets/js/main.js');
    if (url.contains('shinden.pl/episode') || url.contains('shinden.pl/epek')) {
      await controller.injectJavascriptFileFromAsset(assetFilePath: 'assets/js/bypass.js');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: onBack,
      child: Scaffold(
        backgroundColor: const Color(0xff181818),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              if (kDebugMode /* false */) // webview console log for debug version
                ValueListenableBuilder<List<String>>(
                  valueListenable: WebViewDebug.events,
                  builder: (context, events, _) {
                    if (events.isEmpty) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 110),
                      color: const Color(0xCC000000),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: Text(
                          events.join('\n'),
                          style: const TextStyle(color: Color(0xFF7CFC7C), fontSize: 10, height: 1.2),
                        ),
                      ),
                    );
                  },
                ),
              Expanded(
                child: InAppWebView(
                  key: webViewKey,
                  initialUrlRequest: URLRequest(url: WebUri("https://shinden.pl")),
                  initialSettings: settings,
                  initialUserScripts: UnmodifiableListView([
                    UserScript(
                      source: cssInjectionSource(),
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: true,
                    ),
                  ]),
                  contextMenu: contextMenu,
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) async {
                    webViewController = controller;

                    // Opening shared url from outside the app while the app is closed
                    await ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
                      if (value.isEmpty) return;
                      String sharedValue = value.first.path;
                      if (!sharedValue.contains("shinden.pl")) return;
                      webViewController!.loadUrl(
                        urlRequest: URLRequest(url: WebUri(sharedValue)),
                      );
                    });

                    // Utility
                    controller.addJavaScriptHandler(handlerName: 'reload', callback: (args) => pullToRefreshController?.setEnabled(true));
                    controller.addJavaScriptHandler(handlerName: 'no_reload', callback: (args) => pullToRefreshController?.setEnabled(false));

                    // From players_handler.dart
                    // Add handlers for supported video providers
                    controller.addJavaScriptHandler(
                      handlerName: 'handle_link',
                      callback: (args) => handleLink(controller, args[0], args[1], context),
                    );

                    // Add handler for opening in system browser
                    controller.addJavaScriptHandler(
                      handlerName: 'open_browser',
                      callback: (args) async {
                        await AndroidIntent(
                          action: 'action_view',
                          data: args[0],
                        ).launch();
                      },
                    );
                  },
                  onLoadStart: (controller, url) async {
                    pullToRefreshController?.setEnabled(true);
                    tempUrl = url.toString();
                    WebViewDebug.log('LOAD', 'start $tempUrl');
                    if (injectable(tempUrl)) {
                      Future.microtask(() async {
                        await injectCss(controller, tempUrl);
                        await injectJs(controller, tempUrl);
                      });
                    }
                  },
                  shouldInterceptRequest: (controller, request) async {
                    tempRequest = request.url.toString();

                    // Skip intercept for same origin requests
                    if (tempRequest.contains("shinden.pl")) {
                      return null;
                    }

                    // White list
                    if (!urlWhiteList.any((el) => tempRequest.contains(el))) {
                      WebViewDebug.log('BLOCK', tempRequest);
                      return WebResourceResponse(data: Uint8List(0));
                    }

                    // Adblock
                    for (var i = 0; i < hosts.length; i++) {
                      if (tempRequest.contains(hosts.elementAt(i))) {
                        WebViewDebug.log('BLOCK', tempRequest);
                        return WebResourceResponse(data: Uint8List(0));
                      }
                    }

                    return null;
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController?.endRefreshing();
                    tempUrl = url.toString();
                    WebViewDebug.log('LOAD', 'stop $tempUrl');
                    await injectJs(controller, tempUrl, retry: true);
                  },
                  onReceivedError: (controller, request, error) async {
                    pullToRefreshController?.endRefreshing();
                    WebViewDebug.log('ERROR', '${error.type} mainFrame=${request.isForMainFrame} ${request.url}');

                    if (request.isForMainFrame != true) return;

                    await controller.injectJavascriptFileFromAsset(assetFilePath: 'assets/js/error.js');
                  },
                  onProgressChanged: (controller, progress) {
                    if (progress == 100) {
                      pullToRefreshController?.endRefreshing();
                    }
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    if (kDebugMode) print(consoleMessage);
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void onBack(_) async {
    await webViewController!.canGoBack().then((value) async {
      if (value) {
        webViewController!.goBack();
        return false;
      }
      return await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xff181818),
          content: const Text('Czy na pewno chcesz wyjść?', style: TextStyle(color: Colors.white)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // close dialog
              child: const Text('Nie', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => exit(0),
              child: const Text('Tak', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    });
  }
}
