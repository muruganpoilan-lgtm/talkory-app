import 'package:flutter/material.dart';

const kInk = Color(0xFF1B1740);
const kSoftBg = Color(0xFFF5F2FF);

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
      indicatorColor: scheme.primaryContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 44))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: const StadiumBorder())),
  );
}

/// Two-colour gradient made from the app colour (second colour is the same colour with its hue shifted).
LinearGradient brandGradient(Color base) {
  final hsl = HSLColor.fromColor(base);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [base, hsl.withHue((hsl.hue + 40) % 360).toColor()],
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
          shadowColor: const Color(0x401B1740),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
}
