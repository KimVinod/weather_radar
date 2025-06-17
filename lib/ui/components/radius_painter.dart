import 'package:flutter/material.dart';

class RadiusPainter extends CustomPainter {
  final Map<String, double> center;
  final double radiusInPixels;

  RadiusPainter({
    required this.center,
    required this.radiusInPixels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Now, we just draw with the provided pixel value
    canvas.drawCircle(Offset(center['x']!, center['y']!), radiusInPixels, paint);
  }

  @override
  bool shouldRepaint(covariant RadiusPainter oldDelegate) {
    return oldDelegate.center != center || oldDelegate.radiusInPixels != radiusInPixels;
  }
}