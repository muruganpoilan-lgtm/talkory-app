import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:talkory_core/talkory_core.dart';

/// Host records a voice intro of up to 20 seconds. An admin listens before users can hear it.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.api});
  final Api api;
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  static const _maxSeconds = 20;
  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  Map<String, dynamic>? _meta;
  String? _path; // fresh recording not yet sent
  bool _recording = false, _busy = false, _playing = false;
  int _seconds = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec.dispose();
    _player.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.myProfile();
      if (mounted) setState(() => _meta = d);
    } catch (_) {}
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) return _toast('Allow microphone access to record');
      final path = '${Directory.systemTemp.path}/intro_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
      setState(() { _recording = true; _seconds = 0; _path = null; });
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stop();
      });
    } catch (_) {
      _toast('Could not start recording');
    }
  }

  Future<void> _stop() async {
    _tick?.cancel();
    try {
      final path = await _rec.stop();
      if (mounted) setState(() { _recording = false; _path = path; });
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _preview() async {
    if (_path == null) return;
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      setState(() => _playing = true);
      await _player.play(DeviceFileSource(_path!));
    }
  }

  Future<void> _send() async {
    if (_path == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.uploadIntro(base64Encode(await File(_path!).readAsBytes()));
      _toast('Sent for review');
      setState(() => _path = null);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await widget.api.removeIntro();
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _meta?['introStatus'] as String?;
    final live = _meta?['introUrl'] as String?;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Voice intro')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Say a short, friendly hello (up to 20 seconds). Users can play it on your card before they call. Do not share phone numbers or social handles; our team listens before it goes live.'),
          const SizedBox(height: 16),
          if (status == 'pending') const Card(child: ListTile(leading: Icon(Icons.hourglass_top), title: Text('Your intro is being reviewed'))),
          if (status == 'rejected')
            Card(child: ListTile(leading: Icon(Icons.error_outline, color: scheme.error), title: Text((_meta?['introNote'] as String?) ?? 'Your last intro was not approved'))),
          if (live != null && status != 'pending')
            Card(child: ListTile(leading: IntroButton(baseUrl: widget.api.baseUrl, url: live), title: const Text('Your live intro'), trailing: TextButton(onPressed: _busy ? null : _remove, child: const Text('Remove')))),
          const SizedBox(height: 24),
          Center(
            child: Column(children: [
              Text(_recording ? '0:${_seconds.toString().padLeft(2, '0')} / 0:$_maxSeconds' : (_path == null ? 'Tap to record' : 'Recorded'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              IconButton.filled(
                iconSize: 40,
                style: IconButton.styleFrom(backgroundColor: _recording ? Colors.red : scheme.primary, padding: const EdgeInsets.all(20)),
                onPressed: _busy ? null : (_recording ? _stop : _start),
                icon: Icon(_recording ? Icons.stop : Icons.mic),
              ),
            ]),
          ),
          if (_path != null && !_recording) ...[
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _preview, icon: Icon(_playing ? Icons.stop : Icons.play_arrow), label: Text(_playing ? 'Stop' : 'Listen'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _send,
                  child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send for review'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
