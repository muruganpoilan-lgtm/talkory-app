import 'dart:ui' show BlurStyle, MaskFilter;
import 'package:flutter/material.dart';

/// Default profile picture drawn in code: a female or male 3D-style (soft clay look) avatar. [seed] picks the skin tone, hair,
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
        child: ClipOval(
          child: Image.asset(
            'assets/avatars/${female ? 'f' : 'm'}${1 + seed % 15}.jpg',
            package: 'talkory_core',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => CustomPaint(painter: _FigurePainter(female, seed)),
          ),
        ),
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

  Color _l(Color c, double t) => Color.lerp(c, Colors.white, t)!;
  Color _d(Color c, double t) => Color.lerp(c, Colors.black, t)!;

  Paint _lin(Rect r, List<Color> cols) =>
      Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cols).createShader(r);

  // a lit "clay ball": bright at the top left, darker towards the bottom right
  Paint _ball(Rect r, Color base) => Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      radius: 0.85,
      colors: [_l(base, 0.38), base, _d(base, 0.3)],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(r);

  Paint _blur(Color col, double sigma) => Paint()
    ..color = col
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

  Paint _fill(Color col) => Paint()..color = col;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final skin = _skins[seed % 5];
    final hair = _hairs[(seed ~/ 5) % 5];
    final bg = (female ? _bgsF : _bgsM)[(seed ~/ 25) % 5];
    final clothes = (female ? _clothesF : _clothesM)[(seed ~/ 125) % 5];
    final style = (seed ~/ 625) % 4;
    final cx = w * 0.5;
    final hy = w * 0.42;
    final hw = w * 0.17; // half head width
    final hh = w * 0.21; // half head height

    // soft background
    final full = Offset.zero & s;
    c.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 0.95,
          colors: [_l(bg, 0.6), bg, _d(bg, 0.1)],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(full),
    );

    // zoom in a little so the face fills the circle
    c.save();
    c.translate(w * 0.5, w * 0.56);
    c.scale(1.22);
    c.translate(-w * 0.5, -w * 0.5);

    final hairRect = Rect.fromLTWH(w * 0.2, w * 0.05, w * 0.6, w * 0.75);
    final hairP = _lin(hairRect, [_l(hair, 0.22), hair, _d(hair, 0.35)]);

    // hair behind the head
    if (female) {
      if (style == 0) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - hw * 1.35, hy - hh * 1.05, hw * 2.7, hh * 3.0), Radius.circular(hw * 1.2)), hairP);
      } else if (style == 1) {
        c.drawOval(Rect.fromCenter(center: Offset(cx, hy - hh * 0.05), width: hw * 2.5, height: hh * 2.3), hairP);
      } else if (style == 2) {
        c.drawCircle(Offset(cx, hy - hh * 1.15), hw * 0.55, hairP);
        c.drawOval(Rect.fromCenter(center: Offset(cx, hy - hh * 0.05), width: hw * 2.4, height: hh * 2.24), hairP);
      } else {
        c.drawCircle(Offset(cx, hy - hh * 0.1), hw * 1.55, hairP);
      }
    } else if (style == 3) {
      c.drawCircle(Offset(cx, hy - hh * 0.25), hw * 1.2, hairP);
    }

    // shoulders and clothes, with a soft highlight
    final bodyRect = Rect.fromCenter(center: Offset(cx, w * 1.03), width: w * 0.84, height: w * 0.7);
    c.drawOval(bodyRect, _lin(bodyRect, [_l(clothes, 0.28), clothes, _d(clothes, 0.32)]));
    c.drawOval(Rect.fromCenter(center: Offset(w * 0.35, w * 0.745), width: w * 0.3, height: w * 0.07), _blur(Colors.white.withOpacity(0.3), w * 0.012));

    // neck and neckline
    final neck = Rect.fromCenter(center: Offset(cx, w * 0.66), width: hw * 0.7, height: hh * 0.75);
    c.drawRect(
      neck,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_d(skin, 0.2), _d(skin, 0.35)]).createShader(neck),
    );
    c.drawPath(
      Path()
        ..moveTo(cx - hw * 0.55, w * 0.70)
        ..lineTo(cx + hw * 0.55, w * 0.70)
        ..lineTo(cx, w * 0.82)
        ..close(),
      _fill(_d(skin, 0.1)),
    );

    // braid over the shoulder
    if (female && style == 1) {
      for (var i = 0; i < 4; i++) {
        c.drawCircle(Offset(cx + hw * 1.05, hy + hh * 0.9 + i * hw * 0.5), hw * (0.3 - i * 0.03), hairP);
      }
    }

    // shadow under the chin, ears and head
    c.drawOval(Rect.fromCenter(center: Offset(cx, hy + hh * 0.92), width: hw * 1.2, height: hw * 0.36), _blur(Colors.black.withOpacity(0.25), w * 0.012));
    for (final sx in [-1.0, 1.0]) {
      final er = Rect.fromCircle(center: Offset(cx + sx * hw, hy + hh * 0.05), radius: hw * 0.17);
      c.drawOval(er, _ball(er, skin));
    }
    final headRect = Rect.fromCenter(center: Offset(cx, hy), width: hw * 2, height: hh * 2);
    c.drawOval(headRect, _ball(headRect, skin));

    // beard
    if (!female && style == 1) {
      c.drawPath(
        Path()
          ..moveTo(cx - hw * 0.98, hy + hh * 0.1)
          ..quadraticBezierTo(cx - hw * 0.9, hy + hh * 1.05, cx, hy + hh * 1.05)
          ..quadraticBezierTo(cx + hw * 0.9, hy + hh * 1.05, cx + hw * 0.98, hy + hh * 0.1)
          ..quadraticBezierTo(cx + hw * 0.6, hy + hh * 0.5, cx, hy + hh * 0.5)
          ..quadraticBezierTo(cx - hw * 0.6, hy + hh * 0.5, cx - hw * 0.98, hy + hh * 0.1)
          ..close(),
        hairP,
      );
    }

    // fringe and a shine on the hair
    c.drawPath(
      Path()
        ..moveTo(cx - hw * 1.02, hy - hh * 0.1)
        ..quadraticBezierTo(cx - hw * 0.9, hy - hh * 1.15, cx, hy - hh * 1.05)
        ..quadraticBezierTo(cx + hw * 0.9, hy - hh * 1.15, cx + hw * 1.02, hy - hh * 0.1)
        ..quadraticBezierTo(cx + hw * 0.55, hy - hh * 0.55, cx + hw * 0.1, hy - hh * 0.62)
        ..quadraticBezierTo(cx - hw * 0.45, hy - hh * 0.5, cx - hw * 1.02, hy - hh * 0.1)
        ..close(),
      hairP,
    );
    c.drawPath(
      Path()
        ..moveTo(cx - hw * 0.75, hy - hh * 0.62)
        ..quadraticBezierTo(cx - hw * 0.2, hy - hh * 1.0, cx + hw * 0.35, hy - hh * 0.88),
      Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012),
    );

    // glossy eyes, brows, blush
    final ey = hy + hh * 0.06;
    final lid = Paint()
      ..color = const Color(0xFF1A0D09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014
      ..strokeCap = StrokeCap.round;
    final lash = Paint()
      ..color = const Color(0xFF1A0D09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.011
      ..strokeCap = StrokeCap.round;
    final brow = Paint()
      ..color = hair
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014
      ..strokeCap = StrokeCap.round;
    for (final sx in [-1.0, 1.0]) {
      final ex = cx + sx * hw * 0.42;
      c.drawOval(Rect.fromCenter(center: Offset(ex, ey), width: hw * 0.42, height: hw * 0.34), _fill(Colors.white));
      final iris = Rect.fromCircle(center: Offset(ex, ey), radius: hw * 0.135);
      c.drawOval(
        iris,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 0.9,
            colors: const [Color(0xFF8A5A3C), Color(0xFF4A2B1B), Color(0xFF24120B)],
            stops: const [0.0, 0.6, 1.0],
          ).createShader(iris),
      );
      c.drawCircle(Offset(ex, ey), hw * 0.06, _fill(const Color(0xFF0B0504)));
      c.drawCircle(Offset(ex - hw * 0.045, ey - hw * 0.05), hw * 0.045, _fill(Colors.white));
      c.drawCircle(Offset(ex + hw * 0.05, ey + hw * 0.05), hw * 0.02, _fill(Colors.white.withOpacity(0.8)));
      c.drawArc(Rect.fromCenter(center: Offset(ex, ey), width: hw * 0.46, height: hw * 0.38), 3.14159, 3.14159, false, lid);
      if (female) c.drawLine(Offset(ex + sx * hw * 0.21, ey - hw * 0.06), Offset(ex + sx * hw * 0.3, ey - hw * 0.15), lash);
      c.drawPath(
        Path()
          ..moveTo(ex - hw * 0.22, ey - hw * 0.3)
          ..quadraticBezierTo(ex, ey - hw * 0.38, ex + hw * 0.22, ey - hw * 0.3),
        brow,
      );
      final bc = Offset(cx + sx * hw * 0.58, hy + hh * 0.42);
      final br = Rect.fromCircle(center: bc, radius: hw * 0.25);
      final pink = const Color(0xFFFF6F91);
      c.drawCircle(
        bc,
        hw * 0.25,
        Paint()
          ..shader = RadialGradient(colors: [pink.withOpacity(female ? 0.55 : 0.25), pink.withOpacity(0)]).createShader(br),
      );
    }

    // nose
    c.drawOval(Rect.fromCenter(center: Offset(cx, hy + hh * 0.32), width: hw * 0.2, height: hw * 0.14), _blur(_d(skin, 0.25).withOpacity(0.5), w * 0.012));
    c.drawOval(Rect.fromCenter(center: Offset(cx - hw * 0.03, hy + hh * 0.27), width: hw * 0.1, height: hw * 0.07), _fill(Colors.white.withOpacity(0.4)));

    // lips with a glossy highlight
    final my = hy + hh * 0.58;
    final mw = hw * 0.34;
    final lipRect = Rect.fromCenter(center: Offset(cx, my + hh * 0.1), width: mw * 2, height: hh * 0.26);
    c.drawPath(
      Path()
        ..moveTo(cx - mw, my)
        ..quadraticBezierTo(cx, my + hh * 0.26, cx + mw, my)
        ..quadraticBezierTo(cx, my + hh * 0.07, cx - mw, my)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: female ? const [Color(0xFFE0506E), Color(0xFFB0224A)] : const [Color(0xFFC77B6F), Color(0xFF9A5248)],
        ).createShader(lipRect),
    );
    c.drawOval(Rect.fromCenter(center: Offset(cx - mw * 0.2, my + hh * 0.1), width: mw * 0.6, height: hh * 0.04), _fill(Colors.white.withOpacity(0.55)));

    // earrings
    if (female) {
      for (final sx in [-1.0, 1.0]) {
        final r = Rect.fromCircle(center: Offset(cx + sx * hw * 0.99, hy + hh * 0.3), radius: hw * 0.09);
        c.drawOval(
          r,
          Paint()..shader = const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFF3B0), Color(0xFFE0A100)]).createShader(r),
        );
      }
    }
    c.restore();
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
