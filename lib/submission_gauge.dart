import 'dart:math';
import 'package:flutter/material.dart';

/// Segmented ring gauge showing how many of the team have submitted their
/// leg for the active gameweek. One segment per member — lit (brand green)
/// for members who've submitted, dim green for the rest — on a black card,
/// styled after a speedometer/credit-score dial.
class SubmissionGauge extends StatelessWidget {
  final int submittedCount;
  final int totalMembers;

  const SubmissionGauge({
    super.key,
    required this.submittedCount,
    required this.totalMembers,
  });

  static const _brandGreen = Color(0xFF00E676);
  static const _dimGreen = Color(0xFF163322);

  @override
  Widget build(BuildContext context) {
    if (totalMembers <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        height: 200,
        width: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(220, 200),
              painter: _GaugePainter(
                submitted: submittedCount,
                total: totalMembers,
                litColor: _brandGreen,
                unlitColor: _dimGreen,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Legs submitted',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  '$submittedCount',
                  style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold, height: 1),
                ),
                Text(
                  'out of $totalMembers',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final int submitted;
  final int total;
  final Color litColor;
  final Color unlitColor;

  _GaugePainter({
    required this.submitted,
    required this.total,
    required this.litColor,
    required this.unlitColor,
  });

  static const double _startAngle = 135 * pi / 180;
  static const double _totalSweep = 270 * pi / 180;
  static const double _gapDegrees = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = min(size.width, size.height);
    final strokeWidth = shortestSide * 0.14;
    final radius = (shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final gapRad = _gapDegrees * pi / 180;
    final segmentSweep = (_totalSweep - gapRad * total) / total;

    for (int i = 0; i < total; i++) {
      final segmentStart = _startAngle + i * (segmentSweep + gapRad);
      final paint = Paint()
        ..color = i < submitted ? litColor : unlitColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, segmentStart, segmentSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.submitted != submitted ||
        oldDelegate.total != total ||
        oldDelegate.litColor != litColor ||
        oldDelegate.unlitColor != unlitColor;
  }
}