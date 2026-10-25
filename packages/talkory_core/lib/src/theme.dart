import 'package:flutter/material.dart';

const kInk = Color(0xFF1B1740);
const kSoftBg = Color(0xFFF3EEFA);
const kGold = Color(0xFFF2C14E);
const kRoyalDeep = Color(0xFF1E0A56);
const kRoyal = Color(0xFF4B22B0);

/// Shared look for both apps: soft lavender background, white rounded cards, pill buttons, floating tab bar.
/// [seed] is each app's main colour.
ThemeData talkoryTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(seedColor: seed);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kSoftBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kSoftBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: kInk,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: const Color(0xFFE6DAFB),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 44))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: const StadiumBorder())),
  );
}

/// Royal gradient: deep indigo to rich purple (the [base] colour is kept for compatibility).
LinearGradient brandGradient(Color base) => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [kRoyalDeep, kRoyal, Color(0xFF7A3FD0)],
      stops: [0.0, 0.6, 1.0],
    );

class _RoyalPattern extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = kGold.withOpacity(0.22);
    final fill = Paint()..color = kGold.withOpacity(0.07);
    final o = Offset(s.width * 0.92, s.height * 0.15);
    c.drawCircle(o, 86, fill);
    for (final r in [44.0, 70.0, 98.0, 128.0]) {
      c.drawCircle(o, r, ring);
    }
    c.drawCircle(Offset(s.width * 0.05, s.height * 0.95), 60, ring);
    final dot = Paint()..color = kGold.withOpacity(0.5);
    for (final d in [Offset(s.width * 0.62, s.height * 0.2), Offset(s.width * 0.78, s.height * 0.62), Offset(s.width * 0.45, s.height * 0.8)]) {
      c.drawCircle(d, 2.2, dot);
    }
    final line = Paint()
      ..color = kGold.withOpacity(0.7)
      ..strokeWidth = 2;
    c.drawLine(Offset(s.width * 0.2, s.height - 1), Offset(s.width * 0.8, s.height - 1), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Royal header background: gradient with soft gold rings and a thin gold edge.
class RoyalBox extends StatelessWidget {
  const RoyalBox({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: brandGradient(kRoyal),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
          boxShadow: const [BoxShadow(color: Color(0x551E0A56), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: CustomPaint(painter: _RoyalPattern(), child: Padding(padding: padding, child: child)),
        ),
      );
}

/// Wraps a NavigationBar so it floats above the bottom edge as a white rounded bar.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Material(
          color: Colors.white,
          elevation: 8,
          shadowColor: const Color(0x601E0A56),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}

/// Gradient banner at the top of a tab (title, optional subtitle and a widget on the right).
/// The Talkory Tech logo in a small white circle, for the top of the main screens.
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Image.asset('assets/logo.png', package: 'talkory_core'),
      );
}

class GradientHeader extends StatelessWidget {
  const GradientHeader({super.key, required this.title, this.subtitle, this.trailing, this.bottomPadding = 28, this.showLogo = false});
  final bool showLogo;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return RoyalBox(
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, bottomPadding),
      child: Row(children: [
        if (showLogo) const Padding(padding: EdgeInsets.only(right: 12), child: LogoBadge(size: 46)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 14))),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// White rounded card with a soft shadow, used for rows and groups.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.margin = const EdgeInsets.fromLTRB(16, 6, 16, 6), this.color = Colors.white});
  final Widget child;
  final EdgeInsetsGeometry margin;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: color,
          elevation: 3,
          shadowColor: const Color(0x261B1740),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}

/// White rounded "search names" field with a clear (x) button, used at the top of the Call and Chat pages.
class NameSearchField extends StatelessWidget {
  const NameSearchField({super.key, required this.controller, required this.onChanged, this.hint = 'Search names'});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 4,
        shadowColor: const Color(0x551E0A56),
        borderRadius: BorderRadius.circular(16),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      );
}
