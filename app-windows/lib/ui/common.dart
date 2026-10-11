import 'dart:math';

import 'package:flutter/material.dart';

const accentOrange = Color(0xFFF97316);

Color scoreColor(int score) => score >= 80
    ? Colors.green
    : score >= 60
        ? Colors.orange
        : Colors.red;

String scoreLabel(int score) => score >= 90
    ? 'Excelente!'
    : score >= 75
        ? 'Muito bom!'
        : score >= 60
            ? 'Bom'
            : score >= 40
                ? 'Continue praticando'
                : 'Tente de novo';

/// 62 -> "1:02", 3725 -> "1:02:05"
String formatTime(double seconds) {
  final total = seconds.floor();
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// 5842 -> "1h 37min"
String formatDuration(double seconds) {
  final minutes = seconds ~/ 60;
  if (minutes >= 60) return '${minutes ~/ 60}h ${minutes % 60}min';
  return minutes > 0 ? '$minutes min' : '${seconds.round()} s';
}

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// "há 5 minutos", "em 3 dias"
String relativeTime(DateTime date) {
  final difference = date.difference(DateTime.now());
  final future = !difference.isNegative;
  final d = difference.abs();
  final text = d.inMinutes < 1
      ? 'agora'
      : d.inHours < 1
          ? '${d.inMinutes} min'
          : d.inDays < 1
              ? '${d.inHours} h'
              : d.inDays == 1
                  ? '1 dia'
                  : '${d.inDays} dias';
  if (text == 'agora') return text;
  return future ? 'em $text' : 'há $text';
}

/// Circular score from 0 to 100.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 96});
  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(score / 100, scoreColor(score)),
        child: Center(
          child: Text('$score', style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(rect, 0, 2 * pi, false, Paint()..color = Colors.white12..style = PaintingStyle.stroke..strokeWidth = stroke);
    canvas.drawArc(rect, -pi / 2, 2 * pi * value, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}
