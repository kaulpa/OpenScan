import 'package:flutter/material.dart';

/// Draws the caption regions marked on the crop screen, each as the four
/// corners it has on screen — already turned with the page — so a region
/// keeps covering the same words through a rotation.
///
/// A different colour from the crop quad, so it is never mistaken for
/// part of the page's outline; the region still being dragged out is
/// drawn lighter.
class TextRegionPainter extends CustomPainter {
  TextRegionPainter({
    required this.regions,
    this.draft,
    this.color = const Color(0xFFFFC94D),
  });

  /// TL, TR, BR, BL of each marked region, in screen coordinates.
  final List<List<Offset>> regions;
  final List<Offset>? draft;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    for (final region in regions) {
      final path = _path(region);
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, stroke);
    }

    final draft = this.draft;
    if (draft != null) {
      canvas.drawPath(
        _path(draft),
        stroke..color = color.withValues(alpha: 0.6),
      );
    }
  }

  Path _path(List<Offset> corners) => Path()..addPolygon(corners, true);

  @override
  bool shouldRepaint(TextRegionPainter oldDelegate) => true;
}
