import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/live_pulse_badge.dart';
import '../widgets/animated_points_counter.dart';
import '../models/evento.dart';
import '../models/utente.dart';
import '../models/votazione.dart';
import '../models/bonus_malus.dart';
import '../services/api_service.dart';
import 'add_bonus_malus_view.dart';

class EventDetailView extends StatefulWidget {
  final Evento evento;
  final VoidCallback onRefresh;

  const EventDetailView({
    super.key,
    required this.evento,
    required this.onRefresh,
  });

  @override
  State<EventDetailView> createState() => _EventDetailViewState();
}

class _EventDetailViewState extends State<EventDetailView> {
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();
  late Evento _evento;
  List<Votazione> _votazioniEvento = [];
  List<BonusMalus> _allBonusMalus = [];
  Set<String> _invitatiInSospeso = {};
  List<String> _partecipantiConfermati = [];
  Timer? _liveLeaderboardTimer;

  @override
  void initState() {
    super.initState();
    _evento = widget.evento;
    _calcolaCoerenzaInvitiEVotazioni();
    _liveLeaderboardTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _calcolaCoerenzaInvitiEVotazioni();
      }
    });
  }

  @override
  void dispose() {
    _liveLeaderboardTimer?.cancel();
    super.dispose();
  }

  Future<void> _calcolaCoerenzaInvitiEVotazioni() async {
    final creatore = _evento.propostoDa.isNotEmpty ? _evento.propostoDa : 'Cloud';

    final List<String> confermati = [creatore];
    final Set<String> inSospeso = {};

    for (var p in _evento.partecipanti) {
      if (!confermati.any((c) => c.trim().toLowerCase() == p.trim().toLowerCase())) {
        confermati.add(p);
      }
    }

    for (var inv in _evento.invitati) {
      if (!confermati.any((c) => c.trim().toLowerCase() == inv.trim().toLowerCase())) {
        inSospeso.add(inv);
      }
    }

    List<Votazione> votiFiltered = [];
    List<BonusMalus> bmList = [];
    try {
      final allVoti = await _apiService.getVotazioni();
      votiFiltered = allVoti.where((v) =>
        v.titolo.toLowerCase().contains(_evento.titolo.toLowerCase()) ||
        v.descrizione.toLowerCase().contains(_evento.titolo.toLowerCase())
      ).toList();
      bmList = await _apiService.getBonusMalusList();
      for (var bm in bmList) {
        final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
            bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
        if (isSameEv) {
          for (var u in bm.assegnatoA) {
            if (u.trim().isNotEmpty && !confermati.any((c) => c.trim().toLowerCase() == u.trim().toLowerCase())) {
              confermati.add(u.trim());
            }
          }
        }
      }
      _apiService.getUtenti().catchError((_) => <Utente>[]);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _partecipantiConfermati = confermati;
        _invitatiInSospeso = inSospeso;
        _votazioniEvento = votiFiltered;
        _allBonusMalus = bmList;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserNick = _apiService.currentUser?.nome ?? 'Cloud';
    final creatore = _evento.propostoDa.isNotEmpty ? _evento.propostoDa : 'Cloud';
    final isCreatore = creatore.trim().toLowerCase() == currentUserNick.trim().toLowerCase();
    final isConcluso = _evento.isConcluso;
    final giaPartecipa = _partecipantiConfermati.contains(currentUserNick) ||
        _partecipantiConfermati.contains(_apiService.currentUser?.id);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: CustomScrollView(
        slivers: [
          // Slivers AppBar con Copertina dell'Evento
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: const Color(0xFF1E293B),
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _evento.titolo,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [const Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: getEventCoverImageProvider(_evento.copertinaUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, _, __) => Container(
                      color: const Color(0xFF1E293B),
                      child: const Icon(Icons.event, size: 80, color: Colors.white24),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          const Color(0xFF0F172A),
                        ],
                      ),
                    ),
                  ),
                  if (isCreatore && !isConcluso)
                    Positioned(
                      top: 40,
                      right: 14,
                      child: SafeArea(
                        child: InkWell(
                          onTap: _mostraModalCambiaCopertina,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.7)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFFFACC15)),
                                const SizedBox(width: 5),
                                Text(
                                  'Cambia Foto',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Contenuto Dettagliato
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Organizzatore e Stato
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFACC15)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star, size: 14, color: Color(0xFFFACC15)),
                            const SizedBox(width: 4),
                            Text(
                              'Organizzato da: ${_evento.propostoDa.isNotEmpty ? _evento.propostoDa : "Cloud"}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFFACC15),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22C55E)),
                        ),
                        child: Text(
                          _evento.stato.toUpperCase(),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF22C55E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Descrizione Completa
                  Text(
                    'Descrizione Evento',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Text(
                      _evento.descrizione.isNotEmpty ? _evento.descrizione : 'Nessuna descrizione specificata per questo evento.',
                      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFFCBD5E1), height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Data Inizio, Data Fine e Luogo Cards
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981), size: 18),
                                      const SizedBox(width: 6),
                                      Text('Data & Ora Inizio', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_evento.data.day}/${_evento.data.month}/${_evento.data.year} alle ${_evento.data.hour.toString().padLeft(2, '0')}:${_evento.data.minute.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.stop_circle_rounded, color: Color(0xFFEF4444), size: 18),
                                      const SizedBox(width: 6),
                                      Text('Data & Ora Fine', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_evento.dataFine.day}/${_evento.dataFine.month}/${_evento.dataFine.year} alle ${_evento.dataFine.hour.toString().padLeft(2, '0')}:${_evento.dataFine.minute.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.place_rounded, color: Color(0xFF9333EA), size: 20),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Location / Luogo', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11)),
                                Text(
                                  _evento.luogo.isNotEmpty ? _evento.luogo : 'Non specificata',
                                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SEZIONE CLASSIFICA DINAMICA LIVE EVENTO
                  _buildLeaderboardSection(),
                  const SizedBox(height: 28),

                  // SEZIONE TRACCIAMENTO STATO INVITI PARTECEPATI (Coerenza Rigorosa)
                  Row(
                    children: [
                      const Icon(Icons.how_to_reg_rounded, color: Color(0xFFFACC15), size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stato Inviti Partecipanti',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🟢 Partecipanti Confermato (${_partecipantiConfermati.length}):',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _partecipantiConfermati.map((p) {
                            return Chip(
                              avatar: const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                              label: Text(p, style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                              side: const BorderSide(color: Color(0xFF10B981)),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        Text('⏳ Inviti in Sospeso (${_invitatiInSospeso.length}):',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _invitatiInSospeso.map((p) {
                            return Chip(
                              avatar: const Icon(Icons.hourglass_top_rounded, size: 14, color: Color(0xFFFACC15)),
                              label: Text(p, style: GoogleFonts.poppins(color: Colors.white, fontSize: 11)),
                              backgroundColor: const Color(0xFFFACC15).withValues(alpha: 0.15),
                              side: const BorderSide(color: Color(0xFFFACC15)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // SEZIONE TRACCIAMENTO VOTAZIONI PRO / CONTRO / NON VOTATO (Layout anti-overflow)
                  Row(
                    children: [
                      const Icon(Icons.poll_rounded, color: Color(0xFF9333EA), size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Votazioni Bonus & Malus in Tempo Reale',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_votazioniEvento.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        'Nessuna votazione attiva per questo evento al momento.',
                        style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                      ),
                    )
                  else
                    Column(
                      children: _votazioniEvento.map((v) {
                        final Map<String, String> voti = v.votiUtenti;
                        final List<String> favList = [];
                        final List<String> contList = [];
                        final List<String> pendingList = [];

                        voti.forEach((user, vote) {
                          if (vote == 'pro' || vote == 'favorevole') {
                            favList.add(user);
                          } else if (vote == 'contro' || vote == 'contrario') {
                            contList.add(user);
                          }
                        });

                        for (var user in _partecipantiConfermati) {
                          if (!voti.containsKey(user) && !favList.contains(user) && !contList.contains(user)) {
                            pendingList.add(user);
                          }
                        }

                        final isApprovato = v.stato == 'approvato' || favList.length >= v.quorum;
                        final isBocciato = v.stato == 'respinto' || contList.length >= v.quorum || (v.quorum == 2 && contList.length >= 1);
                        final badgeColor = isApprovato
                            ? const Color(0xFF10B981)
                            : isBocciato
                                ? const Color(0xFFEF4444)
                                : const Color(0xFFFACC15);
                        final badgeText = isApprovato
                            ? '✅ APPROVATO'
                            : isBocciato
                                ? '❌ BOCCIATO'
                                : '⏳ IN VOTAZIONE (${favList.length}/${v.quorum} PRO)';

                        final cleanUser = currentUserNick.trim().toLowerCase();
                        final propostoDa = (v.bonusMalus?.propostoDa ?? '').trim().toLowerCase();
                        final isProponente = propostoDa.isNotEmpty && propostoDa == cleanUser ||
                            v.descrizione.toLowerCase().contains('proposto da $cleanUser');

                        final giaVotatoKey = v.votiUtenti.keys.firstWhere(
                          (k) => k.trim().toLowerCase() == cleanUser,
                          orElse: () => '',
                        );
                        final haGiaVotato = giaVotatoKey.isNotEmpty;
                        final votoUtente = haGiaVotato ? v.votiUtenti[giaVotatoKey] : null;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      v.titolo,
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: badgeColor),
                                    ),
                                    child: Text(
                                      badgeText,
                                      style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                                    ),
                                  ),
                                  if (isProponente) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                      tooltip: 'Elimina Proposta',
                                      onPressed: () async {
                                        await _apiService.eliminaBonusMalus(v.id);
                                        setState(() {
                                          _evento.votazioniAttive.removeWhere((item) => item.id == v.id);
                                        });
                                        widget.onRefresh();
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Proposta bonus eliminata con successo! 🗑️')),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                v.descrizione,
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                              ),
                              const SizedBox(height: 14),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.thumb_up_rounded, size: 14, color: Colors.greenAccent),
                                        const SizedBox(width: 6),
                                        Text('PRO (${favList.length}): ', style: GoogleFonts.poppins(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                        Expanded(child: Text(favList.isNotEmpty ? favList.join(', ') : 'Nessun voto pro', style: GoogleFonts.inter(fontSize: 12, color: Colors.white))),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.thumb_down_rounded, size: 14, color: Colors.redAccent),
                                        const SizedBox(width: 6),
                                        Text('CONTRO (${contList.length}): ', style: GoogleFonts.poppins(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                        Expanded(child: Text(contList.isNotEmpty ? contList.join(', ') : 'Nessun voto contro', style: GoogleFonts.inter(fontSize: 12, color: Colors.white))),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.hourglass_empty_rounded, size: 14, color: Color(0xFFFACC15)),
                                        const SizedBox(width: 6),
                                        Text('NON VOTATO: ', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                                        Expanded(child: Text(pendingList.isNotEmpty ? pendingList.join(', ') : 'Tutti hanno votato', style: GoogleFonts.inter(fontSize: 12, color: Colors.white))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              if (!isApprovato && !isBocciato) ...[
                                if (isProponente)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF10B981)),
                                    ),
                                    child: Text(
                                      '🟢 Voto PRO registrato (Proposto da te)',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                                    ),
                                  )
                                else if (haGiaVotato)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: votoUtente == 'pro' ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: votoUtente == 'pro' ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                                    ),
                                    child: Text(
                                      votoUtente == 'pro' ? '🟢 Voto inviato: PRO' : '🔴 Voto inviato: CONTRO',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: votoUtente == 'pro' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                      ),
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            await _apiService.vota(v.id, true);
                                            widget.onRefresh();
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Voto PRO registrato! 👍')),
                                            );
                                          },
                                          icon: const Icon(Icons.thumb_up_rounded, size: 14, color: Colors.white),
                                          label: const Text('VOTA PRO'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF10B981),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            await _apiService.vota(v.id, false);
                                            widget.onRefresh();
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Voto CONTRO registrato! 👎')),
                                            );
                                          },
                                          icon: const Icon(Icons.thumb_down_rounded, size: 14, color: Colors.white),
                                          label: const Text('VOTA CONTRO'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFEF4444),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 32),

                  // Bottoni d'Azione
                  Row(
                    children: [
                      if (!giaPartecipa)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _apiService.partecipaAdEvento(_evento.id, currentUserNick);
                              setState(() {
                                if (!_partecipantiConfermati.contains(currentUserNick)) {
                                  _partecipantiConfermati.add(currentUserNick);
                                }
                                _invitatiInSospeso.remove(currentUserNick);
                              });
                              widget.onRefresh();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ti sei iscritto all\'evento! 🎉')),
                              );
                            },
                            icon: const Icon(Icons.person_add, color: Color(0xFF0F172A)),
                            label: const Text('PARTECIPA'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFACC15),
                              foregroundColor: const Color(0xFF0F172A),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      if (!giaPartecipa) const SizedBox(width: 12),

                      if (_evento.stato.trim().toLowerCase() != 'concluso' && !DateTime.now().isAfter(_evento.dataFine))
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => AddBonusMalusView(evento: _evento)),
                              );
                              widget.onRefresh();
                            },
                            icon: const Icon(Icons.stars, color: Colors.white),
                            label: const Text('PROPONI BONUS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9333EA),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardSection() {
    final now = DateTime.now();
    
    // Calcolo Punti Evento per ciascun partecipante
    final Map<String, int> puntiPerPartecipante = {};
    for (var p in _partecipantiConfermati) {
      puntiPerPartecipante[p] = 0;
    }

    for (var bm in _allBonusMalus) {
      final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
          bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
      if (isSameEv || _allBonusMalus.length == 1) {
        for (var p in _partecipantiConfermati) {
          final count = bm.assegnatoA.where((u) => u.trim().toLowerCase() == p.trim().toLowerCase()).length;
          if (count > 0) {
            puntiPerPartecipante[p] = (puntiPerPartecipante[p] ?? 0) + (bm.punti * count);
          }
        }
      }
    }

    final sortedEntries = puntiPerPartecipante.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final isConcluso = _evento.stato.trim().toLowerCase() == 'concluso' || now.isAfter(_evento.dataFine);
    final isInCorso = !isConcluso && (now.isAfter(_evento.data) || _evento.stato.trim().toLowerCase() == 'in_corso');
    final isInProgramma = !isConcluso && !isInCorso;

    String headerTitle = '🏆 Classifica Live Evento';
    String tagText = '🔴 LIVE';
    Color tagColor = const Color(0xFF9333EA);

    if (isConcluso) {
      headerTitle = '🏆 Classifica Finale Evento';
      tagText = '🔒 CONGELATO';
      tagColor = const Color(0xFF10B981);
    } else if (isInProgramma) {
      headerTitle = '📅 Classifica Evento (In Programma)';
      tagText = '⏳ IN ATTESA';
      tagColor = const Color(0xFF3B82F6);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                headerTitle,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            if (isInCorso)
              const LivePulseBadge(text: 'LIVE', color: Color(0xFF10B981))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tagColor),
                ),
                child: Text(
                  tagText,
                  style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: tagColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (isInProgramma) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'L\'evento è in programma. La classifica live si attiverà al momento dell\'inizio dell\'evento.',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            children: List.generate(sortedEntries.length, (idx) {
              final entry = sortedEntries[idx];
              final nick = entry.key;
              final pts = entry.value;
              final isFirst = idx == 0;
              final isSecond = idx == 1;
              final isThird = idx == 2;

              final badgeColor = isFirst
                  ? const Color(0xFFFACC15)
                  : isSecond
                      ? const Color(0xFF94A3B8)
                      : isThird
                          ? const Color(0xFFB45309)
                          : const Color(0xFF334155);

              final rankIcon = isFirst ? '🥇' : isSecond ? '🥈' : isThird ? '🥉' : '#${idx + 1}';

              return InkWell(
                onTap: () => _mostraDettaglioStoricoGiocatore(nick),
                borderRadius: BorderRadius.vertical(
                  top: idx == 0 ? const Radius.circular(16) : Radius.zero,
                  bottom: idx == sortedEntries.length - 1 ? const Radius.circular(16) : Radius.zero,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: idx < sortedEntries.length - 1
                        ? const Border(bottom: BorderSide(color: Color(0xFF334155)))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          rankIcon,
                          style: TextStyle(
                            fontSize: isFirst || isSecond || isThird ? 18 : 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildAvatarWidget(_apiService.getUtenteInMemoria(nick)?.avatarUrl ?? '', nick, radius: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          nick,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: pts >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: AnimatedPointsCounter(
                          points: pts,
                          showPositiveSign: true,
                          suffix: 'PT',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 18),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        if (isConcluso) ...[
          const SizedBox(height: 18),
          _buildSpecialTitlesSection(sortedEntries),
          const SizedBox(height: 12),
          _buildCondividiPodioButton(sortedEntries),
        ],
      ],
    );
  }

  Widget _buildAvatarWidget(String avatarUrl, String nickname, {double radius = 20}) {
    final imgProvider = getAvatarImageProvider(avatarUrl);
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF9333EA),
      backgroundImage: imgProvider,
    );
  }

  Widget _buildSpecialTitlesSection(List<MapEntry<String, int>> sortedEntries) {
    if (sortedEntries.isEmpty) return const SizedBox.shrink();

    // 1. Campione: primo con punteggio maggiore (se >= 0)
    final campioneEntry = sortedEntries.first;
    final String campioneNick = campioneEntry.key;
    final int campionePts = campioneEntry.value;

    // 2. Re dei Malus: chi ha accumulato il maggior totale di punti malus negativi
    final Map<String, int> malusPunti = {};
    // 3. Giudice Supremo: chi ha proposto o votato più volte
    final Map<String, int> attivitaUtenti = {};
    // 4. Per il Fantasma: totale azioni (ricevute + proposte + voti)
    final Map<String, int> azioniTotali = {};

    for (var p in _evento.partecipanti) {
      final pNorm = p.trim().toLowerCase();
      malusPunti[pNorm] = 0;
      attivitaUtenti[pNorm] = 0;
      azioniTotali[pNorm] = 0;
    }

    for (var bm in _allBonusMalus) {
      final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
          bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
      if (!isSameEv && _allBonusMalus.length > 1) continue;

      // Proposte da
      final prop = bm.propostoDa.trim().toLowerCase();
      if (attivitaUtenti.containsKey(prop)) {
        attivitaUtenti[prop] = (attivitaUtenti[prop] ?? 0) + 1;
        azioniTotali[prop] = (azioniTotali[prop] ?? 0) + 1;
      }

      // Assegnato a
      for (var u in bm.assegnatoA) {
        final uNorm = u.trim().toLowerCase();
        azioniTotali[uNorm] = (azioniTotali[uNorm] ?? 0) + 1;
        if (bm.punti < 0) {
          malusPunti[uNorm] = (malusPunti[uNorm] ?? 0) + bm.punti.abs();
        }
      }
    }

    for (var v in _votazioniEvento) {
      for (var u in v.votiUtenti.keys) {
        final uNorm = u.trim().toLowerCase();
        if (attivitaUtenti.containsKey(uNorm)) {
          attivitaUtenti[uNorm] = (attivitaUtenti[uNorm] ?? 0) + 1;
          azioniTotali[uNorm] = (azioniTotali[uNorm] ?? 0) + 1;
        }
      }
    }

    // Re dei Malus
    String? reMalusNick;
    int maxMalusVal = 0;
    malusPunti.forEach((nickLower, tot) {
      if (tot > maxMalusVal) {
        maxMalusVal = tot;
        reMalusNick = _evento.partecipanti.firstWhere(
          (p) => p.trim().toLowerCase() == nickLower,
          orElse: () => nickLower,
        );
      }
    });

    // Giudice Supremo
    String? giudiceNick;
    int maxAttivita = 0;
    attivitaUtenti.forEach((nickLower, count) {
      if (count > maxAttivita) {
        maxAttivita = count;
        giudiceNick = _evento.partecipanti.firstWhere(
          (p) => p.trim().toLowerCase() == nickLower,
          orElse: () => nickLower,
        );
      }
    });

    // Fantasma: chi ha fatto meno azioni in assoluto (escluso chi ha vinto come campione)
    String? fantasmaNick;
    int minAzioni = 999999;
    if (_evento.partecipanti.length > 1) {
      for (var p in _evento.partecipanti) {
        final pLower = p.trim().toLowerCase();
        if (pLower == campioneNick.trim().toLowerCase()) continue;
        final azioni = azioniTotali[pLower] ?? 0;
        if (azioni < minAzioni) {
          minAzioni = azioni;
          fantasmaNick = p;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎖️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Titoli e Riconoscimenti Speciali',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 1. Campione
          _buildTitleCard(
            icon: '👑',
            title: 'Il Campione',
            subtitle: '1° Classificato ufficiale ($campionePts PT)',
            winnerNick: campioneNick,
            accentColor: const Color(0xFFFACC15),
          ),
          // 2. Re dei Malus
          if (reMalusNick != null && maxMalusVal > 0)
            _buildTitleCard(
              icon: '🤡',
              title: 'Il Re dei Malus',
              subtitle: 'Più malus collezionati (-$maxMalusVal PT)',
              winnerNick: reMalusNick,
              accentColor: const Color(0xFFEF4444),
            ),
          // 3. Giudice Supremo
          if (giudiceNick != null && maxAttivita > 0)
            _buildTitleCard(
              icon: '⚖️',
              title: 'Il Giudice Supremo',
              subtitle: 'Più attivo tra voti e proposte ($maxAttivita azioni)',
              winnerNick: giudiceNick,
              accentColor: const Color(0xFF38BDF8),
            ),
          // 4. Il Fantasma
          if (fantasmaNick != null)
            _buildTitleCard(
              icon: '👻',
              title: 'Il Fantasma',
              subtitle: 'Ha partecipato al minimo indispensabile ($minAzioni azioni)',
              winnerNick: fantasmaNick,
              accentColor: const Color(0xFF94A3B8),
            ),
        ],
      ),
    );
  }

  Widget _buildTitleCard({
    required String icon,
    required String title,
    required String subtitle,
    required String? winnerNick,
    required Color accentColor,
  }) {
    if (winnerNick == null || winnerNick.isEmpty) return const SizedBox.shrink();
    final avatarUrl = _apiService.getUtenteInMemoria(winnerNick)?.avatarUrl ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(icon, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _buildAvatarWidget(avatarUrl, winnerNick, radius: 12),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              winnerNick,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCondividiPodioButton(List<MapEntry<String, int>> sortedEntries) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ElevatedButton.icon(
        onPressed: () => _mostraModalCondividiPodio(sortedEntries),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF9333EA),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: const Color(0xFFFACC15).withValues(alpha: 0.5), width: 1.2),
          ),
          elevation: 4,
        ),
        icon: const Icon(Icons.share_rounded, color: Color(0xFFFACC15), size: 20),
        label: Text(
          'Condividi Podio Serata 📸',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  void _mostraModalCondividiPodio(List<MapEntry<String, int>> sortedEntries) {
    final primo = sortedEntries.isNotEmpty ? sortedEntries[0] : null;
    final secondo = sortedEntries.length > 1 ? sortedEntries[1] : null;
    final terzo = sortedEntries.length > 2 ? sortedEntries[2] : null;

    final buffer = StringBuffer();
    buffer.writeln('🏆 *PODIO FANTAEVENTI* - ${_evento.titolo} 🏆');
    buffer.writeln('');
    if (primo != null) buffer.writeln('🥇 1°: ${primo.key} (+${primo.value} PT)');
    if (secondo != null) buffer.writeln('🥈 2°: ${secondo.key} (+${secondo.value} PT)');
    if (terzo != null) buffer.writeln('🥉 3°: ${terzo.key} (+${terzo.value} PT)');
    buffer.writeln('');
    buffer.writeln('🎉 Complimenti a tutti i partecipanti di FantaEventi!');
    final String riepilogoTestuale = buffer.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.stars_rounded, color: Color(0xFFFACC15), size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'PODIO FINALE UFFICIALE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFFACC15),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _evento.titolo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),

              // Podio visuale
              if (primo != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Text('🥇', style: TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      _buildAvatarWidget(_apiService.getUtenteInMemoria(primo.key)?.avatarUrl ?? '', primo.key, radius: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          primo.key,
                          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Text(
                        '+${primo.value} PT',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (secondo != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF94A3B8).withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      const Text('🥈', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      _buildAvatarWidget(_apiService.getUtenteInMemoria(secondo.key)?.avatarUrl ?? '', secondo.key, radius: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          secondo.key,
                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Text(
                        '+${secondo.value} PT',
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (terzo != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFB45309).withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      const Text('🥉', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      _buildAvatarWidget(_apiService.getUtenteInMemoria(terzo.key)?.avatarUrl ?? '', terzo.key, radius: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          terzo.key,
                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Text(
                        '+${terzo.value} PT',
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFB45309)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Text(
                '📸 Fai uno screenshot di questa schermata per condividerla nelle tue storie Instagram o gruppi!',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: riepilogoTestuale));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        content: Text(
                          'Podio copiato negli appunti! 📋 Incollalo su WhatsApp o Instagram!',
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(
                    'COPIA RIEPILOGO TESTO 📲',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mostraModalCambiaCopertina() async {
    final List<Map<String, String>> copertinePredefinite = [
      {
        'label': '🎤 Concerto',
        'url': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=800&q=80',
      },
      {
        'label': '🍕 Cena',
        'url': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=800&q=80',
      },
      {
        'label': '🍾 Party',
        'url': 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=800&q=80',
      },
      {
        'label': '🪩 Club / DJ',
        'url': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=800&q=80',
      },
      {
        'label': '🏖️ Viaggio',
        'url': 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=80',
      },
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Modifica Foto Copertina Evento 📷',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Solo tu come organizzatore puoi aggiornare la foto dell\'evento.',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        final photo = await _picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 80,
                          maxWidth: 1080,
                          maxHeight: 1080,
                        );
                        if (photo != null) {
                          final bytes = await photo.readAsBytes();
                          final b64 = 'data:image/png;base64,${base64Encode(bytes)}';
                          setState(() {
                            _evento = _evento.copyWith(copertinaUrl: b64);
                          });
                          await _apiService.aggiornaCopertinaEvento(_evento.id, b64);
                          widget.onRefresh();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF10B981),
                                content: Text('Foto copertina aggiornata con successo! 📸',
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                            );
                          }
                        }
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.camera_alt_rounded, size: 18, color: Color(0xFF0F172A)),
                    label: const Text('SCATTA FOTO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        final photo = await _picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 80,
                          maxWidth: 1080,
                          maxHeight: 1080,
                        );
                        if (photo != null) {
                          final bytes = await photo.readAsBytes();
                          final b64 = 'data:image/png;base64,${base64Encode(bytes)}';
                          setState(() {
                            _evento = _evento.copyWith(copertinaUrl: b64);
                          });
                          await _apiService.aggiornaCopertinaEvento(_evento.id, b64);
                          widget.onRefresh();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF10B981),
                                content: Text('Foto copertina aggiornata con successo! 📸',
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                            );
                          }
                        }
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.photo_library_rounded, size: 18, color: Colors.white),
                    label: const Text('DALLA GALLERIA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9333EA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Oppure seleziona un tema predefinito:',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: copertinePredefinite.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (c, idx) {
                  final item = copertinePredefinite[idx];
                  return ActionChip(
                    label: Text(item['label']!),
                    labelStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    backgroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFF334155)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final newUrl = item['url']!;
                      setState(() {
                        _evento = _evento.copyWith(copertinaUrl: newUrl);
                      });
                      await _apiService.aggiornaCopertinaEvento(_evento.id, newUrl);
                      widget.onRefresh();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF10B981),
                            content: Text('Tema copertina applicato! ✨',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _mostraDettaglioStoricoGiocatore(String targetNick) {
    final curUser = _apiService.currentUser?.nome ?? 'Cloud';
    final creatore = _evento.propostoDa.isNotEmpty ? _evento.propostoDa : 'Cloud';
    final isEventoConcluso = _evento.stato.trim().toLowerCase() == 'concluso' || DateTime.now().isAfter(_evento.dataFine);
    final isOrganizzatore = !isEventoConcluso && (creatore.trim().toLowerCase() == curUser.trim().toLowerCase());

    final List<Map<String, dynamic>> istanzeAssegnazioni = [];
    for (var bm in _allBonusMalus) {
      final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
          bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
      if (isSameEv || _allBonusMalus.length == 1) {
        final count = bm.assegnatoA.where((u) => u.trim().toLowerCase() == targetNick.trim().toLowerCase()).length;
        for (int i = 0; i < count; i++) {
          istanzeAssegnazioni.add({
            'bonus': bm,
            'numIstanza': i + 1,
            'totaleIstanze': count,
          });
        }
      }
    }

    final memUser = _apiService.getUtenteInMemoria(targetNick);
    String avatarUrl = memUser?.avatarUrl ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            if (avatarUrl.isEmpty) {
              _apiService.getUtenti().then((utenti) {
                final found = utenti.firstWhere(
                  (u) => u.nome.trim().toLowerCase() == targetNick.trim().toLowerCase() || u.nickname.trim().toLowerCase() == targetNick.trim().toLowerCase(),
                  orElse: () => Utente(
                    id: '', nome: targetNick, email: '', avatarUrl: '', livello: 1, xp: 0, xpProssimoLivello: 1000,
                    puntiTotali: 0, badgeList: [], storicoVoti: [], codiceAmico: '', amici: [], richiesteAmicizia: [], badgeVincitore: [],
                  ),
                );
                if (found.avatarUrl.isNotEmpty && modalCtx.mounted) {
                  setModalState(() {
                    avatarUrl = found.avatarUrl;
                  });
                }
              }).catchError((_) {});
            }

            final Widget avatarWidget = _buildAvatarWidget(avatarUrl, targetNick);
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      avatarWidget,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Storico Bonus: $targetNick',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            Text(
                              isEventoConcluso
                                  ? 'Punteggi congelati per l\'evento "${_evento.titolo}"'
                                  : 'Bonus e Malus assegnati per "${_evento.titolo}"',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (istanzeAssegnazioni.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        'Nessun bonus o malus assegnato a $targetNick in questo evento.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: istanzeAssegnazioni.length,
                        itemBuilder: (context, idx) {
                          final item = istanzeAssegnazioni[idx];
                          final BonusMalus bm = item['bonus'];
                          final int numIstanza = item['numIstanza'];
                          final int totaleIstanze = item['totaleIstanze'];
                          final isBonus = bm.punti >= 0;
                          final ptStr = isBonus ? '+${bm.punti}' : '${bm.punti}';
                          final labelTitolo = totaleIstanze > 1
                              ? '${bm.titolo} (#$numIstanza)'
                              : bm.titolo;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isBonus ? Icons.add_circle : Icons.remove_circle,
                                  color: isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        labelTitolo,
                                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                      ),
                                      if (bm.descrizione.isNotEmpty)
                                        Text(
                                          bm.descrizione,
                                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$ptStr PT',
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                                  ),
                                ),
                                if (isOrganizzatore) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                    tooltip: 'Annulla Singola Assegnazione',
                                    onPressed: () async {
                                      final conf = await showDialog<bool>(
                                        context: context,
                                        builder: (dCtx) => AlertDialog(
                                          backgroundColor: const Color(0xFF1E293B),
                                          title: const Text('Annullare Assegnazione?', style: TextStyle(color: Colors.white)),
                                          content: Text('Vuoi stornare "$labelTitolo" da $targetNick?', style: const TextStyle(color: Color(0xFF94A3B8))),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('NO', style: TextStyle(color: Colors.white70))),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(dCtx, true),
                                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                              child: const Text('SÌ, STORNA', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (conf == true) {
                                        await _apiService.annullaAssegnazioneBonus(
                                          eventoId: _evento.id,
                                          bonusId: bm.id,
                                          utenteDestinatario: targetNick,
                                          punti: bm.punti,
                                        );
                                        Navigator.pop(ctx);
                                        _calcolaCoerenzaInvitiEVotazioni();
                                        widget.onRefresh();
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
