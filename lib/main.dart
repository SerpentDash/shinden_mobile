import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:receive_sharing_intent_plus/receive_sharing_intent_plus.dart';

import 'download_kit.dart';

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
  "ckeditor"
];

String tempUrl = "";
String tempRequest = "";
String tempWebsite = "";

String appLink = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ByteData bytes = await rootBundle.load('assets/css/main.css');
  css = base64Encode(Uint8List.view(bytes.buffer));

  String hostFile = await rootBundle.loadString('assets/host.txt');
  LineSplitter.split(hostFile).forEach((line) => hosts.add(line));

  if (defaultTargetPlatform == TargetPlatform.android) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    await InAppWebViewController.setWebContentsDebuggingEnabled(
        /* kDebugMode */ true);
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
  );

  PullToRefreshController? pullToRefreshController;

  double progress = 0;

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

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
          color: Colors.white, backgroundColor: Colors.black),
      onRefresh: () async => webViewController?.reload(),
    );

    // Opening shared url from outside the app while the app is in the memory
    _textIntent = ReceiveSharingIntentPlus.getTextStream().listen(
      (String value) {
        if (!value.contains("shinden.pl")) return;
        webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(value)));
      },
    );
  }

  @override
  void dispose() {
    _textIntent.cancel();
    super.dispose();
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
              Expanded(
                child: InAppWebView(
                  key: webViewKey,
                  initialUrlRequest:
                      URLRequest(url: WebUri("https://shinden.pl/")),
                  initialSettings: settings,
                  contextMenu: contextMenu,
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) async {
                    webViewController = controller;

                    // Opening shared url from outside the app while the app is closed
                    await ReceiveSharingIntentPlus.getInitialText()
                        .then((String? value) {
                      if (value == null) return;
                      webViewController!.loadUrl(
                        urlRequest: URLRequest(url: WebUri(value)),
                      );
                    });

                    // Utility
                    controller.addJavaScriptHandler(
                        handlerName: 'reload',
                        callback: (args) =>
                            pullToRefreshController?.setEnabled(true));
                    controller.addJavaScriptHandler(
                        handlerName: 'no_reload',
                        callback: (args) =>
                            pullToRefreshController?.setEnabled(false));
                    controller.addJavaScriptHandler(
                        handlerName: 'back_button',
                        callback: (args) async => await controller
                            .canGoBack()
                            .then((value) => controller.goBack()));

                    // From players_handler.dart
                    // Add handlers for supported video providers
                    controller.addJavaScriptHandler(
                      handlerName: 'handle_link',
                      callback: (args) =>
                          handleLink(controller, args[0], args[1]),
                    );
                  },
                  onLoadStart: (controller, url) async {
                    pullToRefreshController?.setEnabled(true);
                    tempUrl = url.toString();

                    if (tempUrl.contains("shinden.pl") &&
                        !tempUrl.contains("shinden.pl/animelist")) {
                      // ADD CSS
                      await controller.evaluateJavascript(source: """
                        const sheet = new CSSStyleSheet();
                        sheet.replaceSync(window.atob('$css'));
                        document.adoptedStyleSheets = [sheet]; 
                        """);

                      // ADD JS
                      await controller.injectJavascriptFileFromAsset(
                          assetFilePath: "assets/js/main.js");

                      // ADD BYPASS JS
                      if (tempUrl.contains("shinden.pl/episode") ||
                          tempUrl.contains("shinden.pl/epek")) {
                        await controller.injectJavascriptFileFromAsset(
                            assetFilePath: "assets/js/bypass.js");
                      }
                    }
                  },
                  shouldInterceptRequest: (controller, request) async {
                    tempRequest = request.url.toString();

                    // Adblock
                    for (var i = 0; i < hosts.length; i++) {
                      if (tempRequest.contains(hosts.elementAt(i))) {
                        NavigationActionPolicy.CANCEL;
                        return WebResourceResponse();
                      }
                    }

                    // White list
                    if (!urlWhiteList.any((el) => tempRequest.contains(el))) {
                      NavigationActionPolicy.CANCEL;
                      return WebResourceResponse();
                    }

                    //log("$tempUrl, $tempRequest");
                    return null;
                  },
                  /* onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                        resources: request.resources,
                        action: PermissionResponseAction.GRANT);
                  }, */
                  onLoadStop: (controller, url) async {
                    pullToRefreshController?.endRefreshing();
                  },
                  onReceivedError: (controller, request, error) async {
                    pullToRefreshController?.endRefreshing();
                    if (error.type.toString() != "UNKNOWN" ||
                        request.isForMainFrame == true) {
                      await controller.injectJavascriptFileFromAsset(
                          assetFilePath: 'assets/js/error.js');
                    }
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
          content: const Text('Czy na pewno chcesz wyjść?',
              style: TextStyle(color: Colors.white)),
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
