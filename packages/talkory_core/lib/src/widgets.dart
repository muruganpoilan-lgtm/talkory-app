import 'package:flutter/material.dart';

/// Default profile picture drawn in code: a female or male illustrated avatar. [seed] picks the skin tone, hair,
/// hair style, outfit and background, so different people look different.
class AvatarFigure extends StatelessWidget {
  const AvatarFigure({super.key, required this.female, this.radius = 28, this.seed = 0});
  final bool female;
  final double radius;
  final int seed;

  /// Stable number from a name (same name, same look).
  static int seedOf(String name) {
    var h = 7;
    for (final u in name.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: ClipOval(child: CustomPaint(painter: _FigurePainter(female, seed))),
      );
}

class _FigurePainter extends CustomPainter {
  _FigurePainter(this.female, this.seed);
  final bool female;
  final int seed;

  static const _skins = [Color(0xFFF3C99B), Color(0xFFE5AE7E), Color(0xFFCB8F5E), Color(0xFFA9703F), Color(0xFF8A5A33)];
  static const _hairs = [Color(0xFF1E1412), Color(0xFF2E1D18), Color(0xFF4A2E22), Color(0xFF6B4630), Color(0xFF16181C)];
  static const _bgsF = [Color(0xFFF8BBD0), Color(0xFFD1C4E9), Color(0xFFB2DFDB), Color(0xFFFFE0B2), Color(0xFFBBDEFB)];
  static const _bgsM = [Color(0xFFBBDEFB), Color(0xFFC8E6C9), Color(0xFFFFE0B2), Color(0xFFD7CCC8), Color(0xFFB2EBF2)];
  static const _clothesF = [Color(0xFFAD1457), Color(0xFF00796B), Color(0xFF3949AB), Color(0xFFEF6C00), Color(0xFF6A1B9A)];
  static const _clothesM = [Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF455A64), Color(0xFF6D4C41), Color(0xFFC62828)];

  Paint _f(Color col) => Paint()..color = col;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final skin = _skins[seed % 5];
    final hair = _hairs[(seed ~/ 5) % 5];
    final bg = (female ? _bgsF : _bgsM)[(seed ~/ 25) % 5];
    final clothes = (female ? _clothesF : _clothesM)[(seed ~/ 125) % 5];
    final style = (seed ~/ 625) % 4;
    final cx = w * 0.5;
    final headC = Offset(cx, w * 0.42);
    final hw = w * 0.17; // half head width
    final hh = w * 0.21; // half head height

