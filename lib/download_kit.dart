// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

part of 'main.dart';

late SimpleDownloader _downloader;
DownloadStatus _status = DownloadStatus.undefined;
DownloaderTask _task = const DownloaderTask();
double _progress = 0.0;
int _offset = 0;
int _total = 0;

bool notificationInitialized = false;

List<DownloadQueue> downloadQueue = [];

// get access to setState of main widget class
late _MyAppState widgetInstance;

String savePath = '';

void downloadQueueAdd(url, fileName) async {
  downloadQueue.add(DownloadQueue(url, fileName));
  if (downloadQueue.length > 1) {
    NativeToast().makeText(
        message: 'Added to Queue:\n$fileName',
        duration: NativeToast.shortLength);
    return;
  }
  downloadQueueCheck();
}

void downloadQueueCheck() async {
  if (downloadQueue.isEmpty) {
    Future.delayed(const Duration(seconds: 1), _downloader.dispose);
    return;
  }
  await _download(downloadQueue[0].url, downloadQueue[0].fileName);
}

Future<void> _download(url, fileName) async {
  _task = DownloaderTask(
    url: downloadQueue[0].url,
    fileName: downloadQueue[0].fileName,
    downloadPath: savePath,
    bufferSize: 634,
  );

  await initNotifications();
  await initSimpleDownloader(int.parse(randomNumeric(5)));
  await _downloader.download();
}

void downloadOrStream(controller, url, fileName) async {
  await SessionManager().get('mode').then((val) async {
    String title = sanitizeFilename(fileName.toString().trim());
    if (p.basename(title).split('.')[0] == "video") {
      // rename generic file name to one before last pathSegment
      Uri u = Uri.parse(url);
      title = u.pathSegments[u.pathSegments.length - 2];
    }
    String ext = p.extension(title);

    switch (val) {
      case 'stream':
        if (ext != '') title = title.substring(0, title.length - ext.length);
        AndroidIntent(
          action: 'action_view',
          type: "video/*",
          data: url,
          arguments: {'title': title},
        ).launch();
        break;
      case 'download':
        if (ext == '') title += '.mp4';
        !(await File('$savePath/$title').exists() ||
                await File('$savePath/$title.tmp').exists())
            ? downloadQueueAdd(url, title)
            : NativeToast().makeText(
                message: _task.fileName == title
                    ? 'Already in Queue'
                    : 'File already exists!',
                duration: NativeToast.longLength);
        break;
      default:
        break;
    }
  });
}

// Notification initialization / click handler / battery optimalization disabler
Future<void> initNotifications() async {
  if (!notificationInitialized) {
    notificationInitialized = await AwesomeNotifications().initialize(
      "resource://drawable/push_icon",
      [
        NotificationChannel(
          channelGroupKey: 'shinden_downloader_group',
          channelKey: 'shinden_downloader',
          importance: NotificationImportance.Low,
          channelName: 'Shinden Downloader',
          channelDescription: 'Shows progress of downloading videos',
          defaultColor: const Color(0xff181818),
          ledColor: Colors.white,
        )
      ],
      // Channel groups are only visual and are not required
      channelGroups: [
        NotificationChannelGroup(
          channelGroupKey: 'shinden_downloader_group',
          channelGroupName: 'Shinden Downloader Group',
        )
      ],
      debug: false,
    );

    await AwesomeNotifications().setListeners(
        onActionReceivedMethod: notificationOnClick,
        onDismissActionReceivedMethod: notificationOnDismiss);

    log('[#] Awesome Notification initialized.');

    await Permission.ignoreBatteryOptimizations.request();
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    await Permission.notification.isDenied.then((value) {
      if (value) Permission.notification.request();
    });

    log('[#] Permissions requested');
  }
}

Future<void> initSimpleDownloader(id) async {
  _downloader = SimpleDownloader.init(task: _task);

  // prevents too much changes in notification UI
  final thr = Throttling(duration: const Duration(seconds: 1));

  _downloader.callback.addListener(() async {
    widgetInstance.setState(() {
      _progress = _downloader.callback.progress;
      _status = _downloader.callback.status;
      _total = _downloader.callback.total;
      _offset = _downloader.callback.offset;
    });

    // slow down notification update, prevents system halting notification update process
    thr.throttle(() async => setNotification(id));

    // to trigger failed notification
    if (_status == DownloadStatus.failed) setNotification(id);

    // make sure completed notification will show
    if (_status == DownloadStatus.completed) {
      setNotification(id);
      await thr.close();
    }
  });

  log('[#] Simple Downloader initialized.');
}

