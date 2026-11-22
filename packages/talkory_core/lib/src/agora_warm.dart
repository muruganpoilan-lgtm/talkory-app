import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Agora regions to connect through: India first, then the rest of Asia. Faster than a worldwide search.
const int kAgoraAreaIndiaAsia = 0x00000020 | 0x00000008;

/// Starts the call engine early (while the phone rings, or while the call request is on its way),
/// so joining the call no longer waits for the engine to start. Saves about 1-2 seconds per call.
class AgoraWarm {
  static Future<RtcEngine>? _pending;
  static String? _pendingAppId;
  static const _key = 'agora_app_id';

  /// Begin starting the engine in the background. Safe to call many times; does nothing until one call has happened
  /// (the app id comes from the server and is remembered after the first call).
  static Future<void> warm([String? appId]) async {
    try {
      appId ??= (await SharedPreferences.getInstance()).getString(_key);
      if (appId == null || appId.isEmpty) return;
      final f = _start(appId);
      unawaited(f.then((_) {}, onError: (_) {
        if (identical(_pending, f)) { _pending = null; _pendingAppId = null; } // failed: the call screen starts a fresh one
      }));
    } catch (_) {}
  }

  static Future<RtcEngine> _start(String appId) {
    if (_pending != null && _pendingAppId == appId) return _pending!;
    _pendingAppId = appId;
    final f = () async {
      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        areaCode: kAgoraAreaIndiaAsia,
      ));
      await engine.enableAudio();
      return engine;
    }();
    _pending = f;
    return f;
  }

  /// The ready engine for a call screen. Uses the warmed-up one if there is one, otherwise starts it now.
  /// The call screen releases it when the call ends; the next call starts a fresh one.
  static Future<RtcEngine> take(String appId) async {
    unawaited(SharedPreferences.getInstance().then((p) => p.setString(_key, appId)).catchError((_) => false));
    final f = _start(appId);
    _pending = null;
    _pendingAppId = null;
    try {
      return await f;
    } catch (_) {
      return _start(appId).whenComplete(() {
        _pending = null;
        _pendingAppId = null;
      });
    }
  }
}
