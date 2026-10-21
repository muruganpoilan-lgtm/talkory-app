import 'dart:async';
import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'contract_screen.dart';
import 'home_screen.dart';
import 'kyc_screen.dart';

/// A host reaches the dashboard only after verification (KYC) is approved AND the partner agreement is signed.
/// Until then this screen shows the two steps and what is left to do.
class SetupGate extends StatefulWidget {
  const SetupGate({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<SetupGate> createState() => _SetupGateState();
}

class _SetupGateState extends State<SetupGate> {
  bool _loaded = false, _ready = false;
  String _kyc = 'none'; // none | pending | approved | rejected
  String? _kycNote, _error;
  bool _signed = false, _submitted = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load()); // picks up the approval while the host waits
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final k = await widget.api.kycStatus();
      final kyc = (k['status'] as String?) ?? 'none';
      var signed = false;
      if (kyc == 'approved') signed = (await widget.api.partnerContract())['signed'] == true;
      if (!mounted) return;
      setState(() {
        _kyc = kyc;
        _kycNote = k['note'] as String?;
        _submitted = k['submitted'] == true;
        _signed = signed;
        _ready = kyc == 'approved' && signed;
        _loaded = true;
        _error = null;
      });
      if (_ready) _poll?.cancel();
    } on ApiException catch (e) {
      if (e.status == 401) return widget.onLogout();
      if (mounted) setState(() { _error = e.message; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Network error. Check your internet and tap Refresh.'; _loaded = true; });
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Widget _step(int n, String title, String sub, {required bool done, required bool locked, String? button, VoidCallback? onTap, Color? subColor}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            backgroundColor: done ? Colors.green : locked ? Colors.black26 : scheme.primary,
            child: done ? const Icon(Icons.check, color: Colors.white) : Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(sub, style: TextStyle(color: subColor ?? Colors.black54)),
              if (button != null && !done && !locked) ...[
                const SizedBox(height: 10),
                FilledButton(onPressed: onTap, child: Text(button)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return HomeScreen(api: widget.api, onLogout: widget.onLogout);
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final kycApproved = _kyc == 'approved';
    final waiting = _kyc == 'pending' && _submitted; // 'pending' with nothing submitted yet = not started
    final rejected = _kyc == 'rejected';
    return Scaffold(
      appBar: AppBar(title: const Text('Finish setup'), automaticallyImplyLeading: false, actions: [
        IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout), tooltip: 'Log out'),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.black87),
              SizedBox(width: 12),
              Expanded(child: Text('Complete verification (KYC) and sign the agreement to start receiving calls.', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600))),
            ]),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          _step(
            1,
            'Complete verification (KYC)',
            kycApproved
                ? 'Verified'
                : waiting
                    ? 'Submitted. We are checking your documents. This screen updates when you are approved.'
                    : rejected
                        ? 'Not approved: ${(_kycNote ?? '').isEmpty ? 'please upload your documents again.' : _kycNote}'
                        : 'Upload your ID and a selfie so we can verify you.',
            done: kycApproved,
            locked: false,
            button: waiting ? 'View status' : rejected ? 'Fix and resubmit' : 'Start verification',
            onTap: () => _open(KycScreen(api: widget.api)),
            subColor: rejected ? Colors.red : null,
          ),
          _step(
            2,
            'Sign the partner agreement',
            _signed ? 'Signed' : kycApproved ? 'Read and sign the agreement to continue.' : 'Opens after your verification is approved.',
            done: _signed,
            locked: !kycApproved,
            button: 'Read and sign',
            onTap: () => _open(ContractScreen(api: widget.api)),
          ),
          const SizedBox(height: 4),
          Center(child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Refresh'))),
        ]),
      ),
    );
  }
}
