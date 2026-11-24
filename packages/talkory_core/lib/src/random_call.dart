import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'call_screen.dart';
import 'post_call_screen.dart';
import 'agora_warm.dart';
import 'theme.dart';

/// Random Call. One tap rings whichever host is free; if that host does not pick up or
/// declines, this screen quietly rings the next one, up to [maxTries] hosts. The user can
/// stop at any point. Nobody is rung twice in the same search.
class RandomCallScreen extends StatefulWidget {
  const RandomCallScreen({super.key, required this.api, this.onAddCoins, this.maxTries = 6});
  final Api api;
  final VoidCallback? onAddCoins; // opens the wallet when the balance is too low
  final int maxTries;

  @override
  State<RandomCallScreen> createState() => _RandomCallScreenState();
}

class _RandomCallScreenState extends State<RandomCallScreen> {
  final _tried = <String>[]; // hosts already rung in this search
  String _line = 'Finding someone to talk to…';
  String? _name; // host currently ringing
  bool _stopped = false; // the user pressed Stop
  bool _inCall = false; // a call screen is open on top of this one
  int _dots = 0;
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && !_inCall) setState(() => _dots = (_dots + 1) % 4);
    });
    AgoraWarm.warm(); // start the call engine while we look, so answering is instant
    WidgetsBinding.instance.addPostFrameCallback((_) => _next());
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    super.dispose();
  }

  void _close([String? message]) {
    if (!mounted) return;
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  Future<void> _next() async {
    if (_stopped || !mounted) return;
    if (_tried.length >= widget.maxTries) {
      return _close('Nobody picked up. Try again in a minute.');
    }
    if (_tried.isNotEmpty) setState(() { _name = null; _line = 'Trying someone else…'; });

    RandomMatch? match;
    try {
      match = await widget.api.startRandomCall(exclude: _tried);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 402) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Not enough coins for a call.'),
          action: widget.onAddCoins == null ? null : SnackBarAction(label: 'Add coins', onPressed: widget.onAddCoins!),
        ));
        return;
      }
      return _close(e.message);
    } catch (_) {
      return _close('Network error. Try again.');
    }
    if (_stopped || !mounted) return;

    if (match == null) {
      return _close(_tried.isEmpty
          ? 'No hosts are free right now. Try again in a minute.'
          : 'Nobody else is free right now.');
    }
    final m = match; // a final local: the closures below cannot see through a nullable one

    _tried.add(m.partnerId);
    setState(() { _name = m.partnerName; _line = 'Ringing ${m.partnerName}'; });

    // The call screen handles the ringing, the talking and the hang-up, exactly as it does
    // for a host the user picked. It hands back true only if the two actually spoke.
    _inCall = true;
    final spoke = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CallScreen(api: widget.api, session: m.session, peerName: m.partnerName, onAddCredits: widget.onAddCoins),
    ));
    _inCall = false;
    if (!mounted) return;

    if (spoke == true) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostCallScreen(api: widget.api, callId: m.session.callId, peerName: m.partnerName, canRate: true),
      ));
      return _close();
    }

    // Did the host miss it, or did the user hang up? Only a miss or a decline rolls on.
    String status = 'ended';
    try {
      status = '${(await widget.api.callStatus(m.session.callId))['status']}';
    } catch (_) {}
    if (_stopped || !mounted) return;
    if (status == 'missed' || status == 'rejected') return _next();
    _close(); // the user ended it, so the search ends too
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        _stopped = true; // swiped back: stop looking for the next host
      },
      child: Scaffold(
        backgroundColor: kRoyalDeep,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Spacer(),
              SizedBox(
                width: 132, height: 132,
                child: Stack(alignment: Alignment.center, children: [
                  const SizedBox(width: 132, height: 132, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
                  Container(
                    width: 104, height: 104,
                    decoration: const BoxDecoration(color: Color(0x22FFFFFF), shape: BoxShape.circle),
                    child: Icon(_name == null ? Icons.shuffle : Icons.call, size: 44, color: kGold),
                  ),
                ]),
              ),
              const SizedBox(height: 34),
              Text(
                _line + ('.' * _dots),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                _tried.length > 1 ? 'Host ${_tried.length} of ${widget.maxTries}' : 'We ring the next host if this one is away',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () { _stopped = true; _close(); },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Stop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The banner that starts a Random Call, for the top of the user's home screen.
class RandomCallBanner extends StatelessWidget {
  const RandomCallBanner({super.key, required this.api, this.onAddCoins, this.onFinished, this.rateLine});
  final Api api;
  final VoidCallback? onAddCoins;
  final VoidCallback? onFinished; // refresh the balance and the host list afterwards
  final String? rateLine; // e.g. '₹10/min' — left out when null

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(colors: [Color(0xFF5B3DF5), Color(0xFF9B4DF5)]),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RandomCallScreen(api: api, onAddCoins: onAddCoins)));
              onFinished?.call();
            },
            child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('Talk to anyone, now',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    rateLine == null ? 'We find a host who is free' : 'We find a host who is free · $rateLine',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(999)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Random Call', style: TextStyle(color: kRoyalDeep, fontWeight: FontWeight.w800, fontSize: 13)),
                  SizedBox(width: 6),
                  Icon(Icons.shuffle, size: 16, color: kRoyalDeep),
                ]),
              ),
            ]),
            ),
          ),
        ),
      ),
    );
  }
}
