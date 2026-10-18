import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api.dart';

/// Group video meeting arranged by the Talkory team. Free. Shared by all three apps:
/// users and hosts can only join; the admin app can also end the meeting for everyone.
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key, required this.api, required this.session, required this.title, this.asAdmin = false});
  final Api api;
  final CallSession session;
  final String title;
  final bool asAdmin;
  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  RtcEngine? _engine;
  Timer? _poll;
  final List<int> _remote = [];
  bool _muted = false, _camOff = false, _leaving = false;

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
        if (mounted && !_remote.contains(uid)) setState(() => _remote.add(uid));
      },
      onUserOffline: (conn, uid, reason) {
        if (mounted) setState(() => _remote.remove(uid));
      },
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
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final st = widget.asAdmin ? await widget.api.adminMeetingStatus(widget.session.callId) : await widget.api.meetingStatus(widget.session.callId);
        if (st == 'ended') _leave('The meeting has ended');
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
    if (!mounted) return;
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  Future<void> _endForAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: const Text('End this meeting for everyone?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('End for all')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.adminEndMeeting(widget.session.callId);
    } catch (_) {}
    _leave('Meeting ended');
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Widget _tile(Widget child) => ClipRRect(borderRadius: BorderRadius.circular(12), child: ColoredBox(color: const Color(0xFF1B1B1F), child: child));

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final tiles = <Widget>[
      if (engine != null)
        _tile(_camOff
            ? const Center(child: Icon(Icons.videocam_off, color: Colors.white54, size: 36))
            : AgoraVideoView(controller: VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0)))),
      if (engine != null)
        for (final uid in _remote)
          _tile(AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(uid: uid),
              connection: RtcConnection(channelId: widget.session.channel),
            ),
          )),
    ];
    final cols = tiles.length <= 1 ? 1 : (tiles.length <= 4 ? 2 : 3);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
                Text('${_remote.length + 1} in meeting', style: const TextStyle(color: Colors.white70)),
              ]),
            ),
            Expanded(
              child: engine == null
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: GridView.count(
                        crossAxisCount: cols,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: cols == 1 ? 0.75 : (cols == 2 ? 0.8 : 0.7),
                        children: tiles,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: () {
                    setState(() => _muted = !_muted);
                    engine?.muteLocalAudioStream(_muted);
                  },
                  icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                ),
                const SizedBox(width: 20),
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: () {
                    setState(() => _camOff = !_camOff);
                    engine?.muteLocalVideoStream(_camOff);
                  },
                  icon: Icon(_camOff ? Icons.videocam_off : Icons.videocam),
                ),
                const SizedBox(width: 20),
                IconButton.filled(
                  iconSize: 28,
                  style: IconButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: _leave,
                  icon: const Icon(Icons.call_end),
                  tooltip: 'Leave',
                ),
                if (widget.asAdmin) ...[
                  const SizedBox(width: 20),
                  FilledButton.tonal(onPressed: _endForAll, child: const Text('End for all')),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
