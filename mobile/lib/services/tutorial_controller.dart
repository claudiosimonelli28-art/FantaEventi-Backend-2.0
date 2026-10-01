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
    final String evTitolo = (evento.titolo ?? '').toString();
    if (tutorialCreatedEventId != null && tutorialCreatedEventId!.isNotEmpty) {
      return evId == tutorialCreatedEventId;
    }
    return evTitolo.contains('Festa di Benvenuto');
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
