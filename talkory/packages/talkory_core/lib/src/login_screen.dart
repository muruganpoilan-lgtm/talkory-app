import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'legal.dart';

/// Phone + OTP login shared by both apps. [role] is 'user' or 'partner'.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.role, required this.title, required this.onLoggedIn});
  final Api api;
  final String role, title;
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _otpSent = false, _adult = false, _terms = false, _busy = false;
  String? _error;
  late final _tapTerms = TapGestureRecognizer()..onTap = () => openLegal(widget.api, 'terms');
  late final _tapPrivacy = TapGestureRecognizer()..onTap = () => openLegal(widget.api, 'privacy');

  @override
  void dispose() {
    _tapTerms.dispose();
    _tapPrivacy.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() { _busy = true; _error = null; });
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

  Future<void> _sendOtp() => _run(() async {
        await widget.api.requestOtp(_phone.text.trim());
        setState(() => _otpSent = true);
      });

  Future<void> _verify() => _run(() async {
        await widget.api.verifyOtp(
          phone: _phone.text.trim(),
          code: _code.text.trim(),
          role: widget.role,
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
          isAdult: _adult,
          acceptedTerms: _terms,
        );
        widget.onLoggedIn();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Text(widget.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            TextField(
              controller: _phone,
              enabled: !_otpSent,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '+919876543210', border: OutlineInputBorder()),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'OTP code', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Display name (new accounts)', helperText: 'Shown instead of your number', border: OutlineInputBorder()),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _adult,
                onChanged: (v) => setState(() => _adult = v ?? false),
                title: const Text('I confirm I am 18 or older'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _terms,
                onChanged: (v) => setState(() => _terms = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(text: 'Terms', style: const TextStyle(decoration: TextDecoration.underline), recognizer: _tapTerms),
                  const TextSpan(text: ' and '),
                  TextSpan(text: 'Privacy Policy', style: const TextStyle(decoration: TextDecoration.underline), recognizer: _tapPrivacy),
                ])),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy || (_otpSent && !_terms) ? null : (_otpSent ? _verify : _sendOtp),
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_otpSent ? 'Verify & continue' : 'Send OTP'),
            ),
          ],
        ),
      ),
    );
  }
}
