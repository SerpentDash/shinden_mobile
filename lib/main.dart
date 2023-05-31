// ignore_for_file: curly_braces_in_flow_control_structures, depend_on_referenced_packages

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_session_manager/flutter_session_manager.dart';
import 'package:flutter_web_browser/flutter_web_browser.dart';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:android_path_provider/android_path_provider.dart';
import 'package:sanitize_filename/sanitize_filename.dart';
import 'package:file_sizes/file_sizes.dart';
import 'package:random_string/random_string.dart';

import 'package:wakelock/wakelock.dart';
import 'package:app_links/app_links.dart';
import 'package:auto_orientation/auto_orientation.dart';

import 'package:simple_downloader/simple_downloader.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:native_toast/native_toast.dart';
import 'package:throttling/throttling.dart';
import 'package:external_video_player_launcher/external_video_player_launcher.dart';

part 'download_kit.dart';

String css = "";
List<String> hosts = [];
RegExp shindenRegex = RegExp(
  r"(https|http)?:\/\/[a-zA-Z.0-9]{7,}\.(com|bid|info)\/[a-zA-Z.-]{1,}\.(js|htm|html|asp|aspx)",
  caseSensitive: false,
  multiLine: false,
);

String tempUrl = "";
String tempRequest = "";

final _appLinks = AppLinks();
String appLink = '';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ByteData bytes = await rootBundle.load('assets/css/main.css');
  css = base64Encode(Uint8List.view(bytes.buffer));

  String hostFile = await rootBundle.loadString('assets/host.txt');
  LineSplitter.split(hostFile).forEach((line) => hosts.add(line));

  if (defaultTargetPlatform == TargetPlatform.android) {
    WebView.debugLoggingSettings.enabled = kDebugMode;
    await InAppWebViewController.setWebContentsDebuggingEnabled(
        true); //kDebugMode);
  }

  savePath = '${await AndroidPathProvider.downloadsPath}/Shinden';

  AutoOrientation.portraitUpMode();

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
    iframeAllowFullscreen: true,
    userAgent:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Chrome/98.0.4758.102 Firefox/113.0",
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

    // Open shinden link in app (be sure to allow it in system settings)
    if (state == AppLifecycleState.resumed) {
      appLink = (await _appLinks.getLatestAppLink()).toString();
      if (appLink.isEmpty) return;
      if (appLink.contains('shinden.pl')) {
        webViewController?.loadUrl(
            urlRequest: URLRequest(url: WebUri(appLink)));
        appLink = '';
        return;
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
                      url: WebUri(appLink.contains('null')
                          ? "https://shinden.pl/"
                          : appLink)),
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

                    // SessionManager 'setter', 'getter', cleaner
                    controller.addJavaScriptHandler(
                        handlerName: 'mode_get',
                        callback: (args) async =>
                            await SessionManager().get('mode'));
                    controller.addJavaScriptHandler(
                        handlerName: 'mode_set',
                        callback: (args) async =>
                            await SessionManager().set('mode', args[0]));
                    controller.addJavaScriptHandler(
                        handlerName: 'mode_clear',
                        callback: (args) async =>
                            await SessionManager().destroy());

                    // Download / stream using direct link (eg cda, gdrive) | test download & notifications
                    controller.addJavaScriptHandler(
                        handlerName: 'download/stream',
                        callback: (args) async {
                          //check if link is correct
                          await http
                              .head(Uri.parse(args[0]))
                              .then((value) async {
                            controller.goBack();
                            value.statusCode == 200
                                ? downloadOrStream(controller, args[0], args[1])
                                : controller.evaluateJavascript(
                                    source:
                                        'alert(`Video does not exist!\nChoose other player.`)');
                          });
                        });

                    // Open url in external browser
                    controller.addJavaScriptHandler(
                        handlerName: 'open_in_browser',
                        callback: (args) async {
                          controller.goBack();
                          FlutterWebBrowser.openWebPage(url: args[0]);
                        });
                    // remove show_info
                    await Future.delayed(
                        const Duration(seconds: 2),
                        () => controller.evaluateJavascript(
                            source: "localStorage.removeItem('show_info')"));
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
                      if (tempUrl.contains("shinden.pl/episode")) {
                        await controller.injectJavascriptFileFromAsset(
                            assetFilePath: "assets/js/bypass.js");
                      }
                    }

                    // PLAYER PROVIDERS
                    if (tempUrl.contains("ebd.cda"))
                      setJS(controller, 'cda');
                    else if (tempUrl.contains("drive.google"))
                      setJS(controller, 'gdrive');
                    else if (tempUrl.contains("dailymotion"))
                      setJS(controller, 'dailymotion');
                    else if (tempUrl.contains("sibnet"))
                      setJS(controller, 'sibnet');
                    else if (tempUrl.contains("streamtape") ||
                        tempUrl.contains("streamadblockplus"))
                      setJS(controller, 'streamtape');
                    else if (tempUrl.contains("mega"))
                      setJS(controller, 'mega.nz');
                    else if (tempUrl.contains("mp4upload"))
                      setJS(controller, 'mp4upload');
                    else if (tempUrl.contains("yourupload"))
                      setJS(controller, 'yourupload');
                  },
                  shouldInterceptRequest: (controller, request) async {
                    tempRequest = request.url.toString();
                    // Adblock
                    for (var i = 0; i < hosts.length; i++) {
                      if (tempRequest.contains(hosts.elementAt(i)) ||
                          shindenRegex.hasMatch(tempRequest)) {
                        NavigationActionPolicy.CANCEL;
                        return WebResourceResponse();
                      }
                    }

                    // Intercept requests to get direct stream links
                    // Dailymotion stream
                    if (tempRequest.contains('hd') &&
                        tempRequest.contains('.m3u8'))
                      downloadOrStream(controller, tempRequest,
                          request.url.pathSegments.last);

                    // Sibnet stream
                    if (tempRequest.contains('sibnet') &&
                        !tempRequest.contains('video.sibnet') &&
                        tempRequest.contains('mp4'))
                      downloadOrStream(controller, tempRequest,
                          request.url.pathSegments.last);

                    // Streamtape stream
                    if (tempRequest.contains('tapecontent') &&
                        tempRequest.contains('mp4'))
                      downloadOrStream(controller, tempRequest,
                          request.url.pathSegments.last);

                    // MP4UPLOAD stream
                    if (tempRequest.contains('mp4upload.com/files'))
                      downloadOrStream(controller, tempRequest,
                          request.url.pathSegments.last);

                    return null;
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                        resources: request.resources,
                        action: PermissionResponseAction.GRANT);
                  },
                  onEnterFullscreen: (controller) {
                    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive,
                        overlays: []);
                    AutoOrientation.landscapeAutoMode(forceSensor: true);
                    Wakelock.enable();
                  },
                  onExitFullscreen: (controller) {
                    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
                        overlays: SystemUiOverlay.values);
                    AutoOrientation.portraitUpMode();
                    Wakelock.disable();
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController?.endRefreshing();
                  },
                  onReceivedError: (controller, request, error) async {
                    pullToRefreshController?.endRefreshing();
                    if (error.type.toString() != "UNKNOWN")
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

  // add correct js file to
  void setJS(controller, target) async {
    await SessionManager().get('mode').then((val) async {
      if (val != null) {
        await controller.injectJavascriptFileFromAsset(
            assetFilePath: 'assets/js/players/${target}_min.js');
      }
    });
  }
}
