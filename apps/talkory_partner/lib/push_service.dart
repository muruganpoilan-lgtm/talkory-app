import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:talkory_core/talkory_core.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Shows or dismisses the native incoming-call screen from a push payload.
/// Runs in the foreground AND in the background isolate (see main.dart).
Future<void> handlePushData(Map<String, dynamic> data) async {
  final callId = data['callId'] as String?;
  if (callId == null) return;

  if (data['type'] == 'incoming_call') {
    await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: callId, // our call ids are UUIDs, as CallKit requires
      nameCaller: (data['callerName'] as String?) ?? 'Caller',
      appName: 'Talkory Partner',
      handle: 'Voice call',
      type: 0, // audio
      duration: 20000, // matches the server's ring timeout
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: {'callId': callId},
      missedCallNotification: const NotificationParams(showNotification: true, isShowCallback: false, subtitle: 'Missed call'),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#00A884',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
      ),
      ios: const IOSParams(handleType: 'generic', supportsVideo: false),
    ));
  } else if (data['type'] == 'call_cancelled') {
    await FlutterCallkitIncoming.endCall(callId);
  }
}

class PushService {
  PushService._();
  static final instance = PushService._();

  Api? _api;
  String? _token;
  final _seen = <String>{}; // call ids we already acted on
  StreamSubscription? _fcm, _callkit, _refresh;

  Future<void> start(Api api) async {
    _api = api;
    await _cancelSubs();

    final fm = FirebaseMessaging.instance;
    await fm.requestPermission(alert: true, sound: true, badge: false);
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission(); // Android 14+: show over lock screen
    } catch (_) {}

    await _register(await fm.getToken());
    _refresh = fm.onTokenRefresh.listen(_register);
    _fcm = FirebaseMessaging.onMessage.listen((m) => handlePushData(m.data));
    _callkit = FlutterCallkitIncoming.onEvent.listen(_onCallEvent);

    await _resumeAccepted();
  }

  Future<void> stop() async {
    await _cancelSubs();
    final token = _token;
    if (token != null) {
      try {
        await _api?.unregisterDevice(token);
      } catch (_) {}
    }
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
    _token = null;
  }

  Future<void> _cancelSubs() async {
    await _fcm?.cancel();
    await _callkit?.cancel();
    await _refresh?.cancel();
  }

  Future<void> _register(String? token) async {
    if (token == null) return;
    _token = token;
    String? voip; // iOS: PushKit token that lets the backend ring the phone with the full-screen CallKit UI
    if (Platform.isIOS) {
      try {
        final v = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (v is String && v.isNotEmpty) voip = v;
      } catch (_) {}
    }
    try {
      await _api?.registerDevice(platform: Platform.isIOS ? 'ios' : 'android', pushToken: token, voipToken: voip);
    } catch (_) {} // retried on next app start / token refresh
  }

  void _onCallEvent(CallEvent? e) {
    if (e == null) return;
    final body = Map<String, dynamic>.from(e.body as Map);
    final callId = (body['extra'] as Map?)?['callId'] as String? ?? body['id'] as String?;
    if (callId == null) return;

    switch (e.event) {
      case Event.actionCallAccept:
        _accept(callId, (body['nameCaller'] as String?) ?? 'Caller');
      case Event.actionCallDecline:
        _decline(callId);
      default:
        break;
    }
  }

  /// App was killed and the user tapped Accept on the native screen: pick that call up now.
  Future<void> _resumeAccepted() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is! List) return;
      for (final c in calls) {
        final m = Map<String, dynamic>.from(c as Map);
        if (m['isAccepted'] == true) {
          final id = (m['extra'] as Map?)?['callId'] as String? ?? m['id'] as String?;
          if (id != null) await _accept(id, (m['nameCaller'] as String?) ?? 'Caller');
        }
      }
    } catch (_) {}
  }

  Future<void> _accept(String callId, String callerName) async {
    final api = _api;
    if (api == null || !_seen.add(callId)) return;
    try {
      final session = await api.acceptCall(callId);
      await FlutterCallkitIncoming.endCall(callId); // our own call screen takes over
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      final connected = await nav.push<bool>(
          MaterialPageRoute(builder: (_) => CallScreen(api: api, session: session, peerName: callerName)));
      if (connected == true) {
        await nav.push(MaterialPageRoute(
            builder: (_) => PostCallScreen(api: api, callId: session.callId, peerName: callerName, canRate: false)));
      }
    } on ApiException catch (e) {
      await FlutterCallkitIncoming.endCall(callId);
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(
            e.status == 409 ? 'That call is no longer available' : e.message)));
      }
    } catch (_) {
      await FlutterCallkitIncoming.endCall(callId);
    }
  }

  Future<void> _decline(String callId) async {
    if (!_seen.add(callId)) return;
    try {
      await _api?.rejectCall(callId);
    } catch (_) {}
  }
}
