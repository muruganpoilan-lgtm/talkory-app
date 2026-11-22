import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';

/// Android battery saving can hold back the incoming-call alert by several seconds (or drop it) when the app is closed.
/// Hosts are asked once to let the app run in the background.
class BackgroundRun {
  /// True when the phone may delay calls because the app is not allowed to run in the background.
  static Future<bool> needed() async {
    if (!Platform.isAndroid) return false;
    try {
      return !(await Permission.ignoreBatteryOptimizations.isGranted);
    } catch (_) {
      return false;
    }
  }

  /// Opens the system prompt. Returns true when allowed.
  static Future<bool> request() async {
    try {
      return (await Permission.ignoreBatteryOptimizations.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Microphone permission ahead of the first call, so accepting a call doesn't stop at a permission dialog.
  static Future<void> askMicrophone() async {
    try {
      await Permission.microphone.request();
    } catch (_) {}
  }
}
