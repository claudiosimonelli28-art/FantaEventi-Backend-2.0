import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bonus_malus.dart';

class BonusMalusCard extends StatefulWidget {
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
  State<BonusMalusCard> createState() => _BonusMalusCardState();
}

class _BonusMalusCardState extends State<BonusMalusCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final bm = widget.bonusMalus;
    final isBonus = bm.punti > 0;
    final colorPunti = isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          // INTESTAZIONE (LIVELLO 2 DROPDOWN: Titolo + Punti + Freccia)
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorPunti.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isBonus ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: colorPunti,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      bm.titolo,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorPunti,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${isBonus ? "+" : ""}${bm.punti} PT',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFFFACC15),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),

          // CONTENUTO ESPANSO (SCHEDA DETTAGLIATA + TASTO ASSEGNA A GIOCATORE)
          if (_isExpanded) ...[
            const Divider(color: Color(0xFF334155), height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bm.descrizione.isNotEmpty) ...[
                    Text(
                      'Descrizione:',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bm.descrizione,
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF9333EA)),
                        ),
                        child: Text(
                          'Cat: ${bm.categoria}',
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (bm.riassegnabileMoltepliciVolte)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFACC15)),
                          ),
                          child: Text(
                            '🔁 Riassegnabile più volte',
                            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFFACC15), fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      if (widget.onAssegna != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onAssegna,
                            icon: const Icon(Icons.emoji_events_rounded, size: 16, color: Color(0xFF0F172A)),
                            label: Text(
                              'ASSEGNA A GIOCATORE',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 11, color: const Color(0xFF0F172A)),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFACC15),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      if (widget.onElimina != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                          tooltip: 'Elimina proposta',
                          onPressed: widget.onElimina,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
