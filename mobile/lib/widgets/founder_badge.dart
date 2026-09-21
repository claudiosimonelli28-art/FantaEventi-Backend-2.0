import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FounderInfo {
  final String title;
  final String subtitle;
  final String emoji;
  final List<Color> gradientColors;
  final Color borderColor;
  final Color textColor;
  final Color shadowColor;

  const FounderInfo({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.gradientColors,
    required this.borderColor,
    required this.textColor,
    required this.shadowColor,
  });
}

class FounderBadge extends StatefulWidget {
  final String nickname;
  final bool isLarge;

  const FounderBadge({
    super.key,
    required this.nickname,
    this.isLarge = false,
  });

  static FounderInfo? getFounderInfo(String nickname) {
    final clean = nickname.replaceAll(' ', '').trim().toLowerCase();

    // 1. Claude / Claudio / Cloud -> Fondatore & Mastermind
    if (clean == 'cloud' || clean == 'claude' || clean == 'claudio') {
      return const FounderInfo(
        title: 'FONDATORE • MASTERMIND',
        subtitle: 'Ideatore & Creatore di FantaEventi',
        emoji: '👑',
        gradientColors: [Color(0xFF6B21A8), Color(0xFFB45309)],
        borderColor: Color(0xFFFACC15),
        textColor: Color(0xFFFEF08A),
        shadowColor: Color(0xFFFACC15),
      );
    }

    // 2. Ziogab / Zio Gab -> Co-Fondatore & Pilastro
    if (clean == 'ziogab' || clean == 'gab' || clean == 'zio') {
      return const FounderInfo(
        title: 'CO-FONDATORE • PILASTRO',
        subtitle: 'Colonna Portante & Stratega',
        emoji: '🛡️',
        gradientColors: [Color(0xFFC2410C), Color(0xFFCA8A04)],
        borderColor: Color(0xFFFB923C),
        textColor: Color(0xFFFFEDD5),
        shadowColor: Color(0xFFFB923C),
      );
    }

    // 3. Ale04 -> Co-Fondatore & Pioniere
    if (clean == 'ale04' || clean == 'ale') {
      return const FounderInfo(
        title: 'CO-FONDATORE • PIONIERE',
        subtitle: 'Pioniere & Game Master Storico',
        emoji: '🚀',
        gradientColors: [Color(0xFF0369A1), Color(0xFF4338CA)],
        borderColor: Color(0xFF38BDF8),
        textColor: Color(0xFFE0F2FE),
        shadowColor: Color(0xFF38BDF8),
      );
    }

    return null;
  }

  static bool isFounder(String nickname) {
    return getFounderInfo(nickname) != null;
  }

  @override
  State<FounderBadge> createState() => _FounderBadgeState();
}

class _FounderBadgeState extends State<FounderBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = FounderBadge.getFounderInfo(widget.nickname);
    if (info == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        // Valore sinusoidale continuo per l'effetto respiro (0.0 -> 1.0)
        final pulse = (math.sin(_animController.value * 2 * math.pi) + 1) / 2;
        final shimmerPos = _animController.value;

        if (widget.isLarge) {
          return Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: info.shadowColor.withValues(alpha: 0.25 + (pulse * 0.35)),
                  blurRadius: 10 + (pulse * 8),
                  spreadRadius: 1 + (pulse * 1.5),
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // Sfondo con gradiente e bordo lucido
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: info.gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Color.lerp(info.borderColor, Colors.white, pulse * 0.4) ?? info.borderColor,
                        width: 1.4 + (pulse * 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 1.0 + (pulse * 0.12),
                          child: Text(info.emoji, style: const TextStyle(fontSize: 19)),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              info.title,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: info.textColor,
                              ),
                            ),
                            Text(
                              info.subtitle,
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Riflesso Shimmer metallico che scorre da sinistra a destra
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment(-2.5 + (shimmerPos * 4.5), -1.0),
                            end: Alignment(-1.5 + (shimmerPos * 4.5), 1.0),
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.28),
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

        // Versione Pill Compatta (per liste amici e schede)
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: info.shadowColor.withValues(alpha: 0.2 + (pulse * 0.25)),
                blurRadius: 5 + (pulse * 4),
                spreadRadius: pulse * 1.0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: info.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color.lerp(info.borderColor, Colors.white, pulse * 0.3) ?? info.borderColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 1.0 + (pulse * 0.1),
                        child: Text(info.emoji, style: const TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        info.title,
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                          color: info.textColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Shimmer sweep pill
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          begin: Alignment(-2.5 + (shimmerPos * 4.5), -1.0),
                          end: Alignment(-1.5 + (shimmerPos * 4.5), 1.0),
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.32),
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
