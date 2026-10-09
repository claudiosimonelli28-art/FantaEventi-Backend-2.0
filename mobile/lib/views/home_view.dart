import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../models/votazione.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/event_card.dart';
import '../widgets/bonus_malus_card.dart';
import '../widgets/vote_card.dart';
import 'create_event_view.dart';
import 'add_bonus_malus_view.dart';
import 'vote_view.dart';
import 'profile_view.dart';
import 'notifications_modal.dart';
import 'event_detail_view.dart';
import 'var_submission_modal.dart';
import '../widgets/guida_regolamento_modal.dart';
import '../widgets/tutorial_spotlight_overlay.dart';
import '../services/tutorial_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_toast.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  List<Evento> _eventi = [];
  List<BonusMalus> _bonusMalusList = [];
  List<Votazione> _votazioniList = [];
  int _numeroNotifiche = 0;
  bool _isLoading = true;

  late TabController _tabController;
  Timer? _liveSyncTimer;

  // Controller e animazioni per lo Speed Dial FAB
  late AnimationController _fabAnimationController;
  late Animation<double> _fabRotationAnimation;
  late Animation<double> _fabMenuAnimation;
  late Animation<Offset> _fabSlideAnimation;
  bool _isFabMenuOpen = false;

  @override
  void initState() {
    super.initState();
    TutorialController.instance.addListener(_onTutorialChanged);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _isFabMenuOpen) {
        _closeFabMenu();
      }
    });

    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    // 0.375 giri = 135 gradi con curva cubica ben visibile ed elegante
    _fabRotationAnimation = Tween<double>(begin: 0.0, end: 0.375).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: Curves.easeInOutCubic,
      ),
    );
    // Animazione di apparizione / dissolvenza
    _fabMenuAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // Comparsa graduale dal basso verso l'alto
    _fabSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.45),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _fabAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (TutorialController.instance.stage == TutorialStage.step1_tap_plus) {
          TutorialController.instance.setStage(TutorialStage.step2_tap_crea_evento);
        }
        if (mounted) setState(() {});
      } else if (status == AnimationStatus.dismissed) {
        if (TutorialController.instance.stage == TutorialStage.step2_tap_crea_evento) {
          TutorialController.instance.setStage(TutorialStage.step1_tap_plus);
        }
        if (mounted) setState(() {});
      }
    });

    _loadData(forceRefresh: true);
    _checkLongTermInactivity();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _loadData(silent: true, forceRefresh: false);
    });
  }

  Future<void> _checkLongTermInactivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActiveMs = prefs.getInt('ultimo_accesso_effettivo_timestamp');
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      if (lastActiveMs != null) {
        final diffDays = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastActiveMs)).inDays;
        if (diffDays >= 180 && mounted) {
          final userNick = _apiService.currentUser?.nome ?? 'Campione';
          _mostraModaleBentornato(userNick);
        }
      }

      await prefs.setInt('ultimo_accesso_effettivo_timestamp', nowMs);
    } catch (_) {}
  }

  void _mostraModaleBentornato(String userNick) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                  blurRadius: 25,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('👋', style: TextStyle(fontSize: 40)),
                ),
                const SizedBox(height: 18),
                Text(
                  'Bentornato, $userNick!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Che bello rivederti su FantaEventi!\nÈ passato un bel po\' di tempo dall\'ultima volta che abbiamo giocato insieme (più di 6 mesi!).\n\nChe ne dici di fare un rapido ripasso guidato per rispolverare tutte le regole e le novità?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFFCBD5E1),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      TutorialController.instance.startTutorial(isReplay: true);
                    },
                    icon: const Icon(Icons.sports_esports_rounded, size: 20),
                    label: Text(
                      'SÌ, FACCIAMO IL RIPASSO 🎮',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      foregroundColor: const Color(0xFF0F172A),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF475569)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      foregroundColor: const Color(0xFF94A3B8),
                    ),
                    child: Text(
                      'Mi ricordo tutto, andiamo a giocare! 🚀',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
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

  final Set<String> _readNotificaIds = {};
  bool _isFetchingData = false;

  Future<void> _loadData({bool silent = false, bool forceRefresh = false}) async {
    if (_isFetchingData) return;
    _isFetchingData = true;
    try {
      if (!silent && mounted) {
        setState(() {
          _isLoading = true;
        });
        await _apiService.syncCurrentUserFromDb();
      }

      final meEventi = await _apiService.getEventi(forceRefresh: forceRefresh);
      final meBonus = await _apiService.getBonusMalusList();
      final meVoti = await _apiService.getVotazioni();

      final curUser = _apiService.currentUser;
      final nick = curUser?.nome ?? 'Cloud';
      final nots = await _apiService.getNotifiche(nick);
      final unreadNots = nots.where((n) {
        final nId = (n['id'] ?? '').toString();
        if (nId.isNotEmpty && _readNotificaIds.contains(nId)) return false;
        if (n['letto'] == true || n['stato'] == 'letto') return false;
        return true;
      }).toList();

      final inAttesa = unreadNots.length;

      if (!mounted) return;

      setState(() {
        _eventi = meEventi;
        _bonusMalusList = meBonus;
        _votazioniList = meVoti;
        _numeroNotifiche = inAttesa;
        if (!silent) _isLoading = false;
      });

      if (!silent) {
        _checkMostraGuidaIniziale();
      }
    } finally {
      _isFetchingData = false;
    }
  }

  String? _lastCheckedUserGuida;

  Future<void> _checkMostraGuidaIniziale() async {
    final curUser = _apiService.currentUser;
    if (curUser == null) return;
    final userKey = curUser.id.isNotEmpty ? curUser.id : curUser.nome.trim().toLowerCase();
    if (_lastCheckedUserGuida == userKey) return;

    final seen = await _apiService.haVistoGuidaRegole(userKey);
    if (seen) {
      _lastCheckedUserGuida = userKey;
      return;
    }

    _lastCheckedUserGuida = userKey;
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        final startTutorial = await GuidaRegolamentoModal.mostra(context, isFirstAccess: true);
        if (startTutorial == true && mounted) {
          _avviaTutorialGuidato();
        }
      }
    }
  }

  void _onTutorialChanged() {
    if (mounted) {
      if (TutorialController.instance.stage == TutorialStage.step7_view_votazioni) {
        if (_tabController.index != 2) {
          _tabController.animateTo(2);
        }
      }
      setState(() {});
    }
  }

  void _avviaTutorialGuidato() {
    TutorialController.instance.startTutorial();
  }

  void _apriCreaEvento() async {
    if (TutorialController.instance.stage == TutorialStage.step2_tap_crea_evento) {
      TutorialController.instance.setStage(TutorialStage.step3_in_create_event);
    }
    _closeFabMenu(fromTutorialNavigation: true);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateEventView()),
    );
    _loadData(forceRefresh: true, silent: true);
  }

  void _apriPrimoEvento() async {
    if (_eventi.isEmpty) return;
    final ev = _eventi.firstWhere(
      (e) => TutorialController.instance.isTutorialEvent(e),
      orElse: () => _eventi.first,
    );
    if (TutorialController.instance.stage == TutorialStage.step4_tap_event_card) {
      TutorialController.instance.setStage(TutorialStage.step5_in_event_detail);
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventDetailView(evento: ev, onRefresh: () => _loadData(forceRefresh: true))),
    );
    _loadData(forceRefresh: true);
  }

  void _apriProfilo() async {
    if (TutorialController.instance.stage == TutorialStage.step9_tap_profile) {
      TutorialController.instance.setStage(TutorialStage.step10_in_profile);
    }
    final restartedTutorial = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProfileView()),
    );
    if (restartedTutorial == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TutorialController.instance.startTutorial();
      });
    }
    if (mounted) {
      setState(() {});
      _loadData(silent: true, forceRefresh: true);
    }
  }

  void _apriNotifiche() async {
    if (TutorialController.instance.stage == TutorialStage.step8_tap_notification) {
      TutorialController.instance.setStage(TutorialStage.step9_tap_profile);
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: NotificationsModal(
          onRefreshHome: () => _loadData(silent: true, forceRefresh: true),
          onNavigateTab: (tabIndex) {
            if (tabIndex >= 0 && tabIndex < _tabController.length) {
              _tabController.animateTo(tabIndex);
            }
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        _loadData(silent: true, forceRefresh: true);
      }
    });
  }

  Future<void> _confermaEliminazioneEvento(Evento evento) async {
    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';
    bool isDeleting = false;

    final confermato = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Eliminare l\'evento?',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Sei sicuro di voler eliminare permanentemente l\'evento "${evento.titolo}"?',
            style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
          ),
          actions: isDeleting
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '⏳ Eliminazione in corso...',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFEF4444),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('ANNULLA', style: TextStyle(color: Colors.white70)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      setDialogState(() {
                        isDeleting = true;
                      });

                      final evId = evento.id;
                      try {
                        await _apiService.eliminaEvento(evId, nick);
                        if (ctx.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() {
                            isDeleting = false;
                          });
                          AppToast.showError(
                            ctx,
                            'Errore Eliminazione',
                            e.toString().replaceAll('Exception: ', ''),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                    child: const Text('ELIMINA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
        ),
      ),
    );

    if (confermato == true) {
      final evId = evento.id;
      setState(() {
        _eventi.removeWhere((e) => e.id == evId);
      });
      _loadData(forceRefresh: true, silent: true);
      if (mounted) {
        AppToast.showSuccess(
          context,
          'Evento Eliminato 🗑️',
          'Evento "${evento.titolo}" eliminato con successo.',
        );
      }
    }
  }

  Future<void> _partecipaEvento(Evento evento) async {
    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';

    if (evento.isConcluso || evento.isInCorso) {
      if (!mounted) return;
      AppToast.showWarning(
        context,
        'Attenzione',
        evento.isConcluso
            ? 'Questo evento è già concluso!'
            : 'Le iscrizioni sono chiuse: l\'evento è già in corso!',
      );
      return;
    }

    try {
      await _apiService.partecipaAdEvento(evento.id, nick);
      if (!mounted) return;
      AppToast.showSuccess(
        context,
        'Iscritto con successo! 🎉',
        'Ora partecipi a "${evento.titolo}".',
      );
      _loadData(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      AppToast.showError(
        context,
        'Errore Iscrizione',
        e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  @override
  void dispose() {
    TutorialController.instance.removeListener(_onTutorialChanged);
    _liveSyncTimer?.cancel();
    _tabController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _toggleFabMenu() {
    setState(() {
      _isFabMenuOpen = !_isFabMenuOpen;
      if (_isFabMenuOpen) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    });
  }

  void _closeFabMenu({bool fromTutorialNavigation = false}) {
    if (_isFabMenuOpen) {
      setState(() {
        _isFabMenuOpen = false;
        _fabAnimationController.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final curUser = _apiService.currentUser;
    final userNick = curUser?.nome ?? 'Cloud';

    final Widget mainScaffold = Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFACC15), Color(0xFF9333EA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/icon/app_icon.jpg',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'FantaEventi',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Icona Guida & Regolamento (?)
          IconButton(
            onPressed: () async {
              final startTutorial = await GuidaRegolamentoModal.mostra(context);
              if (startTutorial == true && mounted) {
                _avviaTutorialGuidato();
              }
            },
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFFFACC15), size: 22),
            tooltip: 'Regole & Guida di FantaEventi',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            visualDensity: VisualDensity.compact,
          ),
          // Icona Campanellino Notifiche
          IconButton(
            key: TutorialController.instance.keyNotifiche,
            onPressed: () {
              if (TutorialController.instance.stage == TutorialStage.step8_tap_notification) {
                TutorialController.instance.setStage(TutorialStage.step9_tap_profile);
              }
              _apriNotifiche();
            },
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            visualDensity: VisualDensity.compact,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                if (_numeroNotifiche > 0 || TutorialController.instance.stage == TutorialStage.step8_tap_notification)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_numeroNotifiche > 0 ? _numeroNotifiche : 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 2),

          // Profile User Chip (Foto Profilo reale + Livello)
          InkWell(
            key: TutorialController.instance.keyProfilo,
            onTap: _apriProfilo,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: _getStableAvatarProvider(curUser?.avatarUrl),
                    backgroundColor: const Color(0xFF334155),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9333EA),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Lvl ${curUser?.livello ?? 1}',
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFACC15),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFACC15),
          unselectedLabelColor: const Color(0xFF94A3B8),
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Feed Eventi'),
            Tab(text: 'Bonus & Malus'),
            Tab(text: 'Votazioni Live'),
          ],
        ),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFACC15)),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // --- TAB 1: FEED EVENTI ---
                    _buildEventiTab(userNick),

                    // --- TAB 2: BONUS & MALUS ---
                    _buildBonusMalusTab(),

                    // --- TAB 3: VOTAZIONI LIVE ---
                    _buildVotazioniTab(),
                  ],
                ),
          // Backdrop Overlay quando il menu del FAB è aperto (solo quando tutorial non attivo per non sovrapporsi)
          if (_isFabMenuOpen && !TutorialController.instance.isActive)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _closeFabMenu(),
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: _fabAnimationController,
                  builder: (context, child) {
                    return Container(
                      color: Colors.black.withValues(alpha: 0.55 * _fabAnimationController.value),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Voci menu Speed Dial a comparsa con scivolamento da sotto
          if (_isFabMenuOpen || _fabAnimationController.isAnimating)
            SlideTransition(
              position: _fabSlideAnimation,
              child: FadeTransition(
                opacity: _fabMenuAnimation,
                child: ScaleTransition(
                  scale: _fabMenuAnimation,
                  alignment: Alignment.bottomRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildSpeedDialItem(
                        key: TutorialController.instance.keyCreaEventoItem,
                        label: 'Crea Evento',
                        icon: Icons.calendar_today_rounded,
                        color: const Color(0xFF6366F1),
                        onTap: () async {
                          if (TutorialController.instance.stage == TutorialStage.step2_tap_crea_evento) {
                            TutorialController.instance.setStage(TutorialStage.step3_in_create_event);
                          }
                          _closeFabMenu(fromTutorialNavigation: true);
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CreateEventView()),
                          );
                          _loadData(forceRefresh: true, silent: true);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildSpeedDialItem(
                        label: 'Crea Bonus / Malus',
                        icon: Icons.flash_on_rounded,
                        color: const Color(0xFFEC4899),
                        onTap: () async {
                          _closeFabMenu();
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AddBonusMalusView()),
                          );
                          _loadData(forceRefresh: true);
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ),
          // FAB rotondo (+ animato a X)
          FloatingActionButton(
            key: TutorialController.instance.keyFabPlus,
            heroTag: 'fab_speed_dial',
            onPressed: _toggleFabMenu,
            backgroundColor: const Color(0xFF9333EA),
            elevation: 6,
            shape: const CircleBorder(),
            child: RotationTransition(
              turns: _fabRotationAnimation,
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );

    final overlay = _buildInteractiveTutorialOverlay();

    return Stack(
      children: [
        mainScaffold,
        ?overlay,
      ],
    );
  }

  Widget? _buildInteractiveTutorialOverlay() {
    final tutorial = TutorialController.instance;
    if (!tutorial.isActive) return null;

    switch (tutorial.stage) {
      case TutorialStage.step1_tap_plus:
        return InteractiveSpotlightOverlay(
          targetKey: tutorial.keyFabPlus,
          isTargetRound: true,
          padding: 8,
          stepTag: 'Tappa 1 di 4 • Hub Azioni',
          title: 'Tocca il pulsante ➕ in basso',
          description: 'Questo è l\'hub rapido delle azioni di gioco. Da qui puoi creare nuovi Eventi o proporre nuove regole Bonus & Malus.',
          onTargetTapped: () => _toggleFabMenu(),
          onSkip: () => tutorial.skipTutorial(),
        );

      case TutorialStage.step2_tap_crea_evento:
        if (_fabAnimationController.isAnimating || !_isFabMenuOpen) {
          return null;
        }
        return InteractiveSpotlightOverlay(
          targetKey: tutorial.keyCreaEventoItem,
          isTargetRound: false,
          padding: 6,
          stepTag: 'Tappa 1 di 4 • Crea Evento',
          title: 'Tocca "Crea Evento"',
          description: 'Apri la schermata per impostare il tuo primo evento di gioco e scoprire come invitare i tuoi compagni.',
          onTargetTapped: () => _apriCreaEvento(),
          onSkip: () => tutorial.skipTutorial(),
        );

      case TutorialStage.step4_tap_event_card:
        return InteractiveSpotlightOverlay(
          targetKey: tutorial.keyFirstEventCard,
          isTargetRound: false,
          padding: 4,
          stepTag: 'Tappa 2 di 4 • Entra nell\'Evento',
          title: 'Tocca la Scheda dell\'Evento!',
          description: 'Ottimo lavoro! Il tuo evento è ora nel feed. Toccalo per aprire i dettagli, visualizzare la classifica e proporre la prima regola.',
          onTargetTapped: () => _apriPrimoEvento(),
          onSkip: () => tutorial.skipTutorial(),
        );

      case TutorialStage.step7_view_votazioni:
        return _buildVotazioniLiveGuideOverlay();

      case TutorialStage.step8_tap_notification:
        return InteractiveSpotlightOverlay(
          targetKey: tutorial.keyNotifiche,
          isTargetRound: true,
          padding: 8,
          stepTag: 'Tappa 3 di 4 • Centro Notifiche',
          title: 'Tocca il Campanellino 🔔',
          description: 'Hai 1 notifica ufficiale! Tocca il campanellino per leggere il messaggio di benvenuto della Redazione e scoprire come gestire gli avvisi.',
          onTargetTapped: () => _apriNotifiche(),
          onSkip: () => tutorial.skipTutorial(),
        );

      case TutorialStage.step9_tap_profile:
        return InteractiveSpotlightOverlay(
          targetKey: tutorial.keyProfilo,
          isTargetRound: false,
          padding: 6,
          stepTag: 'Tappa 4 di 4 • Profilo Giocatore',
          title: 'Tocca il tuo Profilo 📸',
          description: 'Ci siamo quasi! Tocca il tuo profilo in alto a destra per scoprire il tuo Codice Amico, impostare la tua foto e riscuotere la ricompensa (+100 XP)!',
          onTargetTapped: () => _apriProfilo(),
          onSkip: () => tutorial.skipTutorial(),
        );

      default:
        return null;
    }
  }

  Widget _buildVotazioniLiveGuideOverlay() {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
        ),
        Center(
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: const TextStyle(decoration: TextDecoration.none),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.65), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                      blurRadius: 25,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'TAPPA 2 DI 4 • VOTAZIONE LIVE',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFFACC15),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.5,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        const Text('🗳️ DEMOCRAZIA', style: TextStyle(fontSize: 12, color: Color(0xFFC084FC), fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Ecco la tua proposta tra i Voti Live! 🎉',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Come vedi, la proposta è apparsa qui in tempo reale. Visto che l\'hai proposta tu, il tuo voto è già calcolato a favore.\n\nQuando giocherai con i tuoi amici, la votazione sarà democratica e servirà il raggiungimento del Quorum per approvarla ufficialmente!',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: const Color(0xFFE2E8F0),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              TutorialController.instance.setStage(TutorialStage.step8_tap_notification);
                            },
                            icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF0F172A), size: 18),
                            label: Text(
                              'AVANTI: VEDI NOTIFICHE 🔔',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                                decoration: TextDecoration.none,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFACC15),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () => TutorialController.instance.skipTutorial(),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          'Salta Tutorial',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            decoration: TextDecoration.underline,
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
      ],
    );
  }

  Widget _buildSpeedDialItem({
    Key? key,
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      key: key,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventiTab(String userNick) {
    Widget child;
    if (_eventi.isEmpty) {
      child = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_busy_rounded, size: 64, color: Color(0xFF64748B)),
                const SizedBox(height: 16),
                Text(
                  'Nessun evento disponibile',
                  style: GoogleFonts.poppins(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tocca + in basso per creare il primo evento!',
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      child = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _eventi.length,
        itemBuilder: (ctx, idx) {
          final ev = _eventi[idx];
          final tutorialEv = _eventi.cast<Evento?>().firstWhere(
            (e) => e != null && TutorialController.instance.isTutorialEvent(e),
            orElse: () => null,
          );
          final bool isTutorialTarget = TutorialController.instance.stage == TutorialStage.step4_tap_event_card &&
              (tutorialEv != null ? ev.id == tutorialEv.id : idx == 0);
          return Container(
            key: isTutorialTarget ? TutorialController.instance.keyFirstEventCard : null,
            child: EventCard(
              evento: ev,
              currentUserNickname: userNick,
              onTap: () async {
                if (TutorialController.instance.stage == TutorialStage.step4_tap_event_card &&
                    TutorialController.instance.isTutorialEvent(ev)) {
                  TutorialController.instance.setStage(TutorialStage.step5_in_event_detail);
                }
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EventDetailView(evento: ev, onRefresh: () => _loadData(forceRefresh: true))),
                );
                _loadData(forceRefresh: true);
              },
              onPartecipa: () => _partecipaEvento(ev),
              onElimina: () => _confermaEliminazioneEvento(ev),
            ),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      color: const Color(0xFFFACC15),
      backgroundColor: const Color(0xFF1E293B),
      child: child,
    );
  }

  Widget _buildBonusMalusTab() {
    final currentUserNick = _apiService.currentUser?.nome ?? 'Cloud';
    final cleanUser = currentUserNick.trim().toLowerCase();

    final activeEvents = _eventi.where((e) =>
      e.stato.trim().toLowerCase() != 'concluso' && !DateTime.now().isAfter(e.dataFine)
    ).toList();

    Widget child;
    if (activeEvents.isEmpty) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off_rounded, size: 64, color: Color(0xFF64748B)),
                const SizedBox(height: 16),
                Text(
                  'Nessuna cartella evento in corso',
                  style: GoogleFonts.poppins(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Crea o partecipa ad un evento attivo per sbloccare i suoi Bonus/Malus!',
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      child = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: activeEvents.length,
        itemBuilder: (ctx, idx) {
          final ev = activeEvents[idx];
          final cleanCreatore = (ev.creatore.isNotEmpty ? ev.creatore : ev.propostoDa).trim().toLowerCase();
          final isOrganizzatore = cleanCreatore == cleanUser;
          final isPartecipante = ev.partecipanti.any((p) => p.trim().toLowerCase() == cleanUser);

          // Filtra tutti i bonus/malus approvati per questo evento
          final approvedForEvent = _bonusMalusList.where((b) {
            final isSameEv = b.eventoId.trim().toLowerCase() == ev.id.trim().toLowerCase() ||
                b.eventoId.trim().toLowerCase() == ev.titolo.trim().toLowerCase();
            final isApprovato = b.stato == 'approvato' || b.stato == 'confermato' || b.approvato;
            final isMine = b.propostoDa.trim().toLowerCase() == cleanUser;
            return isSameEv && (isApprovato || isMine);
          }).toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.folder_special_rounded, color: Color(0xFFC084FC), size: 24),
                ),
                title: Text(
                  ev.titolo,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                subtitle: Text(
                  '${approvedForEvent.length} Bonus/Malus approvati • Org: ${ev.creatore.isNotEmpty ? ev.creatore : ev.propostoDa}',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: approvedForEvent.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Text(
                              'Nessun bonus o malus approvato al momento per questo evento.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                            ),
                          )
                        : Column(
                            children: approvedForEvent.map((bm) {
                              final isMine = bm.propostoDa.trim().toLowerCase() == cleanUser;
                              final isVarSanction = bm.categoria == 'VAR' || bm.titolo.contains('VAR');
                              return BonusMalusCard(
                                bonusMalus: bm,
                                onElimina: (isMine && !isVarSanction)
                                    ? () async {
                                        await _apiService.eliminaBonusMalus(bm.id);
                                        if (!mounted) return;
                                        AppToast.showSuccess(
                                          context,
                                          'Proposta Eliminata 🗑️',
                                          'Proposta Bonus/Malus eliminata con successo!',
                                        );
                                        _loadData();
                                      }
                                    : null,
                                onAssegna: (isOrganizzatore && !isVarSanction)
                                    ? () => _apriSelettoreAssegnazione(ev, bm)
                                    : null,
                                onRichiediVar: ((isPartecipante || isOrganizzatore) && !isVarSanction)
                                    ? () => _apriRichiestaVar(ev, bm)
                                    : null,
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      color: const Color(0xFFFACC15),
      backgroundColor: const Color(0xFF1E293B),
      child: child,
    );
  }

  ImageProvider? _cachedAvatarProvider;
  String? _cachedAvatarUrl;

  ImageProvider _getStableAvatarProvider(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return const AssetImage('assets/images/cloud.png');
    }
    if (avatarUrl != _cachedAvatarUrl) {
      _cachedAvatarUrl = avatarUrl;
      _cachedAvatarProvider = getAvatarImageProvider(avatarUrl);
    }
    return _cachedAvatarProvider!;
  }

  void _apriRichiestaVar(Evento ev, BonusMalus bm) {
    if (!ev.isInCorso) {
      AppToast.showInfo(
        context,
        'VAR non disponibile ⏳',
        'Il VAR è disponibile solo quando l\'evento è in corso!',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VarSubmissionModal(
        evento: ev,
        bonusMalus: bm,
        onSubmitted: () => _loadData(forceRefresh: true),
      ),
    );
  }

  void _apriSelettoreAssegnazione(Evento ev, BonusMalus bm) {
    if (!ev.isInCorso) {
      AppToast.showInfo(
        context,
        'Evento non in corso ⏳',
        ev.isConcluso
            ? 'Questo evento è concluso: le assegnazioni sono chiuse!'
            : 'L\'assegnazione dei punti è disponibile solo quando l\'evento è in corso!',
      );
      return;
    }

    final partecipanti = ev.partecipanti.isNotEmpty ? ev.partecipanti : ['Cloud', 'Ugnom'];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                        child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assegna "${bm.titolo}"',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            Text(
                              'Seleziona il partecipante all\'evento "${ev.titolo}"',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Partecipanti all\'evento (${partecipanti.length}):',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: partecipanti.length,
                      itemBuilder: (context, i) {
                        final part = partecipanti[i];
                        final giaAssegnato = bm.assegnatoA.any((u) => u.trim().toLowerCase() == part.trim().toLowerCase());

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF9333EA),
                              child: Text(part.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(part, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
                            trailing: (giaAssegnato && !bm.riassegnabileMoltepliciVolte)
                                ? ElevatedButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF94A3B8)),
                                    label: const Text('✓ Già assegnato'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF334155),
                                      foregroundColor: const Color(0xFF94A3B8),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: () async {
                                      final isBonus = bm.punti >= 0;
                                      final ptStr = isBonus ? '+${bm.punti}' : '${bm.punti}';
                                      final xpEarned = isBonus ? bm.punti * 10 : 0;

                                      final confermato = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogCtx) {
                                          return AlertDialog(
                                            backgroundColor: const Color(0xFF1E293B),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            title: Row(
                                              children: [
                                                const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 24),
                                                const SizedBox(width: 10),
                                                Text(
                                                  'Conferma Assegnazione',
                                                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                                ),
                                              ],
                                            ),
                                            content: Text(
                                              'L\'assegnazione del ${isBonus ? "bonus" : "malus"} "${bm.titolo}" comporterà per "$part" una modifica di $ptStr PT ed un incremento di +$xpEarned XP.\n\nSei sicuro di voler procedere?',
                                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1)),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(dialogCtx, false),
                                                child: Text('Annulla', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8))),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => Navigator.pop(dialogCtx, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF10B981),
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                child: Text('Sì, Assegna', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          );
                                        },
                                      );

                                      if (confermato != true) return;

                                      await _apiService.assegnaBonusMalusAPartecipante(
                                        eventoId: ev.id,
                                        bonusId: bm.id,
                                        utenteDestinatario: part,
                                        punti: bm.punti,
                                        eventoTitolo: ev.titolo,
                                        bonusTitolo: bm.titolo,
                                      );

                                      if (!bm.assegnatoA.any((u) => u.trim().toLowerCase() == part.trim().toLowerCase())) {
                                        bm.assegnatoA.add(part);
                                      }

                                      setModalState(() {});
                                      _loadData(silent: true, forceRefresh: true);

                                      if (!mounted) return;
                                      AppToast.showSuccess(
                                        context,
                                        'Regola Assegnata! 🏆',
                                        '${bm.punti >= 0 ? "Bonus" : "Malus"} "${bm.titolo}" (${bm.punti >= 0 ? "+${bm.punti}" : bm.punti} PT) assegnato con successo a $part!',
                                      );
                                      _loadData(forceRefresh: true);
                                    },
                                    icon: const Icon(Icons.check_rounded, size: 16),
                                    label: const Text('Assegna'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
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

  Widget _buildVotazioniTab() {
    final curUser = _apiService.currentUser;
    final cleanUser = (curUser?.nome ?? 'Cloud').trim().toLowerCase();
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanId = (curUser?.id ?? '').trim().toLowerCase();

    final activeVotazioni = _votazioniList.where((v) {
      final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';

      final evMatch = _eventi.firstWhere(
        (e) => (evId.isNotEmpty && (e.id.trim().toLowerCase() == evId || e.titolo.trim().toLowerCase() == evId)) ||
               (e.titolo.isNotEmpty && v.titolo.toLowerCase().contains(e.titolo.toLowerCase())) ||
               (e.titolo.isNotEmpty && v.descrizione.toLowerCase().contains(e.titolo.toLowerCase())),
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

      // REGOLA ASSOLUTA: Se l'evento non appartiene alla lista degli eventi dell'utente (_eventi),
      // significa che l'utente non è invitato e non partecipa: LA VOTAZIONE DEVE ESSERE ESCLUSA!
      if (evMatch.id.isEmpty) {
        return false;
      }

      // Se l'evento è concluso o scaduto, non fa più parte delle votazioni live
      if (evMatch.stato.trim().toLowerCase() == 'concluso' || DateTime.now().isAfter(evMatch.dataFine)) {
        return false;
      }

      // Verifica rigorosa di partecipazione: l'utente deve essere confermato come creatore, partecipante o invitato
      final cleanCreatore = (evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa).trim().toLowerCase();
      final pList = evMatch.partecipanti.map((p) => p.trim().toLowerCase()).toList();
      final iList = evMatch.invitati.map((p) => p.trim().toLowerCase()).toList();

      final bool isCoinvolto = cleanCreatore == cleanUser || cleanCreatore == cleanNick || cleanCreatore == cleanId ||
                               pList.contains(cleanUser) || pList.contains(cleanNick) || pList.contains(cleanId) ||
                               iList.contains(cleanUser) || iList.contains(cleanNick) || iList.contains(cleanId);

      if (!isCoinvolto) {
        return false;
      }

      return true;
    }).toList();

    final activeEventsWithVotes = _eventi.where((ev) {
      if (ev.isConcluso || DateTime.now().isAfter(ev.dataFine)) return false;
      return activeVotazioni.any((v) {
        final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
        return (evId.isNotEmpty && (ev.id.trim().toLowerCase() == evId || ev.titolo.trim().toLowerCase() == evId)) ||
               (ev.titolo.isNotEmpty && v.titolo.toLowerCase().contains(ev.titolo.toLowerCase())) ||
               (ev.titolo.isNotEmpty && v.descrizione.toLowerCase().contains(ev.titolo.toLowerCase()));
      });
    }).toList();

    Widget child;
    if (activeEventsWithVotes.isEmpty) {
      child = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Text(
              'Nessuna votazione attiva al momento per eventi in corso.',
              style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
            ),
          ),
        ),
      );
    } else {
      child = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: activeEventsWithVotes.length,
        itemBuilder: (ctx, idx) {
          final ev = activeEventsWithVotes[idx];
          final votesForEvent = activeVotazioni.where((v) {
            final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
            return (evId.isNotEmpty && (ev.id.trim().toLowerCase() == evId || ev.titolo.trim().toLowerCase() == evId)) ||
                   (ev.titolo.isNotEmpty && v.titolo.toLowerCase().contains(ev.titolo.toLowerCase())) ||
                   (ev.titolo.isNotEmpty && v.descrizione.toLowerCase().contains(ev.titolo.toLowerCase()));
          }).toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.how_to_vote_rounded, color: Color(0xFFFACC15), size: 24),
                ),
                title: Text(
                  ev.titolo,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                subtitle: Text(
                  '${votesForEvent.length} Votazioni attive • Org: ${ev.creatore.isNotEmpty ? ev.creatore : ev.propostoDa}',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: votesForEvent.map((v) {
                        return VoteCard(
                          votazione: v,
                          currentUserNickname: _apiService.currentUser?.nome ?? 'Cloud',
                          onVotaTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => VoteView(votazione: v)),
                            );
                            _loadData(forceRefresh: true);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      color: const Color(0xFFFACC15),
      backgroundColor: const Color(0xFF1E293B),
      child: child,
    );
  }
}
