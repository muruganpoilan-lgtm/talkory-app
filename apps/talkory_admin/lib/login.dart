import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

/// Admin sign-in: phone number + OTP. Admin accounts are created by hand on the server.
class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key, required this.api, required this.onLoggedIn});
  final Api api;
  final VoidCallback onLoggedIn;
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        await widget.api.requestOtp(_phone.text.trim());
        setState(() => _sent = true);
      });

  Future<void> _verify() => _run(() async {
        await widget.api.verifyOtp(phone: _phone.text.trim(), code: _code.text.trim(), role: 'admin');
        widget.onLoggedIn();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        RoyalBox(
          padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 56, 24, 40),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Talkory Admin', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('Team sign-in', style: TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _phone,
              enabled: !_sent,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '+919876543210', border: OutlineInputBorder()),
            ),
            if (_sent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'OTP code', border: OutlineInputBorder()),
              ),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : (_sent ? _verify : _send),
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_busy ? 'Please wait…' : (_sent ? 'Sign in' : 'Send OTP'))),
            ),
          ]),
        ),
      ]),
    );
  }
}
