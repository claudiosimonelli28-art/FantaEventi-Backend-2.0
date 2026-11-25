import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../models/evento.dart';
import '../views/event_detail_view.dart';
import '../views/vote_view.dart';
import '../views/notifications_modal.dart';
import '../views/profile_view.dart';
import '../views/login_view.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('FantaEventi FCM Background Message ID: ${message.messageId}');
}

class PushNotificationService {
  PushNotificationService._internal();
  static final PushNotificationService instance = PushNotificationService._internal();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Dati della notifica cliccata quando l'utente non era ancora autenticato (in attesa di login)
  static Map<String, dynamic>? pendingNotificationData;

  /// Callback invocato alla ricezione di una notifica push in primo piano
  VoidCallback? onNotificationReceived;

  static bool _isShowingBanModal = false;

  /// Espelle immediatamente l'utente bannato dalla sessione attiva e mostra un avviso bloccante
  static Future<void> enforceAccountSuspension() async {
    if (_isShowingBanModal) return;
    if (ApiService().currentUser == null) return;
    _isShowingBanModal = true;

    try {
      await ApiService().logout();
    } catch (_) {}

    final navState = navigatorKey.currentState;
    if (navState != null) {
      navState.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginView()),
        (route) => false,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) {
        _isShowingBanModal = false;
        return;
      }
      showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.gavel_rounded, color: Color(0xFFEF4444), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Account Sospeso',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Il tuo account è stato sospeso dall\'Amministrazione per violazione delle linee guida della community di FantaEventi.\n\nLa sessione attiva è stata terminata. Per maggiori informazioni o chiarimenti contatta l\'Amministratore.',
            style: GoogleFonts.inter(
              color: const Color(0xFFCBD5E1),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _isShowingBanModal = false;
                  Navigator.of(dialogCtx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'HO CAPITO',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ).then((_) => _isShowingBanModal = false);
    });
  }

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  static const MethodChannel _settingsMethodChannel = MethodChannel('com.fantaeventi.mobile/settings');

  /// Canali di notifica nativi Android categorizzati (permettono la personalizzazione del suono nel sistema)
  static const AndroidNotificationChannel channelBonus = AndroidNotificationChannel(
    'fantaeventi_bonus',
    '🏆 Assegnazione Bonus',
    description: 'Suono e notifiche quando ricevi un bonus o punti positivi',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel channelMalus = AndroidNotificationChannel(
    'fantaeventi_malus',
    '💀 Assegnazione Malus',
    description: 'Suono e notifiche quando ricevi un malus o penalità',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel channelVar = AndroidNotificationChannel(
    'fantaeventi_var',
    '⚖️ VAR & Giudice Arbitro',
    description: 'Suono e notifiche per verifiche VAR, testimonianze e sentenze',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel channelInvites = AndroidNotificationChannel(
    'fantaeventi_invites',
    '🎉 Inviti & Amicizie',
    description: 'Notifiche per nuovi inviti ad eventi o richieste di amicizia',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel channelRules = AndroidNotificationChannel(
    'fantaeventi_rules',
    '📜 Nuove Regole Approvate',
    description: 'Suono quando una proposta supera il quorum ed entra nel catalogo',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel channelGeneral = AndroidNotificationChannel(
    'fantaeventi_channel',
    '🗳️ Nuove Proposte & Votazioni',
    description: 'Suono quando un partecipante propone un nuovo Bonus/Malus da votare',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Ritorna il canale nativo Android appropriato in base alla tipologia di notifica
  static AndroidNotificationChannel getChannelForType(String? tipo) {
    final t = (tipo ?? '').toLowerCase().trim();
    // 1. VAR & Giudice Arbitro (richieste, testimonianze ed esito VAR)
    if (t.startsWith('var')) return channelVar;
    // 2. Inviti ad eventi & Richieste di Amicizia
    if (t.contains('invito') || t.contains('amicizia')) return channelInvites;
    // 3. Nuove Regole Approvate nel catalogo ufficiale
    if (t == 'bonus_approvato' || t == 'malus_approvato' || t == 'regola_approvata' || t.contains('approvat')) {
      return channelRules;
    }
    // 4. Nuove Proposte e Votazioni live da votare
    if (t == 'bonus_malus' || t.contains('proposta') || t.contains('vota')) {
      return channelGeneral;
    }
    // 5. Assegnazione Malus (penalità assegnate a un giocatore)
    if (t.contains('malus')) return channelMalus;
    // 6. Assegnazione Bonus (punti assegnati a un giocatore)
    if (t.contains('bonus')) return channelBonus;
    return channelGeneral;
  }

  /// Inizializza Firebase Messaging e le notifiche locali
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      try {
        await Firebase.initializeApp();
      } catch (e) {
        debugPrint('Firebase initializeApp notice: $e');
      }

      try {
        _messaging = FirebaseMessaging.instance;
      } catch (e) {
        debugPrint('FirebaseMessaging instance notice: $e');
      }

      // Registra il gestore in background se messaging è disponibile
      if (_messaging != null) {
        try {
          FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        } catch (e) {
          debugPrint('Notice onBackgroundMessage: $e');
        }
      }

      // Registra tutti i canali di notifica su Android
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        try {
          await androidPlugin.deleteNotificationChannel(channelId: 'fantaeventi_bonus_channel');
          await androidPlugin.deleteNotificationChannel(channelId: 'fantaeventi_malus_channel');
          await androidPlugin.deleteNotificationChannel(channelId: 'fantaeventi_bonus_channel_v2');
          await androidPlugin.deleteNotificationChannel(channelId: 'fantaeventi_malus_channel_v2');
        } catch (_) {}

        await androidPlugin.createNotificationChannel(channelBonus);
        await androidPlugin.createNotificationChannel(channelMalus);
        await androidPlugin.createNotificationChannel(channelVar);
        await androidPlugin.createNotificationChannel(channelInvites);
        await androidPlugin.createNotificationChannel(channelRules);
        await androidPlugin.createNotificationChannel(channelGeneral);
      }

      // Configurazione iniziale di flutter_local_notifications
      const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initDarwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: initAndroid,
        iOS: initDarwin,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payloadStr = response.payload;
          if (payloadStr != null && payloadStr.isNotEmpty) {
            try {
              final data = jsonDecode(payloadStr) as Map<String, dynamic>;
              handleNotificationClick(data);
            } catch (_) {}
          }
        },
      );

      // Richiede i permessi di sistema (Android 13+ e iOS)
      await requestPermissions();

      // 1. Notifiche in PRIMO PIANO (App aperta e attiva)
      ApiService.onCurrentUserBanned = () {
        enforceAccountSuspension();
      };

      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          _showForegroundNotification(message);
          final tipoMsg = (message.data['tipo'] ?? '').toString().toLowerCase().trim();
          if (tipoMsg == 'ban_utente') {
            enforceAccountSuspension();
            return;
          }
          onNotificationReceived?.call();
        });

        // 2. Notifica cliccata con App in BACKGROUND
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          handleNotificationClick(message.data);
        });

        // 3. Notifica cliccata con App CHIUSA / TERMINATA
        if (_messaging != null) {
          final initialMessage = await _messaging!.getInitialMessage();
          if (initialMessage != null) {
            handleNotificationClick(initialMessage.data);
          }

          // Ascolta eventuali rinnovi del token FCM
          _messaging!.onTokenRefresh.listen((newToken) {
            syncCurrentDeviceToken(overrideToken: newToken);
          });
        }
      } catch (e) {
        debugPrint('Notice ascoltatori FirebaseMessaging: $e');
      }

      // Rimuove eventuale vecchia copia locale del service account dal dispositivo per sicurezza
      unawaited(SharedPreferences.getInstance().then((prefs) => prefs.remove('cached_firebase_service_account_v1')));

      _isInitialized = true;
      debugPrint('PushNotificationService inizializzato con successo (Server-Side FCM v1).');
    } catch (e) {
      debugPrint('PushNotificationService initialize notice: $e');
    }
  }

  /// Richiede all'utente i permessi di notifica
  Future<void> requestPermissions() async {
    try {
      if (_messaging != null) {
        await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      }

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notice richiesta permessi push: $e');
    }
  }

  /// Mostra la notifica heads-up nella tendina quando l'app è in primo piano
  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['titolo'] ?? 'FantaEventi';
    final body = notification?.body ?? message.data['messaggio'] ?? '';

    if (body.isEmpty) return;

    final targetChannel = getChannelForType(message.data['tipo']);

    _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          targetChannel.id,
          targetChannel.name,
          channelDescription: targetChannel.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          color: const Color(0xFFFACC15),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Apre le impostazioni native di sistema Android per un canale di notifica (o per l'app)
  Future<void> openChannelSettings([String? channelId]) async {
    try {
      await _settingsMethodChannel.invokeMethod('openNotificationSettings', {
        'channelId': channelId,
      });
    } catch (e) {
      debugPrint('Errore apertura impostazioni canale $channelId: $e');
    }
  }

  /// Invia una notifica di test istantanea su un canale specifico per verificare suoni e vibrazione
  Future<void> triggerTestNotification({
    required String channelId,
    required String title,
    required String body,
  }) async {
    AndroidNotificationChannel ch = channelGeneral;
    if (channelId == channelBonus.id) ch = channelBonus;
    if (channelId == channelMalus.id) ch = channelMalus;
    if (channelId == channelVar.id) ch = channelVar;
    if (channelId == channelInvites.id) ch = channelInvites;
    if (channelId == channelRules.id) ch = channelRules;

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ch.id,
          ch.name,
          channelDescription: ch.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          color: const Color(0xFFFACC15),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode({'tipo': 'test', 'channelId': ch.id}),
    );
  }

  /// Sincronizza il token FCM dell'utente loggato su MongoDB Atlas (protetto da coda seriale contro race condition)
  Future<void> _syncTokenQueue = Future.value();
  String? _lastVerifiedUserTokenKey;

  Future<void> syncCurrentDeviceToken({String? overrideToken, bool forceRefresh = false}) {
    final completer = Completer<void>();
    final prev = _syncTokenQueue;
    _syncTokenQueue = completer.future;

    return () async {
      try {
        await prev;
      } catch (_) {}
      try {
        await _doSyncCurrentDeviceToken(overrideToken: overrideToken, forceRefresh: forceRefresh);
      } finally {
        completer.complete();
      }
    }();
  }

  Future<void> _doSyncCurrentDeviceToken({String? overrideToken, bool forceRefresh = false}) async {
    try {
      if (_messaging == null) {
        try {
          _messaging = FirebaseMessaging.instance;
        } catch (_) {}
      }
      if (_messaging == null) return;

      final cur = ApiService().currentUser;
      if (cur == null) return;

      final prefs = await SharedPreferences.getInstance();

      if (forceRefresh) {
        try {
          _lastVerifiedUserTokenKey = null;
          await _messaging!.deleteToken();
          await Future.delayed(const Duration(milliseconds: 1200));
          debugPrint('FCM Token resettato su richiesta esplicita');
        } catch (e) {
          debugPrint('Notice deleteToken: $e');
        }
      }

      String? token = overrideToken;
      if (token == null || token.isEmpty) {
        token = await _messaging!.getToken();
        if (token == null || token.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 1000));
          token = await _messaging!.getToken();
        }
      }

      if (token != null && token.isNotEmpty) {
        final userKey = '${cur.nickname.toLowerCase()}|$token';
        if (!forceRefresh && _lastVerifiedUserTokenKey == userKey) {
          return;
        }

        final accepted = await ApiService().salvaFcmToken(token);
        if (accepted) {
          _lastVerifiedUserTokenKey = userKey;
          await prefs.setString('cached_fcm_token', token);
          debugPrint('✅ FCM Token registrato e verificato per ${cur.nickname}: $token');
        } else {
          // Il server ha rilevato che Google FCM considera questo token UNREGISTERED (404)!
          // Auto-guarigione immediata: forziamo Google Play Services ad emettere un nuovo token pulito!
          debugPrint('🔄 Token FCM locale obsoleto (UNREGISTERED), rigenerazione automatica in corso...');
          _lastVerifiedUserTokenKey = null;
          await prefs.remove('cached_fcm_token');
          try {
            await _messaging!.deleteToken();
            await Future.delayed(const Duration(milliseconds: 1500));
            final freshToken = await _messaging!.getToken();
            if (freshToken != null && freshToken.isNotEmpty && freshToken != token) {
              final okRetry = await ApiService().salvaFcmToken(freshToken);
              if (okRetry) {
                _lastVerifiedUserTokenKey = '${cur.nickname.toLowerCase()}|$freshToken';
                await prefs.setString('cached_fcm_token', freshToken);
                debugPrint('✅ Nuovo FCM Token rigenerato con successo per ${cur.nickname}: $freshToken');
              }
            }
          } catch (e) {
            debugPrint('Errore rigenerazione FCM token: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Errore sync FCM token: $e');
    }
  }

  /// Rimuove il token FCM corrente dal profilo MongoDB Atlas (chiamato al Logout)
  Future<void> unregisterCurrentDeviceToken() async {
    _lastVerifiedUserTokenKey = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_fcm_token');
      final token = await _messaging?.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService().rimuoviFcmToken(token);
      }
    } catch (_) {}
  }

  /// Gestisce il tocco su una notifica da tendina:
  /// - Se l'utente è loggato (Remember Me attivo): naviga subito alla destinazione.
  /// - Se NON è loggato: salva i dati in pendingNotificationData in attesa del Login.
  void handleNotificationClick(Map<String, dynamic> data) {
    if (data.isEmpty) return;

    final curUser = ApiService().currentUser;
    if (curUser != null) {
      // Già autenticato: naviga direttamente
      navigateWithData(data);
    } else {
      // Non autenticato: memorizza per il post-login
      pendingNotificationData = Map<String, dynamic>.from(data);
      debugPrint('Notifica memorizzata per il post-login: $data');
    }
  }

  /// Indica se c'è una destinazione in attesa di essere aperta dopo il login
  static bool get hasPendingRoute => pendingNotificationData != null && pendingNotificationData!.isNotEmpty;

  /// Consuma la destinazione pendente dopo l'avvenuto login
  static void consumePendingRoute([BuildContext? context]) {
    if (pendingNotificationData == null) return;
    final data = Map<String, dynamic>.from(pendingNotificationData!);
    pendingNotificationData = null;
    navigateWithData(data, context);
  }

  /// Esegue la navigazione verso la schermata corretta in base al tipo di notifica
  static void navigateWithData(Map<String, dynamic> data, [BuildContext? context]) {
    final navContext = context ?? navigatorKey.currentContext;
    if (navContext == null) {
      // Se il BuildContext del navigator non è ancora disponibile, attende il frame successivo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retryCtx = navigatorKey.currentContext;
        if (retryCtx != null) {
          _performNavigation(retryCtx, data);
        }
      });
      return;
    }

    _performNavigation(navContext, data);
  }

  static void _apriCentroNotifiche(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: NotificationsModal(
          onRefreshHome: () {},
        ),
      ),
    );
  }

  static void _performNavigation(BuildContext context, Map<String, dynamic> data) async {
    final tipo = (data['tipo'] ?? '').toString().toLowerCase();
    final eventoId = (data['eventoId'] ?? '').toString();
    final bonusId = (data['bonusId'] ?? '').toString();

    try {
      if (tipo == 'invito' || tipo == 'evento') {
        if (eventoId.isNotEmpty) {
          final eventi = await ApiService().getEventi();
          Evento? ev;
          for (var e in eventi) {
            if (e.id.toLowerCase() == eventoId.toLowerCase() || e.titolo.toLowerCase() == eventoId.toLowerCase()) {
              ev = e;
              break;
            }
          }
          if (ev != null && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EventDetailView(evento: ev!, onRefresh: () {})),
            );
            return;
          }
        }
      } else if (tipo == 'bonus_malus' || tipo.contains('proposta') || tipo == 'votazione') {
        if (eventoId.isNotEmpty) {
          final votazioni = await ApiService().getVotazioni();
          final v = votazioni.firstWhere(
            (vot) =>
                (bonusId.isNotEmpty && (vot.id == bonusId || vot.bonusMalus?.id == bonusId)) ||
                (vot.bonusMalus?.eventoId == eventoId),
            orElse: () => votazioni.isNotEmpty ? votazioni.first : votazioni.first,
          );
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VoteView(votazione: v)),
            );
            return;
          }
        }
      } else if (tipo.startsWith('var')) {
        if (context.mounted) {
          _apriCentroNotifiche(context);
          return;
        }
      } else if (tipo == 'ban_utente') {
        enforceAccountSuspension();
        return;
      } else if (tipo == 'segnalazione_utente') {
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileView(openModerationOnStart: true)),
          );
          return;
        }
      } else if (tipo.contains('amicizia')) {
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileView()),
          );
          return;
        }
      }

      // Fallback generico: se c'è un evento valido aprilo, altrimenti Centro Notifiche
      if (eventoId.isNotEmpty) {
        final eventi = await ApiService().getEventi();
        Evento? ev;
        for (var e in eventi) {
          if (e.id.toLowerCase() == eventoId.toLowerCase()) {
            ev = e;
            break;
          }
        }
        if (ev != null && context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EventDetailView(evento: ev!, onRefresh: () {})),
          );
          return;
        }
      }

      if (context.mounted) {
        _apriCentroNotifiche(context);
      }
    } catch (e) {
      debugPrint('Errore durante il routing da notifica: $e');
      if (context.mounted) {
        _apriCentroNotifiche(context);
      }
    }
  }

  // --- MOTORE DI DISPATCH FCM v1 TRAMITE BACKEND RENDER (ZERO CHIAVI SUL TELEFONO) ---

  /// Invia una notifica push istantanea ai token FCM dei nickname destinatari tramite il backend sicuro
  Future<void> inviaPushAUtenti(
    List<String> destinatariNicknames, {
    required String titolo,
    required String messaggio,
    Map<String, dynamic>? data,
  }) async {
    if (destinatariNicknames.isEmpty) return;

    for (final url in ApiService().baseUrls) {
      try {
        final response = await http
            .post(
              Uri.parse('$url/notifiche/push'),
              headers: ApiService().defaultHeaders,
              body: jsonEncode({
                'destinatari': destinatariNicknames,
                'titolo': titolo,
                'messaggio': messaggio,
                'data': data ?? <String, dynamic>{},
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          debugPrint('✅ Push FCM v1 recapitata tramite backend a $destinatariNicknames ($titolo)');
          return;
        }
      } catch (e) {
        debugPrint('Errore inviaPushAUtenti tramite backend: $e');
      }
    }
  }
}
