import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

const accentOrange = AppColors.orange;

/// Phones: no YouTube downloads (not allowed in the app stores), no drag and drop,
/// files are imported into the app.
final isMobile = Platform.isAndroid || Platform.isIOS;

/// Narrow screens (a phone in portrait) get compact layouts.
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 700;

Color scoreColor(int score) => score >= 80
    ? AppColors.green
    : score >= 60
        ? AppColors.yellow
        : AppColors.red;

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
          child: Text('$score', style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w900)),
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
    canvas.drawArc(rect, 0, 2 * pi, false, Paint()..color = Colors.white10..style = PaintingStyle.stroke..strokeWidth = stroke);
    if (value <= 0) return;
    final sweep = SweepGradient(
      startAngle: 0,
      endAngle: 2 * pi * value,
      colors: [color.withValues(alpha: 0.55), color],
      transform: const GradientRotation(-pi / 2),
    ).createShader(rect);
    // A soft glow under the arc, then the arc itself.
    canvas.drawArc(rect, -pi / 2, 2 * pi * value, false,
        Paint()..color = color.withValues(alpha: 0.35)..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.8));
    canvas.drawArc(rect, -pi / 2, 2 * pi * value, false,
        Paint()..shader = sweep..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}
