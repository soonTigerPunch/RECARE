import 'package:flutter/material.dart';

import '../domain/food_catalog.dart';

/// Original vector artwork: representative ingredients, not package photos.
class FoodIllustration extends StatelessWidget {
  const FoodIllustration({super.key, required this.visual, this.size = 44});
  final FoodVisual visual;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '식재료 대표 이미지',
    child: SizedBox.square(
      dimension: size,
      child: RepaintBoundary(child: CustomPaint(painter: _FoodPainter(visual))),
    ),
  );
}

class _FoodPainter extends CustomPainter {
  _FoodPainter(this.visual);
  final FoodVisual visual;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final brush = Paint()..isAntiAlias = true;
    void oval(double x, double y, double w, double h, int color) {
      canvas.drawOval(Rect.fromLTWH(x, y, w, h), brush..color = Color(color));
    }

    void box(double x, double y, double w, double h, double r, int color) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        brush..color = Color(color),
      );
    }

    void line(Offset a, Offset b, int color, double width) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Color(color)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    void shape(Path path, int color) =>
        canvas.drawPath(path, brush..color = Color(color));
    box(0, 0, 64, 64, 13, 0xFFF0F3F2);
    switch (visual) {
      case FoodVisual.milk:
        shape(
          Path()
            ..moveTo(20, 11)
            ..lineTo(39, 11)
            ..lineTo(46, 22)
            ..lineTo(46, 53)
            ..lineTo(18, 53)
            ..lineTo(18, 22)
            ..close(),
          0xFFFBFDFC,
        );
        shape(
          Path()
            ..moveTo(20, 11)
            ..lineTo(39, 11)
            ..lineTo(46, 22)
            ..lineTo(18, 22)
            ..close(),
          0xFF90AFA4,
        );
        box(18, 28, 28, 16, 0, 0xFF6C8D82);
        oval(27, 32, 10, 9, 0xFFE8F0ED);
        line(const Offset(20, 11), const Offset(39, 11), 0xFF4C6B60, 3);
      case FoodVisual.egg:
        oval(11, 25, 27, 31, 0xFFE4C4A2);
        oval(28, 12, 25, 36, 0xFFF5E5D1);
        oval(33, 18, 6, 12, 0xFFFFF6E9);
      case FoodVisual.carrot:
        shape(
          Path()
            ..moveTo(18, 24)
            ..quadraticBezierTo(45, 17, 45, 31)
            ..lineTo(23, 56)
            ..quadraticBezierTo(20, 58, 20, 53)
            ..close(),
          0xFFD78C50,
        );
        line(const Offset(33, 24), const Offset(28, 12), 0xFF6D8B58, 5);
        line(const Offset(34, 23), const Offset(40, 10), 0xFF87A46E, 5);
        line(const Offset(23, 34), const Offset(30, 37), 0xFFB66E3F, 2);
        line(const Offset(26, 44), const Offset(31, 45), 0xFFB66E3F, 2);
      case FoodVisual.potato:
        oval(10, 17, 43, 34, 0xFFC4AB86);
        oval(18, 20, 8, 3, 0xFFE0C8A3);
        for (final point in [
          const Offset(19, 35),
          const Offset(33, 26),
          const Offset(42, 38),
        ]) {
          oval(point.dx, point.dy, 3, 2, 0xFF927759);
        }
      case FoodVisual.onion:
        oval(14, 20, 37, 34, 0xFFCFB48E);
        line(const Offset(32, 22), const Offset(32, 11), 0xFF8A9A72, 4);
        oval(25, 24, 15, 28, 0xFFE9D3AD);
        line(const Offset(30, 54), const Offset(27, 57), 0xFF9E8463, 1.5);
      case FoodVisual.cucumber:
        canvas.save();
        canvas.rotate(0.4);
        box(29, 0, 16, 48, 8, 0xFF719567);
        line(const Offset(34, 7), const Offset(34, 40), 0xFFAAC391, 2);
        canvas.restore();
      case FoodVisual.greens:
        oval(9, 20, 29, 29, 0xFF8FAB7F);
        oval(27, 13, 27, 32, 0xFF6F925F);
        oval(18, 11, 23, 34, 0xFFA5BC91);
        line(const Offset(31, 55), const Offset(31, 29), 0xFFC6D5AE, 6);
        line(const Offset(31, 45), const Offset(19, 34), 0xFFC6D5AE, 3);
        line(const Offset(31, 40), const Offset(43, 29), 0xFFC6D5AE, 3);
      case FoodVisual.fruit:
        oval(12, 23, 29, 30, 0xFFC77465);
        oval(28, 23, 25, 30, 0xFFD38370);
        line(const Offset(32, 26), const Offset(34, 14), 0xFF8C7055, 3);
        oval(35, 12, 15, 7, 0xFF799461);
        oval(18, 29, 5, 11, 0xFFEAB5A5);
      case FoodVisual.banana:
        shape(
          Path()
            ..moveTo(14, 19)
            ..quadraticBezierTo(12, 50, 43, 49)
            ..quadraticBezierTo(54, 46, 54, 32)
            ..quadraticBezierTo(31, 49, 20, 19)
            ..close(),
          0xFFE0BF66,
        );
        line(const Offset(15, 18), const Offset(17, 24), 0xFF8C8456, 4);
        line(const Offset(46, 48), const Offset(52, 44), 0xFFAB9759, 2);
      case FoodVisual.tofu:
        box(10, 22, 44, 31, 7, 0xFFB0BFB4);
        box(14, 17, 36, 30, 4, 0xFFF6F0DF);
        line(const Offset(31, 20), const Offset(31, 43), 0xFFE0D9C3, 1.5);
        line(const Offset(18, 31), const Offset(46, 31), 0xFFE0D9C3, 1.5);
      case FoodVisual.mushroom:
        box(27, 29, 13, 24, 5, 0xFFE8DBC9);
        shape(
          Path()
            ..moveTo(10, 33)
            ..cubicTo(12, 5, 52, 5, 55, 33)
            ..close(),
          0xFFA58A70,
        );
        oval(21, 18, 8, 5, 0xFFC7AE92);
      case FoodVisual.meat:
        shape(
          Path()
            ..moveTo(16, 25)
            ..cubicTo(29, 9, 52, 15, 52, 32)
            ..cubicTo(53, 54, 24, 58, 13, 43)
            ..quadraticBezierTo(8, 34, 16, 25)
            ..close(),
          0xFFD59A8E,
        );
        oval(31, 24, 13, 16, 0xFFF5DED0);
        oval(35, 28, 5, 8, 0xFFBC7D74);
        line(const Offset(18, 37), const Offset(27, 45), 0xFFEBC4B8, 3);
      case FoodVisual.bread:
        box(17, 24, 31, 31, 4, 0xFFC59764);
        oval(11, 11, 43, 30, 0xFFC59764);
        box(21, 26, 23, 24, 2, 0xFFF2DDB9);
        oval(16, 16, 33, 22, 0xFFF2DDB9);
      case FoodVisual.rice:
        for (final pos in [
          const Offset(23, 24),
          const Offset(31, 19),
          const Offset(39, 25),
          const Offset(30, 29),
        ]) {
          oval(pos.dx, pos.dy, 6, 10, 0xFFFFFDF5);
        }
        shape(
          Path()
            ..moveTo(10, 32)
            ..lineTo(54, 32)
            ..quadraticBezierTo(50, 54, 32, 54)
            ..quadraticBezierTo(14, 54, 10, 32)
            ..close(),
          0xFF8AA2B5,
        );
        line(const Offset(10, 32), const Offset(54, 32), 0xFF627E94, 3);
      case FoodVisual.yogurt:
        shape(
          Path()
            ..moveTo(17, 20)
            ..lineTo(47, 20)
            ..lineTo(43, 53)
            ..lineTo(21, 53)
            ..close(),
          0xFFFAF8EF,
        );
        box(15, 16, 34, 7, 3, 0xFFA9A1B9);
        box(20, 31, 24, 13, 2, 0xFFC4BED0);
      case FoodVisual.grocery:
        box(14, 22, 36, 34, 4, 0xFFD5BD97);
        canvas.drawArc(
          const Rect.fromLTWH(23, 10, 18, 24),
          3.14,
          3.14,
          false,
          Paint()
            ..color = const Color(0xFFA68D69)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        oval(25, 32, 15, 10, 0xFF91A67B);
    }
  }

  @override
  bool shouldRepaint(covariant _FoodPainter oldDelegate) =>
      visual != oldDelegate.visual;
}
