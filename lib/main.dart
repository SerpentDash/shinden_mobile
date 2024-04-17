// ignore_for_file: curly_braces_in_flow_control_structures, depend_on_referenced_packages

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_session_manager/flutter_session_manager.dart';
import 'package:flutter_web_browser/flutter_web_browser.dart';

import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'dart:math' show Random;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/log.dart';
import 'package:ffmpeg_kit_flutter/session.dart';
import 'package:ffmpeg_kit_flutter/statistics.dart';

import 'package:html/parser.dart';
import 'package:path/path.dart' as p;
import 'package:deep_pick/deep_pick.dart';
import 'package:android_path_provider/android_path_provider.dart';
import 'package:sanitize_filename/sanitize_filename.dart';
import 'package:file_sizes/file_sizes.dart';
import 'package:random_string/random_string.dart';

import 'package:app_links/app_links.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:simple_downloader/simple_downloader.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:native_toast/native_toast.dart';
import 'package:throttling/throttling.dart';
import 'package:android_intent_plus/android_intent.dart';

part 'download_kit.dart';
part 'players_handler.dart';

String css = "";
List<String> hosts = [];

//TODO:
// auto retry download?

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

final _appLinks = AppLinks();
String appLink = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterDownloader.initialize(debug: false, ignoreSsl: true);

  FlutterDownloader.cancelAll();

  SessionManager().destroy();

  ByteData bytes = await rootBundle.load('assets/css/main.css');
  css = base64Encode(Uint8List.view(bytes.buffer));

  String hostFile = await rootBundle.loadString('assets/host.txt');
  LineSplitter.split(hostFile).forEach((line) => hosts.add(line));

  if (defaultTargetPlatform == TargetPlatform.android) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    await InAppWebViewController.setWebContentsDebuggingEnabled(
        /* kDebugMode */ true);
  }

  savePath = '${await AndroidPathProvider.downloadsPath}/Shinden';

  appLink = (await _appLinks.getInitialAppLink()).toString();

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
  // ignore: library_private_types_in_public_api
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey webViewKey = GlobalKey();

  InAppWebViewController? webViewController;
  InAppWebViewSettings settings = InAppWebViewSettings(
    javaScriptCanOpenWindowsAutomatically: false,
    useShouldInterceptRequest: true,
    transparentBackground: true,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    supportZoom: false,
    //userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:122.0) Gecko/20100101 Firefox/122.0",
  );

  PullToRefreshController? pullToRefreshController;
  String url = "";
  double progress = 0;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();

    // if user killed app while downloading then remove broken notification and tmp files
    AwesomeNotifications().cancelAll();
    Permission.storage.isGranted.then((granted) {
      if (granted) {
        Directory(savePath).list(recursive: true).listen((file) {
          if (file is File && file.path.endsWith('tmp')) file.deleteSync();
        });
      }
    });

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
          color: Colors.white, backgroundColor: Colors.black),
      onRefresh: () async => webViewController?.reload(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    // Open shinden link in app (be sure to allow it in system settings!)
    if (state == AppLifecycleState.resumed) {
      appLink = (await _appLinks.getLatestAppLink()).toString();
      if (appLink.isEmpty) return;
      if (appLink.contains('shinden.pl')) {
        webViewController?.loadUrl(
            urlRequest: URLRequest(url: WebUri(appLink)));
        appLink = '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: onBack,
      child: Scaffold(
        backgroundColor: const Color(0xff181818),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: InAppWebView(
                  key: webViewKey,
                  initialUrlRequest: URLRequest(
                    url: WebUri(
                      appLink.contains('null')
                          ? "https://shinden.pl/"
                          : appLink,
                    ),
                  ),
                  initialSettings: settings,
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) async {
                    webViewController = controller;
                    widgetInstance = this;

                    // Utility
                    controller.addJavaScriptHandler(
                        handlerName: 'noReload',
                        callback: (args) =>
                            pullToRefreshController?.setEnabled(false));
                    controller.addJavaScriptHandler(
                        handlerName: 'reload',
                        callback: (args) =>
                            pullToRefreshController?.setEnabled(true));
                    controller.addJavaScriptHandler(
                        handlerName: 'back_button',
                        callback: (args) async => await controller
                            .canGoBack()
                            .then((value) => controller.goBack()));

                    // SessionManager 'setter', cleaner
                    controller.addJavaScriptHandler(
                        handlerName: 'mode_set',
                        callback: (args) async =>
                            await SessionManager().set('mode', args[0]));
                    controller.addJavaScriptHandler(
                        handlerName: 'mode_clear',
                        callback: (args) async =>
                            await SessionManager().destroy());

                    // From players_handler.dart
                    // Add handlers for supported video providers
                    for (var entry in playersHandlers) {
                      controller.addJavaScriptHandler(
                        handlerName: entry.key,
                        callback: (args) async {
                          entry.value(args[0], controller);
                        },
                      );
                    }

                    // Download / stream using url from video providers
                    controller.addJavaScriptHandler(
                      handlerName: 'download/stream',
                      callback: (args) async {
                        // Check if link is correct
                        await http.head(Uri.parse(args[0])).then((value) async {
                          controller.goBack();
                          value.statusCode == 200
                              ? downloadOrStream(controller, args[0], args[1])
                              : controller.evaluateJavascript(
                                  source:
                                      'alert(`Video does not exist!\nChoose other player.`)');
                        });
                      },
                    );
                    // Open url in external browser
                    controller.addJavaScriptHandler(
                        handlerName: 'open_in_browser',
                        callback: (args) async {
                          controller.goBack();
                          FlutterWebBrowser.openWebPage(url: args[0]);
                        });
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
                    if (urlWhiteList.none((el) => tempRequest.contains(el))) {
                      NavigationActionPolicy.CANCEL;
                      return WebResourceResponse();
                    }

                    //log("$tempUrl, $tempRequest");
                    return null;
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                        resources: request.resources,
                        action: PermissionResponseAction.GRANT);
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController?.endRefreshing();
                  },
                  onReceivedError: (controller, request, error) async {
                    pullToRefreshController?.endRefreshing();
                    if (error.type.toString() != "UNKNOWN" || request.isForMainFrame == true)
                      await controller.injectJavascriptFileFromAsset(
                          assetFilePath: 'assets/js/error.js');
                  },
                  onProgressChanged: (controller, progress) {
                    if (progress == 100)
                      pullToRefreshController?.endRefreshing();
                  },
                  onUpdateVisitedHistory: (controller, url, androidIsReload) {
                    setState(() => this.url = url.toString());
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

  Future<bool> onBack() async {
    return await webViewController!.canGoBack().then((value) async {
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
