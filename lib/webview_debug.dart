import 'package:flutter/foundation.dart';

class WebViewDebug {
  WebViewDebug._();

  static final ValueNotifier<List<String>> events = ValueNotifier([]);
  static int _seq = 0;

  static void log(String tag, String message) {
    if (!kDebugMode) return;

    final line = '${DateTime.now().toIso8601String().substring(11, 23)} #${++_seq} [$tag] $message';
    debugPrint('[WebViewDebug] $line');

    final current = List<String>.from(events.value);
    current.insert(0, line);
    if (current.length > 14) current.removeRange(14, current.length);
    events.value = current;
  }
}
