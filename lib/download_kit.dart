import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:isolate';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'dart:math' show Random;

import 'package:html/parser.dart';
import 'package:deep_pick/deep_pick.dart';

import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart' as pc;

import 'package:ffmpeg_kit_flutter_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_https/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_https/return_code.dart';

import 'package:background_downloader/background_downloader.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

part 'players_handler.dart';
part 'notification_controller.dart';

String savePath = '/sdcard/Download/Shinden';

void process(controller, url, fileName, mode) async {
  String title = /* sanitizeFilename */ (fileName.toString().trim());
/*   if (p.basename(title).split('.')[0] == "video") {
    // rename generic file name to one before last pathSegment
    Uri u = Uri.parse(url);
    title = u.pathSegments[u.pathSegments.length - 2];
  }
  String ext = p.extension(title); */

  switch (mode) {
    case 'stream':
      /* if (ext != '') title = title.substring(0, title.length - ext.length); */
      AndroidIntent(
        action: 'action_view',
        type: "video/*",
        data: url,
        arguments: {'title': title},
      ).launch();
      break;
    case 'download':
      /* if (ext == '') title += '.mp4'; */
      download(url, fileName);
      /* !(await File('$savePath/$title').exists() ||
              await File('$savePath/$title.tmp').exists())
          ? downloadQueueAdd(url, title)
          : NativeToast().makeText(
              message: _task.fileName == title
                  ? 'Already in Queue'
                  : 'File already exists!',
              duration: NativeToast.longLength); */
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
      directory: '$savePath/$fileName',
      headers: headers,
      updates: Updates.progress,
      retries: 3,
      allowPause: true,
    ),
  );
}

/// Download and decrypt file from MEGA
void runMegaTask(String url) async {
  NotificationController.initialize();

  NotificationController.startIsolate(
    megaTask,
    [NotificationController.uiSendPort, url],
  );
}

