import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api.dart';

/// In-call screen: joins the Agora channel, shows the timer, mute and end buttons.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.api, required this.session, required this.peerName, this.onAddCredits});
  final Api api;
  final CallSession session;
  final String peerName;
  final VoidCallback? onAddCredits; // user app: opens the wallet over the call

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RtcEngine? _engine;
  Timer? _timer, _poll;
  int? _secondsLeft;
  bool _warned = false;
  int _seconds = 0;
  bool _connected = false, _muted = false, _leaving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return _leave('Microphone permission is required for calls');

    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(RtcEngineContext(
      appId: widget.session.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    engine.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (conn, uid, elapsed) {
        if (!mounted) return;
        setState(() => _connected = true);
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
        _poll ??= Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
      },
      onUserOffline: (conn, uid, reason) => _leave(),
    ));
    await engine.enableAudio();
    await engine.joinChannel(
      token: widget.session.token,
      channelId: widget.session.channel,
      uid: widget.session.uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
      ),
    );
  }

  /// Warns the user when talk time is running low, and leaves if the server already ended the call.
  Future<void> _checkStatus() async {
    if (_leaving) return;
    try {
      final s = await widget.api.callStatus(widget.session.callId);
      if (!mounted || _leaving) return;
      if (s['status'] != 'active') {
        return _leave((_secondsLeft ?? 999) <= 30 ? 'Call ended: balance used up' : 'Call ended');
      }
      final left = s['secondsLeft'] as int?;
      if (left != null && left <= 60 && !_warned) {
        _warned = true;
        HapticFeedback.heavyImpact();
      }
      if (left != null && left > 60) _warned = false; // topped up
      setState(() => _secondsLeft = left);
    } catch (_) {} // transient network error: try again in 5s
  }

  Future<void> _leave([String? message]) async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    _poll?.cancel();
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
    } catch (_) {}
    try {
      await widget.api.endCall(widget.session.callId);
    } catch (_) {} // already ended by the other side or the server
    if (!mounted) return;
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop(_connected);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  String get _clock {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerHighest,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(radius: 56, child: Text(widget.peerName.isEmpty ? '?' : widget.peerName[0].toUpperCase(), style: const TextStyle(fontSize: 40))),
              const SizedBox(height: 16),
              Text(widget.peerName, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(_connected ? _clock : 'Connecting…', style: Theme.of(context).textTheme.titleMedium),
              if (_secondsLeft != null && _secondsLeft! <= 60) ...[
                const SizedBox(height: 24),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _secondsLeft! <= 30 ? Colors.red.shade100 : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.black87),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Low balance: about ${_secondsLeft}s of talk time left',
                          style: const TextStyle(color: Colors.black87)),
                    ),
                    if (widget.onAddCredits != null)
                      TextButton(onPressed: widget.onAddCredits, child: const Text('Add credits')),
                  ]),
                ),
              ],
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      iconSize: 32,
                      onPressed: () {
                        setState(() => _muted = !_muted);
                        _engine?.muteLocalAudioStream(_muted);
                      },
                      icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    ),
                    const SizedBox(width: 32),
                    IconButton.filled(
                      iconSize: 32,
                      style: IconButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: _leave,
                      icon: const Icon(Icons.call_end),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
