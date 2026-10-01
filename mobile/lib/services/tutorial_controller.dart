import 'package:flutter/material.dart';
import 'api_service.dart';

enum TutorialStage {
  idle,
  step1_tap_plus,           // Home: Highlight '+' FAB
  step2_tap_crea_evento,    // Home: Highlight 'Crea Evento' Speed Dial option
  step3_in_create_event,    // CreateEventView: Banner guide
  step4_tap_event_card,     // Home: Highlight newly created event card
  step5_in_event_detail,    // EventDetailView: Highlight 'PROPONI BONUS'
  step6_in_add_bonus,       // AddBonusMalusView: Banner guide for proposal & auto-PRO
  step7_view_votazioni,     // Home: Switch to Votazioni tab & view live vote
  step8_tap_notification,   // Home: Highlight Notification bell
  step9_tap_profile,        // Home: Highlight Profile chip in AppBar
  step10_in_profile,        // ProfileView: Guide for Photo & Codice Amico
}

class TutorialController extends ChangeNotifier {
  static final TutorialController instance = TutorialController._internal();
  TutorialController._internal();

  TutorialStage _stage = TutorialStage.idle;
  TutorialStage get stage => _stage;

  bool get isActive => _stage != TutorialStage.idle;

  // Global Keys for targets
  final GlobalKey keyFabPlus = GlobalKey();
  final GlobalKey keyCreaEventoItem = GlobalKey();
  final GlobalKey keyFirstEventCard = GlobalKey();
  final GlobalKey keyProponiBonus = GlobalKey();
  final GlobalKey keyNotifiche = GlobalKey();
  final GlobalKey keyProfilo = GlobalKey();
  final GlobalKey keyCodiceAmico = GlobalKey();
  final GlobalKey keyFotoProfilo = GlobalKey();

  bool isReplay = false;
  String? tutorialCreatedEventId;

  void startTutorial({bool? isReplay}) {
    _stage = TutorialStage.step1_tap_plus;
    final user = ApiService().currentUser;
    final nick = user?.nome ?? 'Cloud';
    
    final bool alreadyDone = ApiService().hasRedeemedTutorialLocally || (user?.haVistoGuida ?? false);
    this.isReplay = isReplay ?? alreadyDone;
    tutorialCreatedEventId = null;

    ApiService().assicuraNotificaBenvenuto(nick);
    notifyListeners();
  }

  void setStage(TutorialStage newStage) {
    if (_stage != newStage) {
      _stage = newStage;
      notifyListeners();
    }
  }

  void rollbackFromEventDetail() {
    if (_stage == TutorialStage.step5_in_event_detail) {
      _stage = TutorialStage.step4_tap_event_card;
      notifyListeners();
    }
  }

  bool isTutorialEvent(dynamic evento) {
    if (evento == null) return false;
    final String evId = (evento.id ?? '').toString();
    final String evTitolo = (evento.titolo ?? '').toString().toLowerCase();

    // 1. Se abbiamo memorizzato l'ID reale dell'evento creato in questo ciclo di tutorial
    if (tutorialCreatedEventId != null && tutorialCreatedEventId!.isNotEmpty) {
      if (evId == tutorialCreatedEventId) return true;
      // Se non coincide con l'ID ma il titolo è Festa di Benvenuto, è un residuo di un tutorial precedente
      if (evTitolo.contains('festa di benvenuto')) return false;
    }

    // 2. Fallback sul titolo per sincronizzare l'ID al primo passaggio
    final bool isTitleMatch = evTitolo.contains('festa di benvenuto');
    if (isTitleMatch && evId.isNotEmpty && (tutorialCreatedEventId == null || tutorialCreatedEventId!.isEmpty)) {
      tutorialCreatedEventId = evId;
    }
    return isTitleMatch;
  }

  void skipTutorial() {
    _stage = TutorialStage.idle;
    tutorialCreatedEventId = null;
    isReplay = false;
    notifyListeners();
  }

  void completeTutorial(BuildContext context) {
    _stage = TutorialStage.idle;
    tutorialCreatedEventId = null;
    isReplay = false;
    notifyListeners();
  }
}
