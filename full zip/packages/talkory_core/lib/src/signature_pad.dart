import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A box to sign in with a finger (or a stylus). Keep a GlobalKey to the state to read the signature or clear it.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, this.height = 150, this.onChanged});
  final double height;
  final VoidCallback? onChanged;
  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];

  bool get isEmpty => _strokes.isEmpty || _strokes.every((s) => s.length < 2);
  int get points => _strokes.fold(0, (a, s) => a + s.length);

  void clear() {
    setState(_strokes.clear);
    widget.onChanged?.call();
  }

  /// The signature as a small black-on-white PNG (base64), or null if nothing was drawn.
  Future<String?> toPngBase64() async {
    if (isEmpty) return null;
    final box = context.findRenderObject() as RenderBox;
    const outW = 480.0;
    final scale = outW / box.size.width;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, outW, box.size.height * scale), Paint()..color = Colors.white);
    _paint(canvas, scale, Colors.black);
    final img = await rec.endRecording().toImage(outW.round(), (box.size.height * scale).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return base64Encode(data.buffer.asUint8List());
  }

  void _paint(Canvas canvas, double scale, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first * scale, 1.6 * scale, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx * scale, s.first.dy * scale);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx * scale, s[i].dy * scale);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black38)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          if (_strokes.isEmpty) const Center(child: Text('Sign here with your finger', style: TextStyle(color: Colors.black38))),
          Positioned(left: 12, right: 12, bottom: 28, child: Container(height: 1, color: Colors.black12)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
            onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
            onPanEnd: (_) => widget.onChanged?.call(),
            child: CustomPaint(size: Size.infinite, painter: _Painter(_strokes, _paint)),
          ),
        ]),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.strokes, this.paintFn);
  final List<List<Offset>> strokes;
  final void Function(Canvas, double, Color) paintFn;
  @override
  void paint(Canvas canvas, Size size) => paintFn(canvas, 1, Colors.black87);
  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
