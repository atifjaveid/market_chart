import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Width of [text] drawn in [style].
double textWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Draws [text] so that [align] of its box sits on [anchor].
void drawText(
  Canvas canvas,
  String text,
  Offset anchor,
  TextStyle style, {
  Alignment align = Alignment.topLeft,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = anchor.dx - (align.x + 1) / 2 * painter.width;
  final dy = anchor.dy - (align.y + 1) / 2 * painter.height;
  painter.paint(canvas, Offset(dx, dy));
  painter.dispose();
}

/// A dashed line from [from] to [to].
void dashedLine(
  Canvas canvas,
  Offset from,
  Offset to,
  Paint paint, {
  double dash = 4,
  double gap = 3,
}) {
  final total = (to - from).distance;
  if (total == 0) return;
  final direction = (to - from) / total;
  for (var d = 0.0; d < total; d += dash + gap) {
    canvas.drawLine(from + direction * d,
        from + direction * math.min(d + dash, total), paint);
  }
}
