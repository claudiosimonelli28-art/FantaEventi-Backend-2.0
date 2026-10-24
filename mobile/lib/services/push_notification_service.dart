import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../models/evento.dart';
import '../views/event_detail_view.dart';
import '../views/vote_view.dart';
import '../views/notifications_modal.dart';
import '../views/profile_view.dart';

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

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Cache per autenticazione OAuth2 con Firebase Service Account (FCM v1)
  static Map<String, dynamic>? _serviceAccountMap;
  static String? _cachedAccessToken;
  static DateTime? _tokenExpiry;

  /// Canale di notifica nativo Android ad alta priorità (suono + vibrazione + pop-up)
  static const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
    'fantaeventi_channel',
    'Notifiche FantaEventi',
    description: 'Canale per notifiche su inviti, proposte bonus, votazioni e VAR',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Canale dedicato per Assegnazione Bonus (suono personalizzato fanta_bonus) v2
  static const AndroidNotificationChannel _bonusChannel = AndroidNotificationChannel(
    'fantaeventi_bonus_channel_v2',
    'Assegnazione Bonus 🏆',
    description: 'Notifiche con suono speciale per i bonus assegnati',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('fanta_bonus'),
    enableVibration: true,
  );

  /// Canale dedicato per Assegnazione Malus (suono personalizzato fanta_malus) v2
  static const AndroidNotificationChannel _malusChannel = AndroidNotificationChannel(
    'fantaeventi_malus_channel_v2',
    'Assegnazione Malus 💀',
    description: 'Notifiche con suono speciale per i malus assegnati',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('fanta_malus'),
    enableVibration: true,
  );

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

      // Crea i canali di notifica nativi su Android
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        try {
          await androidPlugin.deleteNotificationChannel(channelId: 'fantaeventi_bonus_channel');
          await androidPlugin.deleteNotificationChannel(channelId: 'fantaeventi_malus_channel');
        } catch (_) {}
        await androidPlugin.createNotificationChannel(_androidChannel);
        await androidPlugin.createNotificationChannel(_bonusChannel);
        await androidPlugin.createNotificationChannel(_malusChannel);
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
      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          _showForegroundNotification(message);
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

      // Precarica il service account in memoria
      unawaited(_loadServiceAccount());

      _isInitialized = true;
      debugPrint('PushNotificationService inizializzato con successo con FCM v1.');
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

    final String tipo = (message.data['tipo'] ?? '').toString();
    AndroidNotificationChannel targetChannel = _androidChannel;
    RawResourceAndroidNotificationSound? customSound;

    if (tipo == 'assegnazione_bonus') {
      targetChannel = _bonusChannel;
      customSound = const RawResourceAndroidNotificationSound('fanta_bonus');
    } else if (tipo == 'assegnazione_malus') {
      targetChannel = _malusChannel;
      customSound = const RawResourceAndroidNotificationSound('fanta_malus');
    }

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
          sound: customSound,
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

  /// Sincronizza il token FCM dell'utente loggato su MongoDB Atlas
  Future<void> syncCurrentDeviceToken({String? overrideToken, bool forceRefresh = false}) async {
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
      const String currentTokenBuildKey = 'fcm_token_build_v2_3';
      final isNewBuild = prefs.getString('fcm_token_build') != currentTokenBuildKey;

      if (forceRefresh || isNewBuild) {
        try {
          await _messaging!.deleteToken();
          await prefs.setString('fcm_token_build', currentTokenBuildKey);
          debugPrint('FCM Token resettato per garantire emissione token valida');
        } catch (e) {
          debugPrint('Notice deleteToken: $e');
        }
      }

      final token = overrideToken ?? await _messaging!.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService().salvaFcmToken(token);
        await prefs.setString('cached_fcm_token', token);
        debugPrint('FCM Token registrato per l\'utente corrente (${cur.nome}): $token');
      }
    } catch (e) {
      debugPrint('Errore sync FCM token: $e');
    }
  }

  /// Rimuove il token FCM corrente dal profilo MongoDB Atlas (chiamato al Logout)
  Future<void> unregisterCurrentDeviceToken() async {
    try {
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

  // --- MOTORE DI DISPATCH FCM v1 CON GOOGLE SERVICE ACCOUNT ---

  static Future<Map<String, dynamic>?> _loadServiceAccount() async {
    if (_serviceAccountMap != null) return _serviceAccountMap;
    // 1. Prova prima dalla cache locale super-veloce su disco (0 ms)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_firebase_service_account_v1');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        _serviceAccountMap = jsonDecode(cachedJson) as Map<String, dynamic>;
        return _serviceAccountMap;
      }
    } catch (_) {}

    // 2. Se non presente in cache locale, carica da MongoDB Atlas
    try {
      final config = await ApiService().getFirebaseServiceAccountConfig();
      if (config != null) {
        _serviceAccountMap = config;
        // Salva in cache locale per i successivi utilizzi
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_firebase_service_account_v1', jsonEncode(config));
        } catch (_) {}
        return _serviceAccountMap;
      }
    } catch (e) {
      debugPrint('Notice caricamento service account da Atlas: $e');
    }
    return null;
  }

  static Future<String?> _getAccessToken() async {
    try {
      final now = DateTime.now();
      if (_cachedAccessToken != null &&
          _tokenExpiry != null &&
          now.isBefore(_tokenExpiry!.subtract(const Duration(minutes: 2)))) {
        return _cachedAccessToken;
      }

      final sa = await _loadServiceAccount();
      if (sa == null) return null;

      final credentials = ServiceAccountCredentials.fromJson(sa);
      final client = await clientViaServiceAccount(credentials, [
        'https://www.googleapis.com/auth/firebase.messaging',
      ]).timeout(const Duration(seconds: 10));

      _cachedAccessToken = client.credentials.accessToken.data;
      _tokenExpiry = client.credentials.accessToken.expiry;
      client.close();
      return _cachedAccessToken;
    } catch (e) {
      debugPrint('Errore autenticazione OAuth2 FCM v1: $e');
      return null;
    }
  }

  /// Invia una notifica push istantanea ai token FCM dei nickname destinatari
  Future<void> inviaPushAUtenti(
    List<String> destinatariNicknames, {
    required String titolo,
    required String messaggio,
    Map<String, dynamic>? data,
  }) async {
    if (destinatariNicknames.isEmpty) return;

    try {
      final tokens = await ApiService().getFcmTokensPerUtenti(destinatariNicknames);
      if (tokens.isEmpty) {
        debugPrint('Nessun token FCM registrato per i destinatari: $destinatariNicknames');
        return;
      }

      debugPrint('Inizio invio push a ${tokens.length} token per $destinatariNicknames: $titolo');
      for (final token in tokens) {
        try {
          await _sendFcmV1(
            token: token,
            titolo: titolo,
            messaggio: messaggio,
            data: data ?? {},
          );
        } catch (e) {
          debugPrint('Errore invio push singolo token: $e');
        }
      }
    } catch (e) {
      debugPrint('Errore inviaPushAUtenti: $e');
    }
  }

  /// Invia il payload a Firebase Cloud Messaging tramite HTTP v1 (OAuth2)
  Future<void> _sendFcmV1({
    required String token,
    required String titolo,
    required String messaggio,
    required Map<String, dynamic> data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('Impossibile ottenere OAuth2 token per FCM v1');
        return;
      }

      final sa = await _loadServiceAccount();
      final projectId = sa?['project_id'] ?? 'fantaeventi-dd26a';
      final url = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      // FCM v1 richiede che tutti i valori in data siano stringhe
      final Map<String, String> stringData = {};
      data.forEach((k, v) {
        if (v != null) stringData[k] = v.toString();
      });
      stringData['titolo'] = titolo;
      stringData['messaggio'] = messaggio;
      stringData['click_action'] = 'FLUTTER_NOTIFICATION_CLICK';

      final String pushTipo = stringData['tipo'] ?? '';
      String targetChannelId = 'fantaeventi_channel';
      String targetSound = 'default';
      bool isDefaultSound = true;

      if (pushTipo == 'assegnazione_bonus') {
        targetChannelId = 'fantaeventi_bonus_channel_v2';
        targetSound = 'fanta_bonus';
        isDefaultSound = false;
      } else if (pushTipo == 'assegnazione_malus') {
        targetChannelId = 'fantaeventi_malus_channel_v2';
        targetSound = 'fanta_malus';
        isDefaultSound = false;
      }

      final payload = {
        'message': {
          'token': token,
          'notification': {
            'title': titolo,
            'body': messaggio,
          },
          'data': stringData,
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': targetChannelId,
              'sound': targetSound,
              'default_sound': isDefaultSound,
              'default_vibrate_timings': true,
              'notification_priority': 'PRIORITY_MAX',
              'visibility': 'PUBLIC',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'sound': 'default',
                'badge': 1,
                'content-available': 1,
              },
            },
          },
        },
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ Push FCM v1 inviata con successo a $token ($titolo)');
      } else {
        debugPrint('❌ Esito risposta FCM v1 (${response.statusCode}): ${response.body}');
        if (response.statusCode == 404 ||
            response.body.contains('UNREGISTERED') ||
            response.body.contains('NotRegistered')) {
          debugPrint('🧹 Rimozione automatica token FCM non più valido: $token');
          unawaited(ApiService().rimuoviFcmTokenGlobale(token));
        }
      }
    } catch (e) {
      debugPrint('Errore durante la chiamata HTTP a FCM v1: $e');
    }
  }
}
