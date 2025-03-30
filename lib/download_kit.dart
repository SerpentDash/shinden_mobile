import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:math' show Random;

import 'package:html/parser.dart';
import 'package:deep_pick/deep_pick.dart';

import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart' as pc;

import 'package:flutter_hls_parser/flutter_hls_parser.dart';

import 'package:background_downloader/background_downloader.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file_safe_plus/open_file_safe_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

import 'video_server.dart';

part 'players_handler.dart';
part 'notification_controller.dart';

String savePath = '/sdcard/Download/Shinden';

void process(controller, url, fileName, mode) async {
  String title = fileName.toString().trim();
  switch (mode) {
    case 'stream':
      AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: url,
        arguments: {'title': title},
      ).launch();
      break;
    case 'download':
      download(url, fileName);
      break;
    default:
      break;
  }
}

void download(url, fileName, {Map<String, String> headers = const {}}) async {
  await initializeFileDownloader();

  await FileDownloader().enqueue(
    DownloadTask(
      url: url,
      filename: fileName,
      directory: savePath,
      baseDirectory: BaseDirectory.root,
      headers: headers,
      updates: Updates.progress,
      allowPause: true,
      retries: 3,
    ),
  );
}

/// Download and decrypt file from MEGA
void megaTask(dynamic params) async {
  final [sendPort, id, baseUrl] = params;

  String? paramId = extractIdFromUrl(baseUrl);
  String? paramKey = extractKeyFromUrl(baseUrl);

  if (paramId == null || paramKey == null) {
    sendPort.send({
      'content': NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: "Error: Invalid URL",
      ),
    });
    log("Error: Invalid URL");
    return;
  }

  // Prepare Key and IV
  String keyHex;
  try {
    keyHex = HEX.encode((base64.decode(paramKey)));
  } on Exception catch (_) {
    keyHex = HEX.encode((base64.decode(addBase64Padding(paramKey))));
  }

  Uint8List iv = Uint8List.fromList(HEX.decode(keyHex.substring(32, 48) + '0' * 16));

  BigInt key1 = BigInt.parse(keyHex.substring(0, 16), radix: 16) ^ BigInt.parse(keyHex.substring(32, 48), radix: 16);
  BigInt key2 = BigInt.parse(keyHex.substring(16, 32), radix: 16) ^ BigInt.parse(keyHex.substring(48, 64), radix: 16);
  Uint8List key = Uint8List.fromList(HEX.decode('${key1.toRadixString(16).padLeft(16, '0')}${key2.toRadixString(16).padLeft(16, '0')}'));

  // Get json from API request
  final apiResponse = await http.post(
    Uri.parse('https://eu.api.mega.co.nz/cs'),
    body: jsonEncode([
      {"a": "g", "g": 1, "p": paramId}
    ]),
  );

  if (apiResponse.body == '[-6]' || apiResponse.body == '[-9]') {
    sendPort.send({
      'content': NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: "Error: File does not exist",
      ),
    });
    log("Error: File does not exist");
    return;
  }
  // Parse json
  final jsonResponse = jsonDecode(apiResponse.body);

  String url = jsonResponse[0]['g'];
  //int size = jsonResponse[0]['s'];
  String info = jsonResponse[0]['at'].replaceAll('-', '+').replaceAll('_', '/');

  // Decrypt info variable to get file name
  Uint8List input;
  try {
    input = base64.decode(info);
  } on Exception catch (_) {
    input = base64.decode(addBase64Padding(info));
  }

  final cipher = pc.CBCBlockCipher(pc.AESEngine())..init(false, pc.ParametersWithIV(pc.KeyParameter(key), Uint8List(16)));

  Uint8List output = Uint8List(input.length);

  var offset = 0;
  while (offset < input.length) {
    offset += cipher.processBlock(input, offset, output, offset);
  }

  RegExp pattern = RegExp(r'"n":"(.*?)"');
  String fileName = pattern.firstMatch(utf8.decode(output))!.group(1)!;

  //print("File: $fileName, Size:  ${size ~/ (1024 * 1024)}MB");

  final throttler = Throttler(milliseconds: 2000);
  // Start downloading encrypted file
  try {
    final dio = Dio();
    await dio.download(
      url,
      "$savePath/tmp",
      onReceiveProgress: (received, total) {
        if (total != -1) {
          throttler(
            () => sendPort.send({
              'content': NotificationContent(
                  id: id,
                  channelKey: 'downloader',
                  title: fileName,
                  body: "${received ~/ (1024 * 1024)} MB / ${total ~/ (1024 * 1024)} MB",
                  progress: (received / total) * 100,
                  notificationLayout: NotificationLayout.ProgressBar,
                  locked: true,
                  payload: {"isolate": "$id", "fileName": fileName}),
              'actionButtons': [
                NotificationActionButton(
                  key: 'cancel',
                  label: 'Cancel',
                ),
              ],
            }),
          );
        }
      },
    );
  } on DioException catch (ex) {
    sendPort.send({
      'content': NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: fileName,
        body: "Error: Download limit reached. Try again later",
      ),
    });
    log("Error: Download limit reached. Try again later");
    log(ex.toString());
    return;
  }

  final fileCipher = pc.CTRStreamCipher(pc.AESEngine())
    ..init(
      false,
      pc.ParametersWithIV(pc.KeyParameter(key), iv),
    );

  final file = File("$savePath/tmp");

  // Values to show progress in notification
  final totalChunks = await file.openRead().length;
  int chunkIndex = 0;

  // Get chunks from downloaded, encrypted file
  final stream = file.openRead();

  // Open file to save decrypted chunks
  final sink = File("$savePath/$fileName").openWrite();

  await for (final chunk in stream) {
    // Save decrypted chunks to file
    sink.add(fileCipher.process(Uint8List.fromList(chunk)));

    chunkIndex++;
    throttler(
      () => sendPort.send({
        'content': NotificationContent(
            id: id,
            channelKey: 'downloader',
            title: fileName,
            body: 'Decrypting (${((chunkIndex / totalChunks) * 100).toStringAsFixed(2)}%)',
            progress: (chunkIndex / totalChunks) * 100,
            notificationLayout: NotificationLayout.ProgressBar,
            locked: true,
            payload: {"isolate": "$id", "fileName": fileName}),
        'actionButtons': [
          NotificationActionButton(
            key: 'cancel',
            label: 'Cancel',
          ),
        ],
      }),
    );
  }

  await sink.flush();
  await sink.close();
  await File("$savePath/tmp").delete();

  sendPort.send({
    'content': NotificationContent(
      id: id,
      channelKey: 'downloader',
      title: fileName,
      body: "Download completed.",
    ),
  });
}

