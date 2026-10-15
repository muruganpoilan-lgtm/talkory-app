import 'package:flutter/material.dart';

/// Default profile picture drawn in code: a female avatar (pink) or a male avatar (blue).
class AvatarFigure extends StatelessWidget {
  const AvatarFigure({super.key, required this.female, this.radius = 28});
  final bool female;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: ClipOval(child: CustomPaint(painter: _FigurePainter(female))),
      );
}

class _FigurePainter extends CustomPainter {
  _FigurePainter(this.female);
  final bool female;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    Paint fill(Color col) => Paint()..color = col;
    final bg = female ? const Color(0xFFF8BBD0) : const Color(0xFFBBDEFB);
    final clothes = female ? const Color(0xFFAD1457) : const Color(0xFF1565C0);
    final hair = female ? const Color(0xFF3E2723) : const Color(0xFF263238);
    const skin = Color(0xFFFFCC9C);
    c.drawRect(Offset.zero & s, fill(bg));
    if (female) {
      // long hair behind the head and shoulders
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.24, w * 0.18, w * 0.52, w * 0.56), Radius.circular(w * 0.22)), fill(hair));
    }
    // shoulders / body
    c.drawOval(Rect.fromLTWH(w * 0.10, w * 0.66, w * 0.80, w * 0.66), fill(clothes));
    // neck
    c.drawRect(Rect.fromLTWH(w * 0.44, w * 0.52, w * 0.12, w * 0.18), fill(skin));
    // head
    c.drawCircle(Offset(w * 0.5, w * 0.40), w * 0.19, fill(skin));
    // front hair
    if (female) {
      c.drawArc(Rect.fromCircle(center: Offset(w * 0.5, w * 0.38), radius: w * 0.205), 3.14159, 3.14159, true, fill(hair));
    } else {
      c.drawArc(Rect.fromCircle(center: Offset(w * 0.5, w * 0.37), radius: w * 0.20), 3.14159, 3.14159, true, fill(hair));
    }
  }

  @override
  bool shouldRepaint(covariant _FigurePainter old) => old.female != female;
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
      child: url == null ? AvatarFigure(female: female, radius: radius) : null,
    );
    if (ring == null) return avatar;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 3)),
      child: avatar,
    );
  }
}
