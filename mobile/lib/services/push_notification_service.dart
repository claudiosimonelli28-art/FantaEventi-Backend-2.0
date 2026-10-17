import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
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

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Canale di notifica nativo Android ad alta priorità (suono + vibrazione + pop-up)
  static const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
    'fantaeventi_channel',
    'Notifiche FantaEventi',
    description: 'Canale per notifiche su inviti, proposte bonus, votazioni e VAR',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Inizializza Firebase Messaging e le notifiche locali
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();

      // Registra il gestore in background
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Crea il canale di notifica su Android
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

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
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showForegroundNotification(message);
      });

      // 2. Notifica cliccata con App in BACKGROUND
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        handleNotificationClick(message.data);
      });

      // 3. Notifica cliccata con App CHIUSA / TERMINATA
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        handleNotificationClick(initialMessage.data);
      }

      // Ascolta eventuali rinnovi del token FCM
      _messaging.onTokenRefresh.listen((newToken) {
        syncCurrentDeviceToken(overrideToken: newToken);
      });

      _isInitialized = true;
      debugPrint('PushNotificationService inizializzato con successo.');
    } catch (e) {
      debugPrint('PushNotificationService initialize notice: $e');
    }
  }

  /// Richiede all'utente i permessi di notifica
  Future<void> requestPermissions() async {
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Mostra la notifica heads-up nella tendina quando l'app è in primo piano
  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['titolo'] ?? 'FantaEventi';
    final body = notification?.body ?? message.data['messaggio'] ?? '';

    if (body.isEmpty) return;

    _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
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

  /// Sincronizza il token FCM dell'utente loggato su MongoDB Atlas
  Future<void> syncCurrentDeviceToken({String? overrideToken}) async {
    try {
      final token = overrideToken ?? await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService().salvaFcmToken(token);
        debugPrint('FCM Token registrato per l\'utente corrente: $token');
      }
    } catch (e) {
      debugPrint('Errore sync FCM token: $e');
    }
  }

  /// Rimuove il token FCM corrente dal profilo MongoDB Atlas (chiamato al Logout)
  Future<void> unregisterCurrentDeviceToken() async {
    try {
      final token = await _messaging.getToken();
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

      for (final token in tokens) {
        await _sendFcmHttp(
          token: token,
          titolo: titolo,
          messaggio: messaggio,
          data: data ?? {},
        );
      }
    } catch (e) {
      debugPrint('Errore inviaPushAUtenti: $e');
    }
  }

  /// Invia il payload a Firebase Cloud Messaging
  Future<void> _sendFcmHttp({
    required String token,
    required String titolo,
    required String messaggio,
    required Map<String, dynamic> data,
  }) async {
    try {
      final payload = {
        'to': token,
        'priority': 'high',
        'notification': {
          'title': titolo,
          'body': messaggio,
          'sound': 'default',
          'channel_id': 'fantaeventi_channel',
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
        'data': {
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          'titolo': titolo,
          'messaggio': messaggio,
          ...data,
        },
      };

      // Recupera eventuale Server Key da ApiService o Configurazione
      final serverKey = ApiService().fcmServerKey;
      if (serverKey.isNotEmpty) {
        await http.post(
          Uri.parse('https://fcm.googleapis.com/fcm/send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'key=$serverKey',
          },
          body: jsonEncode(payload),
        );
      }
    } catch (e) {
      debugPrint('Errore chiamata FCM HTTP: $e');
    }
  }
}