/// Download playlist (m3u8) as mp4
void playlistTask(dynamic params) async {
  final sendPort = params[0]; // will be added by NotificationController
  int id = params[1]; // will be added by NotificationController
  String url = params[2];
  String title = params[3];
  Map<String, String> headers = params[4];

  sendPort.send({
    'content': NotificationContent(
      id: id,
      channelKey: 'downloader',
      title: "$title.mp4",
      body: "Preparing...",
    ),
  });

  // Get highest quality url from master file

  final highestQualityUrl = url.contains("master") ? await getHighestQualityUrl(Uri.parse(url), headers: headers) : url;
  if (highestQualityUrl == null) {
    sendPort.send({
      'content': NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: "Error: File does not exist",
      ),
    });
    log("Error: File does not exist");
    return;
  }

  final media = await http.get(Uri.parse(highestQualityUrl), headers: headers);
  final mediaPlaylist = await HlsPlaylistParser.create().parseString(Uri.parse(highestQualityUrl), media.body);
  mediaPlaylist as HlsMediaPlaylist;

  final segments = mediaPlaylist.segments.map((segment) => segment.url).toList();

  final sink = File('$savePath/$title.mp4').openWrite();

  final throttler = Throttler(milliseconds: 2000);

  try {
    bool useFullPath = false;
    String urlPart = url;

    // Check if 'segment' is url or just part of url
    Uri segmentUri = Uri.parse(segments.first!);
    if (!segmentUri.hasAbsolutePath) {
      // Remove last part of base url to use as base for downloading segments
      List<String> urlSegments = url.split('/');
      urlSegments.removeLast();
      urlPart = urlSegments.join('/');

      useFullPath = true;
    }

    // Download each segment and save to file
    for (final segment in segments) {
      final segmentData = await http.readBytes(Uri.parse(useFullPath ? "$urlPart/${segment!}" : segment!), headers: headers);
      sink.add(segmentData);
      throttler(
        () => sendPort.send({
          'content': NotificationContent(
              id: id,
              channelKey: 'downloader',
              title: '$title.mp4',
              body: "Segment: ${segments.indexOf(segment) + 1} / ${segments.length}",
              progress: ((segments.indexOf(segment) + 1) / segments.length) * 100,
              notificationLayout: NotificationLayout.ProgressBar,
              locked: true,
              payload: {"isolate": "$id", "fileName": '$title.mp4'}),
          'actionButtons': [
            NotificationActionButton(
              key: 'cancel',
              label: 'Cancel',
            ),
          ],
        }),
      );
      log('Progress: ${segments.indexOf(segment) + 1} / ${segments.length}');
    }
    sendPort.send({
      'content': NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: '$title.mp4',
        body: "Download completed.",
      ),
    });
  } catch (e) {
    sendPort.send({
      'content': NotificationContent(
        id: id,
        channelKey: 'downloader',
        body: "Error: $e",
      ),
    });
    log('Error: $e');
  } finally {
    await sink.flush();
    await sink.close();
  }
}

