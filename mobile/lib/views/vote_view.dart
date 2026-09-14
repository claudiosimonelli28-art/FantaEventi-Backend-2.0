import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/evento.dart';
import '../models/votazione.dart';
import '../services/api_service.dart';

class VoteView extends StatefulWidget {
  final Votazione votazione;

  const VoteView({super.key, required this.votazione});

  @override
  State<VoteView> createState() => _VoteViewState();
}

class _VoteViewState extends State<VoteView> {
  late Votazione _votazione;
  final ApiService _apiService = ApiService();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _votazione = widget.votazione;
  }

  Future<void> _esprimiVoto(bool aFavore) async {
    final curUser = _apiService.currentUser;
    final curUserNick = curUser?.nome.isNotEmpty == true ? curUser!.nome : 'Cloud';
    final cleanUser = curUserNick.trim().toLowerCase();
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanId = (curUser?.id ?? '').trim().toLowerCase();

    final evId = _votazione.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
    final evMatch = _apiService.eventi.firstWhere(
      (e) => (evId.isNotEmpty && (e.id.trim().toLowerCase() == evId || e.titolo.trim().toLowerCase() == evId)) ||
             (e.titolo.isNotEmpty && _votazione.titolo.toLowerCase().contains(e.titolo.toLowerCase())) ||
             (e.titolo.isNotEmpty && _votazione.descrizione.toLowerCase().contains(e.titolo.toLowerCase())),
      orElse: () => Evento(
        id: '',
        titolo: '',
        descrizione: '',
        data: DateTime.now(),
        luogo: '',
        stato: '',
        propostoDa: '',
        partecipanti: [],
        bonusMalusApplicati: [],
        votazioniAttive: [],
      ),
    );

    if (evMatch.id.isNotEmpty) {
      final cleanCreatore = (evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa).trim().toLowerCase();
      final pList = evMatch.partecipanti.map((p) => p.trim().toLowerCase()).toList();
      final iList = evMatch.invitati.map((p) => p.trim().toLowerCase()).toList();

      final bool isPartecipante = cleanCreatore == cleanUser || cleanCreatore == cleanNick || cleanCreatore == cleanId ||
                                  pList.contains(cleanUser) || pList.contains(cleanNick) || pList.contains(cleanId) ||
                                  iList.contains(cleanUser) || iList.contains(cleanNick) || iList.contains(cleanId);

      if (!isPartecipante) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Non puoi votare perché non partecipi a questo evento!'),
          ),
        );
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final vAggiornata = await _apiService.vota(_votazione.id, aFavore);
      if (!mounted) return;

      setState(() {
        _votazione = vAggiornata;
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final curUser = _apiService.currentUser;
    final curUserNick = curUser?.nome.isNotEmpty == true
        ? curUser!.nome
        : 'Cloud';
    final cleanUser = curUserNick.trim().toLowerCase();
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanId = (curUser?.id ?? '').trim().toLowerCase();

    final evId = _votazione.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
    final evMatch = _apiService.eventi.firstWhere(
      (e) => (evId.isNotEmpty && (e.id.trim().toLowerCase() == evId || e.titolo.trim().toLowerCase() == evId)) ||
             (e.titolo.isNotEmpty && _votazione.titolo.toLowerCase().contains(e.titolo.toLowerCase())) ||
             (e.titolo.isNotEmpty && _votazione.descrizione.toLowerCase().contains(e.titolo.toLowerCase())),
      orElse: () => Evento(
        id: '',
        titolo: '',
        descrizione: '',
        data: DateTime.now(),
        luogo: '',
        stato: '',
        propostoDa: '',
        partecipanti: [],
        bonusMalusApplicati: [],
        votazioniAttive: [],
      ),
    );

    bool isPartecipante = true;
    if (evMatch.id.isNotEmpty) {
      final cleanCreatore = (evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa).trim().toLowerCase();
      final pList = evMatch.partecipanti.map((p) => p.trim().toLowerCase()).toList();
      final iList = evMatch.invitati.map((p) => p.trim().toLowerCase()).toList();

      isPartecipante = cleanCreatore == cleanUser || cleanCreatore == cleanNick || cleanCreatore == cleanId ||
                       pList.contains(cleanUser) || pList.contains(cleanNick) || pList.contains(cleanId) ||
                       iList.contains(cleanUser) || iList.contains(cleanNick) || iList.contains(cleanId);
    }

    final propostoDa = (_votazione.bonusMalus?.propostoDa ?? '').trim().toLowerCase();
    final isProponente = propostoDa.isNotEmpty && propostoDa == cleanUser ||
        _votazione.descrizione.toLowerCase().contains('proposto da $cleanUser');

    final giaVotatoKey = _votazione.votiUtenti.keys.firstWhere(
      (k) => k.trim().toLowerCase() == cleanUser,
      orElse: () => '',
    );
    final haGiaVotato = giaVotatoKey.isNotEmpty;
    final votoUtente = haGiaVotato ? _votazione.votiUtenti[giaVotatoKey] : null;

    final int totale = _votazione.totaleVoti;
    final double favRatio = totale > 0 ? (_votazione.votiFavorevoli / totale) : 0.5;
    final double quorumPercent = (_votazione.totaleVoti / _votazione.quorum).clamp(0.0, 1.0);

    final bm = _votazione.bonusMalus;
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
        : _votazione.descrizione;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Votazione Democratica',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Banner Quorum & Stato
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF9333EA).withValues(alpha: 0.3),
                      const Color(0xFF1E293B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF9333EA)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'STATO VOTAZIONE',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _votazione.stato == 'in_corso'
                                ? const Color(0xFFFACC15)
                                : (_votazione.stato == 'approvato' ? Colors.green : Colors.red),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _votazione.stato.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quorum Richiesto',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_votazione.totaleVoti} / ${_votazione.quorum} voti',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _votazione.quorumRaggiunto ? Icons.check_circle : Icons.hourglass_top,
                          color: _votazione.quorumRaggiunto ? Colors.greenAccent : const Color(0xFFFACC15),
                          size: 36,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: quorumPercent,
                        minHeight: 8,
                        backgroundColor: const Color(0xFF334155),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _votazione.quorumRaggiunto ? Colors.greenAccent : const Color(0xFFFACC15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Dettaglio Proposta
              Text(
                _votazione.titolo,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              // Badges parametri proposta (Punti, Categoria, Riassegnabilità)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Badge Punti & Tipo
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: puntiColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: puntiColor.withValues(alpha: 0.6), width: 1.2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isBonus ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded, size: 16, color: puntiColor),
                        const SizedBox(width: 6),
                        Text(
                          puntiText,
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: puntiColor),
                        ),
                      ],
                    ),
                  ),

                  // Badge Categoria
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF64748B), width: 1.2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.category_rounded, size: 15, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 6),
                        Text(
                          categoria,
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // Badge Riassegnabilità
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: riassegnabile ? const Color(0xFF9333EA).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: riassegnabile ? const Color(0xFF9333EA).withValues(alpha: 0.6) : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(riassegnabile ? Icons.replay_rounded : Icons.looks_one_rounded, size: 16, color: riassegnabile ? const Color(0xFFD8B4FE) : const Color(0xFFFACC15)),
                        const SizedBox(width: 6),
                        Text(
                          riassegnabile ? 'Riassegnabile più volte: SÌ' : 'Riassegnabile: Solo una volta',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: riassegnabile ? const Color(0xFFD8B4FE) : const Color(0xFFFACC15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Scheda Testo Descrizione Regola
              if (desc.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.description_outlined, size: 16, color: Color(0xFFFACC15)),
                          const SizedBox(width: 6),
                          Text(
                            'Descrizione Completa della Regola:',
                            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        desc,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFFE2E8F0),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Grafico Distribuzione Voti
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Risultati in Tempo Reale',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'FAVOREVOLI: ${_votazione.votiFavorevoli}',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                        Text(
                          'CONTRARI: ${_votazione.votiContrari}',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: favRatio,
                        minHeight: 14,
                        backgroundColor: Colors.redAccent,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Bottoni di voto
              if (_votazione.stato == 'in_corso') ...[
                if (_isSubmitting)
                  const Center(child: CircularProgressIndicator(color: Color(0xFFFACC15)))
                else if (!isPartecipante)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF475569)),
                    ),
                    child: Text(
                      '🔒 Non partecipi a questo evento, pertanto non puoi votare su questa proposta.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFCBD5E1),
                      ),
                    ),
                  )
                else if (isProponente)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Text(
                      '🟢 Voto PRO registrato (Proposto da te)',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                    ),
                  )
                else if (haGiaVotato)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: votoUtente == 'pro' ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: votoUtente == 'pro' ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                    ),
                    child: Text(
                      votoUtente == 'pro' ? '🟢 Voto inviato: PRO' : '🔴 Voto inviato: CONTRO',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: votoUtente == 'pro' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      if (_votazione.nomeOrganizzatore != null && _votazione.nomeOrganizzatore!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.gavel_rounded, size: 14, color: Color(0xFFFACC15)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'In caso di parità, il voto dell\'organizzatore (${_votazione.nomeOrganizzatore}) 👑 sarà determinante',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFFACC15).withValues(alpha: 0.95), fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: () => _esprimiVoto(true),
                                icon: const Icon(Icons.thumb_up, color: Color(0xFF0F172A)),
                                label: Text(
                                  'VOTA SÌ',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.greenAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: () => _esprimiVoto(false),
                                icon: const Icon(Icons.thumb_down, color: Colors.white),
                                label: Text(
                                  'VOTA NO',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              ] else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _votazione.stato == 'approvato' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _votazione.stato == 'approvato'
                            ? '🟢 VOTAZIONE CONCLUSA: APPROVATA (${_votazione.votiFavorevoli} PRO - ${_votazione.votiContrari} CONTRO)'
                            : '🔴 VOTAZIONE CONCLUSA: RESPINTA (${_votazione.votiFavorevoli} PRO - ${_votazione.votiContrari} CONTRO)',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _votazione.stato == 'approvato' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                      if (_votazione.paritaDecisaDaOrganizzatore || (_votazione.votiFavorevoli == _votazione.votiContrari)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '⚖️ Parità ${_votazione.votiFavorevoli}-${_votazione.votiContrari} risolta dal voto ${_votazione.stato == "approvato" ? "favorevole" : "contrario"} dell\'organizzatore${(_votazione.nomeOrganizzatore != null && _votazione.nomeOrganizzatore!.isNotEmpty) ? " (${_votazione.nomeOrganizzatore}) 👑" : " 👑"}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _votazione.stato == 'approvato' ? const Color(0xFF34D399) : const Color(0xFFF87171),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