    // background
    final rect = Offset.zero & s;
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg, Color.lerp(bg, Colors.white, 0.55)!],
        ).createShader(rect),
    );

    // hair behind the head
    if (female) {
      if (style == 0) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - hw * 1.35, headC.dy - hh * 1.05, hw * 2.7, hh * 3.0), Radius.circular(hw * 1.2)), _f(hair));
      } else if (style == 1) {
        c.drawOval(Rect.fromCenter(center: headC.translate(0, -hh * 0.05), width: hw * 2.5, height: hh * 2.3), _f(hair));
      } else if (style == 2) {
        c.drawCircle(Offset(cx, headC.dy - hh * 1.15), hw * 0.55, _f(hair));
        c.drawOval(Rect.fromCenter(center: headC.translate(0, -hh * 0.05), width: hw * 2.4, height: hh * 2.25), _f(hair));
      } else {
        c.drawCircle(headC.translate(0, -hh * 0.1), hw * 1.55, _f(hair));
      }
    } else if (style == 3) {
      c.drawCircle(headC.translate(0, -hh * 0.25), hw * 1.2, _f(hair));
    }

    // shoulders and clothes
    c.drawOval(Rect.fromLTWH(w * 0.08, w * 0.68, w * 0.84, w * 0.7), _f(clothes));
    // neck
    c.drawRect(Rect.fromCenter(center: Offset(cx, w * 0.66), width: hw * 0.7, height: hh * 0.75), _f(Color.lerp(skin, Colors.brown, 0.15)!));
    // neckline
    c.drawPath(
      Path()
        ..moveTo(cx - hw * 0.55, w * 0.70)
        ..lineTo(cx + hw * 0.55, w * 0.70)
        ..lineTo(cx, w * 0.82)
        ..close(),
      _f(skin),
    );

    // braid over the shoulder
    if (female && style == 1) {
      for (var i = 0; i < 4; i++) {
        c.drawCircle(Offset(cx + hw * 1.05, headC.dy + hh * 0.9 + i * hw * 0.5), hw * (0.3 - i * 0.03), _f(hair));
      }
    }

    // ears and head
    c.drawCircle(Offset(cx - hw, headC.dy + hh * 0.05), hw * 0.17, _f(skin));
    c.drawCircle(Offset(cx + hw, headC.dy + hh * 0.05), hw * 0.17, _f(skin));
    c.drawOval(Rect.fromCenter(center: headC, width: hw * 2, height: hh * 2), _f(skin));

    // beard
    if (!female && style == 1) {
      c.drawPath(
        Path()
          ..moveTo(cx - hw * 0.98, headC.dy + hh * 0.1)
          ..quadraticBezierTo(cx - hw * 0.9, headC.dy + hh * 1.05, cx, headC.dy + hh * 1.05)
          ..quadraticBezierTo(cx + hw * 0.9, headC.dy + hh * 1.05, cx + hw * 0.98, headC.dy + hh * 0.1)
          ..quadraticBezierTo(cx + hw * 0.6, headC.dy + hh * 0.5, cx, headC.dy + hh * 0.5)
          ..quadraticBezierTo(cx - hw * 0.6, headC.dy + hh * 0.5, cx - hw * 0.98, headC.dy + hh * 0.1)
          ..close(),
        _f(hair),
      );
    }

    // fringe / front hair
    c.drawPath(
      Path()
        ..moveTo(cx - hw * 1.02, headC.dy - hh * 0.1)
        ..quadraticBezierTo(cx - hw * 0.9, headC.dy - hh * 1.15, cx, headC.dy - hh * 1.05)
        ..quadraticBezierTo(cx + hw * 0.9, headC.dy - hh * 1.15, cx + hw * 1.02, headC.dy - hh * 0.1)
        ..quadraticBezierTo(cx + hw * 0.55, headC.dy - hh * 0.55, cx + hw * 0.1, headC.dy - hh * 0.62)
        ..quadraticBezierTo(cx - hw * 0.45, headC.dy - hh * 0.5, cx - hw * 1.02, headC.dy - hh * 0.1)
        ..close(),
      _f(hair),
    );

    // eyes and eyebrows
    final brow = Paint()
      ..color = hair
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014
      ..strokeCap = StrokeCap.round;
    for (final sx in [-1.0, 1.0]) {
      final ex = cx + sx * hw * 0.42;
      final ey = headC.dy + hh * 0.05;
      c.drawOval(Rect.fromCenter(center: Offset(ex, ey), width: hw * 0.36, height: hw * 0.22), _f(Colors.white));
      c.drawCircle(Offset(ex, ey), hw * 0.1, _f(const Color(0xFF2B1B14)));
      c.drawCircle(Offset(ex + hw * 0.035, ey - hw * 0.035), hw * 0.03, _f(Colors.white));
      c.drawLine(Offset(ex - hw * 0.2, ey - hw * 0.24), Offset(ex + hw * 0.2, ey - hw * 0.28), brow);
    }

    // nose
    c.drawOval(Rect.fromCenter(center: Offset(cx, headC.dy + hh * 0.3), width: hw * 0.22, height: hw * 0.14), _f(Color.lerp(skin, Colors.brown, 0.3)!));

    // blush and earrings
    if (female) {
      c.drawCircle(Offset(cx - hw * 0.55, headC.dy + hh * 0.38), hw * 0.2, _f(const Color(0x33E91E63)));
      c.drawCircle(Offset(cx + hw * 0.55, headC.dy + hh * 0.38), hw * 0.2, _f(const Color(0x33E91E63)));
      c.drawCircle(Offset(cx - hw * 1.0, headC.dy + hh * 0.3), hw * 0.09, _f(const Color(0xFFFFC107)));
      c.drawCircle(Offset(cx + hw * 1.0, headC.dy + hh * 0.3), hw * 0.09, _f(const Color(0xFFFFC107)));
    }

    // smile
    final smile = Paint()
      ..color = female ? const Color(0xFFC2185B) : const Color(0xFF8D4A43)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * (female ? 0.02 : 0.014)
      ..strokeCap = StrokeCap.round;
    c.drawArc(Rect.fromCenter(center: Offset(cx, headC.dy + hh * 0.52), width: hw * 0.6, height: hw * 0.4), 0.25, 2.65, false, smile);
  }

  @override
  bool shouldRepaint(covariant _FigurePainter old) => old.female != female || old.seed != seed;
}

/// Round profile picture. Without a photo it shows the default avatar: female by default, male when [female] is false.
/// [url] is a server path like /avatars/x.jpg. Pass [ring] to draw a coloured ring around it (green = online).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.baseUrl, required this.name, this.url, this.radius = 28, this.ring, this.female = true});
  final String baseUrl, name;
  final String? url;
  final double radius;
  final Color? ring;
  final bool female;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.transparent,
      backgroundImage: url == null ? null : NetworkImage('$baseUrl$url'),
      child: url == null ? AvatarFigure(female: female, radius: radius, seed: AvatarFigure.seedOf(name)) : null,
    );
    if (ring == null) return avatar;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 3)),
      child: avatar,
    );
  }
}
