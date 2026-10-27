import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/live_pulse_badge.dart';
import '../widgets/animated_points_counter.dart';
import '../models/evento.dart';
import '../models/utente.dart';
import '../models/bonus_malus.dart';
import 'add_bonus_malus_view.dart';
import '../services/tutorial_controller.dart';
import '../widgets/tutorial_spotlight_overlay.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_toast.dart';
import '../widgets/context_info_modal.dart';
import '../viewmodels/event_detail_view_model.dart';

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
  late final EventDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = EventDetailViewModel(widget.evento);
    _viewModel.inizializza();
  }

  @override
  void dispose() {
    TutorialController.instance.rollbackFromEventDetail();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final _evento = _viewModel.evento;
        final _partecipantiConfermati = _viewModel.partecipantiConfermati;
        final _invitatiInSospeso = _viewModel.invitatiInSospeso;
        final isCreatore = _viewModel.isCreatore;
        final isConcluso = _viewModel.isConcluso;
        final giaPartecipa = _viewModel.giaPartecipa;

        final bool isTutorial = TutorialController.instance.stage == TutorialStage.step5_in_event_detail &&
            TutorialController.instance.isTutorialEvent(_evento);

        return PopScope(
      canPop: !isTutorial,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          TutorialController.instance.rollbackFromEventDetail();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
      body: CustomScrollView(
        slivers: [
          // Slivers AppBar con Copertina dell'Evento
          SliverAppBar(
            automaticallyImplyLeading: !isTutorial,
            expandedHeight: 240,
            pinned: true,
            backgroundColor: const Color(0xFF1E293B),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline_rounded, color: Color(0xFFFACC15), size: 24),
                tooltip: 'Guida Dettagli Evento',
                onPressed: () => ContextInfoModal.mostra(context, tipo: ContextInfoType.dettaglioEvento),
              ),
            ],
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
                      right: 62,
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
                  if (TutorialController.instance.stage == TutorialStage.step5_in_event_detail &&
                      TutorialController.instance.isTutorialEvent(_evento))
                    TutorialStepBanner(
                      stepTag: 'Tappa 2 di 4 • Dettaglio Evento',
                      title: 'Proponi la prima Regola di Gioco!',
                      description: 'Scorri fino in fondo a questa pagina e tocca "PROPONI BONUS" per proporre una regola per questa serata!',
                      onSkip: () {
                        TutorialController.instance.skipTutorial();
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
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
                          color: _evento.isAnnullato
                              ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                              : (_evento.isConcluso
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                                  : (_evento.isInCorso
                                      ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                                      : const Color(0xFF9333EA).withValues(alpha: 0.2))),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _evento.isAnnullato
                                ? const Color(0xFFEF4444)
                                : (_evento.isConcluso
                                    ? const Color(0xFFEF4444)
                                    : (_evento.isInCorso
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFF9333EA))),
                          ),
                        ),
                        child: Text(
                          _evento.isAnnullato
                              ? 'ANNULLATO'
                              : (_evento.isConcluso
                                  ? 'CONCLUSO'
                                  : (_evento.isInCorso ? 'IN CORSO' : 'IN PROGRAMMA')),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _evento.isAnnullato || _evento.isConcluso
                                ? const Color(0xFFF87171)
                                : (_evento.isInCorso ? const Color(0xFF22C55E) : const Color(0xFFC084FC)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_evento.isAnnullato) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Evento Annullato Automaticamente',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFF87171),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'L\'orario di inizio è scattato senza altri partecipanti confermati oltre all\'organizzatore. L\'evento non è partito e non sono stati assegnati XP.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                      InkWell(
                        onTap: _evento.luogo.isNotEmpty ? () => _apriModalPortamiLa(_evento) : null,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: (_evento.latitudine != null && _evento.longitudine != null)
                                  ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                  : const Color(0xFF334155),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.place_rounded, color: Color(0xFFC084FC), size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('Location / Luogo', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11)),
                                        if (_evento.latitudine != null && _evento.longitudine != null) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF065F46).withValues(alpha: 0.5),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'GPS MAPPA',
                                              style: GoogleFonts.inter(color: const Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _evento.luogo.isNotEmpty ? _evento.luogo : 'Non specificata',
                                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (_evento.luogo.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _apriModalPortamiLa(_evento),
                                  icon: const Icon(Icons.navigation_rounded, size: 14, color: Color(0xFF0F172A)),
                                  label: Text(
                                    'PORTAMI LÀ',
                                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFACC15),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SEZIONE CLASSIFICA DINAMICA LIVE EVENTO
                  _buildLeaderboardSection(),
                  const SizedBox(height: 24),

                  // SEZIONE QUORUM VOTAZIONI DINAMICO IN TEMPO REALE
                  _buildQuorumLiveCard(),
                  const SizedBox(height: 28),

                  // SEZIONE TRACCIAMENTO STATO INVITI PARTECIPANTI (Coerenza Rigorosa)
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
                      if (isCreatore && _evento.isInProgramma)
                        InkWell(
                          onTap: _mostraModalInvitaAmici,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFACC15), width: 1.2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_add_alt_1_rounded, size: 14, color: Color(0xFFFACC15)),
                                const SizedBox(width: 5),
                                Text(
                                  'INVITA AMICI',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFFACC15),
                                  ),
                                ),
                              ],
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
                        if (_invitatiInSospeso.isEmpty)
                          Text(
                            'Nessun invito in sospeso al momento.',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                          )
                        else
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

                        if (isCreatore && _evento.isInProgramma) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _mostraModalInvitaAmici,
                              icon: const Icon(Icons.group_add_rounded, size: 16, color: Color(0xFFFACC15)),
                              label: Text(
                                'Aggiungi altri amici all\'evento',
                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: const Color(0xFFFACC15).withValues(alpha: 0.6), width: 1.2),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottoni d'Azione
                  Row(
                    children: [
                      if (!giaPartecipa)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_evento.isConcluso || _evento.isInCorso || _evento.isAnnullato)
                                ? null
                                : () async {
                                    try {
                                      final wasInvited = _invitatiInSospeso.contains(_viewModel.currentUserNick);
                                      await _viewModel.partecipaAdEvento();
                                      widget.onRefresh();
                                      if (!mounted) return;
                                      AppToast.showSuccess(
                                        context,
                                        wasInvited ? 'Invito accettato! 🎉' : 'Iscrizione completata! 🎉',
                                        wasInvited
                                            ? 'Hai accettato l\'invito a "${_evento.titolo}".'
                                            : 'Ti sei iscritto a "${_evento.titolo}".',
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      AppToast.showError(
                                        context,
                                        'Errore iscrizione',
                                        e.toString().replaceAll('Exception: ', ''),
                                      );
                                    }
                                  },
                            icon: Icon(
                              _evento.isAnnullato
                                  ? Icons.cancel_outlined
                                  : (_evento.isConcluso
                                      ? Icons.flag_rounded
                                      : _evento.isInCorso
                                          ? Icons.lock_clock_rounded
                                          : (_invitatiInSospeso.contains(_viewModel.currentUserNick)
                                              ? Icons.check_circle_rounded
                                              : Icons.person_add)),
                              color: (_evento.isAnnullato || _evento.isConcluso || _evento.isInCorso)
                                  ? const Color(0xFF64748B)
                                  : (_invitatiInSospeso.contains(_viewModel.currentUserNick)
                                      ? Colors.white
                                      : const Color(0xFF0F172A)),
                            ),
                            label: Text(
                              _evento.isAnnullato
                                  ? 'EVENTO ANNULLATO'
                                  : (_evento.isConcluso
                                      ? 'EVENTO CONCLUSO'
                                      : _evento.isInCorso
                                          ? 'ISCRIZIONI CHIUSE'
                                          : (_invitatiInSospeso.contains(_viewModel.currentUserNick)
                                              ? 'ACCETTA INVITO'
                                              : 'PARTECIPA')),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (_evento.isAnnullato || _evento.isConcluso || _evento.isInCorso)
                                  ? const Color(0xFF334155)
                                  : (_invitatiInSospeso.contains(_viewModel.currentUserNick)
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFFACC15)),
                              foregroundColor: (_evento.isAnnullato || _evento.isConcluso || _evento.isInCorso)
                                  ? const Color(0xFF64748B)
                                  : (_invitatiInSospeso.contains(_viewModel.currentUserNick)
                                      ? Colors.white
                                      : const Color(0xFF0F172A)),
                              disabledBackgroundColor: const Color(0xFF334155),
                              disabledForegroundColor: const Color(0xFF64748B),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      if (!giaPartecipa && (giaPartecipa || isCreatore)) const SizedBox(width: 12),

                      if ((giaPartecipa || isCreatore) && !_evento.isAnnullato && _evento.stato.trim().toLowerCase() != 'concluso' && !DateTime.now().isAfter(_evento.dataFine))
                        Expanded(
                          child: ElevatedButton.icon(
                            key: TutorialController.instance.isTutorialEvent(_evento) ? TutorialController.instance.keyProponiBonus : null,
                            onPressed: () async {
                              if (TutorialController.instance.stage == TutorialStage.step5_in_event_detail &&
                                  TutorialController.instance.isTutorialEvent(_evento)) {
                                TutorialController.instance.setStage(TutorialStage.step6_in_add_bonus);
                              }
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => AddBonusMalusView(evento: _evento)),
                              );
                              widget.onRefresh();
                              if (TutorialController.instance.stage == TutorialStage.step7_view_votazioni && mounted) {
                                Navigator.pop(context);
                              }
                            },
                            icon: const Icon(Icons.stars, color: Colors.white),
                            label: const Text('PROPONI BONUS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9333EA),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: (TutorialController.instance.stage == TutorialStage.step5_in_event_detail &&
                                        TutorialController.instance.isTutorialEvent(_evento))
                                    ? const BorderSide(color: Color(0xFFFACC15), width: 2)
                                    : BorderSide.none,
                              ),
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
    ),
  );
      },
    );
  }

  Widget _buildQuorumLiveCard() {
    final int totalePartecipanti = _viewModel.totalePartecipanti;
    final int quorumCalcolato = _viewModel.quorumCalcolato;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.15),
            const Color(0xFF1E293B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF818CF8)),
                ),
                child: const Icon(Icons.how_to_vote_rounded, color: Color(0xFFFACC15), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUORUM VOTAZIONI LIVE',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF818CF8),
                        letterSpacing: 0.8,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Maggioranza Assoluta Evento',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_viewModel.isSyncing) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF818CF8)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => ContextInfoModal.mostra(context, tipo: ContextInfoType.dettaglioEvento),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFFACC15), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Info Regole',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFACC15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$quorumCalcolato',
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFACC15),
                ),
              ),
              Text(
                ' su $totalePartecipanti',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'partecipanti',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            totalePartecipanti <= 1
                ? 'Con 1 solo partecipante, le proposte si convalidano con il tuo voto.'
                : 'Per approvare o respingere un bonus servono almeno $quorumCalcolato voti concordi. La soglia si ricalcola in tempo reale all\'ingresso di nuovi partecipanti!',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFFCBD5E1),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardSection() {
    final now = DateTime.now();
    final _evento = _viewModel.evento;
    final sortedEntries = _viewModel.getSortedLeaderboardEntries();

    final isAnnullato = _evento.isAnnullato;
    final isConcluso = !isAnnullato && (_evento.stato.trim().toLowerCase() == 'concluso' || now.isAfter(_evento.dataFine));
    final isInCorso = !isAnnullato && !isConcluso && (now.isAfter(_evento.data) || _evento.stato.trim().toLowerCase() == 'in_corso');
    final isInProgramma = !isAnnullato && !isConcluso && !isInCorso;

    String headerTitle = '🏆 Classifica Live Evento';
    String tagText = '🔴 LIVE';
    Color tagColor = const Color(0xFF9333EA);

    if (isAnnullato) {
      headerTitle = '❌ Classifica Evento (Annullato)';
      tagText = 'ANNULLATO';
      tagColor = const Color(0xFFEF4444);
    } else if (isConcluso) {
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
            if (_viewModel.isSyncing)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF818CF8)),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Sincronizzazione...',
                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                    ),
                  ],
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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            children: [
              if (_viewModel.isSyncing)
                const LinearProgressIndicator(
                  minHeight: 2.5,
                  backgroundColor: Color(0xFF1E293B),
                  color: Color(0xFF6366F1),
                ),
              if (sortedEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_outlined, color: Color(0xFF64748B), size: 32),
                        const SizedBox(height: 8),
                        Text(
                          'Nessun punteggio ancora assegnato',
                          style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...List.generate(sortedEntries.length, (idx) {
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
                      _buildAvatarWidget(_viewModel.getAvatarPerUtente(nick), nick, radius: 16),
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
          ],
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
    String effectiveUrl = avatarUrl.trim();
    if (effectiveUrl.isEmpty) {
      effectiveUrl = _viewModel.getAvatarPerUtente(nickname);
    }
    if (effectiveUrl.isNotEmpty) {
      final imgProvider = getAvatarImageProvider(effectiveUrl);
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF9333EA),
        backgroundImage: imgProvider,
      );
    }
    final initial = nickname.trim().isNotEmpty ? nickname.trim()[0].toUpperCase() : 'U';
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF9333EA),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }

  Widget _buildSpecialTitlesSection(List<MapEntry<String, int>> sortedEntries) {
    if (sortedEntries.isEmpty) return const SizedBox.shrink();

    final titoli = _viewModel.calcolaTitoli(sortedEntries);
    final campioneNick = titoli.campioneNick;
    final campionePts = titoli.campionePts;
    final reMalusNick = titoli.reMalusNick;
    final maxMalusVal = titoli.maxMalusVal;
    final giudiceNick = titoli.giudiceNick;
    final maxAttivita = titoli.maxAttivita;
    final fantasmaNick = titoli.fantasmaNick;
    final minAzioni = titoli.minAzioni;
    final sbirroNick = titoli.sbirroNick;
    final maxSbirroVal = titoli.maxSbirroVal;
    final giustiziereNick = titoli.giustiziereNick;
    final maxGiustiziereVal = titoli.maxGiustiziereVal;

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
          // 3. L'Avvocato
          if (giudiceNick != null && maxAttivita > 0)
            _buildTitleCard(
              icon: '⚖️',
              title: "L'Avvocato",
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
          // 5. Lo Sbirro
          if (sbirroNick != null && maxSbirroVal > 0)
            _buildTitleCard(
              icon: '🕵️',
              title: 'Lo Sbirro',
              subtitle: 'Più denunce di malus convalidate al VAR ($maxSbirroVal denunce)',
              winnerNick: sbirroNick,
              accentColor: const Color(0xFFF97316),
            ),
          // 6. Il Giustiziere
          if (giustiziereNick != null && maxGiustiziereVal > 0)
            _buildTitleCard(
              icon: '⚡',
              title: 'Il Giustiziere',
              subtitle: 'Più chiamate VAR convalidate e approvate ($maxGiustiziereVal approvate)',
              winnerNick: giustiziereNick,
              accentColor: const Color(0xFF10B981),
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
    final avatarUrl = _viewModel.getAvatarPerUtente(winnerNick);

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

  Widget _buildCompactChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15))),
          const SizedBox(width: 4),
          Text(value, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  void _mostraModalCondividiPodio(List<MapEntry<String, int>> sortedEntries) {
    final primo = sortedEntries.isNotEmpty ? sortedEntries[0] : null;
    final secondo = sortedEntries.length > 1 ? sortedEntries[1] : null;
    final terzo = sortedEntries.length > 2 ? sortedEntries[2] : null;
    final _evento = _viewModel.evento;

    final titoli = _viewModel.calcolaTitoli(sortedEntries);
    final campioneNick = titoli.campioneNick;
    final campionePts = titoli.campionePts;
    final reMalusNick = titoli.reMalusNick;
    final maxMalusVal = titoli.maxMalusVal;
    final giudiceNick = titoli.giudiceNick;
    final maxAttivita = titoli.maxAttivita;
    final fantasmaNick = titoli.fantasmaNick;
    final minAzioni = titoli.minAzioni;
    final sbirroNick = titoli.sbirroNick;
    final maxSbirroVal = titoli.maxSbirroVal;
    final giustiziereNick = titoli.giustiziereNick;
    final maxGiustiziereVal = titoli.maxGiustiziereVal;

    final buffer = StringBuffer();
    buffer.writeln('🏆 *PODIO FANTAEVENTI* - ${_evento.titolo} 🏆');
    buffer.writeln('');
    if (primo != null) buffer.writeln('🥇 1°: ${primo.key} (${primo.value > 0 ? '+${primo.value}' : '${primo.value}'} PT)');
    if (secondo != null) buffer.writeln('🥈 2°: ${secondo.key} (${secondo.value > 0 ? '+${secondo.value}' : '${secondo.value}'} PT)');
    if (terzo != null) buffer.writeln('🥉 3°: ${terzo.key} (${terzo.value > 0 ? '+${terzo.value}' : '${terzo.value}'} PT)');
    if (campioneNick != null || reMalusNick != null || giudiceNick != null || fantasmaNick != null) {
      buffer.writeln('');
      buffer.writeln('🎖️ *RICONOSCIMENTI SPECIALI*:');
      if (campioneNick != null) buffer.writeln('👑 Il Campione: $campioneNick ($campionePts PT)');
      if (reMalusNick != null && maxMalusVal > 0) buffer.writeln('🤡 Re dei Malus: $reMalusNick (-$maxMalusVal PT)');
      if (giudiceNick != null && maxAttivita > 0) buffer.writeln("⚖️ L'Avvocato: $giudiceNick ($maxAttivita azioni)");
      if (fantasmaNick != null) buffer.writeln('👻 Il Fantasma: $fantasmaNick ($minAzioni azioni)');
      if (sbirroNick != null && maxSbirroVal > 0) buffer.writeln('🕵️ Lo Sbirro: $sbirroNick ($maxSbirroVal denunce)');
      if (giustiziereNick != null && maxGiustiziereVal > 0) buffer.writeln('⚡ Il Giustiziere: $giustiziereNick ($maxGiustiziereVal approvate)');
    }
    buffer.writeln('');
    buffer.writeln('🎉 Complimenti a tutti i partecipanti di FantaEventi!');
    final String riepilogoTestuale = buffer.toString();

    final GlobalKey shareCardKey = GlobalKey();
    bool isSharing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Container(
            margin: const EdgeInsets.only(top: 24, left: 14, right: 14, bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF334155), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 25,
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
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF64748B),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.share_rounded, color: Color(0xFFFACC15), size: 22),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'CONDIVIDI CON GLI AMICI',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pubblica la grafica ufficiale su Instagram o inviala su WhatsApp',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // SCHEDA GRAFICA CATTURABILE PER LA CONDIVISIONE
                  RepaintBoundary(
                    key: shareCardKey,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E293B), Color(0xFF0B1120)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.6), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // BANNER FOTOGRAFICO DELL'EVENTO CON TITOLO OVERLAY
                          Container(
                            height: 120,
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.4), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image(
                                    image: getEventCoverImageProvider(_evento.copertinaUrl),
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, stack) => Container(
                                      color: const Color(0xFF1E293B),
                                      child: const Center(
                                        child: Icon(Icons.celebration_rounded, size: 48, color: Color(0xFFFACC15)),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.3),
                                          const Color(0xFF0F172A).withValues(alpha: 0.92),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    left: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: const Color(0xFFFACC15), width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 14),
                                          const SizedBox(width: 5),
                                          Text(
                                            'PODIO FINALE',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFFFACC15),
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 10,
                                    left: 12,
                                    right: 12,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _evento.titolo,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            shadows: [
                                              const Shadow(color: Colors.black, blurRadius: 8),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            if (_evento.luogo.isNotEmpty) ...[
                                              const Icon(Icons.place_rounded, color: Color(0xFFFACC15), size: 12),
                                              const SizedBox(width: 3),
                                              Flexible(
                                                child: Text(
                                                  _evento.luogo,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(0xFFCBD5E1),
                                                    shadows: [const Shadow(color: Colors.black, blurRadius: 4)],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              const Text('•', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                              const SizedBox(width: 6),
                                            ],
                                            Text(
                                              '${_evento.data.day}/${_evento.data.month}/${_evento.data.year}',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF94A3B8),
                                                shadows: [const Shadow(color: Colors.black, blurRadius: 4)],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 1° Classificato
                          if (primo != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  const Text('🥇', style: TextStyle(fontSize: 24)),
                                  const SizedBox(width: 10),
                                  _buildAvatarWidget(_viewModel.getAvatarPerUtente(primo.key), primo.key, radius: 16),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      primo.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  Text(
                                    '${primo.value > 0 ? "+${primo.value}" : "${primo.value}"} PT',
                                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          // 2° Classificato
                          if (secondo != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF94A3B8).withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                children: [
                                  const Text('🥈', style: TextStyle(fontSize: 20)),
                                  const SizedBox(width: 10),
                                  _buildAvatarWidget(_viewModel.getAvatarPerUtente(secondo.key), secondo.key, radius: 14),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      secondo.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  Text(
                                    '${secondo.value > 0 ? "+${secondo.value}" : "${secondo.value}"} PT',
                                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          // 3° Classificato
                          if (terzo != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFB45309).withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                children: [
                                  const Text('🥉', style: TextStyle(fontSize: 20)),
                                  const SizedBox(width: 10),
                                  _buildAvatarWidget(_viewModel.getAvatarPerUtente(terzo.key), terzo.key, radius: 14),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      terzo.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  Text(
                                    '${terzo.value > 0 ? "+${terzo.value}" : "${terzo.value}"} PT',
                                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFB45309)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Titoli speciali se presenti
                          if (campioneNick != null || reMalusNick != null || giudiceNick != null || fantasmaNick != null || (sbirroNick != null && maxSbirroVal > 0) || (giustiziereNick != null && maxGiustiziereVal > 0)) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (campioneNick != null)
                                    _buildCompactChip('👑 Campione', campioneNick),
                                  if (reMalusNick != null && maxMalusVal > 0)
                                    _buildCompactChip('🤡 Re Malus', reMalusNick),
                                  if (giudiceNick != null && maxAttivita > 0)
                                    _buildCompactChip("⚖️ L'Avvocato", giudiceNick),
                                  if (fantasmaNick != null)
                                    _buildCompactChip('👻 Fantasma', fantasmaNick),
                                  if (sbirroNick != null && maxSbirroVal > 0)
                                    _buildCompactChip('🕵️ Lo Sbirro', sbirroNick),
                                  if (giustiziereNick != null && maxGiustiziereVal > 0)
                                    _buildCompactChip('⚡ Giustiziere', giustiziereNick),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Watermark brand
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                padding: const EdgeInsets.all(1),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Color(0xFFFACC15), Color(0xFF9333EA)],
                                  ),
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/icon/app_icon.jpg',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'FantaEventi App',
                                style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // PULSANTE CONDIVIDI FOTO REALE CON TENDINA DI SISTEMA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isSharing
                          ? null
                          : () async {
                              setModalState(() => isSharing = true);
                              try {
                                await Future.delayed(const Duration(milliseconds: 100));
                                final boundary = shareCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                                if (boundary != null) {
                                  final image = await boundary.toImage(pixelRatio: 3.0);
                                  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                                  if (byteData != null) {
                                    final pngBytes = byteData.buffer.asUint8List();
                                    final tempDir = await getTemporaryDirectory();
                                    final cleanTitle = _evento.titolo.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
                                    final filePath = '${tempDir.path}/podio_$cleanTitle.png';
                                    final file = File(filePath);
                                    await file.writeAsBytes(pngBytes);

                                    final box = context.findRenderObject() as RenderBox?;
                                    final sharePositionOrigin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

                                    await Share.shareXFiles(
                                      [XFile(file.path, mimeType: 'image/png')],
                                      text: '🏆 Podio e Riconoscimenti Ufficiali di "${_evento.titolo}" su FantaEventi! 🎉',
                                      sharePositionOrigin: sharePositionOrigin,
                                    );
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  AppToast.showError(
                                    context,
                                    'Errore Condivisione',
                                    e.toString().replaceAll('Exception: ', ''),
                                  );
                                }
                              } finally {
                                setModalState(() => isSharing = false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9333EA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: const Color(0xFFFACC15).withValues(alpha: 0.6), width: 1.2),
                        ),
                        elevation: 4,
                      ),
                      icon: isSharing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.share_rounded, color: Color(0xFFFACC15), size: 20),
                      label: Text(
                        isSharing ? 'GENERAZIONE IMMAGINE...' : 'CONDIVIDI FOTO (STORIE / STATO) 🚀',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // PULSANTE COPIA TESTO RIEPILOGO
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: riepilogoTestuale));
                        Navigator.pop(ctx);
                        AppToast.showSuccess(
                          context,
                          'Podio Copiato 📋',
                          'Incollalo su WhatsApp o Instagram!',
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFACC15),
                        side: BorderSide(color: const Color(0xFFFACC15).withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text(
                        'COPIA RIEPILOGO TESTO 📲',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
                        final b64 = await _viewModel.scattaFotoCopertina();
                        if (b64 != null) {
                          widget.onRefresh();
                          if (mounted) {
                            AppToast.showSuccess(
                              context,
                              'Foto Copertina Aggiornata 📸',
                              'La foto copertina è stata salvata con successo!',
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
                        final b64 = await _viewModel.selezionaFotoCopertinaDaGalleria();
                        if (b64 != null) {
                          widget.onRefresh();
                          if (mounted) {
                            AppToast.showSuccess(
                              context,
                              'Foto Copertina Aggiornata 📸',
                              'La foto copertina dalla galleria è stata salvata!',
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
                      await _viewModel.aggiornaCopertina(newUrl);
                      widget.onRefresh();
                      if (mounted) {
                        AppToast.showSuccess(
                          context,
                          'Tema Copertina Applicato ✨',
                          'Nuovo tema impostato con successo!',
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
    final _evento = _viewModel.evento;
    final curUser = _viewModel.currentUserNick;
    final creatore = _viewModel.creatore;
    final isEventoConcluso = _viewModel.isAnnullato || _viewModel.isConcluso || DateTime.now().isAfter(_evento.dataFine);
    final isOrganizzatore = !isEventoConcluso && (creatore.trim().toLowerCase() == curUser.trim().toLowerCase());

    final istanzeAssegnazioni = _viewModel.getIstanzeAssegnazioniGiocatore(targetNick);

    final memUser = _viewModel.getUtenteInMemoria(targetNick);
    String avatarUrl = memUser?.avatarUrl ?? _viewModel.getAvatarPerUtente(targetNick);

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
              _viewModel.fetchUtenti().then((utenti) {
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
                          final bool isVar = item['isVar'] == true;
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
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Text(
                                            labelTitolo,
                                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                          ),
                                          if (isVar)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                                ),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFC084FC).withValues(alpha: 0.5)),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Text('📺', style: TextStyle(fontSize: 10)),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    'ASSEGNATO TRAMITE VAR',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 8.5,
                                                      fontWeight: FontWeight.w800,
                                                      letterSpacing: 0.3,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
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
                                if (isOrganizzatore && !isVar && bm.categoria != 'VAR' && !bm.titolo.contains('VAR') && !bm.titolo.contains('Falsa Testimonianza')) ...[
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
                                        await _viewModel.annullaAssegnazioneBonus(
                                          bonusId: bm.id,
                                          utenteDestinatario: targetNick,
                                          punti: bm.punti,
                                        );
                                        Navigator.pop(ctx);
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

  Future<void> _mostraModalInvitaAmici() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFACC15)),
      ),
    );

    final _evento = _viewModel.evento;
    final _partecipantiConfermati = _viewModel.partecipantiConfermati;
    final _invitatiInSospeso = _viewModel.invitatiInSospeso;
    List<Utente> amici;
    try {
      amici = await _viewModel.getGiocatoriInvitabili();
    } catch (_) {
      amici = [];
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (amici.isEmpty) {
      AppToast.showWarning(
        context,
        'Nessun Amico',
        'Non hai ancora aggiunto amici sul tuo profilo!',
      );
      return;
    }

    final Set<String> amiciSelezionati = {};
    String searchQuery = '';
    bool isInvioInCorso = false;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final cleanQuery = searchQuery.trim().toLowerCase();
            final amiciFiltrati = amici.where((u) {
              if (cleanQuery.isEmpty) return true;
              final nick = (u.nickname.isNotEmpty ? u.nickname : u.nome).toLowerCase();
              final email = u.email.toLowerCase();
              return nick.contains(cleanQuery) || email.contains(cleanQuery);
            }).toList();

            final invitabiliCount = amici.where((amico) {
              final aNick = (amico.nickname.isNotEmpty ? amico.nickname : amico.nome).trim().toLowerCase();
              final aNome = amico.nome.trim().toLowerCase();
              final isGiaPart = _partecipantiConfermati.any((p) {
                final pLow = p.trim().toLowerCase();
                return pLow == aNick || pLow == aNome || (aNick == 'cloud' && pLow == 'claudio');
              }) || _evento.propostoDa.trim().toLowerCase() == aNick || _evento.propostoDa.trim().toLowerCase() == aNome;
              final isGiaInv = _invitatiInSospeso.any((i) {
                final iLow = i.trim().toLowerCase();
                return iLow == aNick || iLow == aNome;
              }) || _evento.invitati.any((i) => i.trim().toLowerCase() == aNick || i.trim().toLowerCase() == aNome);
              return !isGiaPart && !isGiaInv;
            }).length;

            return Container(
              height: MediaQuery.of(context).size.height * 0.82,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: const Color(0xFF334155), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFACC15)),
                        ),
                        child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFFACC15), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Invita Amici all\'Evento',
                              style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              invitabiliCount > 0
                                  ? '$invitabiliCount amici disponibili per l\'invito'
                                  : 'Tutti i tuoi amici sono già stati invitati!',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: invitabiliCount > 0 ? const Color(0xFF94A3B8) : const Color(0xFF10B981),
                                fontWeight: invitabiliCount > 0 ? FontWeight.normal : FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val;
                      });
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Cerca per nickname o email...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFACC15), size: 20),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFFACC15), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Expanded(
                    child: amiciFiltrati.isEmpty
                        ? Center(
                            child: Text(
                              'Nessun amico trovato con questo nome.',
                              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: amiciFiltrati.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final amico = amiciFiltrati[idx];
                              final aEffectiveNick = amico.nickname.isNotEmpty ? amico.nickname : amico.nome;
                              final aNorm = aEffectiveNick.trim().toLowerCase();
                              final aNomeNorm = amico.nome.trim().toLowerCase();

                              final bool isGiaPartecipante = _partecipantiConfermati.any((p) {
                                final pLow = p.trim().toLowerCase();
                                return pLow == aNorm || pLow == aNomeNorm || (aNorm == 'cloud' && pLow == 'claudio');
                              }) || _evento.propostoDa.trim().toLowerCase() == aNorm || _evento.propostoDa.trim().toLowerCase() == aNomeNorm;
                              final bool isGiaInvitato = _invitatiInSospeso.any((i) {
                                final iLow = i.trim().toLowerCase();
                                return iLow == aNorm || iLow == aNomeNorm;
                              }) || _evento.invitati.any((i) => i.trim().toLowerCase() == aNorm || i.trim().toLowerCase() == aNomeNorm);
                              final bool isInvitabile = !isGiaPartecipante && !isGiaInvitato;
                              final bool isSelected = amiciSelezionati.contains(aEffectiveNick);

                              return InkWell(
                                onTap: isInvitabile
                                    ? () {
                                        setModalState(() {
                                          if (isSelected) {
                                            amiciSelezionati.remove(aEffectiveNick);
                                          } else {
                                            amiciSelezionati.add(aEffectiveNick);
                                          }
                                        });
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFFACC15).withValues(alpha: 0.12)
                                        : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFFACC15)
                                          : isGiaPartecipante
                                              ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                              : isGiaInvitato
                                                  ? const Color(0xFFEAB308).withValues(alpha: 0.3)
                                                  : const Color(0xFF334155),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: const Color(0xFF334155),
                                        backgroundImage: getAvatarImageProvider(amico.avatarUrl.isNotEmpty ? amico.avatarUrl : _viewModel.getAvatarPerUtente(aEffectiveNick)),
                                      ),
                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              aEffectiveNick,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            if (isGiaPartecipante)
                                              Row(
                                                children: [
                                                  const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Già partecipante confermato',
                                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF10B981), fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              )
                                            else if (isGiaInvitato)
                                              Row(
                                                children: [
                                                  const Icon(Icons.hourglass_top_rounded, size: 13, color: Color(0xFFFACC15)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Invito già inviato (in sospeso)',
                                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFFACC15), fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              )
                                            else
                                              Text(
                                                amico.email.isNotEmpty ? amico.email : 'Amico disponibile per l\'invito',
                                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                              ),
                                          ],
                                        ),
                                      ),

                                      if (isGiaPartecipante)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFF10B981)),
                                          ),
                                          child: Text(
                                            'PARTECIPA',
                                            style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                                          ),
                                        )
                                      else if (isGiaInvitato)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFFACC15)),
                                          ),
                                          child: Text(
                                            'IN SOSPESO',
                                            style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                                          ),
                                        )
                                      else
                                        Icon(
                                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          color: isSelected ? const Color(0xFFFACC15) : const Color(0xFF64748B),
                                          size: 24,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (amiciSelezionati.isEmpty || isInvioInCorso)
                          ? null
                          : () async {
                              setModalState(() => isInvioInCorso = true);
                              try {
                                final daInvitare = amiciSelezionati.toList();
                                await _viewModel.invitaAmiciAdEvento(daInvitare);
                                widget.onRefresh();

                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  AppToast.showSuccess(
                                    context,
                                    'Inviti inviati con successo! ✉️🎉',
                                    'Inviati a ${daInvitare.length} ${daInvitare.length == 1 ? 'amico' : 'amici'}.',
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isInvioInCorso = false);
                                if (context.mounted) {
                                  AppToast.showError(
                                    context,
                                    'Errore invio inviti',
                                    e.toString().replaceAll('Exception: ', ''),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFACC15),
                        foregroundColor: const Color(0xFF0F172A),
                        disabledBackgroundColor: const Color(0xFF334155),
                        disabledForegroundColor: const Color(0xFF64748B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                      ),
                      child: isInvioInCorso
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0F172A)),
                            )
                          : Text(
                              amiciSelezionati.isEmpty
                                  ? 'SELEZIONA GLI AMICI DA INVITARE'
                                  : 'INVIA INVITI (${amiciSelezionati.length}) 🚀',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
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

  Future<void> _lanciaNavigatore(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (_) {}
    }
  }

  void _apriModalPortamiLa(Evento ev) {
    final hasGps = ev.latitudine != null && ev.longitudine != null;
    final String destinationQuery = hasGps
        ? '${ev.latitudine},${ev.longitudine}'
        : Uri.encodeComponent(ev.luogo.trim());

    final String googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$destinationQuery';
    final String appleMapsUrl = 'https://maps.apple.com/?daddr=$destinationQuery';
    final String wazeUrl = hasGps
        ? 'https://waze.com/ul?ll=${ev.latitudine},${ev.longitudine}&navigate=yes'
        : 'https://waze.com/ul?q=$destinationQuery&navigate=yes';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.navigation_rounded, color: Color(0xFFFACC15), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Portami là 🧭',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Scegli il tuo navigatore preferito',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Destinazione Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.place_rounded, color: Color(0xFFFACC15), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Destinazione:',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                            ),
                            Text(
                              ev.luogo,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasGps)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'Coordinate GPS: ${ev.latitudine!.toStringAsFixed(4)}, ${ev.longitudine!.toStringAsFixed(4)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: const Color(0xFF10B981),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copia Indirizzo',
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFF94A3B8), size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: ev.luogo));
                          Navigator.pop(ctx);
                          AppToast.showSuccess(
                            context,
                            'Indirizzo Copiato 📋',
                            'L\'indirizzo è stato copiato negli appunti.',
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Opzione 1: Google Maps
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  tileColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFF334155)),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.map_rounded, color: Color(0xFF4285F4), size: 22),
                  ),
                  title: Text(
                    'Google Maps',
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Indicazioni stradali in tempo reale',
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 14),
                  onTap: () {
                    Navigator.pop(ctx);
                    _lanciaNavigatore(googleMapsUrl);
                  },
                ),
                const SizedBox(height: 10),

                // Opzione 2: Apple Maps
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  tileColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFF334155)),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.apple_rounded, color: Colors.white, size: 22),
                  ),
                  title: Text(
                    'Apple Maps',
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Mappe native per dispositivi iOS',
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 14),
                  onTap: () {
                    Navigator.pop(ctx);
                    _lanciaNavigatore(appleMapsUrl);
                  },
                ),
                const SizedBox(height: 10),

                // Opzione 3: Waze
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  tileColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFF334155)),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF33CCFF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.directions_car_rounded, color: Color(0xFF33CCFF), size: 22),
                  ),
                  title: Text(
                    'Waze',
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Traffico, autovelox e navigazione',
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 14),
                  onTap: () {
                    Navigator.pop(ctx);
                    _lanciaNavigatore(wazeUrl);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}
