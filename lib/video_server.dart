import 'dart:developer';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'dart:convert';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(VideoServerTaskHandler());
}

class VideoServer with WidgetsBindingObserver {
  VideoServer() {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> start() async {
    DartPluginRegistrant.ensureInitialized();
    await _initForegroundTask();
    await FlutterForegroundTask.startService(
      notificationTitle: 'Video Server Running',
      notificationText: 'Tap to return to the app (and stop service)',
      callback: startCallback,
    );
  }

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'video_server',
        channelName: 'Video Server',
        channelDescription: 'Running video server in background',
        channelImportance: NotificationChannelImportance.NONE,
        priority: NotificationPriority.MIN,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
  }

  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(seconds: 1)).then((value) {
        stop();
        WidgetsBinding.instance.removeObserver(this);
      });
    }
  }
}

class VideoServerTaskHandler extends TaskHandler {
  HttpServer? _server;

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onDestroy(DateTime timestamp) {}

  @override
  Future<void> onStart(DateTime timestamp) async {
    _server = await HttpServer.bind('localhost', 8069);
    log('Server started on port 8069');

    _server!.listen((HttpRequest request) async {
      if (request.uri.path == '/mega') {
        await megaHandler(request);
      } else {
        await handleVideoStream(request);
      }
    });
  }

  // Handles video streaming from other providers
  // needed for providers that needs headers to be set
  Future<void> handleVideoStream(HttpRequest request) async {
    final url = request.uri.queryParameters['url'];
    final referer = request.uri.queryParameters['referer'];

    if (url == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing URL parameter')
        ..close();
      return;
    }

    try {
      // Bypass cert verification (needed for mp4upload)
      final client = HttpClient()..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      final videoRequest = await client.getUrl(Uri.parse(url));
      videoRequest.headers.set('Referer', referer ?? '');

      final rangeHeader = request.headers.value('Range');
      if (rangeHeader != null) {
        videoRequest.headers.set('Range', rangeHeader);
        log('Forwarding Range header: $rangeHeader');
      }

      final videoResponse = await videoRequest.close();

      request.response.headers.contentType = videoResponse.headers.contentType;
      request.response.headers.set('Accept-Ranges', 'bytes');

      if (rangeHeader != null) {
        request.response.statusCode = HttpStatus.partialContent;
      } else {
        request.response.statusCode = HttpStatus.ok;
      }

      videoResponse.headers.forEach((name, values) {
        if (name != 'content-type' && name != 'content-length') {
          request.response.headers.set(name, values);
        }
      });

      log('request.response: ${request.response.headers}');

      await request.response.addStream(videoResponse);
      await request.response.close();
    } catch (e) {
      log('Error streaming video: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Error streaming video')
        ..close();
    }
  }

  // Handles encrypted video streaming
  // Still 'work in progress' since seeking doesn't work even with set ranges (i guess?)
  Future<void> megaHandler(HttpRequest request) async {
    final url = request.uri.queryParameters['url'];
    final keyString = request.uri.queryParameters['key'];
    final ivString = request.uri.queryParameters['iv'];

    if (url == null || keyString == null || ivString == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing URL, key, or IV parameter')
        ..close();
      log('Error: Missing URL, key, or IV parameter');
      return;
    }

    log('Handling request for URL: $url with key: $keyString and IV: $ivString');

    try {
      final key = KeyParameter(base64Decode(keyString));
      final iv = base64Decode(ivString);
      final cipher = CTRStreamCipher(AESEngine())..init(false, ParametersWithIV(key, iv));

      final client = HttpClient()..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      final videoRequest = await client.getUrl(Uri.parse(url));

      // TODO: Fix video seeking
      // Setting range headers still doesn't let video seeking
      // Even though file is still being downloaded in background
      // Video stops buffering and shortly after video player throws 'source error'

      if (request.headers.value('Range') != null) {
        videoRequest.headers.set('Range', request.headers.value('Range')!);
      }

      final videoResponse = await videoRequest.close();

      request.response.headers.contentType = videoResponse.headers.contentType;
      request.response.headers.set('Accept-Ranges', 'bytes');

      if (request.headers.value('Range') != null) {
        request.response.statusCode = HttpStatus.partialContent;
      } else {
        request.response.statusCode = HttpStatus.ok;
      }

      videoResponse.headers.forEach((name, values) {
        if (name != 'content-type' && name != 'content-length') {
          request.response.headers.set(name, values);
        }
      });

      await _decryptAndStream(videoResponse, request.response, cipher);
    } catch (e) {
      log('Error handling mega request: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Error handling mega request')
        ..close();
    }
  }

  // Decrypts and streams the video response to the client
  Future<void> _decryptAndStream(HttpClientResponse videoResponse, HttpResponse response, CTRStreamCipher cipher) async {
    try {
      await for (var chunk in videoResponse) {
        final decryptedChunk = Uint8List(chunk.length);
        cipher.processBytes(Uint8List.fromList(chunk), 0, chunk.length, decryptedChunk, 0);
        response.add(decryptedChunk);
      }
      await response.close();
    } catch (e) {
      log('Error during decryption and streaming: $e');
      response
        ..statusCode = HttpStatus.internalServerError
        ..write('Error during decryption and streaming')
        ..close();
    }
  }
}
