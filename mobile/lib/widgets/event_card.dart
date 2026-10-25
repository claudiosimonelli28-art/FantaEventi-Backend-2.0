import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/evento.dart';
import 'live_pulse_badge.dart';

class EventCard extends StatelessWidget {
  final Evento evento;
  final String currentUserNickname;
  final VoidCallback onTap;
  final VoidCallback onPartecipa;
  final VoidCallback onElimina;

  const EventCard({
    super.key,
    required this.evento,
    required this.currentUserNickname,
    required this.onTap,
    required this.onPartecipa,
    required this.onElimina,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUser = currentUserNickname.trim().toLowerCase();
    final cleanCreatore = evento.creatore.trim().toLowerCase();
    
    final isCreatore = cleanCreatore.isNotEmpty &&
        (cleanCreatore == cleanUser ||
         (cleanUser == 'cloud' && (cleanCreatore == 'claudio' || cleanCreatore.contains('claudio'))) ||
         (cleanUser == 'claudio' && cleanCreatore == 'cloud'));

    final isPartecipante = isCreatore || evento.partecipanti.any((p) {
      final pClean = p.trim().toLowerCase();
      return pClean == cleanUser ||
          (cleanUser == 'cloud' && (pClean == 'claudio' || pClean.contains('claudio'))) ||
          (cleanUser == 'claudio' && pClean == 'cloud');
    });

    final isInvitato = evento.invitati.any((i) {
      final iClean = i.trim().toLowerCase();
      return iClean == cleanUser ||
          (cleanUser == 'cloud' && (iClean == 'claudio' || iClean.contains('claudio'))) ||
          (cleanUser == 'claudio' && iClean == 'cloud');
    });

    final isAnnullato = evento.isAnnullato;
    final isConcluso = evento.isConcluso;
    final isInCorso = evento.isInCorso;
    final bool isIscrizioniChiuse = isAnnullato || isConcluso || (isInCorso && !isPartecipante);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAnnullato
              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
              : isConcluso
                  ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                  : isInCorso
                      ? const Color(0xFF10B981).withValues(alpha: 0.8)
                      : isCreatore
                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.7)
                          : isPartecipante
                              ? const Color(0xFF10B981).withValues(alpha: 0.4)
                              : isInvitato
                                  ? const Color(0xFFFACC15).withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.08),
          width: (isCreatore || isPartecipante || isInvitato || isConcluso || isInCorso || isAnnullato) ? 1.5 : 1.0,
        ),
        boxShadow: isInCorso
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : isCreatore
                ? [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isAnnullato)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  '❌ ANNULLATO',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFF87171),
                                  ),
                                ),
                              )
                            else if (isInCorso)
                              const LivePulseBadge(
                                text: 'IN CORSO',
                                color: Color(0xFF10B981),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isConcluso
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                                      : const Color(0xFF9333EA).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isConcluso ? 'EVENTO CONCLUSO' : 'IN PROGRAMMA',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isConcluso
                                        ? const Color(0xFFF87171)
                                        : const Color(0xFFC084FC),
                                  ),
                                ),
                              ),
                            if (isCreatore)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFFACC15).withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.stars_rounded, size: 13, color: Color(0xFFFACC15)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'ORGANIZZATO DA TE',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (evento.creatore.trim().isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_pin_circle_rounded, size: 12, color: const Color(0xFF94A3B8)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'di @${evento.creatore}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          evento.titolo,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCreatore)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                      tooltip: 'Elimina evento',
                      onPressed: onElimina,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                evento.descrizione,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFFFACC15)),
                  const SizedBox(width: 6),
                  Text(
                    '${evento.data.day}/${evento.data.month}/${evento.data.year}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFFFACC15)),
                  const SizedBox(width: 6),
                  Text(
                    '${evento.partecipanti.length} Partecipanti',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isIscrizioniChiuse ? null : onPartecipa,
                  icon: Icon(
                    isAnnullato
                        ? Icons.cancel_outlined
                        : isConcluso
                            ? Icons.flag_rounded
                            : (isInCorso && !isPartecipante)
                                ? Icons.lock_clock_rounded
                                : isPartecipante
                                    ? Icons.check_circle_rounded
                                    : isInvitato
                                        ? Icons.pending_actions_rounded
                                        : Icons.person_add_alt_1_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isAnnullato
                        ? 'EVENTO ANNULLATO (NESSUN PARTECIPANTE)'
                        : isConcluso
                            ? 'EVENTO CONCLUSO'
                            : (isInCorso && !isPartecipante)
                                ? (isInvitato ? 'TEMPO SCADUTO (EVENTO IN CORSO)' : 'ISCRIZIONI CHIUSE (IN CORSO)')
                                : isPartecipante
                                    ? 'GIÀ PARTECIPANTE'
                                    : isInvitato
                                        ? 'INVITO IN SOSPESO (RISPONDI)'
                                        : 'PARTECIPA ALL\'EVENTO',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isIscrizioniChiuse
                        ? const Color(0xFF334155)
                        : isPartecipante
                            ? const Color(0xFF10B981)
                            : isInvitato
                                ? const Color(0xFFEAB308)
                                : const Color(0xFF9333EA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
