import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

/// Shows the Talkory logo for a moment when the app starts, then fades into [child].
/// Used as the first thing inside every app, so there is never a blank white screen.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.subtitle = '', this.duration = const Duration(milliseconds: 1800)});
  final Widget child;
  final String subtitle;
  final Duration duration;
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () { if (mounted) setState(() => _done = true); });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: _done
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : Scaffold(
              key: const ValueKey('splash'),
              body: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kRoyalDeep, kRoyal]),
                ),
                child: SafeArea(
                  child: Column(children: [
                    const Spacer(flex: 5),
                    FadeTransition(
                      opacity: CurvedAnimation(parent: _in, curve: Curves.easeOut),
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1).animate(CurvedAnimation(parent: _in, curve: Curves.easeOutBack)),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: Image.asset('assets/logo.png', package: 'talkory_core', width: 130, height: 130),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FadeTransition(
                      opacity: _in,
                      child: const Text('Talkory', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      FadeTransition(opacity: _in, child: Text(widget.subtitle, style: const TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.w600))),
                    ],
                    const Spacer(flex: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 28),
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70)),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }
}