void megaTask(dynamic params) async {
  final sendPort = params[0];
  int id = params[1]; // will be added by NotificationController
  String baseUrl = params[2];

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

  Uint8List iv =
      Uint8List.fromList(HEX.decode(keyHex.substring(32, 48) + '0' * 16));

  BigInt key1 = BigInt.parse(keyHex.substring(0, 16), radix: 16) ^
      BigInt.parse(keyHex.substring(32, 48), radix: 16);
  BigInt key2 = BigInt.parse(keyHex.substring(16, 32), radix: 16) ^
      BigInt.parse(keyHex.substring(48, 64), radix: 16);
  Uint8List key = Uint8List.fromList(HEX.decode(
      '${key1.toRadixString(16).padLeft(16, '0')}${key2.toRadixString(16).padLeft(16, '0')}'));

  // Get json from API request
  final apiResponse = await http.post(
    Uri.parse('https://eu.api.mega.co.nz/cs'),
    body: jsonEncode([
      {"a": "g", "g": 1, "p": paramId}
    ]),
  );

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

  final cipher = pc.CBCBlockCipher(pc.AESEngine())
    ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), Uint8List(16)));

  Uint8List output = Uint8List(input.length);

  var offset = 0;
  while (offset < input.length) {
    offset += cipher.processBlock(input, offset, output, offset);
  }

  RegExp pattern = RegExp(r'"n":"(.*?)"');
  String fileName = pattern.firstMatch(utf8.decode(output))!.group(1)!;

  //print("File: $fileName, Size:  ${size ~/ (1024 * 1024)}MB");

  final throttler = Throttler(milliseconds: 1000);
  // Start downloading encrypted file
  try {
    final dio = Dio();
    await dio.download(
      url,
      "$savePath/.tmp",
      onReceiveProgress: (received, total) {
        if (total != -1) {
          throttler(
            () => sendPort.send({
              'content': NotificationContent(
                  id: id,
                  channelKey: 'downloader',
                  title: fileName,
                  body:
                      "${received ~/ (1024 * 1024)} MB / ${total ~/ (1024 * 1024)} MB",
                  progress: (received / total) * 100,
                  notificationLayout: NotificationLayout.ProgressBar,
                  locked: true,
                  payload: {"isolate": "$id", "fileName": fileName}),
              'actionButtons': [
                NotificationActionButton(
                  key: 'cancelMega',
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
    print("Error: Download limit reached. Try again later");
    print(ex.toString());
    return;
  }

  final fileCipher = pc.CTRStreamCipher(pc.AESEngine())
    ..init(
      false,
      pc.ParametersWithIV(pc.KeyParameter(key), iv),
    );

  DateTime startTime = DateTime.now();

  RandomAccessFile raf = await File("$savePath/.tmp").open(mode: FileMode.read);
  int chunkSize = 1024 * 8;
  int totalChunks = (await raf.length() / chunkSize).ceil();
  int chunkIndex = 0;

  final outputFileSink = File("$savePath/$fileName").openWrite();

  while (chunkIndex < totalChunks) {
    // Calculate the size of the current chunk (it may be smaller than chunkSize for the last chunk)
    int currentChunkSize = chunkIndex == totalChunks - 1
        ? await raf.length() - (chunkIndex * chunkSize)
        : chunkSize;

    Uint8List chunk = await raf.read(currentChunkSize);

    final decryptedChunk = fileCipher.process(chunk);

    outputFileSink.add(decryptedChunk);

    chunkIndex++;
    throttler(
      () => sendPort.send({
        'content': NotificationContent(
            id: id,
            channelKey: 'downloader',
            title: fileName,
            body:
                'Decrypting (${((chunkIndex / totalChunks) * 100).toStringAsFixed(2)}%)',
            progress: (chunkIndex / totalChunks) * 100,
            notificationLayout: NotificationLayout.ProgressBar,
            locked: true,
            payload: {"isolate": "$id", "fileName": fileName}),
        'actionButtons': [
          NotificationActionButton(
            key: 'cancelMega',
            label: 'Cancel',
          ),
        ],
      }),
    );
  }

  // Close the file
  await raf.close();

  /* final Stream<List<int>> chunks = encryptedFile.openRead();
  int currentChunk = 0;
  int totalChunks = await chunks.length;


  await for (final chunk in chunks) {
    final decryptedChunk = fileCipher.process(Uint8List.fromList(chunk));

    outputFileSink.add(decryptedChunk);

    currentChunk++;
    throttler(
      () => sendPort.send({
        'content': NotificationContent(
            id: id,
            channelKey: 'downloader',
            title: fileName,
            body: '$currentChunk / ${totalChunks / 4096}',
            progress: (currentChunk / totalChunks) * 100,
            notificationLayout: NotificationLayout.ProgressBar,
            locked: true,
            payload: {"isolate": "$id", "fileName": fileName}),
        'actionButtons': [
          NotificationActionButton(
            key: 'cancelMega',
            label: 'Cancel',
          ),
        ],
      }),
    );
  }

  // Close the sink to finish writing to the file
  outputFileSink.close();

  DateTime endTime = DateTime.now();
  Duration taskDuration = endTime.difference(startTime);
   */

  sendPort.send({
    'content': NotificationContent(
      id: id,
      channelKey: 'downloader',
      title: fileName,
      body: "Download completed.",
      /* body: 'Task Time: ${taskDuration.inSeconds} seconds', */
    ),
  });
}

// Sadly ffmpeg_kit_flutter plugin doesn't support isolates...
// Unsupported operation: Background isolates do not support setMessageHandler(). Messages from the host platform always go to the root isolate.
// For now task will run on main thread...

/// Use ffmpeg to download playlist file as video file
void ffmpegTask(String url, String title) async {
  int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

  await NotificationController.initialize();

  AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: id,
      channelKey: 'downloader',
      title: "$title.mp4",
      body: "Preparing...",
    ),
  );

  // Get duration of video to use in progress notification
  double duration = await FFprobeKit.getMediaInformation(url).then(
    (session) async => double.parse(
      (double.parse(session.getMediaInformation()!.getDuration()!) * 1000)
          .toStringAsFixed(3),
    ),
  );

  // Slow down notification updates
  final throttler = Throttler(milliseconds: 2000);

  // Start the FFmpeg task
  final command = '-threads 4 -i $url -c copy -y "$savePath/$title.mp4"';
  FFmpegKit.executeAsync(command, (session) async {
    final returnCode = await session.getReturnCode();

    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: "$title.mp4",
        body: ReturnCode.isSuccess(returnCode)
            ? "Download completed."
            : ReturnCode.isCancel(returnCode)
                ? "Download canceled by user."
                : "Error occurred while downloading.",
      ),
    );
  }, (log) {
    //print(log.getMessage());
  }, (statistics) {
    // log("${statistics.getTime()}");
    throttler(() {
      double progress = statistics.getTime();
      AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: 'downloader',
          notificationLayout: NotificationLayout.ProgressBar,
          title: "$title.mp4",
          progress: (progress / duration) * 100,
          body: "${formatDuration(progress)} / ${formatDuration(duration)}",
          payload: {"session": "${statistics.getSessionId()}"},
          locked: true,
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'cancelFfmpeg',
            label: 'Cancel',
          ),
        ],
      );
    });
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
  Match? match = pattern.firstMatch(url.split('#').last) ??
      pattern.firstMatch(url.split('/').last) ??
      pattern.firstMatch(url);
  return match?.group(0)?.replaceAll('-', '+').replaceAll('_', '/');
}

String addBase64Padding(String value) {
  int paddingNeeded = 4 - (value.length % 4);
  return value + '=' * paddingNeeded;
}

// Return time in hh:mm:ss format for ffmpeg tasks
String formatDuration(double value) {
  int hh = value ~/ 3600000;
  int mm = (value % 3600000) ~/ 60000;
  int ss = ((value % 3600000) % 60000) ~/ 1000;
  return "${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}";
}

Future<void> initializeFileDownloader() async {
  //if(await FileDownloader().ready == true) return;
  log("Initializing FileDownloader");

  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
  await Permission.notification.request();

  await FileDownloader().configure(globalConfig: [
    (Config.requestTimeout, const Duration(seconds: 100))
  ], androidConfig: [
    (Config.useCacheDir, Config.whenAble)
  ]).then((result) => log('Configuration result = $result'));

  FileDownloader()
      .configureNotificationForGroup(
        FileDownloader.defaultGroup,
        running: const TaskNotification('{filename}',
            '{progress} - {networkSpeed} - {timeRemaining} remaining'),
        complete: const TaskNotification('{filename}', 'Download complete'),
        error: const TaskNotification('{filename}', 'Download failed'),
        paused: const TaskNotification('{filename}', 'Paused by user'),
        progressBar: true,
      )
      .configureNotificationForGroup('bunch',
          running: const TaskNotification(
              '{numFinished} out of {numTotal}', 'Progress = {progress}'),
          complete: const TaskNotification("Done!", "Loaded {numTotal} files"),
          error:
              const TaskNotification('Error', '{numFailed}/{numTotal} failed'),
          progressBar: false)
      .configureNotification(
        complete: const TaskNotification('{filename}', 'Download complete'),
        tapOpensFile: true,
      );
}