Future<void> setNotification(id) async {
  log('${_task.fileName} | ${FileSize.getSize(_offset, precision: PrecisionValue.Two)} / ${FileSize.getSize(_total, precision: PrecisionValue.Two)} | $_status');
  switch (_status) {
    case DownloadStatus.running:
    case DownloadStatus.resume:
      notificationProgress(_offset, _total, _progress, _task.fileName, id);
      break;
    case DownloadStatus.paused:
      notificationPaused(_task.fileName, id);
      break;
    case DownloadStatus.failed:
      notificationFailed(
          'Download error', _task.fileName, ActionType.SilentAction, id);
      break;
    case DownloadStatus.canceled:
      notificationMessage(
          'Download canceled', _task.fileName, ActionType.SilentAction, id);
      File('$savePath/${_task.fileName}.tmp').delete();
      downloadQueue.removeAt(0);
      downloadQueueCheck();
      break;
    case DownloadStatus.completed:
      notificationMessage(
          'Download sucessful', _task.fileName, ActionType.Default, id);
      downloadQueue.removeAt(0);
      downloadQueueCheck();
      break;
    default:
      notificationMessage(
          _status.name, _task.fileName, ActionType.DisabledAction, id);
      break;
  }
}

Future<void> notificationOnClick(ReceivedAction receivedAction) async {
  if (receivedAction.body!.contains('Download sucessful')) {
    OpenFile.open('$savePath/${receivedAction.title}');
    return;
  }

  switch (receivedAction.buttonKeyPressed) {
    case 'cancel':
      _downloader.cancel();
      break;
    case 'pause':
      _downloader.pause();
      break;
    case 'resume':
    case 'retry':
      _downloader.retry();
      break;
  }
  setNotification(receivedAction.id);
}

Future<void> notificationOnDismiss(ReceivedAction receivedAction) async {
  if (receivedAction.body!.contains("Download error.")) {
    downloadQueue.removeAt(0);
    downloadQueueCheck();
  }
}

Future<void> notificationMessage(
    msg, fileName, ActionType actionType, id) async {
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: id,
      channelKey: 'shinden_downloader',
      title: fileName,
      body: msg,
      notificationLayout: NotificationLayout.Default,
      locked: false,
      actionType: actionType,
      criticalAlert: false,
      wakeUpScreen: false,
    ),
  );
}

Future<void> notificationProgress(
    received, total, progress, fileName, id) async {
  String progressString = total == 0
      ? 'Initialization'
      : "${FileSize.getSize(received)} / ${FileSize.getSize(total)}";
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: id,
      channelKey: 'shinden_downloader',
      title: fileName,
      body: progressString,
      progress: progress.floor(),
      category: NotificationCategory.Progress,
      notificationLayout: NotificationLayout.ProgressBar,
      locked: true,
      actionType: ActionType.SilentBackgroundAction,
      wakeUpScreen: false,
      criticalAlert: true,
      autoDismissible: false,
    ),
    actionButtons: [
      NotificationActionButton(
        key: 'cancel',
        label: 'Cancel',
        autoDismissible: false,
      ),
      NotificationActionButton(
        key: 'pause',
        label: 'Pause',
        autoDismissible: false,
      ),
    ],
  );
}

Future<void> notificationFailed(
    msg, fileName, ActionType actionType, id) async {
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: id,
      channelKey: 'shinden_downloader',
      title: fileName,
      body: msg,
      notificationLayout: NotificationLayout.Default,
      locked: false,
      actionType: actionType,
      autoDismissible: false,
    ),
    actionButtons: [
      NotificationActionButton(
        key: 'retry',
        label: 'Retry',
        autoDismissible: false,
      ),
    ],
  );
}

Future<void> notificationPaused(fileName, id) async {
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: id,
      channelKey: 'shinden_downloader',
      title: fileName,
      body: "Paused",
      notificationLayout: NotificationLayout.Default,
      locked: true,
      actionType: ActionType.SilentAction,
      autoDismissible: false,
    ),
    actionButtons: [
      NotificationActionButton(
        key: 'cancel',
        label: 'Cancel',
        autoDismissible: false,
      ),
      NotificationActionButton(
        key: 'resume',
        label: 'Resume',
        autoDismissible: false,
      ),
    ],
  );
}

class DownloadQueue {
  String url = '';
  String fileName = '';

  DownloadQueue(this.url, this.fileName);
}
