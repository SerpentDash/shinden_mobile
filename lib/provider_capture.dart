import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'webview_debug.dart';

const _defaultUserAgent =
    'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36';

class ProviderCaptureResult {
  const ProviderCaptureResult({required this.url, required this.title});

  final String url;
  final String title;
}

class ProviderCaptureConfig {
  const ProviderCaptureConfig({
    required this.dialogTitle,
    required this.hint,
    this.fallbackTitle,
    this.userAgent = _defaultUserAgent,
  });

  final String dialogTitle;
  final String hint;
  final String Function(String embedUrl)? fallbackTitle;
  final String userAgent;
}

Future<ProviderCaptureResult?> showProviderCaptureDialog(
  BuildContext context, {
  required String embedUrl,
  required ProviderCaptureConfig config,
}) {
  return showDialog<ProviderCaptureResult>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ProviderCaptureDialog(embedUrl: embedUrl, config: config),
  );
}

InAppWebViewSettings _captureWebViewSettings(String userAgent) => InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      thirdPartyCookiesEnabled: true,
      cacheEnabled: false,
      mediaPlaybackRequiresUserGesture: false,
      useOnLoadResource: true,
      useShouldOverrideUrlLoading: true,
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
  });

  final String embedUrl;
  final ProviderCaptureConfig config;

  @override
  State<_ProviderCaptureDialog> createState() => _ProviderCaptureDialogState();
}

class _ProviderCaptureDialogState extends State<_ProviderCaptureDialog> {
  InAppWebViewController? _webViewController;
  int _sessionId = 0;
  bool _captured = false;
  String _title = '';
  String? _pendingStreamUrl;

  late final String _embedHost = Uri.parse(widget.embedUrl).host;

  ProviderCaptureConfig get _config => widget.config;

  URLRequest _embedRequest() => URLRequest(
        url: WebUri(widget.embedUrl),
        headers: _embedRequestHeaders(widget.embedUrl, _config.userAgent),
      );

  void _onStreamUrl(String url) {
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

  /// Embed players load on the original host; API calls are fetch/XHR.
  /// Main-frame hops to ad mirrors (e.g. jnbhi.com/4/...) cause CONNECTION_REFUSED.
  Future<NavigationActionPolicy> _onNavigation(InAppWebViewController controller, NavigationAction action) async {
    if (action.isForMainFrame != true) {
      return NavigationActionPolicy.ALLOW;
    }

    final targetHost = action.request.url?.host ?? '';
    if (targetHost.isEmpty || targetHost == _embedHost) {
      return NavigationActionPolicy.ALLOW;
    }

    WebViewDebug.log('CAPTURE', 'block main-frame redirect ${action.request.url}');
    return NavigationActionPolicy.CANCEL;
  }

  void _onCaptureError(InAppWebViewController controller, WebResourceRequest request, WebResourceError error) {
    WebViewDebug.log(
      'CAPTURE',
      '${error.type} mainFrame=${request.isForMainFrame} ${request.url}',
    );

    if (request.isForMainFrame != true || _captured) return;

    final failedHost = Uri.tryParse(request.url.toString())?.host ?? '';
    if (failedHost.isEmpty || failedHost == _embedHost) return;

    // Landed on a failed ad/mirror redirect — return to the embed page.
    controller.loadUrl(urlRequest: _embedRequest());
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _captured = false;
      _pendingStreamUrl = null;
      _title = '';
      _webViewController = null;
      _sessionId++;
    });
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
      title: Text(
        _config.dialogTitle,
        style: const TextStyle(color: Colors.white, fontSize: 18),
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
                  key: ValueKey('capture-$_sessionId'),
                  initialUrlRequest: _embedRequest(),
                  initialSettings: _captureWebViewSettings(_config.userAgent),
                  initialUserScripts: UnmodifiableListView([]),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                  },
                  onLoadStart: (_, uri) {
                    if (uri == null) return;
                    WebViewDebug.log('CAPTURE', 'start $uri');
                  },
                  onLoadStop: (_, uri) {
                    if (uri == null) return;
                    WebViewDebug.log('CAPTURE', 'stop $uri');
                  },
                  onTitleChanged: (_, title) {
                    final trimmed = title?.trim() ?? '';
                    if (trimmed.isNotEmpty) _title = trimmed;
                  },
                  onLoadResource: (_, resource) {
                    _onStreamUrl(resource.url.toString());
                  },
                  shouldOverrideUrlLoading: _onNavigation,
                  onReceivedError: _onCaptureError,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _retry,
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
