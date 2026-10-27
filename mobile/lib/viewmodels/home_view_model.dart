import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../models/votazione.dart';
import '../models/utente.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/tutorial_controller.dart';
import 'base_view_model.dart';

/// ViewModel dedicato alla schermata Home e Feed Eventi (MVVM).
///
/// Separa completamente:
/// - Polling periodico dei dati in background (timer 12s)
/// - Stato degli Eventi, Bonus & Malus e Votazioni Live
/// - Conteggio badge notifiche non lette
/// - Sincronizzazione MongoDB ordinata per prevenire conflitti di socket
/// - Verifica dell'inattività prolungata (> 180 giorni)
/// - Filtro degli eventi attivi, votazioni attive e regole approvate
class HomeViewModel extends BaseViewModel {
  final ApiService _apiService;
  final PushNotificationService _pushService;

  HomeViewModel({
    ApiService? apiService,
    PushNotificationService? pushService,
  })  : _apiService = apiService ?? ApiService(),
        _pushService = pushService ?? PushNotificationService.instance;

  List<Evento> _eventi = [];
  List<BonusMalus> _bonusMalusList = [];
  List<Votazione> _votazioniList = [];
  int _numeroNotifiche = 0;
  bool _networkError = false;

  Timer? _liveSyncTimer;
  bool _isFetchingData = false;
  final Set<String> _readNotificaIds = {};
  String? _lastCheckedUserGuida;

  // --- GETTER STATO ---
  List<Evento> get eventi => List.unmodifiable(_eventi);
  List<BonusMalus> get bonusMalusList => List.unmodifiable(_bonusMalusList);
  List<Votazione> get votazioniList => List.unmodifiable(_votazioniList);
  int get numeroNotifiche => _numeroNotifiche;
  bool get networkError => _networkError;
  Utente? get currentUser => _apiService.currentUser;
  String get currentUserNick {
    final u = _apiService.currentUser;
    if (u == null) return 'Cloud';
    if (u.nickname.isNotEmpty) return u.nickname;
    if (u.nome.isNotEmpty) return u.nome;
    return 'Cloud';
  }

  // --- INIZIALIZZAZIONE & TIMERS ---
  void inizializza() {
    // Se ci sono già dati caricati in ApiService o in memoria, mostrali istantaneamente a zero attesa!
    if (_apiService.eventi.isNotEmpty) {
      _eventi = List<Evento>.from(_apiService.eventi);
      _bonusMalusList = List<BonusMalus>.from(_apiService.bonusMalusList);
      _votazioniList = List<Votazione>.from(_apiService.votazioniList);
      notifyListeners();
    }
    loadData(forceRefresh: true, silent: _eventi.isNotEmpty);
    _checkLongTermInactivity();
    _startLiveSyncTimer();
  }

