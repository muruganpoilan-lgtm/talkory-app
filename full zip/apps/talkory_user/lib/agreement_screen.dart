import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

/// The user agreement: read it, type your name, sign with your finger, tick the box, tap Sign.
/// Returns true when signed. It cannot be skipped.
class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  final _name = TextEditingController();
  final _pad = GlobalKey<SignaturePadState>();
  String? _text, _error;
  bool _agree = false, _busy = false, _drawn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await widget.api.userAgreement();
      if (a['signed'] == true && mounted) return Navigator.pop(context, true);
      if (mounted) setState(() => _text = a['text'] as String);
    } on ApiException catch (e) {
      if (e.status == 401) return widget.onLogout();
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error. Pull back and try again.');
    }
  }

  bool get _ready => _agree && _drawn && _name.text.trim().length >= 2 && !_busy;

  Future<void> _sign() async {
    final png = await _pad.currentState?.toPngBase64();
    if (png == null) return setState(() => _error = 'Please sign in the box');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.signUserAgreement(fullName: _name.text.trim(), signaturePng: png);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // the agreement has to be signed to use Talkory
      child: Scaffold(
        appBar: AppBar(title: const Text('User agreement'), automaticallyImplyLeading: false),
        body: _text == null
            ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))) : const CircularProgressIndicator())
            : Column(children: [
                Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [Text(_text!, style: const TextStyle(fontSize: 14, height: 1.45))])),
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Your full name', isDense: true, border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      SignaturePad(key: _pad, height: 130, onChanged: () => setState(() => _drawn = !(_pad.currentState?.isEmpty ?? true))),
                      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _pad.currentState?.clear(), child: const Text('Clear signature'))),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _agree,
                        onChanged: (v) => setState(() => _agree = v ?? false),
                        title: const Text('I have read and agree to this agreement', style: TextStyle(fontSize: 14)),
                      ),
                      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _ready ? _sign : null,
                          child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign agreement'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
      ),
    );
  }
}
