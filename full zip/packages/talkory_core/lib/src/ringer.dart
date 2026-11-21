import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// Real sounds (generated in code, no audio files needed): a looping ring for calls
/// and a short beep for new messages. Plays through the media volume.
class Ringer {
  Ringer._();
  static final Ringer instance = Ringer._();

  final AudioPlayer _ring = AudioPlayer();
  final AudioPlayer _ping = AudioPlayer();
  Uint8List? _ringWav, _pingWav;

  static const _rate = 22050;

  Uint8List _wav(List<double> samples) {
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32000).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// [segments]: (frequency Hz or 0 for silence, seconds)
  List<double> _tone(List<(double, double)> segments) {
    final out = <double>[];
    for (final (f, secs) in segments) {
      final n = (secs * _rate).round();
      for (var i = 0; i < n; i++) {
        if (f == 0) {
          out.add(0);
        } else {
          final t = i / _rate;
          final fade = math.min(1.0, math.min(i, n - i) / (0.02 * _rate)); // soft edges, no clicks
          out.add(0.45 * fade * (math.sin(2 * math.pi * f * t) + math.sin(2 * math.pi * (f + 40) * t)) / 2 * 2);
        }
      }
    }
    return out;
  }

  /// Starts a looping ring (double ring, pause, repeat).
  Future<void> startRing() async {
    try {
      _ringWav ??= _wav(_tone([(440, 0.4), (0, 0.2), (440, 0.4), (0, 1.6)]));
      await _ring.setReleaseMode(ReleaseMode.loop);
      await _ring.setVolume(1.0);
      await _ring.play(BytesSource(_ringWav!, mimeType: 'audio/wav'));
    } catch (_) {}
  }

  Future<void> stopRing() async {
    try {
      await _ring.stop();
    } catch (_) {}
  }

  /// One short beep for a new chat message.
  Future<void> message() async {
    try {
      _pingWav ??= _wav(_tone([(880, 0.12), (0, 0.04), (1175, 0.16)]));
      await _ping.setReleaseMode(ReleaseMode.release);
      await _ping.setVolume(1.0);
      await _ping.play(BytesSource(_pingWav!, mimeType: 'audio/wav'));
    } catch (_) {}
  }
}
