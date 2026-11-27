import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/utente.dart';

class VipBadge extends StatefulWidget {
  final bool isLarge;

  const VipBadge({
    super.key,
    this.isLarge = false,
  });

  static bool isVip(Utente? u) {
    if (u == null) return false;
    if (u.isNoAds) return true;
    return u.badgeList.any((b) => b.toLowerCase().contains('vip no-ads'));
  }

  @override
  State<VipBadge> createState() => _VipBadgeState();
}

class _VipBadgeState extends State<VipBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
        final shimmerPos = _controller.value;

        if (widget.isLarge) {
          return Container(
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFACC15).withValues(alpha: 0.22 + (pulse * 0.25)),
                  blurRadius: 8 + (pulse * 6),
                  spreadRadius: 0.5 + pulse,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFB45309), Color(0xFFCA8A04), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Color.lerp(const Color(0xFFFACC15), Colors.white, pulse * 0.45)!,
                        width: 1.3,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        Text(
                          'VIP • CLUB SUPPORTER',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: const Color(0xFFFEF9C3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-2.5 + (shimmerPos * 4.5), -1.0),
                            end: Alignment(-1.5 + (shimmerPos * 4.5), 1.0),
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.30),
                              Colors.white.withValues(alpha: 0.0),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Pill compatta per Lista Amici e Classifica Evento
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFACC15).withValues(alpha: 0.20 + (pulse * 0.22)),
                blurRadius: 4 + (pulse * 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB45309), Color(0xFFEAB308)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFEF08A),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⭐', style: TextStyle(fontSize: 9.5)),
                      const SizedBox(width: 3),
                      Text(
                        'VIP',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: const Color(0xFFFEFCE8),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-2.5 + (shimmerPos * 4.5), -1.0),
                          end: Alignment(-1.5 + (shimmerPos * 4.5), 1.0),
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.34),
                            Colors.white.withValues(alpha: 0.0),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
