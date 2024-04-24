part of 'download_kit.dart';

class NotificationController {
  static SendPort? _uiSendPort;
  static ReceivePort? _receivePort;
  static final Map<int, Isolate> _isolates = {};

  static Future<void> initialize() async {
    if (_receivePort != null) return;

    await _initializeNotifications();

    _receivePort = ReceivePort();
    _uiSendPort = _receivePort!.sendPort;

    _receivePort!.listen((message) {
      if (message.containsKey('content')) {
        NotificationContent content = message['content'];
        List<NotificationActionButton>? actionButtons =
            message['actionButtons'];
        AwesomeNotifications().createNotification(
          content: content,
          actionButtons: actionButtons,
        );
      }
    });
  }

  static void killIsolate(dynamic args) {
    int id = int.parse(args[0]);
    String fileName = args[1];

    _isolates[id]!.kill(priority: Isolate.immediate);
    _isolates.remove(id);

    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'downloader',
        title: fileName,
        body: 'Canceled by user',
      ),
    );
  }

  static void startIsolate(
      void Function(dynamic) entryPoint, List<dynamic> args) async {
    await initialize();

    int isolateId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    args.insert(0, _uiSendPort);    // add port to comunicate between isolates
    args.insert(1, isolateId);      // add id to use as notification id

    Isolate isolate = await Isolate.spawn(entryPoint, [...args]);
    _isolates[isolateId] = isolate;
  }

  @pragma('vm:entry-point')
  static Future<void> onActionReceived(ReceivedAction receivedAction) async {
    if (receivedAction.body!.contains("Download completed.")) {
      OpenFile.open("$savePath/${receivedAction.title}", type: "video/*");
      return;
    }

    if (receivedAction.buttonKeyPressed == 'cancel') {
      String? id = receivedAction.payload?['isolate'];
      String? fileName = receivedAction.payload?['fileName'];
      if (id != null || fileName != null) {
        NotificationController.killIsolate([id, fileName]);
      }
    } else if (receivedAction.buttonKeyPressed == 'cancelFfmpeg') {
      FFmpegKit.cancel(int.parse(receivedAction.payload!["session"]!));
    }
  }

  static Future<void> _initializeNotifications() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    await Permission.videos.request();
    await Permission.notification.request();

    await AwesomeNotifications().requestPermissionToSendNotifications();

    AwesomeNotifications().initialize(
      'resource://drawable/outline_file_download',
      [
        NotificationChannel(
          channelKey: 'downloader',
          channelName: 'Downloader',
          channelDescription: 'Display download progress',
        ),
      ],
    );

    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceived,
    );
  }
}
