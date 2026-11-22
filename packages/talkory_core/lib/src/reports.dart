import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'api.dart';

/// Sends app crashes and per-call quality (time to connect, why it ended, network, phone model) to the server.
/// The admin panel shows them under App health. Never sends anything the user typed or said.
class AppReports {
  static Api? _api;
  static String? _device, _os;
  static int _crashesSent = 0;

  /// Call once at app start, after the Api is created.
  static Future<void> init(Api api) async {
    _api = api;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        _device = '${a.manufacturer} ${a.model}'.trim();
        _os = 'Android ${a.version.release}';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _device = i.utsname.machine;
        _os = 'iOS ${i.systemVersion}';
      }
    } catch (_) {}
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      crash(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      crash(error, stack);
      return false; // keep the normal handling too
    };
  }

  static void crash(Object error, StackTrace? stack) {
    final api = _api;
    if (api == null || api.token == null || _crashesSent >= 5) return; // a few per app session are enough
    _crashesSent++;
    unawaited(api.sendReport('crash', {'error': '$error', 'stack': '$stack', 'device': _device, 'os': _os}).catchError((_) {}));
  }

  static void call({
    required Api api,
    required String callId,
    required int? connectMs,
    required int durationS,
    required String endReason,
    required double? netQuality,
  }) {
    unawaited(api.sendReport('call', {
      'callId': callId,
      'connectMs': connectMs,
      'durationS': durationS,
      'endReason': endReason,
      'netQuality': netQuality,
      'device': _device,
      'os': _os,
    }).catchError((_) {}));
  }
}
