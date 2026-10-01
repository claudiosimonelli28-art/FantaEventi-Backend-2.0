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

  void startTutorial() {
    _stage = TutorialStage.step1_tap_plus;
    final user = ApiService().currentUser;
    final nick = user?.nome ?? 'Cloud';
    ApiService().assicuraNotificaBenvenuto(nick);
    notifyListeners();
  }

  void setStage(TutorialStage newStage) {
    if (_stage != newStage) {
      _stage = newStage;
      notifyListeners();
    }
  }

  void skipTutorial() {
    _stage = TutorialStage.idle;
    ApiService().segnaGuidaRegoleCompletata();
    notifyListeners();
  }

  void completeTutorial(BuildContext context) {
    _stage = TutorialStage.idle;
    ApiService().segnaGuidaRegoleCompletata();
    notifyListeners();
  }
}
