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
    final nick = curUser?.nome ?? 'Cloud';
    final res = await _apiService.getNotifiche(nick);

    if (mounted) {
      setState(() {
        _notifiche = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _rispondi(String notificaId, String azione, {String? mittente, String? tipo}) async {
    if (_respondingNotificaId != null) return;

    setState(() {
      _respondingNotificaId = notificaId;
      _respondingAction = azione;
    });

    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';

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

  Future<void> _eliminaNotifica(String notificaId) async {
    await _apiService.eliminaNotifica(notificaId);
    if (mounted) {
      setState(() {
        _notifiche.removeWhere((n) => (n['id'] ?? n['notificaId']) == notificaId);
      });
    }
    widget.onRefreshHome();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active, color: Color(0xFFFACC15), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Centro Notifiche & Inviti',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: Color(0xFFFACC15)),
                ))
              : _notifiche.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          const Icon(Icons.notifications_none_rounded, size: 48, color: Color(0xFF64748B)),
                          const SizedBox(height: 12),
                          Text(
                            'Nessun nuovo invito o notifica al momento.',
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
                          itemCount: _notifiche.length,
                          itemBuilder: (ctx, idx) {
                            final not = _notifiche[idx];
                            final notId = (not['id'] ?? not['notificaId'] ?? '').toString();
                            final tipo = (not['tipo'] ?? '').toString().toLowerCase().trim();
                            final titolo = (not['titolo'] ?? '').toString().toLowerCase();
                            final messaggio = (not['messaggio'] ?? '').toString().toLowerCase();
                            final stato = (not['stato'] ?? '').toString().toLowerCase().trim();

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

                            // 3. Notifica di assegnazione o riassegnazione bonus/malus
                            final bool isAssegnazioneBonusMalus = tipo == 'assegnazione_bonus' ||
                                titolo.contains('assegnat') ||
                                titolo.contains('ricevuto') ||
                                messaggio.contains('ha ricevuto') ||
                                messaggio.contains('assegnato');

                            // Notifiche del VAR
                            final String varId = (not['varId'] ?? '').toString();
                            final bool isVarGiudice = tipo == 'var_richiesta_giudice' && varId.isNotEmpty;
                            final bool isVarTestimone = tipo == 'var_testimone' && varId.isNotEmpty;
                            final bool isVarEsito = tipo == 'var_esito';
                            final bool isVarRelated = isVarGiudice || isVarTestimone || isVarEsito;

                            // 4. Proposta attiva per Votazioni Live:
                            // Compare ESCLUSIVAMENTE per le proposte di bonus/malus create dagli utenti in attesa di voto
                            final bool isProposal = !isVarRelated &&
                                !isAmicizia &&
                                !isInvito &&
                                !isAssegnazioneBonusMalus &&
                                stato == 'in_attesa' &&
                                (tipo == 'proposta_bonus_malus' ||
                                 tipo == 'proposta_votazione' ||
                                 tipo == 'proposta' ||
                                 (tipo == 'bonus_malus' && (titolo.contains('proposta') || messaggio.contains('ha proposto') || titolo.contains('votazione'))));

                            // 5. Richiesta in sospeso con opzione ACCETTA / RIFIUTA (inviti evento o richieste amicizia)
                            final bool isPending = !isVarRelated &&
                                !isAssegnazioneBonusMalus &&
                                (tipo == 'invito' || tipo == 'richiesta_amicizia') &&
                                stato == 'in_attesa';

                            // 6. Etichetta di stato (solo per richieste o inviti già decisi in precedenza, o esiti VAR)
                            final bool showStatusTag = (!isProposal &&
                                !isAssegnazioneBonusMalus &&
                                !titolo.contains('accettat') &&
                                (tipo == 'invito' || tipo == 'richiesta_amicizia') &&
                                (stato == 'accettato' || stato == 'rifiutato')) ||
                                (isVarRelated && stato != 'in_attesa');

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isPending ? const Color(0xFFFACC15).withValues(alpha: 0.5) : const Color(0xFF334155),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          not['titolo'] ?? 'Notifica',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (showStatusTag) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: (stato == 'accettato' || stato == 'approvato' || stato == 'confermato')
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            stato.toUpperCase(),
                                            style: GoogleFonts.poppins(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                                        tooltip: 'Elimina notifica',
                                        onPressed: () => _eliminaNotifica((not['id'] ?? not['notificaId'] ?? '').toString()),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    not['messaggio'] ?? '',
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                                  ),
                                  if (isProposal) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          if (widget.onNavigateTab != null) {
                                            widget.onNavigateTab!(2);
                                          }
                                        },
                                        icon: const Icon(Icons.how_to_vote_rounded, size: 16, color: Colors.white),
                                        label: Text(
                                          '🗳️ VAI A VOTAZIONI LIVE',
                                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6366F1),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ] else if (isVarGiudice && stato == 'in_attesa') ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
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
                                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6366F1),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ] else if (isVarTestimone && stato == 'in_attesa') ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
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
                                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF38BDF8),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ] else if (isPending) ...[
                                    const SizedBox(height: 12),
                                    if (_respondingNotificaId == notId) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  _respondingAction == 'accetta'
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFFEF4444),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              _respondingAction == 'accetta'
                                                  ? '⏳ Accettazione in corso...'
                                                  : '⏳ Rifiuto in corso...',
                                              style: GoogleFonts.poppins(
                                                color: _respondingAction == 'accetta'
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFFEF4444),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _respondingNotificaId != null
                                                  ? null
                                                  : () => _rispondi(notId, 'accetta', mittente: not['mittente'], tipo: not['tipo']),
                                              icon: const Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                                              label: const Text('ACCETTA'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF10B981),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _respondingNotificaId != null
                                                  ? null
                                                  : () => _rispondi(notId, 'rifiuta', mittente: not['mittente'], tipo: not['tipo']),
                                              icon: const Icon(Icons.cancel_rounded, size: 16, color: Colors.white),
                                              label: const Text('RIFIUTA'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFEF4444),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ],
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
