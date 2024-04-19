part of 'main.dart';

bool fileDownloaderInitialized = false;
bool notificationInitialized = false;
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
  if (!fileDownloaderInitialized) await initializeFileDownloader();

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

Future<void> initializeFileDownloader() async {
  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
  await Permission.notification.request();
  await Permission.ignoreBatteryOptimizations.request();

  await FileDownloader().configure(globalConfig: [
    (Config.requestTimeout, const Duration(seconds: 100))
  ], androidConfig: [
    (Config.useCacheDir, Config.whenAble)
  ]).then((result) => debugPrint('Configuration result = $result'));

  FileDownloader()
      .configureNotificationForGroup(
        FileDownloader.defaultGroup,
        running: const TaskNotification('{filename}',
            '{progress} - {networkSpeed} - {timeRemaining} remaining'),
        complete: const TaskNotification(
            '{filename}', 'Download complete'),
        error: const TaskNotification('{filename}', 'Download failed'),
        paused: const TaskNotification(
            '{filename}', 'Paused by user'),
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
        complete:
            const TaskNotification('{filename}', 'Download complete'),
        tapOpensFile: true,
      );

  fileDownloaderInitialized = true;
}

//////////////////////////////////////////////////////////////////////
// FFMPEG
//////////////////////////////////////////////////////////////////////

void startFFmpegTask(url, title, {headers = const {}}) async {
  // Request needed permissions
  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
  await Permission.notification.request();
  await Permission.ignoreBatteryOptimizations.request();

  if (!notificationInitialized) await initializeNotifications();

  // Generate id for this task notification
  var id = generateId();

  // Show information about task in notification
  void messenge(String text) {
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'Downloader',
        title: title,
        body: text,
        autoDismissible: false,
      ),
    );
  }

  // Show progress of task in notification
  void progress(double progress, double duration, int sessionId) {
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'Downloader',
        title: title,
        body: "${formatDuration(progress)} / ${formatDuration(duration)}",
        notificationLayout: NotificationLayout.ProgressBar,
        progress: progress / duration,
        payload: {"sessionId": sessionId.toString()},
        autoDismissible: false,
        locked: true,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'cancel',
          label: 'Cancel',
        ),
      ],
    );
  }

  messenge("Loading");
  log(url);

  // Get duration of video to use in progress notification
  double duration = await FFprobeKit.getMediaInformation(url).then(
    (session) async => double.parse(
      (double.parse(session.getMediaInformation()!.getDuration()!) * 1000)
          .toStringAsFixed(3),
    ),
  );

  // Slow down notification updates
  final throttler = Throttler(milliseconds: 3000);

  // Start the FFmpeg task
  // -user_agent "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.6312.118 Mobile Safari/537.36"
  final command = '-threads 4 -i $url -c copy -y "$savePath/$title.mp4"';
  FFmpegKit.executeAsync(command, (session) async {
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      messenge("Download completed.");
    } else if (ReturnCode.isCancel(returnCode)) {
      messenge("Download canceled by user.");
    } else {
      messenge("Error occurred while downloading.");
    }
  }, (log) {
    // print(log.getMessage());
  }, (statistics) {
    // log("${statistics.getTime()}");
    throttler(() =>
        progress(statistics.getTime(), duration, statistics.getSessionId()));
  });
}

Future<void> notificationOnClick(ReceivedAction receivedAction) async {
  if (receivedAction.body!.contains('Download completed.')) {
    OpenFile.open('$savePath/${receivedAction.title}');
    return;
  }

  if (receivedAction.buttonKeyPressed == "cancel") {
    FFmpegKit.cancel(int.parse(receivedAction.payload!["sessionId"]!));
  }
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

int generateId() {
  DateTime now = DateTime.now();
  int millisecondsSinceEpoch = now.millisecondsSinceEpoch;
  return millisecondsSinceEpoch % 1000000;
}

// Return time in hh:mm:ss format for ffmpeg tasks
String formatDuration(double value) {
  int hh = value ~/ 3600000;
  int mm = (value % 3600000) ~/ 60000;
  int ss = ((value % 3600000) % 60000) ~/ 1000;
  return "${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}";
}

Future<void> initializeNotifications() async {
  AwesomeNotifications().initialize(
    'resource://drawable/outline_file_download',
    [
      NotificationChannel(
        channelKey: 'Downloader',
        channelName: 'Downloader',
        channelDescription: 'Display download progress',
      ),
    ],
  );

  await AwesomeNotifications()
      .setListeners(onActionReceivedMethod: notificationOnClick);

  notificationInitialized = true;
}
