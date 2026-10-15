import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talkory_core/talkory_core.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.api,
    required this.balance,
    required this.onWallet,
    required this.onLogout,
    required this.language,
    required this.onLanguage,
    required this.active,
  });
  final Api api;
  final int? balance; // paise
  final VoidCallback onWallet, onLogout;
  final String? language; // preferred language filter for the Call tab
  final void Function(String?) onLanguage;
  final bool active; // true while this tab is shown, so the level card refreshes after calls

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? _me;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProfileTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    try {
      final m = await widget.api.accountMe();
      if (mounted) setState(() => _me = m);
    } catch (_) {}
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _photo() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, 'gallery')),
          if (_me?['avatarUrl'] != null) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove photo'), onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (choice == null) return;
    setState(() => _photoBusy = true);
    try {
      if (choice == 'remove') {
        await widget.api.removeUserAvatar();
      } else {
        final x = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 800, imageQuality: 80);
        if (x == null) return;
        await widget.api.uploadUserAvatar(base64Encode(await x.readAsBytes()));
      }
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _gst() async {
    final c = TextEditingController(text: (_me?['gstNumber'] as String?) ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GST number'),
        content: TextField(
          controller: c,
          textCapitalization: TextCapitalization.characters,
          maxLength: 15,
          decoration: const InputDecoration(hintText: '22AAAAA0000A1Z5', helperText: 'Optional. Used for GST invoices.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await widget.api.setGst(c.text.trim().toUpperCase());
      _snack(c.text.trim().isEmpty ? 'GST number removed' : 'GST number saved');
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _pickLanguage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Show hosts who speak…', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final l in [null, ...kLanguages])
            ListTile(
              title: Text(l ?? 'All languages'),
              trailing: widget.language == l ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, l ?? ''),
            ),
        ]),
      ),
    );
    if (choice == null) return;
    widget.onLanguage(choice.isEmpty ? null : choice);
  }

  Widget _levelCard(BuildContext context) {
    final level = (_me?['level'] as String?) ?? 'New';
    final minutes = (_me?['minutes'] as num?)?.toInt() ?? 0;
    final next = _me?['nextLevel'] as String?;
    final nextAt = (_me?['nextAt'] as num?)?.toInt();
    final from = (_me?['levelFrom'] as num?)?.toInt() ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final progress = (next == null || nextAt == null || nextAt <= from) ? 1.0 : ((minutes - from) / (nextAt - from)).clamp(0.0, 1.0);
    return Card(
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.workspace_premium, color: scheme.primary),
            const SizedBox(width: 8),
            Text('$level  ·  $minutes mins', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 6),
          Text(next == null ? 'You have reached the top level' : '${nextAt! - minutes} more mins to $next', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (_me?['displayName'] as String?) ?? '';
    final phone = (_me?['phone'] as String?) ?? '';
    final gst = (_me?['gstNumber'] as String?) ?? '';
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Column(children: [
            Stack(children: [
              ProfileAvatar(baseUrl: widget.api.baseUrl, name: name, url: _me?['avatarUrl'] as String?, radius: 48, female: false),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: _photoBusy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : IconButton(padding: EdgeInsets.zero, iconSize: 16, color: Colors.white, icon: const Icon(Icons.photo_camera), onPressed: _photo),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(name.isEmpty ? '—' : name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            if (phone.isNotEmpty) Text(phone, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Only you can see your photo', style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 16),
        _levelCard(context),
        const SizedBox(height: 4),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.monetization_on_outlined),
            title: Text(widget.balance == null ? 'Coins' : '${formatCoins(widget.balance!)} coins'),
            subtitle: const Text('Add coins and see your activity'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onWallet,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Privacy & Security'),
          subtitle: const Text('Terms, Privacy Policy, delete account'),
          onTap: () => showLegalSheet(context, widget.api, onAccountDeleted: widget.onLogout),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Language'),
          subtitle: Text(widget.language ?? 'All languages'),
          onTap: _pickLanguage,
        ),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: const Text('Customer Support'),
          subtitle: const Text('Chat with the Talkory team'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupportScreen(api: widget.api))),
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(gst.isEmpty ? 'Add GST Number' : 'GST Number'),
          subtitle: gst.isEmpty ? null : Text(gst),
          onTap: _gst,
        ),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'), onTap: widget.onLogout),
      ],
    );
  }
}
