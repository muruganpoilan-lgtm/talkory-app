import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'legal.dart';
import 'theme.dart';

/// Phone login shared by both apps. [role] is 'user' or 'partner'.
/// First time on a phone: number, then an OTP (and a display name for a new account).
/// After that this phone is remembered and "Continue" signs in straight away, with no OTP.
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
  bool _otpSent = false, _agree = false, _busy = false;
  String? _error;
  late final _tapTerms = TapGestureRecognizer()..onTap = () => openLegal(widget.api, 'terms');
  late final _tapPrivacy = TapGestureRecognizer()..onTap = () => openLegal(widget.api, 'privacy');

  String get _full => '+91${_phone.text.trim()}';
  bool get _phoneOk => RegExp(r'^[6-9]\d{9}$').hasMatch(_phone.text.trim());

  @override
  void dispose() {
    _tapTerms.dispose();
    _tapPrivacy.dispose();
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } on ApiException catch (e) {
      final m = e.message;
      setState(() => _error = m == 'displayName required' ? 'New here? Please type a display name.' : m == 'invalid code' ? 'That code is not right. Try again.' : m);
    } catch (_) {
      setState(() => _error = 'Network error. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Remembered phone: straight in. Otherwise send the OTP.
  Future<void> _continue() => _run(() async {
        if (await widget.api.deviceLogin(phone: _full, role: widget.role)) {
          widget.onLoggedIn();
          return;
        }
        await widget.api.requestOtp(_full);
        setState(() => _otpSent = true);
      });

  Future<void> _resend() => _run(() async {
        await widget.api.requestOtp(_full);
        setState(() => _error = 'A new code has been sent.');
      });

  Future<void> _verify() => _run(() async {
        await widget.api.verifyOtp(
          phone: _full,
          code: _code.text.trim(),
          role: widget.role,
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
          isAdult: _agree,
          acceptedTerms: _agree,
        );
        widget.onLoggedIn();
      });

  Widget _bubble(IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kInk.withAlpha(150), width: 1.5)),
        child: Icon(icon, size: 18, color: kInk),
      );

  // A simple original picture: two people on a call, with chat bubbles
  Widget _picture() => SizedBox(
        height: 210,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: 210, height: 190, decoration: const BoxDecoration(color: Color(0xFFEDE2F8), shape: BoxShape.circle)),
          Positioned(left: 56, bottom: 8, child: _person(const Color(0xFFB4B2F2), Icons.face_3, 64)),
          Positioned(right: 56, bottom: 8, child: _person(const Color(0xFFFAD9A0), Icons.face, 56)),
          Positioned(left: 112, top: 14, child: _bubble(Icons.more_horiz)),
          Positioned(right: 86, top: 56, child: _bubble(Icons.more_horiz)),
          Positioned(left: 108, bottom: 54, child: Icon(Icons.phone_in_talk, color: kRoyal, size: 26)),
        ]),
      );

  Widget _person(Color c, IconData icon, double size) => Container(
        width: size + 20,
        height: size + 20,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: kInk.withAlpha(180), width: 1.5)),
        child: Icon(icon, size: size, color: kInk),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final ready = !_busy && (_otpSent ? _code.text.trim().length >= 4 : (_phoneOk && _agree));
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, top + 28, 24, 24),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [kRoyalDeep, kRoyal]), borderRadius: BorderRadius.circular(10)),
                child: const Text('T', style: TextStyle(color: kGold, fontSize: 26, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Text(widget.title, style: const TextStyle(color: kRoyal, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            ]),
            const SizedBox(height: 18),
            _picture(),
            const SizedBox(height: 10),
            const Text('Make New Friends On', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
            const Text('Audio Calls', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF9B3FD0))),
            const SizedBox(height: 28),
            Text(_otpSent ? 'Enter the code' : 'Login or Sign Up', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
            const SizedBox(height: 16),
            if (!_otpSent) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(border: Border.all(color: Colors.black26, width: 1.5), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Text('🇮🇳', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  const Text('+91', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: kInk)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 18, color: kInk),
                      decoration: const InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, hintText: 'Enter your number'),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Checkbox(value: _agree, activeColor: kRoyal, onChanged: (v) => setState(() => _agree = v ?? false)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text.rich(TextSpan(style: const TextStyle(color: Colors.black54, fontSize: 13.5), children: [
                      const TextSpan(text: 'I am 18 or older. By entering my number, I agree to the '),
                      TextSpan(text: 'Terms & Conditions', style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600, color: kInk), recognizer: _tapTerms),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Privacy Policy', style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600, color: kInk), recognizer: _tapPrivacy),
                    ])),
                  ),
                ),
              ]),
            ] else ...[
              Text('We sent a code to +91 ${_phone.text.trim()}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 20, letterSpacing: 4),
                decoration: const InputDecoration(labelText: 'OTP code', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Display name', helperText: 'Only for new accounts. Shown instead of your number.', border: OutlineInputBorder()),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(onPressed: _busy ? null : () => setState(() { _otpSent = false; _error = null; _code.clear(); }), child: const Text('Change number')),
                TextButton(onPressed: _busy ? null : _resend, child: const Text('Resend code')),
              ]),
            ],
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kRoyal, disabledBackgroundColor: kRoyal.withAlpha(90), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: ready ? (_otpSent ? _verify : _continue) : null,
                child: _busy
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_otpSent ? 'Verify & continue' : 'Continue', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            if (!_otpSent)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('You need an OTP only the first time on this phone.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black45, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}
