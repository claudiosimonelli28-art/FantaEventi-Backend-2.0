import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../models/bonus_malus.dart';
import '../models/evento.dart';
import '../services/tutorial_controller.dart';
import '../widgets/tutorial_spotlight_overlay.dart';
import '../widgets/app_toast.dart';
import '../widgets/context_info_modal.dart';

class AddBonusMalusView extends StatefulWidget {
  final Evento? evento;
  const AddBonusMalusView({super.key, this.evento});

  @override
  State<AddBonusMalusView> createState() => _AddBonusMalusViewState();
}

class _AddBonusMalusViewState extends State<AddBonusMalusView> {
  final _formKey = GlobalKey<FormState>();
  final _titoloController = TextEditingController();
  final _descrizioneController = TextEditingController();
  final _puntiController = TextEditingController(text: '10');

  bool _isBonus = true;
  bool _riassegnabileMoltepliciVolte = false;
  String _categoriaSelezionata = 'Goliardia';
  Evento? _eventoSelezionato;
  bool _isLoading = false;

  final List<String> _categorie = [
    'Goliardia',
    'Cibo & Drink',
    'Stile & Outfit',
    'Puntualità',
    'Performance',
    'Special',
  ];

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    if (widget.evento != null && !widget.evento!.isConcluso) {
      final meUser = _apiService.currentUser;
      final myNick = (meUser?.nickname.isNotEmpty == true ? meUser!.nickname : meUser?.nome ?? '').trim().toLowerCase();
      final myAlias = meUser?.nickname.trim().toLowerCase() ?? '';
      final isCreatore = widget.evento!.creatore.trim().toLowerCase() == myNick || (myAlias.isNotEmpty && widget.evento!.creatore.trim().toLowerCase() == myAlias);
      final isPartecipante = isCreatore || widget.evento!.partecipanti.any((p) {
        final pLow = p.trim().toLowerCase();
        return pLow == myNick || (myAlias.isNotEmpty && pLow == myAlias);
      });
      if (isPartecipante) {
        _eventoSelezionato = widget.evento;
      }
    }
    if (TutorialController.instance.stage == TutorialStage.step6_in_add_bonus) {
      _titoloController.text = 'Bicchierata alla goccia 🍺';
      _descrizioneController.text = 'Bere un bicchiere tutto d\'un fiato senza posarlo';
      _puntiController.text = '15';
    }
  }

  @override
  void dispose() {
    _titoloController.dispose();
    _descrizioneController.dispose();
    _puntiController.dispose();
    super.dispose();
  }

  Future<bool?> _mostraConfermaProposta({
    required String titolo,
    required String descrizione,
    required int punti,
    required bool isBonus,
    required String categoria,
    required bool riassegnabile,
    required String nomeEvento,
  }) async {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: Color(0xFF9333EA), width: 2),
            ),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.fact_check_rounded, color: Color(0xFFC084FC), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Riepilogo Proposta',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Controlla attentamente prima di inviare',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isBonus
                                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                : const Color(0xFFEF4444).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isBonus ? '+$punti PT (BONUS)' : '-$punti PT (MALUS)',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            categoria,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      titolo,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (descrizione.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        descrizione,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF334155), height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.event_note_rounded, size: 14, color: Color(0xFFFACC15)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Evento: $nomeEvento',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFCBD5E1),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          riassegnabile ? Icons.replay_rounded : Icons.looks_one_rounded,
                          size: 14,
                          color: const Color(0xFFFACC15),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          riassegnabile ? 'Riassegnabile più volte' : 'Assegnabile una sola volta',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAB308).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFFACC15), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Una volta inviata, la proposta entrerà subito nelle Votazioni Live e non potrà più essere ritirata o modificata da nessuno.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFFDE047),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFCBD5E1),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Fammi rileggere',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isBonus ? const Color(0xFFFACC15) : const Color(0xFF9333EA),
                        foregroundColor: isBonus ? const Color(0xFF0F172A) : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.rocket_launch_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Sì, invia proposta',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitForm() async {
    if (_isLoading) return;

    if (_formKey.currentState?.validate() ?? false) {
      if (_eventoSelezionato == null) {
        AppToast.showWarning(
          context,
          'Evento Mancante',
          'Seleziona un evento attivo a cui collegare il bonus/malus!',
        );
        return;
      }

      if (_eventoSelezionato!.isConcluso) {
        AppToast.showWarning(
          context,
          'Evento Concluso',
          'Questo evento è concluso. Non puoi proporre bonus/malus per eventi chiusi.',
        );
        return;
      }

      final meUser = _apiService.getCurrentUser();
      final myNick = (meUser.nickname.isNotEmpty ? meUser.nickname : meUser.nome).trim().toLowerCase();
      final myAlias = meUser.nickname.trim().toLowerCase();
      final isCreatore = _eventoSelezionato!.creatore.trim().toLowerCase() == myNick || (myAlias.isNotEmpty && _eventoSelezionato!.creatore.trim().toLowerCase() == myAlias);
      final isPartecipante = isCreatore || _eventoSelezionato!.partecipanti.any((p) {
        final pLow = p.trim().toLowerCase();
        return pLow == myNick || (myAlias.isNotEmpty && pLow == myAlias);
      });

      if (!isPartecipante) {
        AppToast.showWarning(
          context,
          'Accesso Negato',
          'Non puoi proporre bonus/malus per un evento a cui non partecipi!',
        );
        return;
      }

      int mePunti = int.tryParse(_puntiController.text.trim()) ?? 10;
      if (mePunti.abs() > 100) {
        AppToast.showError(context, 'Punti non validi', 'Il punteggio massimo per un bonus o malus è 100 punti.');
        return;
      }
      if (mePunti.abs() == 0) {
        AppToast.showError(context, 'Punti non validi', 'Il punteggio minimo è 1 punto.');
        return;
      }
      if (!_isBonus && mePunti > 0) {
        mePunti = -mePunti;
      } else if (_isBonus && mePunti < 0) {
        mePunti = mePunti.abs();
      }

      final confermato = await _mostraConfermaProposta(
        titolo: _titoloController.text.trim(),
        descrizione: _descrizioneController.text.trim(),
        punti: mePunti.abs(),
        isBonus: _isBonus,
        categoria: _categoriaSelezionata,
        riassegnabile: _riassegnabileMoltepliciVolte,
        nomeEvento: _eventoSelezionato!.titolo,
      );

      if (confermato != true) {
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {

        final meUser = _apiService.getCurrentUser();
        final rawUserNick = (meUser.nickname.isNotEmpty ? meUser.nickname : meUser.nome).trim();
        final finalPropostoDa = _apiService.resolveNickname(rawUserNick);

        final nuovoBonus = BonusMalus(
          id: 'bm_${DateTime.now().millisecondsSinceEpoch}',
          titolo: _titoloController.text.trim(),
          descrizione: _descrizioneController.text.trim(),
          punti: mePunti,
          categoria: _categoriaSelezionata,
          propostoDa: finalPropostoDa,
          approvato: false,
          riassegnabileMoltepliciVolte: _riassegnabileMoltepliciVolte,
        );

        final bool isTutorial = TutorialController.instance.stage == TutorialStage.step6_in_add_bonus;
        await _apiService
            .proponiBonusMalusPerEvento(_eventoSelezionato!.id, nuovoBonus, awardXp: !isTutorial)
            .timeout(const Duration(seconds: 15));

        if (isTutorial) {
          TutorialController.instance.setStage(TutorialStage.step7_view_votazioni);
        }

        if (!mounted) return;

        AppToast.showSuccess(
          context,
          'Proposta inviata con successo! 🚀',
          '${nuovoBonus.titolo} è stato inserito nelle Votazioni Live.',
        );

        Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          AppToast.showError(
            context,
            'Errore durante la proposta',
            e.toString().replaceAll("Exception: ", ""),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTutorial = TutorialController.instance.stage == TutorialStage.step6_in_add_bonus;
    return PopScope(
      canPop: !isTutorial,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          automaticallyImplyLeading: !isTutorial,
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'Proponi Bonus / Malus',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline_rounded, color: Color(0xFFFACC15), size: 24),
              tooltip: 'Guida Proposta Regole',
              onPressed: () => ContextInfoModal.mostra(context, tipo: ContextInfoType.propostaBonusMalus),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (TutorialController.instance.stage == TutorialStage.step6_in_add_bonus)
                    TutorialStepBanner(
                      stepTag: 'Tappa 2 di 4 • Proposta Regola',
                      title: 'Proponi una Regola Goliardica!',
                      description: 'Siccome questa regola la stai proponendo tu, il tuo voto è già automaticamente a favore (PRO)! Quando giocherai con i tuoi amici, la proposta apparirà a tutti loro nelle Votazioni Live per essere convalidata.',
                      onSkip: () {
                        TutorialController.instance.skipTutorial();
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                // Event Banner
                if (_eventoSelezionato != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available_rounded, color: Color(0xFFFACC15)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Evento Collegato:',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                              ),
                              Text(
                                _eventoSelezionato!.titolo,
                                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  FutureBuilder<List<Evento>>(
                    future: _apiService.getEventi(),
                    builder: (context, snapshot) {
                      final meUser = _apiService.currentUser;
                      final myNick = (meUser?.nickname.isNotEmpty == true ? meUser!.nickname : meUser?.nome ?? '').trim().toLowerCase();
                      final myAlias = meUser?.nickname.trim().toLowerCase() ?? '';

                      // Filtra rigorosamente solo gli eventi attivi e non conclusi a cui l'utente partecipa
                      final eventi = (snapshot.data ?? []).where((e) {
                        if (e.isConcluso) return false;
                        final isCreatore = e.creatore.trim().toLowerCase() == myNick ||
                            (myAlias.isNotEmpty && e.creatore.trim().toLowerCase() == myAlias);
                        final isPartecipante = isCreatore ||
                            e.partecipanti.any((p) {
                              final pLow = p.trim().toLowerCase();
                              return pLow == myNick || (myAlias.isNotEmpty && pLow == myAlias);
                            });
                        return isPartecipante;
                      }).toList();

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          child: const Center(
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFACC15)),
                            ),
                          ),
                        );
                      }
                      if (eventi.isEmpty) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_busy_rounded, color: Color(0xFFEF4444)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Nessun evento attivo disponibile a cui partecipi.\nTutti gli eventi risultano conclusi o non ne fai parte.',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        child: DropdownButtonFormField<Evento>(
                          dropdownColor: const Color(0xFF1E293B),
                          decoration: InputDecoration(
                            labelText: 'Seleziona Evento Attivo',
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          items: eventi.map((e) {
                            return DropdownMenuItem(
                              value: e,
                              child: Text(e.titolo, style: const TextStyle(color: Colors.white)),
                            );
                          }).toList(),
                          onChanged: (ev) {
                            setState(() {
                              _eventoSelezionato = ev;
                            });
                          },
                        ),
                      );
                    },
                  ),

                Text(
                  'Nuova Regola Goliardica',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Proponi un bonus o malus legato all\'evento. Verrà creata una votazione con quorum democratico.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 24),

                // Toggle Switch BONUS vs MALUS
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isBonus = true;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _isBonus ? const Color(0xFFFACC15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: _isBonus ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'BONUS (+)',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: _isBonus ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isBonus = false;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: !_isBonus ? const Color(0xFF9333EA) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.dangerous_rounded,
                                  color: !_isBonus ? Colors.white : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'MALUS (-)',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: !_isBonus ? Colors.white : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Titolo
                TextFormField(
                  controller: _titoloController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Titolo Regola',
                    hintText: _isBonus ? 'Es. Canto epico al Karaoke' : 'Es. Bicchiere rovesciato',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: Icon(
                      _isBonus ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: _isBonus ? const Color(0xFFFACC15) : const Color(0xFF9333EA),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Inserisci un titolo' : null,
                ),
                const SizedBox(height: 16),

                // Descrizione
                TextFormField(
                  controller: _descrizioneController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Descrizione / Regola di ingaggio',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.notes, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Inserisci la descrizione' : null,
                ),
                const SizedBox(height: 16),

                // Punteggio & Categoria
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _puntiController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Punti',
                          prefixIcon: Icon(
                            Icons.score,
                            color: _isBonus ? const Color(0xFFFACC15) : const Color(0xFF9333EA),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Punti?';
                          final p = int.tryParse(val);
                          if (p == null) return 'Numero valido';
                          if (p.abs() == 0) return 'Min 1';
                          if (p.abs() > 100) return 'Max 100';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _categoriaSelezionata,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Categoria',
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                        items: _categorie.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(c, style: GoogleFonts.inter(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _categoriaSelezionata = val;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'Punti rapidi (Max 100):',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [5, 10, 20, 50, 100].map((pt) {
                            final isSel = _puntiController.text.trim() == pt.toString();
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _puntiController.text = pt.toString();
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFFFACC15).withValues(alpha: 0.25) : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSel ? const Color(0xFFFACC15) : const Color(0xFF334155),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '${_isBonus ? "+" : "-"}$pt',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSel ? const Color(0xFFFACC15) : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Checkbox Riassegnabile Molteplici Volte
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: CheckboxListTile(
                    value: _riassegnabileMoltepliciVolte,
                    onChanged: (val) {
                      setState(() {
                        _riassegnabileMoltepliciVolte = val ?? false;
                      });
                    },
                    activeColor: const Color(0xFFFACC15),
                    checkColor: const Color(0xFF0F172A),
                    title: Text(
                      'Riassegnabile più di una volta',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    subtitle: Text(
                      'Consente di riassegnare questo bonus/malus più volte alla stessa persona',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isBonus ? const Color(0xFFFACC15) : const Color(0xFF9333EA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            TutorialController.instance.stage == TutorialStage.step6_in_add_bonus
                                ? 'PROPONI ALL\'EVENTO (TUTORIAL)'
                                : 'PROPONI ALL\'EVENTO (+50 XP)',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _isBonus ? const Color(0xFF0F172A) : Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
