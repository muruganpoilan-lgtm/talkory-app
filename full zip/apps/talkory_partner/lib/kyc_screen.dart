import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talkory_core/talkory_core.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key, required this.api});
  final Api api;
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _picker = ImagePicker();
  Map<String, dynamic>? _s;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.kycStatus();
      if (mounted) setState(() { _s = s; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Network error');
    }
  }

  Future<void> _guard(Future<void> Function() task, [String? ok]) async {
    setState(() => _busy = true);
    try {
      await task();
      if (ok != null) _snack(ok);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(String kind) async {
    ImageSource? source = ImageSource.camera; // selfies are camera-only
    if (kind == 'id_front') {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ]),
        ),
      );
      if (source == null) return;
    }
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
      preferredCameraDevice: kind == 'selfie' ? CameraDevice.front : CameraDevice.rear,
    );
    if (x == null) return;
    await _guard(() async => widget.api.uploadKycDocument(kind, base64Encode(await x.readAsBytes())), 'Photo uploaded');
  }

  Widget _docTile(String kind, String title, String hint, bool done, bool locked) => Card(
        child: ListTile(
          leading: Icon(done ? Icons.check_circle : Icons.add_a_photo_outlined, color: done ? Colors.green : null),
          title: Text(title),
          subtitle: Text(done ? 'Uploaded. Tap to replace' : hint),
          onTap: locked || _busy ? null : () => _upload(kind),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Verification (KYC)')),
      body: s == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : _body(s),
    );
  }

  Widget _body(Map<String, dynamic> s) {
    final status = s['status'] as String;
    final docs = List<String>.from(s['docs']);
    final submitted = s['submitted'] == true;
    final locked = status == 'approved' || (submitted && status == 'pending');
    final ready = docs.contains('id_front') && docs.contains('selfie');

    final (icon, color, headline, detail) = switch (status) {
      'approved' => (Icons.verified, Colors.green, 'You are verified', 'You can go online and receive calls.'),
      'rejected' => (Icons.error_outline, Colors.red, 'Verification was not approved', (s['note'] as String?) ?? 'Please upload clear photos and submit again.'),
      _ when submitted => (Icons.hourglass_top, Colors.orange, 'Under review', 'We will unlock going online once your documents are approved.'),
      _ => (Icons.info_outline, Colors.blueGrey, 'Verify your identity', 'Upload both photos, then submit them for review.'),
    };

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          color: color.withValues(alpha: 0.12),
          child: ListTile(leading: Icon(icon, color: color), title: Text(headline), subtitle: Text(detail)),
        ),
        const SizedBox(height: 8),
        _docTile('id_front', 'Government ID photo', 'Clear photo of the front of your ID', docs.contains('id_front'), locked),
        _docTile('selfie', 'Selfie', 'Take a clear photo of your face', docs.contains('selfie'), locked),
        const SizedBox(height: 8),
        Text('Your documents are only used to verify your identity. They are never shown to callers.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        if (!locked)
          FilledButton(
            onPressed: _busy || !ready ? null : () => _guard(widget.api.submitKyc, 'Submitted for review'),
            child: Text(status == 'rejected' ? 'Submit again' : 'Submit for review'),
          ),
      ],
    );
  }
}
