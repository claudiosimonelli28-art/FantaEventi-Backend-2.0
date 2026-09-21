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

class FounderBadge extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final info = getFounderInfo(nickname);
    if (info == null) return const SizedBox.shrink();

    if (isLarge) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: info.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: info.borderColor, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: info.shadowColor.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
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
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Small pill version (for lists, modal cards, chips)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: info.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: info.borderColor.withValues(alpha: 0.8), width: 1),
        boxShadow: [
          BoxShadow(
            color: info.shadowColor.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(info.emoji, style: const TextStyle(fontSize: 11)),
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
    );
  }
}
