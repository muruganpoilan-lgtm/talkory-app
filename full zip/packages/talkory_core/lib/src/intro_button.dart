import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// "Play" button for a host's voice intro. [url] is a server path like /intros/abc.m4a.
class IntroButton extends StatefulWidget {
  const IntroButton({super.key, required this.baseUrl, required this.url});
  final String baseUrl, url;
  @override
  State<IntroButton> createState() => _IntroButtonState();
}

class _IntroButtonState extends State<IntroButton> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.stop();
        setState(() => _playing = false);
      } else {
        setState(() => _playing = true);
        await _player.play(UrlSource('${widget.baseUrl}${widget.url}'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play the intro')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _toggle,
      icon: Icon(_playing ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 18),
      label: Text(_playing ? 'Stop' : 'Play'),
      style: OutlinedButton.styleFrom(shape: const StadiumBorder(), visualDensity: VisualDensity.compact),
    );
  }
}
