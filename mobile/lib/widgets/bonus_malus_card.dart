import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bonus_malus.dart';

class BonusMalusCard extends StatelessWidget {
  final BonusMalus bonusMalus;
  final VoidCallback? onElimina;
  final VoidCallback? onAssegna;

  const BonusMalusCard({
    super.key,
    required this.bonusMalus,
    this.onElimina,
    this.onAssegna,
  });

  @override
  Widget build(BuildContext context) {
    final isBonus = bonusMalus.punti > 0;
    final colorPunti = isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorPunti.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBonus ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: colorPunti,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bonusMalus.titolo,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bonusMalus.descrizione,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorPunti,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${isBonus ? "+" : ""}${bonusMalus.punti} PT',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
              if (onElimina != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                  tooltip: 'Elimina proposta',
                  onPressed: onElimina,
                ),
              ],
            ],
          ),
          if (onAssegna != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAssegna,
                icon: const Icon(Icons.emoji_events_rounded, size: 16, color: Color(0xFF0F172A)),
                label: Text(
                  'ASSEGNA A PARTECIPANTE',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 11, color: const Color(0xFF0F172A)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFACC15),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