// Sort available links and get the highest quality one
Future<String?> getHighestQualityUrl(Uri masterUrl, {headers = const {}}) async {
  final master = await http.get(masterUrl, headers: headers);
  if (master.statusCode != 200) return null;

  final masterPlayList = await HlsPlaylistParser.create().parseString(masterUrl, master.body);
  masterPlayList as HlsMasterPlaylist;
  final sortedVariants = masterPlayList.variants..sort((a, b) => b.format.bitrate!.compareTo(a.format.bitrate!));
  final highestQualityVariant = sortedVariants.first;
  return highestQualityVariant.url.toString();
}

// This one needs more care that other providers...
// Send 'post' request, get redirect link and download this link without veryfing cert
void mp4uploadTask(dynamic params) async {
  final sendPort = params[0]; // will be added by NotificationController
  int id = params[1]; // will be added by NotificationController
  String url = params[2];
  String title = params[3];

  Dio dio = Dio();
  // Bypass cert verification...
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final HttpClient client = HttpClient(context: SecurityContext(withTrustedRoots: false));
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    },
  );

  final throttler = Throttler(milliseconds: 1000);
  try {
    await dio.download(
      url,
      '$savePath/title.mp4',
      options: Options(headers: {"Referer": "https://www.mp4upload.com/"}),
      onReceiveProgress: (received, total) {
        //print("${received ~/ (1024 * 1024)} MB / ${total ~/ (1024 * 1024)} MB");
        throttler(
          () => sendPort.send({
            'content': NotificationContent(
                id: id,
                channelKey: 'downloader',
                title: '$title.mp4',
                body: "${received ~/ (1024 * 1024)} MB / ${total ~/ (1024 * 1024)} MB",
                progress: (received / total) * 100,
                notificationLayout: NotificationLayout.ProgressBar,
                locked: true,
                payload: {"isolate": "$id", "fileName": '$title.mp4'}),
            'actionButtons': [
              NotificationActionButton(
                key: 'cancel',
                label: 'Cancel',
              ),
            ],
          }),
        );
      },
    );
  } on DioException catch (_) {
    sendPort.send({
      'content': NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: "$title.mp4",
        body: "Error occurred while downloading.",
      ),
    });
  }

  sendPort.send({
    'content': NotificationContent(
      id: id,
      channelKey: 'downloader',
      title: "$title.mp4",
      body: "Download completed.",
    ),
  });
}

class Throttler {
  final int milliseconds;
  VoidCallback? action;
  Timer? _timer;

  Throttler({required this.milliseconds});

  call(VoidCallback action) {
    if (_timer == null || !_timer!.isActive) {
      action();
      _timer = Timer(Duration(milliseconds: milliseconds), () {});
    }
  }
}

// Helper functions for mega
String? extractIdFromUrl(String url) {
  const pattern = r'[-_a-zA-Z0-9]{8,}';
  final match = RegExp(pattern).firstMatch(url);
  return match?.group(0);
}

String? extractKeyFromUrl(String url) {
  RegExp pattern = RegExp(r'[a-zA-Z0-9_-]{22,}');
  Match? match = pattern.firstMatch(url.split('#').last) ?? pattern.firstMatch(url.split('/').last) ?? pattern.firstMatch(url);
  return match?.group(0)?.replaceAll('-', '+').replaceAll('_', '/');
}

String addBase64Padding(String value) {
  int paddingNeeded = 4 - (value.length % 4);
  return value + '=' * paddingNeeded;
}

Future<void> initializeFileDownloader() async {
  //if(await FileDownloader().ready == true) return;
  log("Initializing FileDownloader");

  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
  await Permission.videos.request();
  await Permission.notification.request();

  await FileDownloader().configure(globalConfig: [
    (Config.requestTimeout, const Duration(seconds: 30))
  ], androidConfig: [
    (Config.useCacheDir, Config.never),
    (Config.useExternalStorage, Config.always),
    (Config.runInForeground, Config.always),
  ]).then((result) => log('Configuration result = $result'));

  FileDownloader()
      .configureNotificationForGroup(
        FileDownloader.defaultGroup,
        running: const TaskNotification('{filename}', '{progress} - {networkSpeed} - {timeRemaining} remaining'),
        complete: const TaskNotification('{filename}', 'Download complete'),
        error: const TaskNotification('{filename}', 'Download failed'),
        paused: const TaskNotification('{filename}', 'Paused by user'),
        progressBar: true,
        tapOpensFile: true,
      )
      .configureNotificationForGroup('bunch',
          running: const TaskNotification('{numFinished} out of {numTotal}', 'Progress = {progress}'),
          complete: const TaskNotification("Done!", "Loaded {numTotal} files"),
          error: const TaskNotification('Error', '{numFailed}/{numTotal} failed'),
          progressBar: false)
      .configureNotification(
        complete: const TaskNotification('{filename}', 'Download complete'),
        tapOpensFile: true,
      );
}
