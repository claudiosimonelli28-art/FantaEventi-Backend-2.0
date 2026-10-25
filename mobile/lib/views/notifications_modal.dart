import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'var_decision_modal.dart';
import 'var_witness_modal.dart';
import '../services/tutorial_controller.dart';
import '../widgets/tutorial_spotlight_overlay.dart';
import '../widgets/app_toast.dart';

class NotificationsModal extends StatefulWidget {
  final VoidCallback onRefreshHome;
  final void Function(int tabIndex)? onNavigateTab;
  const NotificationsModal({super.key, required this.onRefreshHome, this.onNavigateTab});

  @override
  State<NotificationsModal> createState() => _NotificationsModalState();
}

class _NotificationsModalState extends State<NotificationsModal> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _notifiche = [];
  bool _isLoading = true;
  String? _respondingNotificaId;
  String? _respondingAction;

  // Gestione Sezioni: 0 = Da Leggere, 1 = Già Lette
  int _selectedTabIndex = 0;

  // Gestione Selezione Multipla (Stile Gmail)
  bool _isSelectionMode = false;
  final Set<String> _selectedNotificationIds = {};

  @override
  void initState() {
    super.initState();
    _caricaNotifiche();
  }

  @override
  void dispose() {
    if (TutorialController.instance.stage == TutorialStage.step8_tap_notification) {
      TutorialController.instance.setStage(TutorialStage.step9_tap_profile);
    }
    super.dispose();
  }

  Future<void> _caricaNotifiche() async {
    setState(() {
      _isLoading = true;
    });

    final curUser = _apiService.currentUser;
    final nick = _apiService.resolveNickname(curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome);
    final res = await _apiService.getNotifiche(nick);

    if (mounted) {
      setState(() {
        _notifiche = res;
        _isLoading = false;
        // Se non ci sono notifiche da leggere ma ce ne sono di lette, posizionati su Già Lette
        if (_notifiche.isNotEmpty && !_notifiche.any((n) => n['letto'] != true)) {
          _selectedTabIndex = 1;
        }
      });
    }
  }

  List<Map<String, dynamic>> get _unreadNotifications =>
      _notifiche.where((n) => n['letto'] != true).toList();

  List<Map<String, dynamic>> get _readNotifications =>
      _notifiche.where((n) => n['letto'] == true).toList();

  List<Map<String, dynamic>> get _currentTabNotifications =>
      _selectedTabIndex == 0 ? _unreadNotifications : _readNotifications;

  Future<void> _rispondi(String notificaId, String azione, {String? mittente, String? tipo}) async {
    if (_respondingNotificaId != null) return;

    setState(() {
      _respondingNotificaId = notificaId;
      _respondingAction = azione;
    });

    final curUser = _apiService.currentUser;
    final nick = _apiService.resolveNickname(curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome);

    try {
      if (tipo == 'richiesta_amicizia' && mittente != null) {
        await _apiService.rispondiRichiestaAmicizia(notificaId, mittente, azione == 'accetta');
      } else {
        await _apiService.rispondiNotifica(notificaId, azione, nick);
      }

      if (mounted) {
        if (azione == 'accetta') {
          AppToast.showSuccess(
            context,
            tipo == 'richiesta_amicizia' ? 'Amicizia Accettata! 👥' : 'Invito Accettato! 🎉',
            tipo == 'richiesta_amicizia'
                ? 'Ora siete amici su FantaEventi.'
                : 'Sei ufficialmente iscritto all\'evento!',
          );
        } else {
          AppToast.showInfo(
            context,
            'Notifica Rifiutata',
            tipo == 'richiesta_amicizia' ? 'Richiesta di amicizia rifiutata.' : 'Invito rifiutato.',
          );
        }
      }

      widget.onRefreshHome();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _respondingNotificaId = null;
          _respondingAction = null;
        });
        AppToast.showError(
          context,
          'Errore Notifica',
          e.toString().replaceAll("Exception: ", ""),
        );
      }
    }
  }

  Future<void> _segnaComeLetta(String notificaId) async {
    final idx = _notifiche.indexWhere((n) => (n['id'] ?? n['notificaId'] ?? '').toString() == notificaId);
    if (idx != -1 && _notifiche[idx]['letto'] != true) {
      setState(() {
        _notifiche[idx]['letto'] = true;
      });
      await _apiService.segnaSingolaNotificaComeLetta(notificaId);
      widget.onRefreshHome();
      if (mounted) {
        AppToast.showInfo(
          context,
          'Notifica Letta 📬',
          'Spostata nella sezione "Già Lette".',
        );
      }
    }
  }

  Future<void> _segnaTutteComeLette() async {
    final curUser = _apiService.currentUser;
    final nick = _apiService.resolveNickname(curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome);
    setState(() {
      for (var n in _notifiche) {
        n['letto'] = true;
      }
      _selectedNotificationIds.clear();
      _isSelectionMode = false;
      _selectedTabIndex = 1; // Sposta visivamente alla tab "Già Lette"
    });
    await _apiService.segnaNotificheComeLette(nick);
    widget.onRefreshHome();
    if (mounted) {
      AppToast.showSuccess(
        context,
        'Tutte Lette 🎉',
        'Tutte le notifiche sono state trasferite in "Già Lette".',
      );
    }
  }

  Future<void> _eliminaSingolaNotifica(String notificaId) async {
    await _apiService.eliminaNotifica(notificaId);
    if (mounted) {
      setState(() {
        _notifiche.removeWhere((n) => (n['id'] ?? n['notificaId']) == notificaId);
        _selectedNotificationIds.remove(notificaId);
        if (_selectedNotificationIds.isEmpty) {
          _isSelectionMode = false;
        }
      });
      AppToast.showInfo(context, 'Eliminata', 'Notifica rimossa con successo.');
    }
    widget.onRefreshHome();
  }

  void _toggleSelection(String notId) {
    setState(() {
      if (_selectedNotificationIds.contains(notId)) {
        _selectedNotificationIds.remove(notId);
        if (_selectedNotificationIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedNotificationIds.add(notId);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final currentList = _currentTabNotifications;
      final currentIds = currentList.map((n) => (n['id'] ?? n['notificaId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();
      if (_selectedNotificationIds.containsAll(currentIds)) {
        _selectedNotificationIds.removeAll(currentIds);
        if (_selectedNotificationIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedNotificationIds.addAll(currentIds);
      }
    });
  }

  void _confermaEliminazioneSelezionate() {
    final count = _selectedNotificationIds.length;
    if (count == 0) return;

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 10),
            Text(
              'Elimina Selezionate',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Vuoi eliminare definitivamente $count ${count == 1 ? "notifica selezionata" : "notifiche selezionate"}?',
          style: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text('Annulla', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dCtx);
              final idsToDelete = _selectedNotificationIds.toList();
              setState(() {
                _notifiche.removeWhere((n) => idsToDelete.contains((n['id'] ?? n['notificaId']).toString()));
                _selectedNotificationIds.clear();
                _isSelectionMode = false;
              });
              await _apiService.eliminaNotificheMultiple(idsToDelete);
              widget.onRefreshHome();
              if (mounted) {
                AppToast.showSuccess(context, 'Eliminate', '$count ${count == 1 ? "notifica rimossa" : "notifiche rimosse"}.');
              }
            },
            child: Text('Elimina ($count)', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confermaSvuotaSezione() {
    final currentList = _currentTabNotifications;
    final count = currentList.length;
    if (count == 0) return;

    final isTabLette = _selectedTabIndex == 1;
    final String labelSezione = isTabLette ? 'Già Lette' : 'Da Leggere';

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 10),
            Text(
              'Svuota $labelSezione',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Vuoi cancellare tutte le $count notifiche della sezione "$labelSezione"? Questa azione è irreversibile.',
          style: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text('Annulla', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dCtx);
              final curUser = _apiService.currentUser;
              final nick = _apiService.resolveNickname(curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome);

              final idsToRemove = currentList.map((n) => (n['id'] ?? n['notificaId'] ?? '').toString()).where((id) => id.isNotEmpty).toList();

              setState(() {
                _notifiche.removeWhere((n) => idsToRemove.contains((n['id'] ?? n['notificaId']).toString()));
                _selectedNotificationIds.removeAll(idsToRemove);
                if (_selectedNotificationIds.isEmpty) {
                  _isSelectionMode = false;
                }
              });

              if (isTabLette) {
                await _apiService.eliminaTutteNotifiche(destinatario: nick, soloLette: true);
              } else {
                await _apiService.eliminaNotificheMultiple(idsToRemove);
              }

              widget.onRefreshHome();
              if (mounted) {
                AppToast.showSuccess(context, 'Sezione Svuotata', 'Tutte le notifiche in "$labelSezione" sono state rimosse.');
              }
            },
            child: Text('Svuota Tutte', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _unreadNotifications.length;
    final readCount = _readNotifications.length;
    final currentList = _currentTabNotifications;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle drag
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header: Modalità Selezione Stile Gmail vs Header Standard
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    tooltip: 'Annulla selezione',
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = false;
                        _selectedNotificationIds.clear();
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${_selectedNotificationIds.length} selezionate',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _selectedNotificationIds.containsAll(currentList.map((n) => (n['id'] ?? n['notificaId'] ?? '').toString()).where((id) => id.isNotEmpty))
                          ? Icons.select_all_rounded
                          : Icons.deselect_rounded,
                      color: const Color(0xFFFACC15),
                      size: 22,
                    ),
                    tooltip: 'Seleziona tutte / Deseleziona',
                    onPressed: _toggleSelectAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 24),
                    tooltip: 'Elimina selezionate',
                    onPressed: _confermaEliminazioneSelezionate,
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications_active, color: Color(0xFFFACC15), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Centro Notifiche',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Aggiornamenti, inviti e chiamate al VAR',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                // Tasto Selezione Multipla
                if (currentList.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.checklist_rtl_rounded, color: Color(0xFFCBD5E1), size: 22),
                    tooltip: 'Selezione multipla (Gmail)',
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = true;
                      });
                    },
                  ),
                // Tasto Segna tutte come lette (solo nella tab Da Leggere se ce ne sono)
                if (_selectedTabIndex == 0 && unreadCount > 0)
                  IconButton(
                    icon: const Icon(Icons.done_all_rounded, color: Color(0xFFFACC15), size: 22),
                    tooltip: 'Segna tutte come lette',
                    onPressed: _segnaTutteComeLette,
                  ),
                // Tasto Cestino per svuotare l'intera sezione corrente
                if (currentList.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFF87171), size: 22),
                    tooltip: _selectedTabIndex == 0 ? 'Svuota non lette' : 'Svuota già lette',
                    onPressed: _confermaSvuotaSezione,
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          const SizedBox(height: 14),

          // Selettore Sezioni: [ 📥 Da Leggere (X) ] | [ 📬 Già Lette (Y) ]
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = 0;
                        _isSelectionMode = false;
                        _selectedNotificationIds.clear();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedTabIndex == 0 ? const Color(0xFF6366F1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mark_email_unread_rounded,
                            size: 15,
                            color: _selectedTabIndex == 0 ? Colors.white : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Da Leggere',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: _selectedTabIndex == 0 ? FontWeight.bold : FontWeight.w500,
                              color: _selectedTabIndex == 0 ? Colors.white : const Color(0xFF94A3B8),
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _selectedTabIndex == 0 ? const Color(0xFFFACC15) : const Color(0xFF475569),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unreadCount',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTabIndex == 0 ? const Color(0xFF0F172A) : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = 1;
                        _isSelectionMode = false;
                        _selectedNotificationIds.clear();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedTabIndex == 1 ? const Color(0xFF6366F1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.drafts_rounded,
                            size: 15,
                            color: _selectedTabIndex == 1 ? Colors.white : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Già Lette',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: _selectedTabIndex == 1 ? FontWeight.bold : FontWeight.w500,
                              color: _selectedTabIndex == 1 ? Colors.white : const Color(0xFF94A3B8),
                            ),
                          ),
                          if (readCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$readCount',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFCBD5E1),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (TutorialController.instance.stage == TutorialStage.step8_tap_notification)
            TutorialStepBanner(
              stepTag: 'Tappa 3 di 4 • Centro Notifiche',
              title: 'Ecco la tua prima Notifica!',
              description: 'La Redazione ti dà il benvenuto! Da qui gestirai gli inviti agli eventi e le chiamate al VAR. Puoi eliminare le notifiche vecchie toccando la "X" sulla card. Chiudi questo pannello con la "X" in alto per proseguire verso il tuo Profilo!',
              onSkip: () {
                TutorialController.instance.skipTutorial();
                setState(() {});
              },
            ),

          _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(color: Color(0xFFFACC15)),
                  ),
                )
              : currentList.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20),
                      child: Column(
                        children: [
                          Icon(
                            _selectedTabIndex == 0
                                ? Icons.mark_email_read_rounded
                                : Icons.delete_outline_rounded,
                            size: 48,
                            color: const Color(0xFF475569),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedTabIndex == 0
                                ? 'Nessuna notifica da leggere 🎉\nTutti i tuoi avvisi sono in "Già Lette"!'
                                : 'Nessuna notifica archiviata in "Già Lette".',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.65,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: currentList.length,
                          itemBuilder: (ctx, idx) {
                            final not = currentList[idx];
                            final notId = (not['id'] ?? not['notificaId'] ?? '').toString();
                            final tipo = (not['tipo'] ?? '').toString().toLowerCase().trim();
                            final titolo = (not['titolo'] ?? '').toString().toLowerCase();
                            final messaggio = (not['messaggio'] ?? '').toString().toLowerCase();
                            final stato = (not['stato'] ?? '').toString().toLowerCase().trim();
                            final bool isLetto = not['letto'] == true;
                            final bool haGiaVotato = not['haGiaVotato'] == true;
                            final bool votazioneChiusa = not['votazioneChiusa'] == true;
                            final String votoEspresso = (not['votoEspresso'] ?? '').toString();
                            final String esitoVotazione = (not['esitoVotazione'] ?? '').toString();

                            final bool isSelected = _selectedNotificationIds.contains(notId);

                            // Notifiche del VAR
                            final String varId = (not['varId'] ?? '').toString();
                            final bool isVarGiudice = tipo == 'var_richiesta_giudice' && varId.isNotEmpty;
                            final bool isVarTestimone = tipo == 'var_testimone' && varId.isNotEmpty;
                            final bool isVarEsito = tipo == 'var_esito';
                            final bool isVarRelated = isVarGiudice || isVarTestimone || isVarEsito;

                            // 1. Notifica di amicizia
                            final bool isAmicizia = tipo.contains('amicizia') ||
                                tipo.contains('amico') ||
                                titolo.contains('amicizia') ||
                                messaggio.contains('amicizia') ||
                                messaggio.contains('amici');

                            // 2. Notifica di invito evento
                            final bool isInvito = tipo.contains('invito') ||
                                titolo.contains('invito') ||
                                messaggio.contains('invitato') ||
                                messaggio.contains('partecipare all\'evento');

                            // 3. Proposta attiva per Votazioni Live (bonus/malus proposto da votare)
                            final bool isProposal = !isVarRelated &&
                                !isAmicizia &&
                                !isInvito &&
                                (tipo == 'proposta_bonus_malus' ||
                                    tipo == 'proposta_votazione' ||
                                    tipo == 'proposta' ||
                                    tipo == 'votazione' ||
                                    titolo.contains('proposta') ||
                                    titolo.contains('votazione') ||
                                    messaggio.contains('ha proposto') ||
                                    messaggio.contains('entra a votare') ||
                                    messaggio.contains('vota') ||
                                    (tipo == 'bonus_malus' && (titolo.contains('proposta') || messaggio.contains('ha proposto') || titolo.contains('votazione') || stato == 'in_attesa')));

                            // 4. Notifica di assegnazione o riassegnazione bonus/malus (punti già assegnati)
                            final bool isAssegnazioneBonusMalus = !isProposal &&
                                !isVarRelated &&
                                !isAmicizia &&
                                !isInvito &&
                                (tipo == 'assegnazione_bonus' ||
                                    tipo == 'assegnazione_malus' ||
                                    tipo == 'bonus_assegnato' ||
                                    tipo == 'malus_assegnato' ||
                                    titolo.contains('assegnat') ||
                                    titolo.contains('ricevuto') ||
                                    messaggio.contains('ha ricevuto') ||
                                    messaggio.contains('assegnato') ||
                                    tipo == 'bonus' ||
                                    tipo == 'malus');

                            // 5. Richiesta in sospeso con opzione ACCETTA / RIFIUTA
                            final bool isPending = !isVarRelated &&
                                !isAssegnazioneBonusMalus &&
                                !isProposal &&
                                (tipo == 'invito' || tipo == 'richiesta_amicizia') &&
                                stato == 'in_attesa';

                            // 6. Etichetta di stato
                            final bool showStatusTag = (!isProposal &&
                                    !isAssegnazioneBonusMalus &&
                                    !titolo.contains('accettat') &&
                                    (tipo == 'invito' || tipo == 'richiesta_amicizia') &&
                                    (stato == 'accettato' || stato == 'rifiutato')) ||
                                (isVarRelated && stato != 'in_attesa');

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                                    : (isLetto ? const Color(0xFF1E293B) : const Color(0xFF1E293B)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF6366F1)
                                      : (!isLetto
                                          ? const Color(0xFFFACC15).withValues(alpha: 0.8)
                                          : (isPending ? const Color(0xFFFACC15).withValues(alpha: 0.4) : const Color(0xFF334155))),
                                  width: isSelected || !isLetto ? 1.5 : 1.0,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onLongPress: () {
                                    setState(() {
                                      _isSelectionMode = true;
                                      _toggleSelection(notId);
                                    });
                                  },
                                  onTap: () {
                                    if (_isSelectionMode) {
                                      _toggleSelection(notId);
                                    } else {
                                      // Se siamo in Da Leggere, tocca per segnare come letta e trasferire in Già Lette
                                      if (!isLetto) {
                                        _segnaComeLetta(notId);
                                      }
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Checkbox in modalità selezione (Stile Gmail)
                                            if (_isSelectionMode) ...[
                                              Checkbox(
                                                value: isSelected,
                                                activeColor: const Color(0xFF6366F1),
                                                checkColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                onChanged: (_) => _toggleSelection(notId),
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            Expanded(
                                              child: Text(
                                                not['titolo'] ?? 'Notifica',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.poppins(
                                                  fontWeight: isLetto ? FontWeight.w600 : FontWeight.bold,
                                                  fontSize: 13.5,
                                                  color: isLetto ? const Color(0xFFE2E8F0) : Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            if (!isLetto) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFFACC15), width: 1),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.stars_rounded, size: 11, color: Color(0xFFFACC15)),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      'NUOVA',
                                                      style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            if (showStatusTag) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: (stato == 'accettato' || stato == 'approvato' || stato == 'confermato')
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFFEF4444),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  stato.toUpperCase(),
                                                  style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            // Tasto eliminazione singola
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                                              tooltip: 'Elimina notifica',
                                              onPressed: () => _eliminaSingolaNotifica(notId),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          not['messaggio'] ?? '',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: isLetto ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1),
                                            height: 1.35,
                                          ),
                                        ),
                                        if (!isLetto && !isPending && !isProposal && !(isVarGiudice && stato == 'in_attesa') && !(isVarTestimone && stato == 'in_attesa')) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(Icons.touch_app_outlined, size: 13, color: const Color(0xFFFACC15).withValues(alpha: 0.85)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Tocca per segnare come letta e spostare',
                                                style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFFFACC15).withValues(alpha: 0.85), fontWeight: FontWeight.w500),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (isProposal) ...[
                                          const SizedBox(height: 10),
                                          if (haGiaVotato) ...[
                                            InkWell(
                                              onTap: () {
                                                Navigator.pop(context);
                                                if (widget.onNavigateTab != null) {
                                                  widget.onNavigateTab!(2);
                                                }
                                              },
                                              borderRadius: BorderRadius.circular(10),
                                              child: Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 15),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '✓ VOTO GIÀ ESPRESSO${votoEspresso.isNotEmpty ? ' (${votoEspresso.toUpperCase()})' : ''} • VEDI LIVE',
                                                      style: GoogleFonts.poppins(color: const Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ] else if (votazioneChiusa) ...[
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF64748B).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: const Color(0xFF64748B).withValues(alpha: 0.4)),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.flag_outlined, color: Color(0xFF94A3B8), size: 15),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '🏁 VOTAZIONE CONCLUSA${esitoVotazione.isNotEmpty ? ': ${esitoVotazione.toUpperCase()}' : ''}',
                                                    style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else ...[
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                onPressed: () {
                                                  _segnaComeLetta(notId);
                                                  Navigator.pop(context);
                                                  if (widget.onNavigateTab != null) {
                                                    widget.onNavigateTab!(2);
                                                  }
                                                },
                                                icon: const Icon(Icons.how_to_vote_rounded, size: 15, color: Colors.white),
                                                label: Text(
                                                  '🗳️ VAI A VOTAZIONI LIVE',
                                                  style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.bold),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF6366F1),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ] else if (isVarGiudice && stato == 'in_attesa') ...[
                                          const SizedBox(height: 10),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                _segnaComeLetta(notId);
                                                showModalBottomSheet(
                                                  context: context,
                                                  isScrollControlled: true,
                                                  backgroundColor: Colors.transparent,
                                                  builder: (_) => VarDecisionModal(
                                                    varId: varId,
                                                    onResolved: () {
                                                      _caricaNotifiche();
                                                      widget.onRefreshHome();
                                                    },
                                                  ),
                                                );
                                              },
                                              icon: const Text('⚖️', style: TextStyle(fontSize: 14)),
                                              label: Text(
                                                'ESAMINA AL VAR',
                                                style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.bold),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF6366F1),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 9),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          ),
                                        ] else if (isVarTestimone && stato == 'in_attesa') ...[
                                          const SizedBox(height: 10),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                _segnaComeLetta(notId);
                                                showModalBottomSheet(
                                                  context: context,
                                                  isScrollControlled: true,
                                                  backgroundColor: Colors.transparent,
                                                  builder: (_) => VarWitnessModal(
                                                    varId: varId,
                                                    onVoted: () {
                                                      _caricaNotifiche();
                                                      widget.onRefreshHome();
                                                    },
                                                  ),
                                                );
                                              },
                                              icon: const Text('🗳️', style: TextStyle(fontSize: 14)),
                                              label: Text(
                                                'VOTA AL VAR',
                                                style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.bold),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF38BDF8),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 9),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          ),
                                        ] else if (isPending) ...[
                                          const SizedBox(height: 10),
                                          () {
                                            String evStato = (not['eventoStato'] ?? '').toString().toLowerCase();
                                            final String evDataStr = (not['eventoDataInizio'] ?? '').toString();
                                            DateTime? evDataInizio = evDataStr.isNotEmpty ? DateTime.tryParse(evDataStr) : null;
                                            final String evId = (not['eventoId'] ?? '').toString().trim().toLowerCase();

                                            if ((evStato.isEmpty || evDataInizio == null) && evId.isNotEmpty) {
                                              for (final e in _apiService.eventi) {
                                                if (e.id.toLowerCase() == evId || e.titolo.toLowerCase() == evId) {
                                                  if (evStato.isEmpty) evStato = e.stato.toLowerCase();
                                                  evDataInizio ??= e.data;
                                                  break;
                                                }
                                              }
                                            }

                                            final bool isIscrizioniChiuse = isInvito &&
                                                (evStato == 'in_corso' ||
                                                    evStato == 'concluso' ||
                                                    (evDataInizio != null && DateTime.now().isAfter(evDataInizio)));

                                            if (isIscrizioniChiuse) {
                                              return Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.timer_off_rounded, color: Color(0xFFEF4444), size: 15),
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                      child: Text(
                                                        '⚠️ ISCRIZIONI CHIUSE: EVENTO GIÀ INIZIATO',
                                                        style: GoogleFonts.poppins(
                                                          color: const Color(0xFFEF4444),
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }

                                            if (_respondingNotificaId == notId) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                                                decoration: BoxDecoration(
                                                  color: _respondingAction == 'accetta'
                                                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                      : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: _respondingAction == 'accetta'
                                                        ? const Color(0xFF10B981)
                                                        : const Color(0xFFEF4444),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor: AlwaysStoppedAnimation<Color>(
                                                          _respondingAction == 'accetta'
                                                              ? const Color(0xFF10B981)
                                                              : const Color(0xFFEF4444),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _respondingAction == 'accetta'
                                                          ? '⏳ Accettazione in corso...'
                                                          : '⏳ Rifiuto in corso...',
                                                      style: GoogleFonts.poppins(
                                                        color: _respondingAction == 'accetta'
                                                            ? const Color(0xFF10B981)
                                                            : const Color(0xFFEF4444),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }

                                            return Row(
                                              children: [
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: _respondingNotificaId != null
                                                        ? null
                                                        : () {
                                                            _segnaComeLetta(notId);
                                                            _rispondi(notId, 'accetta', mittente: not['mittente'], tipo: not['tipo']);
                                                          },
                                                    icon: const Icon(Icons.check_circle_rounded, size: 15, color: Colors.white),
                                                    label: const Text('ACCETTA'),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF10B981),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: _respondingNotificaId != null
                                                        ? null
                                                        : () {
                                                            _segnaComeLetta(notId);
                                                            _rispondi(notId, 'rifiuta', mittente: not['mittente'], tipo: not['tipo']);
                                                          },
                                                    icon: const Icon(Icons.cancel_rounded, size: 15, color: Colors.white),
                                                    label: const Text('RIFIUTA'),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFFEF4444),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }(),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
        ],
      ),
    );
  }
}
