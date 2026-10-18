import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api.dart';
import 'ringer.dart';
import 'widgets.dart';

/// In-call screen: joins the Agora channel, shows the timer, mute and end buttons.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.api, required this.session, required this.peerName, this.onAddCredits, this.peerFemale = true});
  final Api api;
  final CallSession session;
  final String peerName;
  final bool peerFemale; // which default avatar to show for the other person
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
  bool _connected = false, _muted = false, _leaving = false, _speaker = false, _free = false;

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
        Ringer.instance.stopRing();
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
    // Also watch the call while it is still ringing, so a decline or no-answer closes this screen
    _poll ??= Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
    if (!_connected && !_leaving) Ringer.instance.startRing(); // ringback tone for the caller
  }

  /// Warns the user when talk time is running low, and leaves if the server already ended the call.
  Future<void> _checkStatus() async {
    if (_leaving) return;
    try {
      final s = await widget.api.callStatus(widget.session.callId);
      if (!mounted || _leaving) return;
      if (s['status'] == 'ringing') return; // still ringing on the other phone
      if (s['status'] != 'active') {
        return _leave(s['status'] == 'rejected' ? 'Call declined' : !_connected ? 'No answer' : _free ? 'Free call ended' : (_secondsLeft ?? 999) <= 30 ? 'Call ended: balance used up' : 'Call ended');
      }
      final left = s['secondsLeft'] as int?;
      if (left != null && left <= 60 && !_warned) {
        _warned = true;
        HapticFeedback.heavyImpact();
      }
      if (left != null && left > 60) _warned = false; // topped up
      setState(() {
        _secondsLeft = left;
        _free = s['free'] == true;
      });
    } catch (_) {} // transient network error: try again in 5s
  }

  Future<void> _leave([String? message]) async {
    if (_leaving) return;
    _leaving = true;
    Ringer.instance.stopRing();
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
    Ringer.instance.stopRing();
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
              AvatarFigure(female: widget.peerFemale, radius: 56, seed: AvatarFigure.seedOf(widget.peerName)),
              const SizedBox(height: 16),
              Text(widget.peerName, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(_connected ? _clock : 'Ringing…', style: Theme.of(context).textTheme.titleMedium),
              if (_secondsLeft != null && !_free && _secondsLeft! <= 60) ...[
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
                      child: Text(_free ? 'Free call: about ${_secondsLeft}s left' : 'Low balance: about ${_secondsLeft}s of talk time left',
                          style: const TextStyle(color: Colors.black87)),
                    ),
                    if (widget.onAddCredits != null && !_free)
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
                    IconButton.filledTonal(
                      iconSize: 32,
                      onPressed: () {
                        setState(() => _speaker = !_speaker);
                        _engine?.setEnableSpeakerphone(_speaker);
                      },
                      icon: Icon(_speaker ? Icons.volume_up : Icons.volume_down),
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
