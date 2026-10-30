import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
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
import '../services/push_notification_service.dart';
import '../viewmodels/home_view_model.dart';
import '../widgets/app_toast.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin, WidgetsBindingObserver {
  final HomeViewModel _viewModel = HomeViewModel();

  late TabController _tabController;

  // Controller e animazioni per lo Speed Dial FAB
  late AnimationController _fabAnimationController;
  late Animation<double> _fabRotationAnimation;
  late Animation<double> _fabMenuAnimation;
  late Animation<Offset> _fabSlideAnimation;
  bool _isFabMenuOpen = false;

  // Filtro Tab 1: Feed Eventi
  String _filtroFeedEventi = 'tutti'; // 'tutti', 'in_corso', 'in_programma', 'conclusi'

  // Filtri Tab 2: Bonus & Malus per cartella evento
  final Map<String, String> _bmSearchQueries = {};
  final Map<String, String> _bmTipoFiltri = {}; // 'tutti', 'bonus', 'malus'
  final Map<String, bool> _bmSoloRiassegnabili = {}; // true/false
  final Map<String, int?> _bmFiltroPunti = {}; // null per tutti, altrimenti valore assoluto punti
  final Map<String, TextEditingController> _bmSearchControllers = {};

  TextEditingController _getSearchControllerForEvent(String eventId) {
    return _bmSearchControllers.putIfAbsent(
      eventId,
      () => TextEditingController(text: _bmSearchQueries[eventId] ?? ''),
    );
  }

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

    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.instance.onNotificationReceived = () {
      if (mounted) {
        _viewModel.refreshNotifications();
      }
    };
    _viewModel.inizializza();
    _checkInitialModals();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _viewModel.loadData(forceRefresh: true, silent: true);
    }
  }

  Future<void> _checkInitialModals() async {
    final shouldShowInactive = await _viewModel.checkShouldShowLongTermInactivity();
    if (shouldShowInactive && mounted) {
      _mostraModaleBentornato(_viewModel.currentUserNick);
    }
    final shouldShowGuide = await _viewModel.shouldShowInitialGuide();
    if (shouldShowGuide && mounted) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        final startTutorial = await GuidaRegolamentoModal.mostra(context, isFirstAccess: true);
        if (startTutorial == true && mounted) {
          _avviaTutorialGuidato();
        }
      }
    }
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

  Future<void> _loadData({bool silent = false, bool forceRefresh = false}) async {
    await _viewModel.loadData(silent: silent, forceRefresh: forceRefresh);
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
    if (_viewModel.eventi.isEmpty) return;
    final ev = _viewModel.eventi.firstWhere(
      (e) => TutorialController.instance.isTutorialEvent(e),
      orElse: () => _viewModel.eventi.first,
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
        _riprendiTutorialDaHome();
      });
    }
    if (mounted) {
      setState(() {});
      _loadData(silent: true, forceRefresh: true);
    }
  }

  Future<void> _riprendiTutorialDaHome() async {
    final savedStage = await TutorialController.instance.getSavedStage();
    final savedEvId = await TutorialController.instance.getSavedEventId();
    if (savedEvId != null && savedEvId.isNotEmpty) {
      TutorialController.instance.tutorialCreatedEventId = savedEvId;
    }

    if (savedStage == null || savedStage == TutorialStage.idle || savedStage == TutorialStage.step1_tap_plus) {
      TutorialController.instance.startTutorial();
      return;
    }

    if (savedStage == TutorialStage.step2_tap_crea_evento) {
      TutorialController.instance.setStage(TutorialStage.step2_tap_crea_evento);
      if (!_isFabMenuOpen) _toggleFabMenu();
      return;
    }

    if (savedStage == TutorialStage.step3_in_create_event) {
      _apriCreaEvento();
      return;
    }

    if (savedStage == TutorialStage.step4_tap_event_card) {
      TutorialController.instance.setStage(TutorialStage.step4_tap_event_card);
      return;
    }

    if (savedStage == TutorialStage.step5_in_event_detail || savedStage == TutorialStage.step6_in_add_bonus) {
      Evento? targetEvent;
      if (_viewModel.eventi.isNotEmpty) {
        targetEvent = _viewModel.eventi.firstWhere(
          (e) => TutorialController.instance.isTutorialEvent(e),
          orElse: () => _viewModel.eventi.first,
        );
      }
      if (targetEvent != null) {
        if (!mounted) return;
        if (savedStage == TutorialStage.step5_in_event_detail) {
          TutorialController.instance.setStage(TutorialStage.step5_in_event_detail);
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EventDetailView(evento: targetEvent!, onRefresh: () => _loadData(forceRefresh: true))),
          );
        } else {
          TutorialController.instance.setStage(TutorialStage.step6_in_add_bonus);
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddBonusMalusView(evento: targetEvent)),
          );
        }
      } else {
        TutorialController.instance.startTutorial();
      }
      return;
    }

    if (savedStage == TutorialStage.step7_view_votazioni) {
      TutorialController.instance.setStage(TutorialStage.step7_view_votazioni);
      if (_tabController.index != 2) _tabController.animateTo(2);
      return;
    }

    if (savedStage == TutorialStage.step8_tap_notification) {
      TutorialController.instance.setStage(TutorialStage.step8_tap_notification);
      return;
    }

    if (savedStage == TutorialStage.step9_tap_profile) {
      TutorialController.instance.setStage(TutorialStage.step9_tap_profile);
      return;
    }

    if (savedStage == TutorialStage.step10_in_profile) {
      _apriProfilo();
      return;
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
    final nick = _viewModel.currentUserNick;
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
                        await _viewModel.eliminaEvento(evId, nick);
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
    final nick = _viewModel.currentUserNick;

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
      await _viewModel.partecipaAdEvento(evento.id, nick);
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
    WidgetsBinding.instance.removeObserver(this);
    TutorialController.instance.removeListener(_onTutorialChanged);
    for (final c in _bmSearchControllers.values) {
      c.dispose();
    }
    _viewModel.dispose();
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
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final curUser = _viewModel.currentUser;
        final userNick = _viewModel.currentUserNick;

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
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(1.5),
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
                  'assets/icon/fantaeventi_header_logo.jpg',
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
                if (_viewModel.numeroNotifiche > 0 || TutorialController.instance.stage == TutorialStage.step8_tap_notification)
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
                        '${_viewModel.numeroNotifiche > 0 ? _viewModel.numeroNotifiche : 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 2),

          // Profile User Chip (Foto Profilo reale + Livello) + Pallino rosso tutorial incompleto
          Stack(
            clipBehavior: Clip.none,
            children: [
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
              if (curUser != null && !curUser.haVistoGuida)
                Positioned(
                  top: -2,
                  right: 8,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1E293B), width: 1.8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xAAEF4444),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
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
          _viewModel.isLoading
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
      },
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

  String _getNomeFiltroEventi(String filtro) {
    switch (filtro) {
      case 'in_corso':
        return 'in corso';
      case 'in_programma':
        return 'in programma';
      case 'conclusi':
        return 'concluso';
      default:
        return '';
    }
  }

  Widget _buildFeedEventiFilterBar(List<Evento> tuttiEventi) {
    final countTutti = tuttiEventi.length;
    final countInCorso = tuttiEventi.where((e) => e.isInCorso).length;
    final countInProgramma = tuttiEventi.where((e) => e.isInProgramma).length;
    final countConclusi = tuttiEventi.where((e) => e.isConcluso).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildEventFilterChip(
              id: 'tutti',
              label: 'Tutti',
              count: countTutti,
              icon: Icons.all_inclusive_rounded,
              accentColor: const Color(0xFF818CF8),
            ),
            const SizedBox(width: 8),
            _buildEventFilterChip(
              id: 'in_corso',
              label: 'In Corso',
              count: countInCorso,
              icon: Icons.play_circle_fill_rounded,
              accentColor: const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            _buildEventFilterChip(
              id: 'in_programma',
              label: 'In Programma',
              count: countInProgramma,
              icon: Icons.schedule_rounded,
              accentColor: const Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            _buildEventFilterChip(
              id: 'conclusi',
              label: 'Conclusi',
              count: countConclusi,
              icon: Icons.check_circle_rounded,
              accentColor: const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventFilterChip({
    required String id,
    required String label,
    required int count,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _filtroFeedEventi == id;
    return InkWell(
      onTap: () {
        setState(() {
          _filtroFeedEventi = id;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.2) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? accentColor : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? accentColor.withValues(alpha: 0.35) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventiTab(String userNick) {
    final tuttiEventi = _viewModel.eventi;
    final networkError = _viewModel.networkError;

    if (tuttiEventi.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: const Color(0xFFFACC15),
        backgroundColor: const Color(0xFF1E293B),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    networkError ? Icons.wifi_off_rounded : Icons.event_busy_rounded,
                    size: 64,
                    color: networkError ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    networkError ? 'Connessione non disponibile' : 'Nessun evento disponibile',
                    style: GoogleFonts.poppins(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    networkError
                        ? 'Verifica la tua connessione internet o riprova tra poco.'
                        : 'Tocca + in basso per creare il primo evento!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  ),
                  if (networkError) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _loadData(forceRefresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        'RIPROVA 🔄',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFACC15),
                        foregroundColor: const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Filtraggio in-memory istantaneo
    final filteredEventi = tuttiEventi.where((ev) {
      if (_filtroFeedEventi == 'in_corso') return ev.isInCorso;
      if (_filtroFeedEventi == 'in_programma') return ev.isInProgramma;
      if (_filtroFeedEventi == 'conclusi') return ev.isConcluso;
      return true;
    }).toList();

    return Column(
      children: [
        // Barra dei filtri feed eventi
        _buildFeedEventiFilterBar(tuttiEventi),

        // Lista eventi filtrati o messaggio vuoto con RefreshIndicator diretto sul contenuto scrollabile
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadData(forceRefresh: true),
            color: const Color(0xFFFACC15),
            backgroundColor: const Color(0xFF1E293B),
            child: filteredEventi.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.filter_alt_off_rounded, size: 54, color: Color(0xFF64748B)),
                            const SizedBox(height: 12),
                            Text(
                              'Nessun evento ${_getNomeFiltroEventi(_filtroFeedEventi)}',
                              style: GoogleFonts.poppins(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Non sono presenti eventi in questo stato al momento.',
                              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _filtroFeedEventi = 'tutti';
                                });
                              },
                              icon: const Icon(Icons.clear_all_rounded, size: 18),
                              label: Text('MOSTRA TUTTI GLI EVENTI', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: filteredEventi.length,
                    itemBuilder: (ctx, idx) {
                      final ev = filteredEventi[idx];
                      final tutorialEv = tuttiEventi.cast<Evento?>().firstWhere(
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
                            final cleanUser = userNick.trim().toLowerCase();
                            final cleanCreator = ev.creatore.trim().toLowerCase();
                            final bool isCreatore = cleanCreator.isNotEmpty &&
                                (cleanCreator == cleanUser ||
                                 (cleanUser == 'cloud' && (cleanCreator == 'claudio' || cleanCreator.contains('claudio'))) ||
                                 (cleanUser == 'claudio' && cleanCreator == 'cloud'));

                            final bool isPartecipante = isCreatore || ev.partecipanti.any((p) {
                              final pClean = p.trim().toLowerCase();
                              return pClean == cleanUser ||
                                  (cleanUser == 'cloud' && (pClean == 'claudio' || pClean.contains('claudio'))) ||
                                  (cleanUser == 'claudio' && pClean == 'cloud');
                            });

                            if (!isPartecipante && (ev.isInCorso || ev.isConcluso)) {
                              AppToast.showWarning(
                                context,
                                'Iscrizioni Chiuse',
                                'Non puoi accedere a questo evento: le iscrizioni si sono chiuse con l\'inizio dell\'evento.',
                              );
                              return;
                            }

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
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBMFilterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.25) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF334155),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildBonusMalusFolderFilters(Evento ev, List<BonusMalus> approvedForEvent) {
    final searchCtrl = _getSearchControllerForEvent(ev.id);
    final currentQuery = _bmSearchQueries[ev.id] ?? '';
    final currentTipo = _bmTipoFiltri[ev.id] ?? 'tutti';
    final soloRiassegnabili = _bmSoloRiassegnabili[ev.id] ?? false;
    final filtroPunti = _bmFiltroPunti[ev.id];

    // Punteggi unici presenti in questo evento
    final uniquePoints = approvedForEvent
        .map((b) => b.punti.abs())
        .where((p) => p > 0)
        .toSet()
        .toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Barra di ricerca per titolo o descrizione
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: TextField(
            controller: searchCtrl,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            onChanged: (val) {
              setState(() {
                _bmSearchQueries[ev.id] = val;
              });
            },
            decoration: InputDecoration(
              hintText: 'Cerca bonus o malus (nome o descrizione)...',
              hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF818CF8), size: 18),
              suffixIcon: currentQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 16),
                      onPressed: () {
                        setState(() {
                          _bmSearchQueries[ev.id] = '';
                          searchCtrl.clear();
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              isDense: true,
            ),
          ),
        ),

        // 2. Chip Filtri (Scroll orizzontale privo di overflow)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // Chip Tipo: TUTTI
              _buildBMFilterChip(
                label: 'Tutti',
                isSelected: currentTipo == 'tutti' && !soloRiassegnabili && filtroPunti == null,
                color: const Color(0xFF818CF8),
                onTap: () {
                  setState(() {
                    _bmTipoFiltri[ev.id] = 'tutti';
                    _bmSoloRiassegnabili[ev.id] = false;
                    _bmFiltroPunti[ev.id] = null;
                  });
                },
              ),
              const SizedBox(width: 6),

              // Chip Tipo: BONUS (+)
              _buildBMFilterChip(
                label: 'Bonus (+)',
                isSelected: currentTipo == 'bonus',
                color: const Color(0xFF10B981),
                onTap: () {
                  setState(() {
                    _bmTipoFiltri[ev.id] = currentTipo == 'bonus' ? 'tutti' : 'bonus';
                  });
                },
              ),
              const SizedBox(width: 6),

              // Chip Tipo: MALUS (-)
              _buildBMFilterChip(
                label: 'Malus (-)',
                isSelected: currentTipo == 'malus',
                color: const Color(0xFFEF4444),
                onTap: () {
                  setState(() {
                    _bmTipoFiltri[ev.id] = currentTipo == 'malus' ? 'tutti' : 'malus';
                  });
                },
              ),
              const SizedBox(width: 6),

              // Chip: SOLO RIASSEGNABILI 🔁
              _buildBMFilterChip(
                label: 'Riassegnabili 🔁',
                isSelected: soloRiassegnabili,
                color: const Color(0xFFA855F7),
                onTap: () {
                  setState(() {
                    _bmSoloRiassegnabili[ev.id] = !soloRiassegnabili;
                  });
                },
              ),

              // Chips per punteggio specifico (es. 10 PT, 20 PT, 50 PT)
              if (uniquePoints.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  height: 16,
                  width: 1,
                  color: const Color(0xFF334155),
                ),
                const SizedBox(width: 8),
                for (final pts in uniquePoints) ...[
                  _buildBMFilterChip(
                    label: '$pts PT',
                    isSelected: filtroPunti == pts,
                    color: const Color(0xFFFACC15),
                    onTap: () {
                      setState(() {
                        _bmFiltroPunti[ev.id] = filtroPunti == pts ? null : pts;
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildBonusMalusTab() {
    final cleanUser = _viewModel.currentUserNick.trim().toLowerCase();
    final activeEvents = _viewModel.activeEvents;

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
          final isOrganizzatore = cleanCreatore == cleanUser ||
              (cleanUser == 'cloud' && (cleanCreatore == 'claudio' || cleanCreatore.contains('claudio'))) ||
              (cleanUser == 'claudio' && cleanCreatore == 'cloud');
          final isPartecipante = ev.partecipanti.any((p) {
            final pClean = p.trim().toLowerCase();
            return pClean == cleanUser ||
                (cleanUser == 'cloud' && (pClean == 'claudio' || pClean.contains('claudio'))) ||
                (cleanUser == 'claudio' && pClean == 'cloud');
          });

          final approvedForEvent = _viewModel.getApprovedBonusMalusForEvent(ev, cleanUser);

          // Filtraggio in-memory locale per la cartella di questo evento
          final query = (_bmSearchQueries[ev.id] ?? '').trim().toLowerCase();
          final tipo = _bmTipoFiltri[ev.id] ?? 'tutti';
          final soloRiassegnabili = _bmSoloRiassegnabili[ev.id] ?? false;
          final filtroPunti = _bmFiltroPunti[ev.id];

          final filteredForEvent = approvedForEvent.where((bm) {
            if (tipo == 'bonus' && !bm.isBonus) return false;
            if (tipo == 'malus' && bm.isBonus) return false;
            if (soloRiassegnabili && !bm.riassegnabileMoltepliciVolte) return false;
            if (filtroPunti != null && bm.punti.abs() != filtroPunti) return false;
            if (query.isNotEmpty) {
              final tMatch = bm.titolo.toLowerCase().contains(query);
              final dMatch = bm.descrizione.toLowerCase().contains(query);
              if (!tMatch && !dMatch) return false;
            }
            return true;
          }).toList();

          final bool hasActiveFilter = query.isNotEmpty || tipo != 'tutti' || soloRiassegnabili || filtroPunti != null;

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
                  hasActiveFilter
                      ? '${filteredForEvent.length} di ${approvedForEvent.length} filtrati • Org: ${ev.creatore.isNotEmpty ? ev.creatore : ev.propostoDa}'
                      : '${approvedForEvent.length} Bonus/Malus approvati • Org: ${ev.creatore.isNotEmpty ? ev.creatore : ev.propostoDa}',
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Barra di ricerca e filtri chip per questa cartella
                              _buildBonusMalusFolderFilters(ev, approvedForEvent),

                              if (filteredForEvent.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.search_off_rounded, size: 36, color: Color(0xFF64748B)),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Nessun elemento trovato',
                                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Nessun bonus o malus corrisponde ai criteri cercati.',
                                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _bmSearchQueries[ev.id] = '';
                                            _bmTipoFiltri[ev.id] = 'tutti';
                                            _bmSoloRiassegnabili[ev.id] = false;
                                            _bmFiltroPunti[ev.id] = null;
                                            _bmSearchControllers[ev.id]?.clear();
                                          });
                                        },
                                        icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFFFACC15)),
                                        label: Text(
                                          'Reimposta filtri',
                                          style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFFACC15), fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Column(
                                  children: filteredForEvent.map((bm) {
                                    final isVarSanction = bm.categoria == 'VAR' || bm.titolo.contains('VAR');
                                    return BonusMalusCard(
                                      bonusMalus: bm,
                                      onElimina: null,
                                      onAssegna: (isOrganizzatore && !isVarSanction)
                                          ? () => _apriSelettoreAssegnazione(ev, bm)
                                          : null,
                                      onRichiediVar: ((isPartecipante || isOrganizzatore) && !isVarSanction)
                                          ? () => _apriRichiestaVar(ev, bm)
                                          : null,
                                    );
                                  }).toList(),
                                ),
                            ],
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
    if (avatarUrl == null || avatarUrl.isEmpty || avatarUrl.contains('pravatar') || avatarUrl.contains('unsplash.com/photo-1535713875002')) {
      return const AssetImage('assets/icon/app_icon.jpg');
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

                                      try {
                                        await _viewModel.assegnaBonusMalusAPartecipante(
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

                                        // Chiude il selettore bottom sheet per visualizzare la Home e il toast di conferma
                                        Navigator.of(ctx).pop();

                                        if (!mounted) return;
                                        AppToast.showSuccess(
                                          this.context,
                                          'Regola Assegnata! 🏆',
                                          '${bm.punti >= 0 ? "Bonus" : "Malus"} "${bm.titolo}" (${bm.punti >= 0 ? "+${bm.punti}" : bm.punti} PT) assegnato con successo a $part!',
                                        );
                                        _loadData(forceRefresh: true);
                                      } catch (e) {
                                        if (!mounted) return;
                                        AppToast.showError(
                                          modalContext,
                                          'Errore Assegnazione',
                                          e.toString().replaceAll('Exception: ', ''),
                                        );
                                      }
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
    final curUser = _viewModel.currentUser;
    final cleanUser = (curUser?.nickname.isNotEmpty == true ? curUser!.nickname : (curUser?.nome ?? 'Cloud')).trim().toLowerCase();
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanId = (curUser?.id ?? '').trim().toLowerCase();

    final activeVotazioni = _viewModel.getActiveVotazioni(cleanUser, cleanNick, cleanId);
    final activeEventsWithVotes = _viewModel.getActiveEventsWithVotes(activeVotazioni);

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
          final votesForEvent = _viewModel.getVotesForEvent(ev, activeVotazioni);

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
                          currentUserNickname: _viewModel.currentUserNick,
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
