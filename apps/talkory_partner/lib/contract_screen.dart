import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

/// The partner agreement. Shown once KYC is approved; a host cannot go online until it is signed.
class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key, required this.api});
  final Api api;
  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  final _name = TextEditingController();
  Map<String, dynamic>? _c;
  bool _agree = false, _busy = false;
  String? _error;

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
      final c = await widget.api.partnerContract();
      if (mounted) setState(() => _c = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error. Try again.');
    }
  }

  Future<void> _sign() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.signContract(_name.text.trim());
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
    final c = _c;
    final signed = c?['signed'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Partner agreement')),
      body: c == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(c['text'] as String, style: const TextStyle(fontSize: 14, height: 1.45)),
                ]),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: signed
                      ? Row(children: [
                          const Icon(Icons.verified, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Signed by ${c['signedName']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        ])
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Type your full name (as on your ID)', border: OutlineInputBorder()),
                            onChanged: (_) => setState(() {}),
                          ),
                          CheckboxListTile(
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
                              onPressed: _busy || !_agree || _name.text.trim().length < 3 ? null : _sign,
                              child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign agreement'),
                            ),
                          ),
                        ]),
                ),
              ),
            ]),
    );
  }
}
