import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'webview_debug.dart';

const _defaultUserAgent =
    'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36';

enum ProviderCaptureEventType {
  fetchRequest,
  fetchResponse,
  networkRequest,
}

class ProviderCaptureEvent {
  const ProviderCaptureEvent({
    required this.type,
    required this.url,
    this.body,
  });

  final ProviderCaptureEventType type;
  final String url;
  final String? body;
}

class ProviderCaptureResult {
  const ProviderCaptureResult({required this.url, required this.title});

  final String url;
  final String title;
}

class _ProviderCaptureRestart {
  const _ProviderCaptureRestart();
}

Future<void> _resetCaptureSession(String embedUrl) async {
  final origin = Uri.tryParse(embedUrl)?.origin;
  if (origin == null || origin.isEmpty) return;
  await CookieManager.instance().deleteCookies(url: WebUri(origin));
}

class ProviderCaptureConfig {
  const ProviderCaptureConfig({
    required this.dialogTitle,
    required this.hint,
    this.watchFetchPatterns = const [],
    this.watchNetworkPatterns = const [],
    this.enableDefaultStreamCapture = false,
    this.extraUserScript,
    this.fallbackTitle,
    this.onCapture,
    this.userAgent = _defaultUserAgent,
  });

  final String dialogTitle;
  final String hint;
  final List<String> watchFetchPatterns;
  final List<String> watchNetworkPatterns;
  final bool enableDefaultStreamCapture;
  final String? extraUserScript;
  final String Function(String embedUrl)? fallbackTitle;
  final String? Function(ProviderCaptureEvent event)? onCapture;
  final String userAgent;
}

String? _captureScriptCache;

Future<String> _captureScriptSource() async {
  return _captureScriptCache ??= await rootBundle.loadString('assets/js/capture.js');
}

Future<ProviderCaptureResult?> showProviderCaptureDialog(
  BuildContext context, {
  required String embedUrl,
  required ProviderCaptureConfig config,
}) async {
  final captureScript = await _captureScriptSource();
  if (!context.mounted) return null;

  while (context.mounted) {
    await _resetCaptureSession(embedUrl);
    if (!context.mounted) return null;

    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProviderCaptureDialog(
        embedUrl: embedUrl,
        config: config,
        captureScript: captureScript,
      ),
    );

    if (result is ProviderCaptureResult) {
      return result;
    }
    if (result is _ProviderCaptureRestart) {
      await Future.delayed(const Duration(milliseconds: 200));
      continue;
    }
    return null;
  }

  return null;
}

InAppWebViewSettings _captureWebViewSettings(String userAgent) => InAppWebViewSettings(
      javaScriptEnabled: true,
      incognito: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      thirdPartyCookiesEnabled: true,
      cacheEnabled: false,
      mediaPlaybackRequiresUserGesture: false,
      useShouldInterceptRequest: true,
      useShouldInterceptAjaxRequest: false,
      useShouldInterceptFetchRequest: false,
      userAgent: userAgent,
    );

Map<String, String> _embedRequestHeaders(String embedUrl, String userAgent) {
  final uri = Uri.parse(embedUrl);
  return {
    'User-Agent': userAgent,
    'Referer': embedUrl,
    'Origin': uri.origin,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'pl,en-US;q=0.9,en;q=0.8',
  };
}

class _ProviderCaptureDialog extends StatefulWidget {
  const _ProviderCaptureDialog({
    required this.embedUrl,
    required this.config,
    required this.captureScript,
  });

  final String embedUrl;
  final ProviderCaptureConfig config;
  final String captureScript;

  @override
  State<_ProviderCaptureDialog> createState() => _ProviderCaptureDialogState();
}

class _ProviderCaptureDialogState extends State<_ProviderCaptureDialog> {
  InAppWebViewController? _webViewController;
  bool _captured = false;
  bool _autoRestarted = false;
  String _title = '';
  String? _pendingStreamUrl;

  ProviderCaptureConfig get _config => widget.config;

  Future<void> _injectCaptureHook(InAppWebViewController controller) async {
    final patterns = jsonEncode(_config.watchFetchPatterns);
    final source = 'window.__shinden_capture_patterns=$patterns;\n${widget.captureScript}';
    try {
      await controller.evaluateJavascript(source: source);
    } catch (_) {}
  }

