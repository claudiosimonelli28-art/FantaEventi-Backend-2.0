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

    final bm = votazione.bonusMalus;
    final int punti = bm?.punti ?? 0;
    final bool isBonus = punti >= 0;
    final String puntiText = isBonus ? '+$punti PT (Bonus)' : '$punti PT (Malus)';
    final Color puntiColor = isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final String categoria = (bm?.categoria != null && bm!.categoria.isNotEmpty)
        ? bm.categoria
        : (isBonus ? 'Bonus' : 'Malus');
    final bool riassegnabile = bm?.riassegnabileMoltepliciVolte == true;
    final String desc = (bm?.descrizione != null && bm!.descrizione.isNotEmpty)
        ? bm.descrizione
        : votazione.descrizione;

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
          const SizedBox(height: 12),

          // Badges parametri proposta (Punti, Categoria, Riassegnabilità)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Badge Punti & Tipo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: puntiColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: puntiColor.withValues(alpha: 0.6), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isBonus ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded, size: 14, color: puntiColor),
                    const SizedBox(width: 5),
                    Text(
                      puntiText,
                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: puntiColor),
                    ),
                  ],
                ),
              ),

              // Badge Categoria
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF64748B)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.category_rounded, size: 13, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 5),
                    Text(
                      categoria,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // Badge Riassegnabilità
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: riassegnabile ? const Color(0xFF9333EA).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: riassegnabile ? const Color(0xFF9333EA).withValues(alpha: 0.6) : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(riassegnabile ? Icons.replay_rounded : Icons.looks_one_rounded, size: 14, color: riassegnabile ? const Color(0xFFD8B4FE) : const Color(0xFFFACC15)),
                    const SizedBox(width: 5),
                    Text(
                      riassegnabile ? 'Riassegnabile più volte: SÌ' : 'Riassegnabile: Solo una volta',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: riassegnabile ? const Color(0xFFD8B4FE) : const Color(0xFFFACC15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Box Descrizione della Regola
          if (desc.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Descrizione della Regola:',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFE2E8F0), height: 1.4),
                  ),
                ],
              ),
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

          if (votazione.stato == 'approvato')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    '🟢 VOTAZIONE CONCLUSA: APPROVATA (${votazione.votiFavorevoli} PRO - ${votazione.votiContrari} CONTRO)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                  ),
                  if (votazione.paritaDecisaDaOrganizzatore || (votazione.votiFavorevoli == votazione.votiContrari)) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⚖️ Parità ${votazione.votiFavorevoli}-${votazione.votiContrari} risolta dal voto favorevole dell\'organizzatore${(votazione.nomeOrganizzatore != null && votazione.nomeOrganizzatore!.isNotEmpty) ? " (${votazione.nomeOrganizzatore}) 👑" : " 👑"}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF34D399)),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (votazione.stato == 'respinto')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    '🔴 VOTAZIONE CONCLUSA: RESPINTA (${votazione.votiFavorevoli} PRO - ${votazione.votiContrari} CONTRO)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                  ),
                  if (votazione.paritaDecisaDaOrganizzatore || (votazione.votiFavorevoli == votazione.votiContrari)) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⚖️ Parità ${votazione.votiFavorevoli}-${votazione.votiContrari} risolta dal voto contrario dell\'organizzatore${(votazione.nomeOrganizzatore != null && votazione.nomeOrganizzatore!.isNotEmpty) ? " (${votazione.nomeOrganizzatore}) 👑" : " 👑"}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFF87171)),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (isProponente)
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
