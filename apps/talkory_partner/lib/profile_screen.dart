import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talkory_core/talkory_core.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.api});
  final Api api;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _tagline = TextEditingController();
  final _langs = <String>{};
  Map<String, dynamic>? _meta;
  double _rate = 10;
  bool _saving = false;
  String? _error, _avatarUrl, _avatarStatus, _avatarNote;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.myProfile();
      if (!mounted) return;
      setState(() {
        _meta = d;
        _name.text = d['displayName'];
        _tagline.text = (d['tagline'] as String?) ?? '';
        _setAvatar(d);
        _bio.text = d['bio'];
        _langs.addAll(List<String>.from(d['languages']));
        _rate = (d['rateRupees'] as num).toDouble().clamp((d['minRate'] as num).toDouble(), (d['maxRate'] as num).toDouble());
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Network error');
    }
  }

  void _setAvatar(Map<String, dynamic> d) {
    _avatarUrl = d['avatarUrl'] as String?;
    _avatarStatus = d['avatarStatus'] as String?;
    _avatarNote = d['avatarNote'] as String?;
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _photoTask(Future<void> Function() task, String ok) async {
    setState(() => _photoBusy = true);
    try {
      await task();
      final d = await widget.api.myProfile(); // refresh only the photo, never the unsaved name/bio fields
      if (mounted) setState(() => _setAvatar(d));
      _toast(ok);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final x = await ImagePicker().pickImage(source: source, maxWidth: 800, imageQuality: 80);
    if (x == null) return;
    await _photoTask(() async => widget.api.uploadAvatar(base64Encode(await x.readAsBytes())), 'Photo sent for review');
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.saveProfile(
        displayName: _name.text.trim(),
        tagline: _tagline.text.trim(),
        bio: _bio.text.trim(),
        languages: _langs.toList(),
        rateRupees: _rate.round(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _meta;
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: m == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Column(children: [
                    ProfileAvatar(baseUrl: widget.api.baseUrl, name: '', url: _avatarUrl, radius: 48),
                    const SizedBox(height: 8),
                    if (_avatarStatus == 'pending') const Text('Your new photo is being reviewed'),
                    if (_avatarStatus == 'rejected')
                      Text(_avatarNote ?? 'Your last photo was not approved', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    Wrap(spacing: 8, children: [
                      TextButton.icon(
                        onPressed: _photoBusy ? null : _pickPhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(_avatarUrl == null ? 'Add photo' : 'Change photo'),
                      ),
                      if (_avatarUrl != null || _avatarStatus == 'pending')
                        TextButton(onPressed: _photoBusy ? null : () => _photoTask(widget.api.removeAvatar, 'Photo removed'), child: const Text('Remove')),
                    ]),
                    Text('Use a clear photo of yourself. No contact details, text or explicit content. Photos are reviewed before they appear.',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  maxLength: 30,
                  decoration: const InputDecoration(labelText: 'Display name', helperText: 'Shown to callers instead of your number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tagline,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Tagline', helperText: 'A short line shown under your name, e.g. Calm Friend', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bio,
                  maxLength: 300,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'About you', helperText: 'No phone numbers, links or social handles', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Text('Languages you speak', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final l in List<String>.from(m['allLanguages']))
                      FilterChip(
                        label: Text(l),
                        selected: _langs.contains(l),
                        onSelected: (on) => setState(() => on ? _langs.add(l) : _langs.remove(l)),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Call rate (same for every host)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('Callers pay ₹10 per minute. You earn ₹6 for every minute you talk.',
                    style: Theme.of(context).textTheme.bodySmall),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                ),
              ],
            ),
    );
  }
}
