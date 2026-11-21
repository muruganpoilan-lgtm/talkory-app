import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api.dart';
import 'meeting.dart';
import 'ringer.dart';

/// Watches for a video call from the Talkory team (started in the admin panel) and shows Accept / Decline.
/// Shared by both apps. Users and hosts can only answer these calls, never start them. They are free.
class AdminCallWatcher {
  AdminCallWatcher._();
  static final AdminCallWatcher instance = AdminCallWatcher._();

  Timer? _timer;
  bool _busy = false;
  final Set<String> _seen = {};
  final Set<String> _seenMeetings = {};
  final Map<String, DateTime> _snoozed = {};
  int _tick = 0;

  void start(BuildContext context, Api api) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check(context, api));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check(BuildContext context, Api api) async {
    if (_busy || !context.mounted) return;
    try {
      final c = await api.adminCallIncoming();
      final id = c?['id'] as String?;
      if (id != null && _seen.add(id) && context.mounted) {
        _busy = true;
        await _ring(context, api, id);
        return;
      }
      // Meetings arranged by the team: look every ~9 seconds
      if (++_tick % 3 == 0 && context.mounted) await _checkMeetings(context, api);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }


  Future<void> _checkMeetings(BuildContext context, Api api) async {
    final list = await api.liveMeetings();
    for (final m in list) {
      final id = (m as Map)['id'] as String;
      final snooze = _snoozed[id];
      if (_seenMeetings.contains(id) || (snooze != null && DateTime.now().isBefore(snooze)) || !context.mounted) continue;
      _busy = true;
      final title = '${m['title'] ?? 'Meeting'}';
      final join = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => AlertDialog(
          title: const Text('Video meeting'),
          content: Text('The Talkory team has started a meeting: $title'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Join')),
          ],
        ),
      );
      if (join != true || !context.mounted) {
        _snoozed[id] = DateTime.now().add(const Duration(minutes: 10));
        return;
      }
      try {
        final session = await api.joinMeeting(id);
        if (!context.mounted) return;
        _seenMeetings.add(id);
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingScreen(api: api, session: session, title: title)));
      } on ApiException catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
  }

  Future<void> _ring(BuildContext context, Api api, String id) async {
    Ringer.instance.startRing();
    HapticFeedback.vibrate();
    final nav = Navigator.of(context, rootNavigator: true);
    final buzz = Timer.periodic(const Duration(milliseconds: 1500), (_) => HapticFeedback.vibrate());
    var open = true;
    // Close the box when the admin hangs up or the ring runs out
    final watch = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        if (await api.adminCallStatus(id) != 'ringing' && open) nav.pop();
      } catch (_) {}
    });
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('Video call'),
        content: const Text('The Talkory team is calling you on video.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Decline')),
          FilledButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Accept')),
        ],
      ),
    );
    open = false;
    watch.cancel();
    buzz.cancel();
    Ringer.instance.stopRing();
    if (accept == false) {
      try {
        await api.rejectAdminCall(id);
      } catch (_) {}
      return;
    }
    if (accept != true || !context.mounted) return;
    try {
      final session = await api.acceptAdminCall(id);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminVideoScreen(api: api, session: session)));
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {}
  }
}

/// Full-screen video call with the Talkory team.
class AdminVideoScreen extends StatefulWidget {
  const AdminVideoScreen({super.key, required this.api, required this.session, this.asAdmin = false});
  final Api api;
  final CallSession session;
  final bool asAdmin; // true in the admin app: this phone started the call
  @override
  State<AdminVideoScreen> createState() => _AdminVideoScreenState();
}

class _AdminVideoScreenState extends State<AdminVideoScreen> {
  RtcEngine? _engine;
  Timer? _poll;
  int? _remoteUid;
  bool _muted = false, _camOff = false, _leaving = false, _answered = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final r = await [Permission.microphone, Permission.camera].request();
    if (r[Permission.microphone]?.isGranted != true) return _leave('Microphone permission is required');
    final camOk = r[Permission.camera]?.isGranted == true;

    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(RtcEngineContext(appId: widget.session.appId, channelProfile: ChannelProfileType.channelProfileCommunication));
    engine.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (conn, uid, elapsed) {
        if (mounted) setState(() => _remoteUid = uid);
      },
      onUserOffline: (conn, uid, reason) => _leave('Call ended'),
    ));
    await engine.enableAudio();
    if (camOk) {
      await engine.enableVideo();
      await engine.startPreview();
    } else {
      _camOff = true;
    }
    await engine.setEnableSpeakerphone(true);
    await engine.joinChannel(
      token: widget.session.token,
      channelId: widget.session.channel,
      uid: widget.session.uid,
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        publishCameraTrack: camOk,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
      ),
    );
    if (mounted) setState(() {});
    _poll = Timer.periodic(Duration(seconds: widget.asAdmin ? 2 : 4), (_) async {
      try {
        if (widget.asAdmin) {
          final st = await widget.api.adminVideoStatus(widget.session.callId);
          if (st == 'rejected') return _leave('Declined');
          if (st == 'missed') return _leave('No answer');
          if (st == 'ended') return _leave('Call ended');
          if (st == 'active' && mounted && !_answered) setState(() => _answered = true);
        } else if (await widget.api.adminCallStatus(widget.session.callId) != 'active') {
          _leave('Call ended');
        }
      } catch (_) {}
    });
  }

  Future<void> _leave([String? message]) async {
    if (_leaving) return;
    _leaving = true;
    _poll?.cancel();
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
    } catch (_) {}
    try {
      if (widget.asAdmin) {
        await widget.api.adminEndVideo(widget.session.callId);
      } else {
        await widget.api.endAdminCall(widget.session.callId);
      }
    } catch (_) {}
    if (!mounted) return;
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: engine != null && _remoteUid != null
                ? AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: engine,
                      canvas: VideoCanvas(uid: _remoteUid),
                      connection: RtcConnection(channelId: widget.session.channel),
                    ),
                  )
                : Center(child: Text(widget.asAdmin ? (_answered ? 'Connecting…' : 'Ringing…') : 'Connecting…', style: const TextStyle(color: Colors.white70, fontSize: 18))),
          ),
          if (engine != null && !_camOff)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              width: 110,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AgoraVideoView(controller: VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0))),
              ),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                iconSize: 30,
                onPressed: () {
                  setState(() => _muted = !_muted);
                  engine?.muteLocalAudioStream(_muted);
                },
                icon: Icon(_muted ? Icons.mic_off : Icons.mic),
              ),
              const SizedBox(width: 24),
              IconButton.filledTonal(
                iconSize: 30,
                onPressed: () {
                  setState(() => _camOff = !_camOff);
                  engine?.muteLocalVideoStream(_camOff);
                },
                icon: Icon(_camOff ? Icons.videocam_off : Icons.videocam),
              ),
              const SizedBox(width: 24),
              IconButton.filled(
                iconSize: 30,
                style: IconButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: _leave,
                icon: const Icon(Icons.call_end),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
