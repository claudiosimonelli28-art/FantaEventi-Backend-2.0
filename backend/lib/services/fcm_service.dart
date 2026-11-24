import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';
import '../db/db_service.dart';
import '../controllers/utente_controller.dart';
import '../utils/nickname_helper.dart';

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  Map<String, dynamic>? _serviceAccountMap;
  String? _cachedAccessToken;
  DateTime? _tokenExpiry;

  String _getChannelIdForType(String? tipo) {
    final t = (tipo ?? '').toLowerCase();
    if (t.startsWith('var')) {
      return 'fantaeventi_var_v2';
    } else if (t.contains('assegnazione') ||
        t == 'bonus' ||
        t == 'malus' ||
        t.contains('ammonizione') ||
        t.contains('ban_utente') ||
        t.contains('segnalazione')) {
      return 'fantaeventi_bonus_v2';
    } else if (t.contains('proposta') || t.contains('votazione') || t == 'bonus_malus') {
      return 'fantaeventi_votes_v2';
    } else {
      return 'fantaeventi_invites_v2';
    }
  }

  Future<Map<String, dynamic>?> _loadServiceAccount() async {
    if (_serviceAccountMap != null) return _serviceAccountMap;

    // 1. Variabile d'ambiente FIREBASE_SERVICE_ACCOUNT (JSON o Base64)
    final envSa = Platform.environment['FIREBASE_SERVICE_ACCOUNT'];
    if (envSa != null && envSa.trim().isNotEmpty) {
      try {
        final raw = envSa.trim();
        final decoded = raw.startsWith('{') ? raw : utf8.decode(base64Decode(raw));
        _serviceAccountMap = jsonDecode(decoded) as Map<String, dynamic>;
        return _serviceAccountMap;
      } catch (e) {
        print('⚠️ Errore parsing FIREBASE_SERVICE_ACCOUNT da env: $e');
      }
    }

    // 2. Fallback: lettura server-side dalla collection AppConfig di MongoDB Atlas
    try {
      final doc = await DbService.instance.db
          .collection('AppConfig')
          .findOne(where.eq('chiave', 'firebase_service_account'));
      if (doc != null && doc['config'] != null) {
        _serviceAccountMap = Map<String, dynamic>.from(doc['config'] as Map);
        return _serviceAccountMap;
      }
    } catch (e) {
      print('⚠️ Errore lettura firebase_service_account da MongoDB AppConfig: $e');
    }
    return null;
  }

  Future<String?> _getAccessToken() async {
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
      print('❌ Errore autenticazione OAuth2 FCM v1 su Backend: $e');
      return null;
    }
  }

  Future<List<String>> getTokensForUsers(List<String> nicknames) async {
    if (nicknames.isEmpty) return [];
    final Set<String> allTokens = {};
    try {
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final resolvedTargets = nicknames.map((n) => NicknameHelper.resolve(n, uDocs)).toSet();

      for (var u in uDocs) {
        final raw = (u['nickname'] ?? u['username'] ?? u['nome'] ?? '').toString();
        for (var target in resolvedTargets) {
          if (NicknameHelper.isSame(raw, target, uDocs)) {
            final tokens = List<String>.from(u['fcmTokens'] ?? []);
            allTokens.addAll(tokens.where((t) => t.trim().isNotEmpty));
          }
        }
      }
    } catch (e) {
      print('⚠️ Errore recupero token FCM per $nicknames: $e');
    }
    return allTokens.toList();
  }

  Future<int> inviaPushAUtenti(
    List<String> destinatariNicknames, {
    required String titolo,
    required String messaggio,
    Map<String, dynamic>? data,
  }) async {
    if (destinatariNicknames.isEmpty) return 0;
    final tokens = await getTokensForUsers(destinatariNicknames);
    if (tokens.isEmpty) return 0;

    int sentCount = 0;
    for (final token in tokens) {
      final ok = await _sendFcmV1(
        token: token,
        titolo: titolo,
        messaggio: messaggio,
        data: data ?? {},
      );
      if (ok) sentCount++;
    }
    return sentCount;
  }

  Future<bool> _sendFcmV1({
    required String token,
    required String titolo,
    required String messaggio,
    required Map<String, dynamic> data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null || accessToken.isEmpty) return false;

      final sa = await _loadServiceAccount();
      final projectId = sa?['project_id'] ?? 'fantaeventi-dd26a';
      final url = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      final Map<String, String> stringData = {};
      data.forEach((k, v) {
        if (v != null) stringData[k] = v.toString();
      });
      stringData['titolo'] = titolo;
      stringData['messaggio'] = messaggio;
      stringData['click_action'] = 'FLUTTER_NOTIFICATION_CLICK';

      final channelId = _getChannelIdForType(data['tipo']?.toString());

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
              'channel_id': channelId,
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

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      } else {
        if (response.statusCode == 404 ||
            response.body.contains('UNREGISTERED') ||
            response.body.contains('NotRegistered')) {
          print('🧹 [FCM Backend] Rimozione token non più valido: $token');
          unawaited(
            DbService.instance.utentiCollection
                .update(
                  where.eq('fcmTokens', token),
                  modify.pull('fcmTokens', token),
                  multiUpdate: true,
                )
                .then((_) => UtenteController.invalidateCache()),
          );
        }
        return false;
      }
    } catch (e) {
      print('⚠️ Errore invio FCM v1 su Backend: $e');
      return false;
    }
  }
}
