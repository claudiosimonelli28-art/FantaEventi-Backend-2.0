import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnimatedPointsCounter extends StatelessWidget {
  final int points;
  final TextStyle? style;
  final String suffix;
  final bool showPositiveSign;

  const AnimatedPointsCounter({
    super.key,
    required this.points,
    this.style,
    this.suffix = 'PT',
    this.showPositiveSign = false,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: points.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        final currentInt = val.round();
        final sign = (showPositiveSign && currentInt > 0) ? '+' : '';
        final textContent = suffix.isEmpty ? '$sign$currentInt' : '$sign$currentInt $suffix';
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            textContent,
            maxLines: 1,
            style: style ??
                GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: currentInt >= 0
                      ? const Color(0xFFFACC15)
                      : const Color(0xFFEF4444),
                ),
          ),
        );
      },
    );
  }
}