  List<UserScript> _initialUserScripts() {
    final scripts = <UserScript>[];

    final extra = _config.extraUserScript?.trim();
    if (extra != null && extra.isNotEmpty) {
      scripts.add(
        UserScript(
          source: extra,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      );
    }

    return scripts;
  }

  bool _matchesNetworkWatch(String url) {
    return _config.watchNetworkPatterns.any(url.contains);
  }

  void _handleCaptureEvent(ProviderCaptureEvent event) {
    if (_captured) return;

    final custom = _config.onCapture?.call(event);
    if (custom != null && custom.isNotEmpty) {
      _finishCapture(custom);
      return;
    }

    if (_config.enableDefaultStreamCapture) {
      _tryDefaultStreamCapture(event.url);
    }
  }

  void _onCaptureError(InAppWebViewController controller, WebResourceRequest request, WebResourceError error) {
    final type = error.type.toString();
    WebViewDebug.log(
      'CAPTURE',
      '$type mainFrame=${request.isForMainFrame} ${request.url}',
    );

    if (request.isForMainFrame != true || _captured || _autoRestarted) return;
    if (!type.contains('CONNECT') && !type.contains('REFUSED')) return;

    _autoRestarted = true;
    Future.microtask(_restartCaptureSession);
  }

  void _tryDefaultStreamCapture(String url) {
    if (_captured || url.isEmpty) return;

    final isM3u8 = url.contains('.m3u8');
    final isMp4 = url.contains('.mp4');
    if (!isM3u8 && !isMp4) return;

    if (isM3u8) {
      if (url.contains('master.m3u8')) {
        _finishCapture(url);
        return;
      }

      _pendingStreamUrl ??= url;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_captured || !mounted || _pendingStreamUrl == null) return;
        _finishCapture(_pendingStreamUrl!);
      });
      return;
    }

    _finishCapture(url);
  }

  void _onJsCaptureMessage(String? raw) {
    if (raw == null || raw.isEmpty) return;

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      payload = decoded;
    } catch (_) {
      return;
    }

    final typeName = payload['type']?.toString() ?? '';
    final url = payload['url']?.toString() ?? '';
    if (url.isEmpty) return;

    final type = switch (typeName) {
      'fetch_request' => ProviderCaptureEventType.fetchRequest,
      'fetch_response' => ProviderCaptureEventType.fetchResponse,
      _ => null,
    };
    if (type == null) return;

    _handleCaptureEvent(
      ProviderCaptureEvent(
        type: type,
        url: url,
        body: payload['body']?.toString(),
      ),
    );
  }

  void _onNetworkRequest(String url) {
    if (_captured || url.isEmpty) return;

    if (_matchesNetworkWatch(url)) {
      _handleCaptureEvent(ProviderCaptureEvent(type: ProviderCaptureEventType.networkRequest, url: url));
      return;
    }

    if (_config.enableDefaultStreamCapture) {
      _tryDefaultStreamCapture(url);
    }
  }

  void _restartCaptureSession() {
    if (!mounted) return;
    Navigator.of(context).pop(const _ProviderCaptureRestart());
  }

  Future<void> _finishCapture(String url, {String? title}) async {
    if (_captured || !mounted) return;
    _captured = true;
    _pendingStreamUrl = null;

    var resolvedTitle = title?.trim() ?? _title.trim();
    if (resolvedTitle.isEmpty && _webViewController != null) {
      try {
        final pageTitle = await _webViewController!.getTitle();
        resolvedTitle = pageTitle?.trim() ?? '';
      } catch (_) {}
    }
    if (resolvedTitle.isEmpty) {
      resolvedTitle = _config.fallbackTitle?.call(widget.embedUrl) ?? 'Video';
    }

    if (!mounted) return;
    Navigator.of(context).pop(ProviderCaptureResult(url: url, title: resolvedTitle));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    return AlertDialog(
      backgroundColor: const Color(0xff181818),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _config.dialogTitle,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: screen.width,
        height: screen.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _config.hint,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.embedUrl),
                    headers: _embedRequestHeaders(widget.embedUrl, _config.userAgent),
                  ),
                  initialSettings: _captureWebViewSettings(_config.userAgent),
                  initialUserScripts: UnmodifiableListView(_initialUserScripts()),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    controller.addJavaScriptHandler(
                      handlerName: 'shinden_capture',
                      callback: (args) {
                        if (args.isEmpty) return;
                        _onJsCaptureMessage(args[0]?.toString());
                      },
                    );
                  },
                  onLoadStart: (_, uri) {
                    if (uri == null) return;
                    WebViewDebug.log('CAPTURE', 'start $uri');
                  },
                  onLoadStop: (controller, uri) {
                    if (uri == null) return;
                    WebViewDebug.log('CAPTURE', 'stop $uri');
                    _injectCaptureHook(controller);
                  },
                  onTitleChanged: (_, title) {
                    final trimmed = title?.trim() ?? '';
                    if (trimmed.isNotEmpty) _title = trimmed;
                  },
                  onReceivedError: _onCaptureError,
                  shouldInterceptRequest: (_, request) async {
                    _onNetworkRequest(request.url.toString());
                    return null;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restartCaptureSession,
          child: const Text('Spróbuj ponownie', style: TextStyle(color: Colors.white)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
