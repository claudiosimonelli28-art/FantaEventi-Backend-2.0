import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/votazione.dart';

class VoteCard extends StatelessWidget {
  final Votazione votazione;
  final String currentUserNickname;
  final VoidCallback onVotaTap;

  const VoteCard({
    super.key,
    required this.votazione,
    required this.currentUserNickname,
    required this.onVotaTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalVoti = votazione.totaleVoti;
    final double proPercent = totalVoti > 0 ? (votazione.votiFavorevoli / totalVoti) : 0.5;

    final cleanUser = currentUserNickname.trim().toLowerCase();
    final propostoDa = (votazione.bonusMalus?.propostoDa ?? '').trim().toLowerCase();
    final isProponente = propostoDa.isNotEmpty && propostoDa == cleanUser ||
        votazione.descrizione.toLowerCase().contains('proposto da $cleanUser');

    final giaVotatoKey = votazione.votiUtenti.keys.firstWhere(
      (k) => k.trim().toLowerCase() == cleanUser,
      orElse: () => '',
    );
    final giaVotato = giaVotatoKey.isNotEmpty;
    final votoEspresso = giaVotato ? votazione.votiUtenti[giaVotatoKey] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.how_to_vote_rounded, color: Color(0xFFFACC15), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  votazione.titolo,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            votazione.descrizione,
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 14),

          // Favorevoli
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Favorevoli 👍', style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
              Text('${votazione.votiFavorevoli} voti', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF10B981))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: proPercent,
              minHeight: 6,
              backgroundColor: const Color(0xFF0F172A),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),

          const SizedBox(height: 10),

          // Contrari
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Contrari 👎', style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
              Text('${votazione.votiContrari} voti', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: totalVoti > 0 ? (votazione.votiContrari / totalVoti) : 0.5,
              minHeight: 6,
              backgroundColor: const Color(0xFF0F172A),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
            ),
          ),

          const SizedBox(height: 14),

          if (isProponente)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981)),
              ),
              child: Text(
                '🟢 Voto PRO registrato (Proposto da te)',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
              ),
            )
          else if (giaVotato)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: votoEspresso == 'pro' ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: votoEspresso == 'pro' ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
              ),
              child: Text(
                votoEspresso == 'pro' ? '🟢 Hai già votato: PRO' : '🔴 Hai già votato: CONTRO',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: votoEspresso == 'pro' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onVotaTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(
                  'VOTA ORA',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