  void _startLiveSyncTimer() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      loadData(silent: true, forceRefresh: false);
    });
  }

  Future<bool> _checkLongTermInactivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActiveMs = prefs.getInt('ultimo_accesso_effettivo_timestamp');
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      bool isInactive = false;
      if (lastActiveMs != null) {
        final diffDays = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastActiveMs)).inDays;
        if (diffDays >= 180) {
          isInactive = true;
        }
      }

      await prefs.setInt('ultimo_accesso_effettivo_timestamp', nowMs);
      return isInactive;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkShouldShowLongTermInactivity() async {
    return await _checkLongTermInactivity();
  }

  // --- CARICAMENTO DATI ---
  Future<void> loadData({bool silent = false, bool forceRefresh = false}) async {
    if (_isFetchingData && !forceRefresh) return;
    _isFetchingData = true;

    try {
      if (forceRefresh) {
        _apiService.invalidateCache();
      }
      // 1. Il self-healing dell'utente e delle amicizie viene eseguito in background
      //    SENZA bloccare l'interfaccia o far attendere l'utente davanti allo spinner!
      unawaited(_apiService.syncCurrentUserFromDb());

      final bool hasExistingData = _eventi.isNotEmpty;
      if (!silent && !hasExistingData) {
        setLoading(true);
      }

      // 2. Caricamento prioritario immediato degli eventi
      final meEventi = await _apiService.getEventi(forceRefresh: forceRefresh);
      if (isDisposed) return;
      _eventi = List<Evento>.from(meEventi);

      // Sblocca SUBITO la schermata: gli eventi appaiono all'istante!
      if (!silent && !hasExistingData) {
        setLoading(false);
        notifyListeners();
      }

      // 3. Caricamento sequenziale protetto per socket MongoDB delle risorse di supporto
      await _apiService.getUtenti();
      final meVoti = await _apiService.getVotazioni();
      final meBonus = _apiService.bonusMalusList;

      final curUser = _apiService.currentUser;
      final nick = (curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome) ?? 'Cloud';
      final nots = await _apiService.getNotifiche(nick);
      final unreadNots = nots.where((n) {
        final nId = (n['id'] ?? '').toString();
        if (nId.isNotEmpty && _readNotificaIds.contains(nId)) return false;
        if (n['letto'] == true || n['stato'] == 'letto') return false;
        return true;
      }).toList();

      final inAttesa = unreadNots.length;

      if (isDisposed) return;

      _bonusMalusList = List<BonusMalus>.from(meBonus);
      _votazioniList = List<Votazione>.from(meVoti);
      _numeroNotifiche = inAttesa;
      _networkError = false;

      notifyListeners();
      unawaited(_pushService.syncCurrentDeviceToken());
    } catch (e) {
      if (_eventi.isEmpty) {
        _networkError = true;
      }
      setLoading(false);
      notifyListeners();
    } finally {
      _isFetchingData = false;
    }
  }

  /// Aggiorna istantaneamente il contatore notifiche non lette per la campanellina
  Future<void> refreshNotifications() async {
    final curUser = _apiService.currentUser;
    if (curUser == null) return;
    final nick = curUser.nickname.isNotEmpty ? curUser.nickname : curUser.nome;
    final nots = await _apiService.getNotifiche(nick);
    final unreadNots = nots.where((n) {
      final nId = (n['id'] ?? '').toString();
      if (nId.isNotEmpty && _readNotificaIds.contains(nId)) return false;
      if (n['letto'] == true || n['stato'] == 'letto') return false;
      return true;
    }).toList();
    _numeroNotifiche = unreadNots.length;
    notifyListeners();
  }

  // --- CONTROLLO GUIDA REGOLE ---
  Future<bool> shouldShowInitialGuide() async {
    final curUser = _apiService.currentUser;
    if (curUser == null) return false;
    final userKey = curUser.id.isNotEmpty ? curUser.id : curUser.nome.trim().toLowerCase();
    if (_lastCheckedUserGuida == userKey) return false;

    final seen = await _apiService.haVistoGuidaRegole(userKey);
    if (seen) {
      _lastCheckedUserGuida = userKey;
      return false;
    }

    final savedStage = await TutorialController.instance.getSavedStage();
    if (savedStage != null && savedStage != TutorialStage.idle) {
      _lastCheckedUserGuida = userKey;
      return false;
    }

    _lastCheckedUserGuida = userKey;
    return true;
  }

  // --- FILTRI & LOGICA DI PRESENTAZIONE ---
  List<Evento> get activeEvents {
    return _eventi.where((e) =>
      e.stato.trim().toLowerCase() != 'concluso' && !DateTime.now().isAfter(e.dataFine)
    ).toList();
  }

  List<BonusMalus> getApprovedBonusMalusForEvent(Evento ev, String cleanUser) {
    return _bonusMalusList.where((b) {
      final isSameEv = b.eventoId.trim().toLowerCase() == ev.id.trim().toLowerCase() ||
          b.eventoId.trim().toLowerCase() == ev.titolo.trim().toLowerCase();
      final isApprovato = b.stato == 'approvato' || b.stato == 'confermato' || b.approvato;
      final isMine = b.propostoDa.trim().toLowerCase() == cleanUser;
      return isSameEv && (isApprovato || isMine);
    }).toList();
  }

  List<Votazione> getActiveVotazioni(String cleanUser, String cleanNick, String cleanId) {
    return _votazioniList.where((v) {
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

      if (evMatch.id.isEmpty) return false;
      if (evMatch.stato.trim().toLowerCase() == 'concluso' || DateTime.now().isAfter(evMatch.dataFine)) return false;

      final cleanCreatore = (evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa).trim().toLowerCase();
      final pList = evMatch.partecipanti.map((p) => p.trim().toLowerCase()).toList();
      final iList = evMatch.invitati.map((p) => p.trim().toLowerCase()).toList();

      final bool isCoinvolto = cleanCreatore == cleanUser || cleanCreatore == cleanNick || cleanCreatore == cleanId ||
                               pList.contains(cleanUser) || pList.contains(cleanNick) || pList.contains(cleanId) ||
                               iList.contains(cleanUser) || iList.contains(cleanNick) || iList.contains(cleanId);

      return isCoinvolto;
    }).toList();
  }

  List<Evento> getActiveEventsWithVotes(List<Votazione> activeVotazioni) {
    return _eventi.where((ev) {
      if (ev.isConcluso || DateTime.now().isAfter(ev.dataFine)) return false;
      return activeVotazioni.any((v) {
        final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
        return (evId.isNotEmpty && (ev.id.trim().toLowerCase() == evId || ev.titolo.trim().toLowerCase() == evId)) ||
               (ev.titolo.isNotEmpty && v.titolo.toLowerCase().contains(ev.titolo.toLowerCase())) ||
               (ev.titolo.isNotEmpty && v.descrizione.toLowerCase().contains(ev.titolo.toLowerCase()));
      });
    }).toList();
  }

  List<Votazione> getVotesForEvent(Evento ev, List<Votazione> activeVotazioni) {
    return activeVotazioni.where((v) {
      final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
      return (evId.isNotEmpty && (ev.id.trim().toLowerCase() == evId || ev.titolo.trim().toLowerCase() == evId)) ||
             (ev.titolo.isNotEmpty && v.titolo.toLowerCase().contains(ev.titolo.toLowerCase())) ||
             (ev.titolo.isNotEmpty && v.descrizione.toLowerCase().contains(ev.titolo.toLowerCase()));
    }).toList();
  }

  // --- AZIONI SUI DATI ---
  Future<void> eliminaEvento(String eventoId, String nick) async {
    await _apiService.eliminaEvento(eventoId, nick);
    _eventi = _eventi.where((e) => e.id != eventoId).toList();
    _bonusMalusList = _bonusMalusList.where((b) => b.eventoId != eventoId && b.id != eventoId).toList();
    _votazioniList = _votazioniList.where((v) => v.bonusMalus?.eventoId != eventoId && v.id != eventoId).toList();
    notifyListeners();
  }

  Future<void> partecipaAdEvento(String eventoId, String nick) async {
    await _apiService.partecipaAdEvento(eventoId, nick);
  }

  Future<void> eliminaBonusMalus(String bonusId) async {
    await _apiService.eliminaBonusMalus(bonusId);
    _bonusMalusList = _bonusMalusList.where((b) => b.id != bonusId).toList();
    notifyListeners();
  }

  Future<void> assegnaBonusMalusAPartecipante({
    required String eventoId,
    required String bonusId,
    required String utenteDestinatario,
    required int punti,
    required String eventoTitolo,
    required String bonusTitolo,
  }) async {
    await _apiService.assegnaBonusMalusAPartecipante(
      eventoId: eventoId,
      bonusId: bonusId,
      utenteDestinatario: utenteDestinatario,
      punti: punti,
      eventoTitolo: eventoTitolo,
      bonusTitolo: bonusTitolo,
    );
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    super.dispose();
  }
}
