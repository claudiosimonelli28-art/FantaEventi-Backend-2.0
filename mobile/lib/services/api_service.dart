import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/utente.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../models/votazione.dart';
import '../models/richiesta_var.dart';
import 'push_notification_service.dart';

class NeedsPasswordSetupException implements Exception {
  final String username;
  final String email;
  NeedsPasswordSetupException({required this.username, required this.email});

  @override
  String toString() => 'Questo account non ha ancora una password impostata. Impostala ora per proteggere il profilo!';
}

class NicknameCheckResult {
  final bool disponibile;
  final String? messaggio;
  final List<String> suggerimenti;

  const NicknameCheckResult({
    required this.disponibile,
    this.messaggio,
    this.suggerimenti = const [],
  });
}

class NicknameAlreadyTakenException implements Exception {
  final String nickname;
  final List<String> suggerimenti;
  final String message;

  NicknameAlreadyTakenException({
    required this.nickname,
    required this.suggerimenti,
    String? message,
  }) : message = message ?? 'Nome utente "$nickname" già in uso. Prova uno dei suggerimenti!';

  @override
  String toString() => message;
}

class ApiService {
  static String formattaVoceStorico(String logText) {
    if (logText.startsWith('[')) return logText;
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateTag = '[${now.toIso8601String().substring(0, 10)} $timeStr]';
    return '$dateTag $logText';
  }

  static List<String> filtraStorico(List<String> storico, {int maxGiorni = 7}) {
    final now = DateTime.now();
    final List<String> result = [];
    final RegExp fullDateRegex = RegExp(r'\[(\d{4}-\d{2}-\d{2})(?:\s+(\d{2}):(\d{2}))?\]');

    for (var item in storico) {
      final match = fullDateRegex.firstMatch(item);
      if (match != null) {
        final dateStr = match.group(1)!;
        final hourStr = match.group(2) ?? '12';
        final minStr = match.group(3) ?? '00';
        final itemDate = DateTime.tryParse('${dateStr}T$hourStr:$minStr:00');

        if (itemDate != null) {
          final diffHours = now.difference(itemDate).inHours;

          // Se più vecchio di 7 giorni (168 ore), viene eliminato ed escluso dal DB e dalla UI
          if (diffHours > 168) {
            continue;
          }

          if (maxGiorni == 1 && diffHours > 24) {
            continue; // Filtro 24h: solo elementi svolti nelle ultime 24 ore
          } else if (maxGiorni == 3 && diffHours > 72) {
            continue; // Filtro 3 giorni: solo elementi svolti nelle ultime 72 ore
          } else if (maxGiorni == 7 && diffHours > 168) {
            continue; // Filtro 7 giorni: solo elementi svolti nelle ultime 168 ore
          }
          result.add(item);
        }
      }
    }
    return result;
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  static const String _kCachedUtentiKey = 'cached_utenti_json_v1';
  static const String _kCachedAvatarsKey = 'cached_avatars_map_v1';
  final Map<String, String> _avatarCache = {};

  ApiService._internal() {
    _loadCachedUsersAndAvatars();
  }

  Future<void> loadLocalCache() async {
    await _loadCachedUsersAndAvatars();
  }

  void _cacheSingleAvatar(String name, String nick, String avatarUrl) {
    final trimmed = avatarUrl.trim();
    if (trimmed.isEmpty) return;
    final cleanNome = name.replaceAll(' ', '').trim().toLowerCase();
    final cleanNick = nick.replaceAll(' ', '').trim().toLowerCase();
    final rawNome = name.trim().toLowerCase();
    final rawNick = nick.trim().toLowerCase();
    if (cleanNome.isNotEmpty) _avatarCache[cleanNome] = trimmed;
    if (cleanNick.isNotEmpty) _avatarCache[cleanNick] = trimmed;
    if (rawNome.isNotEmpty) _avatarCache[rawNome] = trimmed;
    if (rawNick.isNotEmpty) _avatarCache[rawNick] = trimmed;
  }

  Future<void> _loadCachedUsersAndAvatars() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final avStr = prefs.getString(_kCachedAvatarsKey);
      if (avStr != null && avStr.isNotEmpty) {
        final Map<String, dynamic> map = jsonDecode(avStr);
        map.forEach((k, v) {
          if (v is String && v.isNotEmpty && !v.contains('pravatar') && !v.contains('unsplash.com/photo-1535713875002')) {
            final keyLower = k.toLowerCase().trim();
            final keyNoSpaces = keyLower.replaceAll(' ', '');
            _avatarCache[keyLower] = v;
            _avatarCache[keyNoSpaces] = v;
          }
        });
      }

      final uStr = prefs.getString(_kCachedUtentiKey);
      if (uStr != null && uStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(uStr);
        final List<Utente> loaded = [];
        for (var item in list) {
          final u = Utente.fromJson(Map<String, dynamic>.from(item as Map));
          loaded.add(u);
          if (u.avatarUrl.isNotEmpty && !u.avatarUrl.contains('pravatar') && !u.avatarUrl.contains('unsplash.com/photo-1535713875002')) {
            _cacheSingleAvatar(u.nome, u.nickname, u.avatarUrl);
          }
        }
        if (loaded.isNotEmpty && _utenti.isEmpty) {
          _utenti.addAll(loaded);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCachedUsersAndAvatars() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_utenti.isNotEmpty) {
        final list = _utenti.map((u) => u.toJson()).toList();
        await prefs.setString(_kCachedUtentiKey, jsonEncode(list));
      }
      if (_avatarCache.isNotEmpty) {
        await prefs.setString(_kCachedAvatarsKey, jsonEncode(_avatarCache));
      }
    } catch (_) {}
  }

  static String get _mongoUri {
    const envUri = String.fromEnvironment('MONGODB_URI');
    if (envUri.isNotEmpty && envUri.startsWith('mongodb') && envUri.contains('appName=Cluster0') && !envUri.contains('^')) {
      return envUri;
    }
    return utf8.decode(base64.decode(
        'bW9uZ29kYitzcnY6Ly9Mb3JlbnpvOlQzUlVINEdKRGZhWGVlZUBjbHVzdGVyMC56YmJxZmNyLm1vbmdvZGIubmV0L0ZhbnRhRXZlbnRpP3JldHJ5V3JpdGVzPXRydWUmdz1tYWpvcml0eSZhcHBOYW1lPUNsdXN0ZXIw'));
  }

  static String get _directMongoSeedlist => utf8.decode(base64.decode(
      'bW9uZ29kYjovL0xvcmVuem86VDNSVUg0R0pEZmFYZWVlQGFjLXphbDQ3M3ctc2hhcmQtMDAtMDAuemJicWZjci5tb25nb2RiLm5ldDoyNzAxNyxhYy16YWw0NzN3LXNoYXJkLTAwLTAxLnpiYnFmY3IubW9uZ29kYi5uZXQ6MjcwMTcsYWMtemFsNDczdy1zaGFyZC0wMC0wMi56YmJxZmNyLm1vbmdvZGIubmV0OjI3MDE3L0ZhbnRhRXZlbnRpP3NzbD10cnVlJnJlcGxpY2FTZXQ9YXRsYXMtemFsNDczdy1zaGFyZC0wJmF1dGhTb3VyY2U9YWRtaW4mcmV0cnlXcml0ZXM9dHJ1ZSZ3PW1ham9yaXR5'));

  static String get _brevoKey {
    const envKey = String.fromEnvironment('BREVO_API_KEY');
    if (envKey.isNotEmpty && envKey.startsWith('xkeysib') && envKey.length > 50) return envKey;
    return 'J9P85UUEuUPXGfwG-941e20fe51bd1e1b903adf425484e929acec2622f261bf5c8d9d1894267dac93-bisyekx'
        .split('')
        .reversed
        .join();
  }


  Db? _db;
  Completer<Db?>? _mongoConnectingCompleter;

  Future<Db?> _getMongoDb() async {
    if (_db != null && _db!.isConnected) {
      return _db;
    }
    if (_db != null && !_db!.isConnected) {
      markMongoDbDisconnected();
    }
    if (_mongoConnectingCompleter != null && !_mongoConnectingCompleter!.isCompleted) {
      return _mongoConnectingCompleter!.future;
    }

    final completer = Completer<Db?>();
    _mongoConnectingCompleter = completer;

    try {
      final newDb = await Db.create(_mongoUri);
      await newDb.open(secure: true).timeout(const Duration(seconds: 7));
      _db = newDb;
      completer.complete(_db);
      return _db;
    } catch (_) {
      try {
        final directDb = await Db.create(_directMongoSeedlist);
        await directDb.open(secure: true).timeout(const Duration(seconds: 8));
        _db = directDb;
        completer.complete(_db);
        return _db;
      } catch (_) {
        _db = null;
        completer.complete(null);
        return null;
      }
    } finally {
      _mongoConnectingCompleter = null;
    }
  }

  void markMongoDbDisconnected() {
    try {
      _db?.close();
    } catch (_) {}
    _db = null;
  }

  Future<Db?> _getSafeMongoDb() async {
    if (_db != null && _db!.isConnected) {
      return _db;
    }
    markMongoDbDisconnected();
    return await _getMongoDb();
  }

  final List<String> baseUrls = [
    'https://fantaeventi-backend-2-0.onrender.com/api',
  ];

  Map<String, String> get defaultHeaders => {
    'content-type': 'application/json',
    'bypass-tunnel-reminder': 'true',
    'User-Agent': 'FantaEventiApp',
  };

  Utente? _currentUser;
  final List<Utente> _utenti = [];
  final List<Evento> _eventi = [];
  final List<BonusMalus> _bonusMalusList = [];
  final List<Votazione> _votazioniList = [];
  final List<RichiestaVar> _richiesteVar = [];

  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(seconds: 45);

  void invalidateCache() {
    _lastFetchTime = null;
  }

  void clearUserSessionCache() {
    _lastFetchTime = null;
    _cachedTutorialPremioRiscattato = null;
    _eventi.clear();
    _bonusMalusList.clear();
    _votazioniList.clear();
    _richiesteVar.clear();
  }

  Utente? get currentUser => _currentUser;
  List<Evento> get eventi => List.unmodifiable(_eventi);
  List<BonusMalus> get bonusMalusList => List.unmodifiable(_bonusMalusList);
  List<Votazione> get votazioniList => List.unmodifiable(_votazioniList);

  static String hashPassword(String password) {
    const salt = 'FantaEventi2026_Secure_Salt_#99';
    final bytes = utf8.encode('$password$salt');
    return sha256.convert(bytes).toString();
  }

  bool _rememberMeSession = false;

  Future<void> _saveSession(Utente utente, {bool? rememberMe}) async {
    final shouldRemember = rememberMe ?? _rememberMeSession;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (shouldRemember) {
        await prefs.setString('saved_user_json', jsonEncode(utente.toJson()));
        await prefs.setString('saved_user_nickname', utente.nickname);
        await prefs.setBool('has_password_auth_v2', true);
        await prefs.setBool('remember_me_enabled', true);
      } else {
        await prefs.remove('saved_user_json');
        await prefs.remove('saved_user_nickname');
        await prefs.remove('has_password_auth_v2');
        await prefs.setBool('remember_me_enabled', false);
      }
    } catch (_) {}
  }

  // --- GESTIONE TOKEN NOTIFICHE PUSH FCM ---
  String _fcmServerKey = '';
  String get fcmServerKey => _fcmServerKey;

  void impostaFcmServerKey(String key) {
    _fcmServerKey = key.trim();
  }

  Future<void> salvaFcmToken(String token) async {
    final cur = _currentUser;
    final cleanToken = token.trim();
    if (cur == null || cleanToken.isEmpty) return;
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? uObjId;
        try {
          if (cur.id.isNotEmpty && cur.id.length == 24) {
            uObjId = ObjectId.fromHexString(cur.id);
          }
        } catch (_) {}

        final selector = uObjId != null
            ? where.id(uObjId)
            : where.eq('nome', cur.nome);

        await db.collection('Utenti').update(
          selector,
          modify.addToSet('fcmTokens', cleanToken),
        );
        debugPrint('✅ FCM token registrato su MongoDB per ${cur.nome}: $cleanToken');
      }
    } catch (e) {
      debugPrint('Errore salvaFcmToken MongoDB: $e');
    }
  }

  Future<void> rimuoviFcmToken(String token) async {
    await rimuoviFcmTokenGlobale(token);
  }

  Future<void> rimuoviFcmTokenGlobale(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        await db.collection('Utenti').update(
          where.eq('fcmTokens', cleanToken),
          modify.pull('fcmTokens', cleanToken),
          multiUpdate: true,
        );
        debugPrint('🧹 Token FCM rimosso globalmente da MongoDB: $cleanToken');
      }
    } catch (e) {
      debugPrint('Errore rimuoviFcmTokenGlobale MongoDB: $e');
    }
  }

  /// Risolve rigorosamente qualsiasi nome o alias nel NICKNAME ufficiale del giocatore.
  /// Il Nome e Cognome NON devono MAI apparire nel gameplay, notifiche, votazioni o feed.
  String resolveNickname(String? candidate) {
    if (candidate == null) return _currentUser?.nickname ?? 'Cloud';
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return _currentUser?.nickname ?? 'Cloud';
    final lower = trimmed.toLowerCase();

    // Mappe statiche di sicurezza blindata per gli account principali
    if (lower == 'claudio' || lower == 'cloud' || lower == 'claude') return 'Cloud';
    if (lower == 'filippo' || lower == 'pippoforte' || lower == 'pippo forte') return 'Pippoforte';
    if (lower == 'antonio' || lower == 'ugnom' || lower == 'ugnome') return 'Ugnom';

    // Ricerca dinamica su utenti caricati in memoria
    for (var u in _utenti) {
      if (u.nickname.isNotEmpty) {
        if (u.nickname.toLowerCase() == lower) return u.nickname;
        if (u.nome.isNotEmpty && u.nome.toLowerCase() == lower) return u.nickname;
        if (u.cognome.isNotEmpty && '${u.nome} ${u.cognome}'.toLowerCase() == lower) return u.nickname;
        if (u.username.isNotEmpty && u.username.toLowerCase() == lower) return u.nickname;
      }
    }

    // Se corrisponde all'utente corrente
    if (_currentUser != null && _currentUser!.nickname.isNotEmpty) {
      if (_currentUser!.nome.toLowerCase() == lower ||
          _currentUser!.username.toLowerCase() == lower ||
          _currentUser!.nickname.toLowerCase() == lower) {
        return _currentUser!.nickname;
      }
    }

    return trimmed;
  }

  /// Verifica se due stringhe (nome, nickname o alias) appartengono alla stessa persona
  bool isSamePerson(String? a, String? b) {
    if (a == null || b == null) return false;
    final nickA = resolveNickname(a).toLowerCase();
    final nickB = resolveNickname(b).toLowerCase();
    if (nickA.isNotEmpty && nickA == nickB) return true;
    final cleanA = a.trim().toLowerCase();
    final cleanB = b.trim().toLowerCase();
    if (cleanA.isNotEmpty && cleanA == cleanB) return true;
    return false;
  }

  /// Verifica se un documento Utente da MongoDB corrisponde al nickname/alias specificato.
  /// Evita il bug del mismatch con il campo 'nome' anagrafico (es. Claudio vs Cloud).
  bool matchesUserDoc(Map<String, dynamic> uDoc, String? candidate) {
    if (candidate == null) return false;
    final c = resolveNickname(candidate).trim().toLowerCase();
    if (c.isEmpty) return false;
    final uNick = resolveNickname((uDoc['nickname'] ?? uDoc['username'] ?? '').toString()).trim().toLowerCase();
    if (uNick.isNotEmpty && (uNick == c || isSamePerson(uNick, c))) return true;
    final uName = (uDoc['nome'] ?? '').toString().trim().toLowerCase();
    if (uName.isNotEmpty && (uName == c || isSamePerson(uName, c))) return true;
    final raw = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString();
    if (isSamePerson(raw, candidate)) return true;
    return false;
  }

  Future<List<String>> getFcmTokensPerUtenti(List<String> nicknames) async {
    if (nicknames.isEmpty) return [];
    final resolvedTargets = nicknames.map((n) => resolveNickname(n).trim().toLowerCase()).toSet();
    final Set<String> allTokens = {};

    // 1. Interroga SEMPRE direttamente MongoDB per recuperare i token FCM più aggiornati di tutti i destinatari
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final users = await db.collection('Utenti').find(
          where.fields(['fcmTokens', 'nome', 'nickname', 'username', 'cognome'])
        ).toList().timeout(const Duration(seconds: 4));

        for (var u in users) {
          final raw = (u['nickname'] ?? u['username'] ?? u['nome'] ?? '').toString();
          final uNick = resolveNickname(raw).trim().toLowerCase();
          final rawNome = (u['nome'] ?? '').toString().trim().toLowerCase();
          for (var target in resolvedTargets) {
            if (target == uNick || isSamePerson(target, uNick) || target == rawNome) {
              final tokens = List<String>.from(u['fcmTokens'] ?? []);
              allTokens.addAll(tokens.where((t) => t.trim().isNotEmpty));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Errore getFcmTokensPerUtenti MongoDB: $e');
    }

    // 2. Fallback offline: se MongoDB non è momentaneamente raggiungibile, usa la memoria locale
    if (allTokens.isEmpty) {
      for (var u in _utenti) {
        final uNick = resolveNickname(u.nickname.isNotEmpty ? u.nickname : u.nome).trim().toLowerCase();
        for (var target in resolvedTargets) {
          if (target == uNick || isSamePerson(target, uNick)) {
            allTokens.addAll(u.fcmTokens.where((t) => t.trim().isNotEmpty));
          }
        }
      }
      if (_currentUser != null) {
        final curNick = resolveNickname(_currentUser!.nickname.isNotEmpty ? _currentUser!.nickname : _currentUser!.nome).trim().toLowerCase();
        for (var target in resolvedTargets) {
          if (target == curNick || isSamePerson(target, curNick)) {
            allTokens.addAll(_currentUser!.fcmTokens.where((t) => t.trim().isNotEmpty));
          }
        }
      }
    }

    return allTokens.toList();
  }

  Future<Map<String, dynamic>?> getFirebaseServiceAccountConfig() async {
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final doc = await db.collection('AppConfig').findOne(where.eq('chiave', 'firebase_service_account'));
        if (doc != null && doc['config'] != null) {
          return Map<String, dynamic>.from(doc['config'] as Map);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> logout() async {
    try {
      unawaited(PushNotificationService.instance.unregisterCurrentDeviceToken());
    } catch (_) {}
    _currentUser = null;
    _rememberMeSession = false;
    _cachedTutorialPremioRiscattato = null;
    clearUserSessionCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_json');
      await prefs.remove('saved_user_nickname');
      await prefs.remove('has_password_auth_v2');
      await prefs.remove('remember_me_enabled');
    } catch (_) {}
  }

  Future<bool> eliminaAccount({String? utenteId, String? nickname, String? nome}) async {
    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/utenti/elimina-account'),
          headers: defaultHeaders,
          body: jsonEncode({
            'utenteId': utenteId,
            'nickname': nickname,
            'nome': nome,
          }),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          await logout();
          invalidateCache();
          return true;
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    try {
      final db = await _getMongoDb();
      if (db == null || !db.isConnected) return false;

      final cleanNick = (nickname ?? '').trim().toLowerCase();
      final cleanName = (nome ?? '').trim().toLowerCase();

      // 1. Trova e rimuovi l'utente da MongoDB Atlas
      final allUsers = await db.collection('Utenti').find().toList();
      Map<String, dynamic>? targetUser;
      for (var u in allUsers) {
        final uIdStr = u['_id']?.toHexString() ?? u['_id']?.toString() ?? '';
        final uNick = (u['nickname'] ?? u['username'] ?? '').toString().trim().toLowerCase();
        final uNome = (u['nome'] ?? '').toString().trim().toLowerCase();

        if (utenteId != null && utenteId.isNotEmpty && uIdStr == utenteId) {
          targetUser = u;
          break;
        }
        if (cleanNick.isNotEmpty && (uNick == cleanNick || uNome == cleanNick)) {
          targetUser = u;
          break;
        }
        if (cleanName.isNotEmpty && (uNome == cleanName || uNick == cleanName)) {
          targetUser = u;
          break;
        }
      }

      if (targetUser != null) {
        final uId = targetUser['_id'];
        final sel = uId is ObjectId ? where.id(uId) : where.eq('_id', uId);
        await db.collection('Utenti').remove(sel);
      }

      // 2. Rimuovi notifiche collegate
      final matchNames = <String>{};
      if (cleanNick.isNotEmpty) matchNames.add(cleanNick);
      if (cleanName.isNotEmpty) matchNames.add(cleanName);
      if (targetUser != null) {
        final tn = (targetUser['nickname'] ?? targetUser['username'] ?? '').toString();
        final tm = (targetUser['nome'] ?? '').toString();
        if (tn.isNotEmpty) matchNames.add(tn);
        if (tm.isNotEmpty) matchNames.add(tm);
      }

      for (var name in matchNames) {
        try {
          await db.collection('Notifiche').remove(
            where.eq('destinatario', name).or(where.eq('mittente', name)),
          );
        } catch (_) {}
      }

      // 3. Esegui logout e pulizia sessione locale
      await logout();
      invalidateCache();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Utente?> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasPasswordAuth = prefs.getBool('has_password_auth_v2') ?? false;
      final rememberMe = prefs.getBool('remember_me_enabled') ?? false;

      // Se la sessione e' precedente al sistema password o rememberMe e' disattivato, forza il Login
      if (!hasPasswordAuth || !rememberMe) {
        await prefs.remove('saved_user_json');
        await prefs.remove('saved_user_nickname');
        await prefs.remove('has_password_auth_v2');
        _rememberMeSession = false;
        return null;
      }

      final userJsonStr = prefs.getString('saved_user_json');
      if (userJsonStr != null && userJsonStr.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(userJsonStr);
        _currentUser = Utente.fromJson(data);
        if (_currentUser != null && (_currentUser!.avatarUrl.contains('pravatar') || _currentUser!.avatarUrl.contains('unsplash.com/photo-1535713875002'))) {
          _currentUser = _currentUser!.copyWith(avatarUrl: '');
        }
        _rememberMeSession = true;
        await _loadCachedUsersAndAvatars();
        clearUserSessionCache();
        return _currentUser;
      }
    } catch (_) {}
    _rememberMeSession = false;
    return null;
  }

  // --- GUIDA & REGOLAMENTO ONBOARDING (PROFILATO PER UTENTE) ---
  Future<bool> haVistoGuidaRegole([String? userIdentifier]) async {
    try {
      final curUser = _currentUser;
      if (curUser != null && curUser.haVistoGuida) {
        return true;
      }

      final prefs = await SharedPreferences.getInstance();
      final idKey = userIdentifier ?? curUser?.id ?? curUser?.nome ?? '';
      final cleanKey = idKey.trim().toLowerCase();

      if (cleanKey.isNotEmpty) {
        if (prefs.getBool('guida_regole_completata_$cleanKey') == true) return true;
        if (curUser != null && curUser.id.isNotEmpty && prefs.getBool('guida_regole_completata_${curUser.id}') == true) return true;
        if (curUser != null && prefs.getBool('guida_regole_completata_${curUser.nome.toLowerCase()}') == true) return true;
      }

      if (curUser != null) {
        final db = await _getSafeMongoDb();
        if (db != null && db.isConnected) {
          ObjectId? uObjId;
          try {
            if (curUser.id.isNotEmpty && curUser.id.length == 24) {
              uObjId = ObjectId.fromHexString(curUser.id);
            }
          } catch (_) {}

          final selector = uObjId != null ? where.id(uObjId) : where.eq('nome', curUser.nome);
          final uDoc = await db.collection('Utenti').findOne(selector);
          if (uDoc != null && (uDoc['haVistoGuida'] == true || uDoc['tutorialV3Completato'] == true)) {
            await prefs.setBool('guida_regole_completata_${curUser.nome.toLowerCase()}', true);
            if (curUser.id.isNotEmpty) {
              await prefs.setBool('guida_regole_completata_${curUser.id}', true);
            }
            _currentUser = curUser.copyWith(haVistoGuida: true);
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool? _cachedTutorialPremioRiscattato;

  bool get hasRedeemedTutorialLocally {
    if (_cachedTutorialPremioRiscattato == true) return true;
    final cur = _currentUser;
    if (cur != null && cur.haVistoGuida) return true;
    return false;
  }

  Future<bool> haGiaRiscattatoPremioTutorial() async {
    try {
      final curUser = _currentUser;
      if (curUser == null) return false;
      if (curUser.haVistoGuida) {
        _cachedTutorialPremioRiscattato = true;
        return true;
      }
      if (_cachedTutorialPremioRiscattato == true) return true;

      final prefs = await SharedPreferences.getInstance();
      final localVal = prefs.getBool('tutorial_premio_riscattato_v3_${curUser.nome.toLowerCase()}') ??
          prefs.getBool('tutorial_premio_riscattato_v3_${curUser.nome}') ??
          (curUser.id.isNotEmpty ? prefs.getBool('tutorial_premio_riscattato_v3_${curUser.id}') : null);
      if (localVal == true) {
        _cachedTutorialPremioRiscattato = true;
        return true;
      }

      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? uObjId;
        try {
          if (curUser.id.isNotEmpty && curUser.id.length == 24) {
            uObjId = ObjectId.fromHexString(curUser.id);
          }
        } catch (_) {}

        final selector = uObjId != null ? where.id(uObjId) : where.eq('nome', curUser.nome);
        final uDoc = await db.collection('Utenti').findOne(selector);
        if (uDoc != null) {
          if (uDoc['tutorialPremioRiscattato'] == true ||
              uDoc['tutorialV3Completato'] == true ||
              uDoc['haVistoGuida'] == true) {
            _cachedTutorialPremioRiscattato = true;
            await prefs.setBool('tutorial_premio_riscattato_v3_${curUser.nome.toLowerCase()}', true);
            if (curUser.id.isNotEmpty) {
              await prefs.setBool('tutorial_premio_riscattato_v3_${curUser.id}', true);
            }
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> segnaGuidaRegoleCompletata({bool awardXp = true}) async {
    try {
      final curUser = _currentUser;
      if (curUser != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('guida_regole_completata_${curUser.nome.toLowerCase()}', true);
        if (curUser.id.isNotEmpty) {
          await prefs.setBool('guida_regole_completata_${curUser.id}', true);
        }

        // Prevenzione totale farming: se ha già riscattato, non incrementare MAI più XP
        final bool alreadyRedeemed = await haGiaRiscattatoPremioTutorial();
        final bool shouldActuallyAward = awardXp && !alreadyRedeemed;

        _cachedTutorialPremioRiscattato = true;
        await prefs.setBool('tutorial_premio_riscattato_v3_${curUser.nome.toLowerCase()}', true);
        if (curUser.id.isNotEmpty) {
          await prefs.setBool('tutorial_premio_riscattato_v3_${curUser.id}', true);
        }

        final badge = curUser.livello >= 2 ? '🎓 Pioniero FantaEventi' : '🌱 Recluta FantaEventi';
        final newBadges = List<String>.from(curUser.badgeList);
        if (!newBadges.contains(badge)) {
          newBadges.add(badge);
        }
        
        final prog = shouldActuallyAward
            ? XpProgression.aggiungiXp(
                livelloAttuale: curUser.livello,
                xpLivelloAttuale: curUser.xp,
                deltaXp: 100,
                xpTotaliAttuali: curUser.xpTotali,
              )
            : XpProgression.calcolaProgressione(xpTotali: curUser.xpTotali > 0 ? curUser.xpTotali : curUser.xp);

        _currentUser = curUser.copyWith(
          haVistoGuida: true,
          livello: prog.livello,
          xp: prog.xp,
          xpProssimoLivello: prog.xpProssimoLivello,
          xpTotali: prog.xpTotali,
          badgeList: newBadges,
        );
        await _saveSession(_currentUser!);

        final db = await _getSafeMongoDb();
        if (db != null && db.state == State.open) {
          final uColl = db.collection('Utenti');
          var mod = modify
            .set('haVistoGuida', true)
            .set('tutorialV3Completato', true)
            .set('tutorialPremioRiscattato', true)
            .set('livello', prog.livello)
            .set('xp', prog.xp)
            .set('xpProssimoLivello', prog.xpProssimoLivello)
            .set('xpTotali', prog.xpTotali)
            .addToSet('badgeList', badge);

          ObjectId? uObjId;
          try {
            if (curUser.id.isNotEmpty && curUser.id.length == 24) {
              uObjId = ObjectId.fromHexString(curUser.id);
            }
          } catch (_) {}

          final selector = uObjId != null ? where.id(uObjId) : where.eq('nome', curUser.nome);
          await uColl.update(selector, mod);
        }
      }
    } catch (_) {}
  }

  Future<void> resettaTutorialGuidato() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final curUser = _currentUser;
      if (curUser != null) {
        await prefs.remove('guida_regole_completata_${curUser.nome.toLowerCase()}');
        if (curUser.id.isNotEmpty) {
          await prefs.remove('guida_regole_completata_${curUser.id}');
        }
        await prefs.remove('tutorial_premio_riscattato_v3_${curUser.nome.toLowerCase()}');
        if (curUser.id.isNotEmpty) {
          await prefs.remove('tutorial_premio_riscattato_v3_${curUser.id}');
        }
        _currentUser = curUser.copyWith(haVistoGuida: false);
        await _saveSession(_currentUser!);
      }
      _cachedTutorialPremioRiscattato = null;
      await prefs.remove('tutorial_interactive_v3_completato');
      await prefs.remove('tutorial_premio_riscattato_v3');
      await prefs.remove('tutorial_spotlight_v2_completato');
      await prefs.remove('guida_regole_completata_v1');
    } catch (_) {}
  }

  Future<void> assicuraNotificaBenvenuto(String nickname) async {
    try {
      final nots = await getNotifiche(nickname);
      final hasWelcome = nots.any((n) => 
        (n['titolo'] ?? '').toString().contains('Benvenuto') || 
        (n['mittente'] ?? '').toString().contains('Redazione'));
      if (!hasWelcome) {
        final db = await _getMongoDb();
        if (db != null && db.isConnected) {
          await db.collection('Notifiche').insertOne({
            'mittente': 'Redazione FantaEventi 👑',
            'destinatario': nickname,
            'titolo': 'Benvenuto in FantaEventi! 🎉',
            'messaggio': 'Ciao $nickname! Benvenuto nella community ufficiale di FantaEventi. Da qui riceverai tutti gli inviti ad eventi dei tuoi amici, le notifiche del VAR e gli aggiornamenti di classifica. Puoi eliminare qualsiasi notifica toccando la \'X\' in alto a destra nella card!',
            'tipo': 'benvenuto',
            'stato': 'letto',
            'letto': false,
            'data': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (_) {}
  }

  List<String> _extractAndHealBadgeList(Map<String, dynamic> d, [Db? db]) {
    final List<String> list = [];
    if (d['badgeList'] is List) {
      for (var b in (d['badgeList'] as List)) {
        final str = b.toString().trim();
        if (str.isNotEmpty && !list.contains(str)) {
          list.add(str);
        }
      }
    }
    // Self-healing automatico: se sono presenti badge memorizzati sotto 'badges'
    if (d['badges'] is List) {
      bool addedFromBadges = false;
      for (var b in (d['badges'] as List)) {
        final str = b.toString().trim();
        if (str.isNotEmpty && !list.contains(str)) {
          list.add(str);
          addedFromBadges = true;
        }
      }
      if (addedFromBadges && db != null && db.isConnected) {
        try {
          ObjectId? uId;
          if (d['_id'] is ObjectId) {
            uId = d['_id'] as ObjectId;
          } else if (d['_id'] != null) {
            uId = ObjectId.fromHexString(d['_id'].toString());
          }
          if (uId != null) {
            db.collection('Utenti').update(
              where.id(uId),
              modify.set('badgeList', list).unset('badges'),
            );
          }
        } catch (_) {}
      }
    }
    return list;
  }

  // --- LOGIN RIGOROSO REALE DA MONGODB ATLAS (CON PASSWORD HASHATA) ---
  Future<Utente> login(String identifier, String password, {bool rememberMe = true}) async {
    clearUserSessionCache();
    _rememberMeSession = rememberMe;
    final rawIdentifier = identifier.trim();
    final cleanIdentifier = rawIdentifier;
    final cleanIdentifierLower = rawIdentifier.toLowerCase();
    final cleanPassword = password.trim();

    if (rawIdentifier.isEmpty) {
      throw Exception('Inserisci il tuo Nickname o la tua Email');
    }

    final bool isEmailLogin = rawIdentifier.contains('@');

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/login'),
          headers: defaultHeaders,
          body: jsonEncode({
            'username': cleanIdentifier,
            'email': cleanIdentifier,
            'nickname': cleanIdentifier,
            'password': cleanPassword,
          }),
        ).timeout(const Duration(seconds: 8));

        if (response.body.contains('<html>') || response.body.contains('Welcome to localhost.run')) {
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['needsPasswordSetup'] == true) {
          throw NeedsPasswordSetupException(
            username: data['username']?.toString() ?? cleanIdentifier,
            email: data['email']?.toString() ?? '',
          );
        }

        if (response.statusCode == 200 && data.containsKey('utente')) {
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          if (_currentUser!.isBanned) {
            clearUserSessionCache();
            throw Exception('Account sospeso. Questo profilo è stato bloccato per violazione delle linee guida della community.');
          }
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe);
          return _currentUser!;
        } else if (response.statusCode == 403 || response.statusCode == 401) {
          throw Exception(data['error']?.toString() ?? 'Password non corretta. Riprova!');
        } else if (response.statusCode == 404 || data['notFound'] == true) {
          throw Exception('Nessun utente trovato nel database per "$cleanIdentifier". Registrati prima di accedere!');
        }
      } catch (e) {
        if (e is NeedsPasswordSetupException) rethrow;
        if (e is Exception && (e.toString().contains('Nessun utente trovato') || e.toString().contains('Password non corretta') || e.toString().contains('Inserisci la password') || e.toString().contains('sospeso') || e.toString().contains('bloccato'))) {
          rethrow;
        }
      }
    }

    // 2. Rete di salvataggio: fallback trasparente su MongoDB Atlas
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find(where.excludeFields(['avatarUrl'])).toList().timeout(const Duration(seconds: 8));

        for (var d in docs) {
          final actualNick = (d['nickname'] ?? d['username'] ?? '').toString().trim();
          final actualUser = (d['username'] ?? '').toString().trim();
          final actualNome = (d['nome'] ?? '').toString().trim();
          final actualCognome = (d['cognome'] ?? '').toString().trim();
          final actualEmail = (d['email'] ?? '').toString().trim();

          final primaryNick = actualNick.isNotEmpty ? actualNick : (actualUser.isNotEmpty ? actualUser : actualNome);
          final primaryNome = actualNome.isNotEmpty ? actualNome : primaryNick;

          final isClaudioAlias = (cleanIdentifierLower == 'claudio' &&
              (primaryNick.toLowerCase() == 'cloud' || actualEmail.toLowerCase().contains('claudio.simonelli')));

          bool isMatch = false;

          if (isEmailLogin) {
            // Accesso con Email: case-insensitive
            if (actualEmail.toLowerCase() == cleanIdentifierLower) {
              isMatch = true;
            }
          } else {
            // Accesso con Nickname o Nome: case-sensitive o case-insensitive
            if (rawIdentifier == primaryNick ||
                rawIdentifier == actualUser ||
                rawIdentifier == actualNome ||
                isClaudioAlias) {
              isMatch = true;
            } else if (cleanIdentifierLower == primaryNick.toLowerCase() ||
                cleanIdentifierLower == actualUser.toLowerCase() ||
                cleanIdentifierLower == actualNome.toLowerCase()) {
              isMatch = true;
            }
          }

          if (isMatch) {
            final existingPasswordHash = (d['password'] ?? d['passwordHash'] ?? '').toString().trim();

            // Riconoscimento al primo accesso: utente esistente ma senza password impostata
            if (existingPasswordHash.isEmpty) {
              throw NeedsPasswordSetupException(
                username: primaryNick,
                email: actualEmail,
              );
            }

            // Utente con password già registrata
            if (cleanPassword.isEmpty) {
              throw Exception('Inserisci la password per accedere.');
            }

            final inputHash = hashPassword(cleanPassword);
            if (inputHash != existingPasswordHash) {
              throw Exception('Password non corretta. Riprova!');
            }

            // Recupera il documento completo con avatarUrl solo per l'utente loggato
            final fullDoc = await db.collection('Utenti').findOne(where.id(d['_id']));
            final userDoc = fullDoc ?? d;

            final jsonMap = {
              'id': userDoc['_id']?.toHexString() ?? userDoc['_id']?.toString() ?? '',
              'nome': primaryNome,
              'cognome': actualCognome,
              'username': primaryNick,
              'nickname': primaryNick,
              'email': actualEmail,
              'avatarUrl': userDoc['avatarUrl'] ?? '',
              'livello': userDoc['livello'] ?? 1,
              'xp': userDoc['xp'] ?? 100,
              'xpProssimoLivello': userDoc['xpProssimoLivello'] ?? 1000,
              'puntiTotali': userDoc['puntiTotali'] ?? 0,
              'badgeList': _extractAndHealBadgeList(userDoc, db),
              'storicoVoti': userDoc['storicoVoti'] ?? [],
              'codiceAmico': userDoc['codiceAmico'] ?? '',
              'amici': userDoc['amici'] ?? [],
              'richiesteAmicizia': userDoc['richiesteAmicizia'] ?? [],
              'badgeVincitore': userDoc['badgeVincitore'] ?? [],
              'countGiudice': userDoc['countGiudice'] ?? 0,
              'countReMalus': userDoc['countReMalus'] ?? 0,
              'countFantasma': userDoc['countFantasma'] ?? 0,
              'countSbirro': userDoc['countSbirro'] ?? 0,
              'countGiustiziere': userDoc['countGiustiziere'] ?? 0,
              'haVistoGuida': userDoc['haVistoGuida'] == true,
              'dataRegistrazione': userDoc['dataRegistrazione'] ?? userDoc['dataCreazione'] ?? '',
              'utentiBloccati': userDoc['utentiBloccati'] ?? [],
              'isBanned': userDoc['isBanned'] == true,
            };
            final uAvatar = (userDoc['avatarUrl'] ?? '').toString();
            if (uAvatar.isNotEmpty) {
              _cacheSingleAvatar(primaryNome, primaryNick, uAvatar);
            }
            _currentUser = Utente.fromJson(jsonMap);
            if (_currentUser!.isBanned) {
              clearUserSessionCache();
              throw Exception('Account sospeso. Questo profilo è stato bloccato per violazione delle linee guida della community.');
            }
            clearUserSessionCache();
            await _saveCachedUsersAndAvatars();
            await _saveSession(_currentUser!, rememberMe: rememberMe);
            return _currentUser!;
          }
        }

        throw Exception(
          isEmailLogin
              ? 'Nessun utente trovato con l\'email "$rawIdentifier". Registrati prima di accedere!'
              : 'Nessun utente trovato con il nickname "$rawIdentifier". Registrati prima di accedere!',
        );
      }
      throw Exception('Impossibile connettersi al database MongoDB.');
    } catch (e) {
      markMongoDbDisconnected();
      if (e is NeedsPasswordSetupException) rethrow;
      if (e is Exception && (
          e.toString().contains('Nessun utente trovato') ||
          e.toString().contains('Password non corretta') ||
          e.toString().contains('Inserisci la password') ||
          e.toString().contains('Attenzione alle maiuscole/minuscole') ||
          e.toString().contains('sospeso') ||
          e.toString().contains('bloccato'))) {
        rethrow;
      }
      throw Exception('Impossibile connettersi al server. Verifica la tua connessione internet e riprova.');
    }
  }

  // --- IMPOSTAZIONE PASSWORD AL PRIMO ACCESSO (PER UTENTI ESISTENTI) ---
  Future<Utente> impostaPasswordPrimoAccesso({
    required String username,
    required String nuovaPassword,
    bool rememberMe = true,
  }) async {
    clearUserSessionCache();
    _rememberMeSession = rememberMe;
    final cleanPass = nuovaPassword.trim();
    if (cleanPass.length < 6) {
      throw Exception('La password deve contenere almeno 6 caratteri.');
    }
    final hashedPassword = hashPassword(cleanPass);
    final cleanUser = username.trim().toLowerCase();

    // 1. Connessione DIRETTA a MongoDB Atlas (<30ms)
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        for (var d in docs) {
          final actualNick = (d['nickname'] ?? d['username'] ?? '').toString().trim();
          final actualUser = (d['username'] ?? '').toString().trim();
          final actualNome = (d['nome'] ?? '').toString().trim();
          final actualCognome = (d['cognome'] ?? '').toString().trim();
          final actualEmail = (d['email'] ?? '').toString().trim();

          final primaryNick = actualNick.isNotEmpty ? actualNick : (actualUser.isNotEmpty ? actualUser : actualNome);
          final primaryNome = actualNome.isNotEmpty ? actualNome : primaryNick;

          final isClaudioAlias = (cleanUser == 'claudio' && (primaryNick.toLowerCase() == 'cloud' || actualEmail.toLowerCase().contains('claudio.simonelli')));
          if (primaryNick.toLowerCase() == cleanUser ||
              actualUser.toLowerCase() == cleanUser ||
              actualNome.toLowerCase() == cleanUser ||
              actualEmail.toLowerCase() == cleanUser ||
              isClaudioAlias) {
            ObjectId? objId;
            try {
              objId = d['_id'] is ObjectId ? d['_id'] as ObjectId : ObjectId.fromHexString(d['_id'].toString());
            } catch (_) {}
            final selector = objId != null ? where.id(objId) : where.eq('_id', d['_id']);

            await db.collection('Utenti').update(
              selector,
              modify.set('password', hashedPassword).set('passwordHash', hashedPassword),
            );

            final jsonMap = {
              'id': objId?.toHexString() ?? d['_id']?.toString() ?? '',
              'nome': primaryNome,
              'cognome': actualCognome,
              'username': primaryNick,
              'nickname': primaryNick,
              'email': actualEmail,
              'avatarUrl': d['avatarUrl'] ?? '',
              'livello': d['livello'] ?? 1,
              'xp': d['xp'] ?? 100,
              'xpProssimoLivello': d['xpProssimoLivello'] ?? 1000,
              'puntiTotali': d['puntiTotali'] ?? 0,
              'badgeList': _extractAndHealBadgeList(d, db),
              'storicoVoti': d['storicoVoti'] ?? [],
              'codiceAmico': d['codiceAmico'] ?? '',
              'amici': d['amici'] ?? [],
              'richiesteAmicizia': d['richiesteAmicizia'] ?? [],
              'badgeVincitore': d['badgeVincitore'] ?? [],
              'countGiudice': d['countGiudice'] ?? 0,
              'countReMalus': d['countReMalus'] ?? 0,
              'countFantasma': d['countFantasma'] ?? 0,
              'countSbirro': d['countSbirro'] ?? 0,
              'countGiustiziere': d['countGiustiziere'] ?? 0,
              'haVistoGuida': d['haVistoGuida'] == true,
              'dataRegistrazione': d['dataRegistrazione'] ?? d['dataCreazione'] ?? '',
              'utentiBloccati': d['utentiBloccati'] ?? [],
              'isBanned': d['isBanned'] == true,
            };
            _currentUser = Utente.fromJson(jsonMap);
            clearUserSessionCache();
            await _saveSession(_currentUser!, rememberMe: rememberMe);
            return _currentUser!;
          }
        }
      }
    } catch (_) {}

    // 2. Fallback HTTP su backend
    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/utenti/imposta-password'),
          headers: defaultHeaders,
          body: jsonEncode({
            'username': username,
            'password': cleanPass,
          }),
        ).timeout(const Duration(seconds: 10));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 200 && data.containsKey('utente')) {
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe);
          return _currentUser!;
        }
      } catch (_) {}
    }

    throw Exception('Impossibile salvare la nuova password. Verifica la connessione di rete.');
  }

  // Genera suggerimenti intelligenti e alternativi per un nickname occupato
  List<String> generaSuggerimentiNickname(String baseNick, Set<String> existingLowerNicks) {
    final clean = baseNick.trim();
    final List<String> candidates = [];

    // 1. Aggiunte numeriche comuni
    candidates.add('${clean}1234');
    candidates.add('${clean}2026');
    candidates.add('${clean}99');
    candidates.add('${clean}7');

    // 2. Raddoppio ultima lettera se alfabetica (es. cloudd)
    if (clean.isNotEmpty) {
      final lastChar = clean[clean.length - 1];
      if (RegExp(r'[a-zA-Z]').hasMatch(lastChar)) {
        candidates.add('$clean$lastChar');
      }
    }

    // 3. Prefissi e suffissi fanta / goliardici
    candidates.add('${clean}_fanta');
    candidates.add('il_$clean');
    candidates.add('${clean}_pro');
    candidates.add('${clean}_real');

    // 4. Numeri casuali
    final rnd = Random();
    candidates.add('${clean}_${rnd.nextInt(899) + 100}');
    candidates.add('$clean${rnd.nextInt(89) + 10}');

    final List<String> results = [];
    final Set<String> seenLower = {};

    for (final cand in candidates) {
      final candLower = cand.toLowerCase();
      if (!existingLowerNicks.contains(candLower) && !seenLower.contains(candLower)) {
        seenLower.add(candLower);
        results.add(cand);
        if (results.length >= 3) break;
      }
    }

    return results;
  }

  // Verifica asincrona di disponibilità del nickname con generazione suggerimenti
  Future<NicknameCheckResult> verificaDisponibilitaNickname(String nickname) async {
    final cleanNick = nickname.trim();
    if (cleanNick.length < 3) {
      return const NicknameCheckResult(
        disponibile: false,
        messaggio: 'Il nickname deve contenere almeno 3 caratteri.',
        suggerimenti: [],
      );
    }

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.get(
          Uri.parse('$url/utenti/check-nickname?nick=${Uri.encodeComponent(cleanNick)}'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final bool disp = data['disponibile'] == true;
          final List<String> sugg = (data['suggerimenti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          return NicknameCheckResult(
            disponibile: disp,
            messaggio: data['messaggio']?.toString(),
            suggerimenti: sugg,
          );
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    try {
      final db = await _getMongoDb().timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        final existingLower = <String>{};
        for (var d in docs) {
          final uNick = (d['nickname'] ?? d['username'] ?? '').toString().trim().toLowerCase();
          final uUser = (d['username'] ?? '').toString().trim().toLowerCase();
          final uName = (d['nome'] ?? '').toString().trim().toLowerCase();
          if (uNick.isNotEmpty) existingLower.add(uNick);
          if (uUser.isNotEmpty) existingLower.add(uUser);
          if (uName.isNotEmpty) existingLower.add(uName);
        }

        if (existingLower.contains(cleanNick.toLowerCase())) {
          final suggerimenti = generaSuggerimentiNickname(cleanNick, existingLower);
          return NicknameCheckResult(
            disponibile: false,
            messaggio: 'Nome utente già in uso! Prova uno di questi:',
            suggerimenti: suggerimenti,
          );
        } else {
          return const NicknameCheckResult(
            disponibile: true,
            messaggio: 'Nome utente disponibile! ✨',
            suggerimenti: [],
          );
        }
      }
    } catch (_) {}

    return const NicknameCheckResult(
      disponibile: true,
      messaggio: null,
      suggerimenti: [],
    );
  }

  // --- REGISTRAZIONE ESPLICITA DI UN NUOVO UTENTE SU MONGODB ATLAS (CON PASSWORD) ---
  Future<Utente> registrazione({
    required String nome,
    required String cognome,
    required String nickname,
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    clearUserSessionCache();
    _rememberMeSession = rememberMe;
    final cleanPass = password.trim();
    if (cleanPass.length < 6) {
      throw Exception('La password deve contenere almeno 6 caratteri.');
    }
    final cleanNick = nickname.trim();
    if (cleanNick.length < 3) {
      throw Exception('Il nickname deve contenere almeno 3 caratteri.');
    }
    final hashedPassword = hashPassword(cleanPass);
    final cleanEmail = email.trim();

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/registrazione'),
          headers: defaultHeaders,
          body: jsonEncode({
            'nome': nome.trim(),
            'cognome': cognome.trim(),
            'username': cleanNick,
            'nickname': cleanNick,
            'email': cleanEmail,
            'password': cleanPass,
          }),
        ).timeout(const Duration(seconds: 8));

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (response.statusCode == 200 && data.containsKey('utente')) {
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe);
          return _currentUser!;
        } else if (data['suggerimenti'] != null) {
          final sugg = (data['suggerimenti'] as List<dynamic>).map((e) => e.toString()).toList();
          throw NicknameAlreadyTakenException(
            nickname: cleanNick,
            suggerimenti: sugg,
          );
        } else if (data.containsKey('error')) {
          throw Exception(data['error'].toString());
        }
      } catch (e) {
        if (e is NicknameAlreadyTakenException) rethrow;
        if (e is Exception && e.toString().contains('esiste già')) rethrow;
      }
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        final existingLower = <String>{};

        for (var d in docs) {
          final uNick = (d['nickname'] ?? d['username'] ?? '').toString().trim().toLowerCase();
          final uUser = (d['username'] ?? '').toString().trim().toLowerCase();
          final uName = (d['nome'] ?? '').toString().trim().toLowerCase();
          final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
          if (uNick.isNotEmpty) existingLower.add(uNick);
          if (uUser.isNotEmpty) existingLower.add(uUser);
          if (uName.isNotEmpty) existingLower.add(uName);

          if (cleanEmail.isNotEmpty && uEmail == cleanEmail.toLowerCase()) {
            throw Exception('Un account con questa Email esiste già!');
          }
        }

        if (existingLower.contains(cleanNick.toLowerCase())) {
          final suggerimenti = generaSuggerimentiNickname(cleanNick, existingLower);
          throw NicknameAlreadyTakenException(
            nickname: cleanNick,
            suggerimenti: suggerimenti,
          );
        }

        final cleanNome = nome.trim();
        final newDoc = {
          'nome': cleanNome.isNotEmpty ? cleanNome : cleanNick,
          'username': cleanNick,
          'nickname': cleanNick,
          'cognome': cognome.trim(),
          'email': cleanEmail.isNotEmpty ? cleanEmail : '${cleanNick.toLowerCase().replaceAll(' ', '')}@fantaeventi.it',
          'password': hashedPassword,
          'passwordHash': hashedPassword,
          'ruolo': 'partecipante',
          'avatarUrl': '',
          'livello': 1,
          'xp': 100,
          'xpProssimoLivello': 1000,
          'puntiTotali': 0,
          'badgeList': [],
          'storicoVoti': [],
          'codiceAmico': (cleanNick.length >= 3 ? cleanNick.substring(0, 3).toUpperCase() : 'FAN') + (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString(),
          'amici': [],
          'richiesteAmicizia': [],
          'badgeVincitore': [],
          'createdAt': DateTime.now().toIso8601String(),
          'haVistoGuida': false,
          'tutorialV3Completato': false,
          'tutorialPremioRiscattato': false,
        };

        final insertResult = await db.collection('Utenti').insertOne(newDoc);
        final objId = insertResult.id as ObjectId;
        final jsonMap = Map<String, dynamic>.from(newDoc);
        jsonMap['id'] = objId.toHexString();

        _currentUser = Utente.fromJson(jsonMap);
        clearUserSessionCache();
        await _saveSession(_currentUser!, rememberMe: rememberMe);
        return _currentUser!;
      }
    } catch (e) {
      if (e is NicknameAlreadyTakenException) rethrow;
      if (e is Exception && e.toString().contains('esiste già')) rethrow;
    }

    String? lastError;

    // 2. Fallback HTTP su backend Render
    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/registrazione'),
          headers: defaultHeaders,
          body: jsonEncode({
            'nome': nome.trim(),
            'cognome': cognome.trim(),
            'username': cleanNick,
            'nickname': cleanNick,
            'email': cleanEmail,
            'password': cleanPass,
          }),
        ).timeout(const Duration(seconds: 35));

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (response.statusCode == 200 && data.containsKey('utente')) {
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe);
          return _currentUser!;
        } else if (data.containsKey('error')) {
          lastError = data['error'].toString();
        }
      } catch (e) {
        lastError = 'Impossibile contattare il server backend: $e';
      }
    }

    throw Exception(lastError ?? 'Errore durante la registrazione del nuovo utente.');
  }

  // --- INVIO EMAIL TRAMITE BREVO (DIRETTO) ---
  Future<bool> _sendResetEmailDirect({
    required String recipientEmail,
    required String recipientName,
    required String code,
  }) async {
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #121212; color: #FFFFFF; margin: 0; padding: 20px; }
    .card { background-color: #1E1E1E; border-radius: 16px; border: 1px solid #333333; max-width: 500px; margin: 0 auto; padding: 32px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); text-align: center; }
    .logo { font-size: 28px; font-weight: bold; color: #E5A93C; letter-spacing: 1px; margin-bottom: 8px; }
    .subtitle { font-size: 15px; color: #AAAAAA; margin-bottom: 24px; }
    .code-box { background-color: #2A2A2A; border: 2px dashed #E5A93C; border-radius: 12px; padding: 18px 24px; font-size: 32px; font-weight: bold; letter-spacing: 8px; color: #FFD56B; margin: 24px 0; display: inline-block; }
    .info { font-size: 13px; color: #888888; line-height: 1.6; margin-top: 16px; }
    .footer { margin-top: 32px; font-size: 12px; color: #555555; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🎉 FANTA-EVENTI</div>
    <div class="subtitle">Recupero della Password</div>
    <p style="color: #DDDDDD; font-size: 16px;">Ciao <b>$recipientName</b>,</p>
    <p style="color: #BBBBBB; font-size: 14px;">Abbiamo ricevuto una richiesta di reimpostazione della tua password. Usa il seguente codice a 6 cifre per procedere:</p>
    <div class="code-box">$code</div>
    <p class="info">Questo codice scadr&agrave; tra <b>15 minuti</b>.<br>Se non hai richiesto tu il recupero, puoi tranquillamente ignorare questa email.</p>
    <div class="footer">&copy; 2026 Fanta-Eventi. Tutti i diritti riservati.</div>
  </div>
</body>
</html>
''';

    // Invio tramite Brevo REST API (recapito istantaneo a qualsiasi indirizzo)
    try {
      final res = await http.post(
        Uri.parse('https://api.brevo.com/v3/smtp/email'),
        headers: {
          'api-key': _brevoKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'sender': {
            'name': 'Fanta-Eventi',
            'email': 'claudio.simonelli28@gmail.com',
          },
          'to': [
            {
              'email': recipientEmail,
              'name': recipientName,
            }
          ],
          'subject': '🔑 Il tuo codice di recupero Fanta-Eventi: $code',
          'htmlContent': html,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return true;
      }
      print('Errore risposta Brevo (${res.statusCode}): ${res.body}');
      return false;
    } catch (e) {
      print('Eccezione invio Brevo: $e');
      return false;
    }
  }

  // --- RICHIESTA CODICE RECUPERO PASSWORD (6 CIFRE VIA EMAIL) ---
  Future<Map<String, String>> richiediCodiceReset(String identifier) async {
    final cleanIdent = identifier.trim().toLowerCase();
    if (cleanIdent.isEmpty) {
      throw Exception('Inserisci il tuo Nickname o la tua Email.');
    }

    // 1. Connessione DIRETTA a MongoDB Atlas (Istantanea <30ms) + Invio Brevo
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        Map<String, dynamic>? targetDoc;

        for (var d in docs) {
          final uNick = (d['nickname'] ?? d['username'] ?? '').toString().trim().toLowerCase();
          final uUser = (d['username'] ?? '').toString().trim().toLowerCase();
          final uName = (d['nome'] ?? '').toString().trim().toLowerCase();
          final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
          final isClaudioAlias = (cleanIdent == 'claudio' && (uNick == 'cloud' || uName == 'cloud' || uEmail.contains('claudio.simonelli')));
          if (uNick == cleanIdent || uUser == cleanIdent || uName == cleanIdent || uEmail == cleanIdent || isClaudioAlias) {
            targetDoc = d;
            break;
          }
        }

        if (targetDoc == null) {
          throw Exception('Nessun account trovato per "$identifier". Verifica il Nickname o l\'Email.');
        }

        final email = (targetDoc['email'] ?? '').toString().trim();
        final username = (targetDoc['nickname'] ?? targetDoc['username'] ?? targetDoc['nome'] ?? 'Utente').toString();

        if (email.isEmpty) {
          throw Exception('Nessun indirizzo email collegato a questo profilo.');
        }

        // Genera codice casuale a 6 cifre (100000 - 999999)
        final random = Random.secure();
        final code = (100000 + random.nextInt(900000)).toString();
        final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 15));

        await db.collection('PasswordResetTokens').update(
          where.eq('email', email),
          {
            'email': email,
            'username': username,
            'codice': code,
            'scadenza': expiresAt.toIso8601String(),
            'tentativi': 0,
            'creatoIl': DateTime.now().toUtc().toIso8601String(),
          },
          upsert: true,
        );

        final emailSent = await _sendResetEmailDirect(
          recipientEmail: email,
          recipientName: username,
          code: code,
        );

        if (!emailSent) {
          throw Exception('Impossibile recapitare l\'email di verifica. Controlla la tua connessione e riprova.');
        }

        final parts = email.split('@');
        String maskedEmail = email;
        if (parts.length == 2) {
          final local = parts[0];
          if (local.length > 3) {
            maskedEmail = '${local.substring(0, 3)}****@${parts[1]}';
          } else {
            maskedEmail = '${local[0]}****@${parts[1]}';
          }
        }

        return {
          'email': email,
          'maskedEmail': maskedEmail,
          'username': username,
        };
      }
    } catch (e) {
      if (e is Exception && (e.toString().contains('Nessun account trovato') || e.toString().contains('Nessun indirizzo email') || e.toString().contains('Impossibile recapitare'))) {
        rethrow;
      }
    }

    // 2. Fallback HTTP su backend Render
    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/utenti/richiedi-reset-password'),
          headers: defaultHeaders,
          body: jsonEncode({'identifier': cleanIdent}),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return {
            'email': data['email']?.toString() ?? '',
            'maskedEmail': data['maskedEmail']?.toString() ?? '',
            'username': data['username']?.toString() ?? '',
          };
        } else {
          try {
            final data = jsonDecode(response.body);
            if (data is Map && data.containsKey('error')) {
              throw Exception(data['error']);
            }
          } catch (_) {}
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
      }
    }

    throw Exception('Impossibile inviare il codice in questo momento. Verifica la connessione di rete.');
  }

  // --- CONFERMA CODICE E REIMPOSTAZIONE NUOVA PASSWORD ---
  Future<void> confermaCodiceEReset({
    required String email,
    required String codice,
    required String nuovaPassword,
  }) async {
    final cleanEmail = email.trim();
    final cleanCode = codice.trim();
    final cleanPass = nuovaPassword.trim();

    if (cleanPass.length < 6) {
      throw Exception('La password deve contenere almeno 6 caratteri.');
    }

    // 1. Verifica e aggiornamento DIRETTO su MongoDB Atlas (<30ms)
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final resetToken = await db.collection('PasswordResetTokens').findOne(
          where.eq('email', cleanEmail),
        );

        if (resetToken == null) {
          throw Exception('Nessun codice attivo trovato. Richiedi un nuovo codice.');
        }

        final scadenzaStr = resetToken['scadenza']?.toString() ?? '';
        final scadenza = DateTime.tryParse(scadenzaStr);
        if (scadenza == null || DateTime.now().toUtc().isAfter(scadenza)) {
          await db.collection('PasswordResetTokens').remove(where.eq('email', cleanEmail));
          throw Exception('Il codice di verifica è scaduto. Richiedine uno nuovo.');
        }

        final tentativi = (resetToken['tentativi'] ?? 0) as int;
        if (tentativi >= 5) {
          await db.collection('PasswordResetTokens').remove(where.eq('email', cleanEmail));
          throw Exception('Troppi tentativi errati. Per sicurezza richiedi un nuovo codice.');
        }

        final codiceSalvato = (resetToken['codice'] ?? '').toString().trim();
        if (codiceSalvato != cleanCode) {
          await db.collection('PasswordResetTokens').update(
            where.eq('email', cleanEmail),
            modify.inc('tentativi', 1),
          );
          throw Exception('Codice di verifica non corretto. Riprova.');
        }

        // Codice corretto: aggiorno password hashata
        final hashedPassword = hashPassword(cleanPass);
        await db.collection('Utenti').update(
          where.eq('email', cleanEmail),
          modify.set('password', hashedPassword).set('passwordHash', hashedPassword),
        );

        await db.collection('PasswordResetTokens').remove(where.eq('email', cleanEmail));
        clearUserSessionCache();
        return;
      }
    } catch (e) {
      if (e is Exception && (e.toString().contains('Nessun codice attivo') || e.toString().contains('scaduto') || e.toString().contains('Troppi tentativi') || e.toString().contains('Codice di verifica non corretto'))) {
        rethrow;
      }
    }

    // 2. Fallback HTTP su backend Render
    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/utenti/conferma-reset-password'),
          headers: defaultHeaders,
          body: jsonEncode({
            'email': cleanEmail,
            'codice': cleanCode,
            'nuovaPassword': cleanPass,
          }),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          clearUserSessionCache();
          return;
        } else {
          try {
            final data = jsonDecode(response.body);
            if (data is Map && data.containsKey('error')) {
              throw Exception(data['error']);
            }
          } catch (_) {}
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
      }
    }

    throw Exception('Impossibile completare il reset della password. Riprova.');
  }



  Utente getCurrentUser() {
    if (_currentUser == null) {
      throw Exception('Nessun utente autenticato.');
    }
    return _currentUser!;
  }

  Future<Utente?> syncCurrentUserFromDb() async {
    final curUser = _currentUser;
    if (curUser == null) return null;
    try {
      final utenti = await getUtenti();
      final match = utenti.firstWhere(
        (u) => (curUser.id.isNotEmpty && u.id == curUser.id) ||
               u.nickname.trim().toLowerCase() == curUser.nickname.trim().toLowerCase() ||
               u.nome.trim().toLowerCase() == curUser.nome.trim().toLowerCase(),
        orElse: () => curUser,
      );
      final safeAvatar = match.avatarUrl.isNotEmpty
          ? match.avatarUrl
          : (curUser.avatarUrl.isNotEmpty
              ? curUser.avatarUrl
              : (_avatarCache[curUser.nickname.toLowerCase()] ?? ''));
      String finalAvatar = safeAvatar;
      if (finalAvatar.isEmpty) {
        finalAvatar = await fetchAvatarPerUtente(curUser.nickname);
      }
      _currentUser = match.copyWith(avatarUrl: finalAvatar);
      await _saveSession(_currentUser!);
      return _currentUser;
    } catch (_) {
      return _currentUser;
    }
  }

  // --- SALVATAGGIO FOTO PROFILO / AVATAR PERMANENTE SU MONGODB ATLAS ---
  Future<void> aggiornaAvatarUtente(String username, String newAvatarUrl) async {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(avatarUrl: newAvatarUrl);
      await _saveSession(_currentUser!);
    }

    final clean = username.replaceAll(' ', '').trim().toLowerCase();
    if (newAvatarUrl.isNotEmpty) {
      _avatarCache[clean] = newAvatarUrl;
      if (clean == 'cloud') _avatarCache['claudio'] = newAvatarUrl;
      if (clean == 'claudio') _avatarCache['cloud'] = newAvatarUrl;
      if (_currentUser != null) {
        final cNick = _currentUser!.nickname.trim().toLowerCase().replaceAll(' ', '');
        final cNome = _currentUser!.nome.trim().toLowerCase().replaceAll(' ', '');
        if (cNick.isNotEmpty) _avatarCache[cNick] = newAvatarUrl;
        if (cNome.isNotEmpty) _avatarCache[cNome] = newAvatarUrl;
      }
      await _saveCachedUsersAndAvatars();
    }

    // 1. Invio primario al Backend REST Render (invalida la cache RAM del server e aggiorna il DB)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/utenti/avatar'),
          headers: defaultHeaders,
          body: jsonEncode({
            'utente': username,
            'avatarUrl': newAvatarUrl,
          }),
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          break;
        }
      } catch (_) {}
    }

    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final curId = _currentUser?.id;
        ObjectId? curObjId;
        if (curId != null && curId.isNotEmpty) {
          try { curObjId = ObjectId.fromHexString(curId); } catch (_) {}
        }

        final uDocs = await db.collection('Utenti').find().toList();
        for (var uDoc in uDocs) {
          final uName = (uDoc['nome'] ?? '').toString().trim().toLowerCase();
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? '').toString().trim().toLowerCase();
          final uUser = (uDoc['username'] ?? '').toString().trim().toLowerCase();
          final uIdStr = uDoc['_id']?.toHexString() ?? uDoc['_id']?.toString() ?? '';

          final bool isMatchById = (curId != null && curId.isNotEmpty && uIdStr == curId) ||
                                   (curObjId != null && uDoc['_id'] == curObjId);
          final bool isMatchByNick = clean.isNotEmpty && (uNick == clean || uName == clean || uUser == clean);
          final bool isClaudioAlias = (clean == 'cloud' && (uName.contains('claudio') || uNick == 'cloud')) ||
                                      (clean == 'claudio' && (uNick == 'cloud' || uName.contains('claudio')));

          if (isMatchById || isMatchByNick || isClaudioAlias) {
            ObjectId? targetObjId;
            try {
              targetObjId = uDoc['_id'] is ObjectId ? uDoc['_id'] as ObjectId : ObjectId.fromHexString(uDoc['_id'].toString());
            } catch (_) {}
            final sel = targetObjId != null ? where.id(targetObjId) : where.eq('_id', uDoc['_id']);

            await db.collection('Utenti').update(
              sel,
              modify.set('avatarUrl', newAvatarUrl).set('foto', newAvatarUrl),
            );
          }
        }
      }
    } catch (_) {}
  }

  // --- REPERIMENTO UTENTI REALI DAL DB (MONGODB ATLAS DIRETTO) ---
  Future<List<Utente>>? _pendingGetUtentiFuture;

  Future<List<Utente>> getUtenti() async {
    if (_pendingGetUtentiFuture != null) {
      return _pendingGetUtentiFuture!;
    }
    _pendingGetUtentiFuture = _fetchUtentiFromDb();
    try {
      return await _pendingGetUtentiFuture!;
    } finally {
      _pendingGetUtentiFuture = null;
    }
  }

  Future<List<Utente>> _fetchUtentiFromDb() async {
    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.get(
          Uri.parse('$url/utenti'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final List<dynamic> listJson = jsonDecode(res.body);
          final List<Utente> list = [];
          for (var item in listJson) {
            final jsonMap = Map<String, dynamic>.from(item as Map);
            final rawNome = (jsonMap['nome'] ?? '').toString().trim();
            final rawNick = (jsonMap['nickname'] ?? jsonMap['username'] ?? '').toString().trim();
            final resolvedNick = resolveNickname(rawNick.isNotEmpty ? rawNick : rawNome);
            jsonMap['nome'] = rawNome.isNotEmpty ? rawNome : resolvedNick;
            jsonMap['nickname'] = resolvedNick;
            jsonMap['username'] = resolvedNick;

            final rawServerAv = (jsonMap['avatarUrl'] ?? jsonMap['foto'] ?? '').toString().trim();
            final validServerAv = (rawServerAv.isNotEmpty && !rawServerAv.contains('pravatar') && !rawServerAv.contains('unsplash.com/photo-1535713875002'))
                ? rawServerAv
                : '';
            final uObj = Utente.fromJson(jsonMap).copyWith(avatarUrl: validServerAv);
            list.add(uObj);

            if (validServerAv.isNotEmpty) {
              _cacheSingleAvatar(uObj.nome, uObj.nickname, validServerAv);
            }

            if (_currentUser != null &&
                (isSamePerson(uObj.nickname, _currentUser!.nickname) ||
                 isSamePerson(uObj.nome, _currentUser!.nome))) {
              final curAv = _currentUser!.avatarUrl;
              final validCurAv = (curAv.isNotEmpty && !curAv.contains('pravatar') && !curAv.contains('unsplash.com/photo-1535713875002'))
                  ? curAv
                  : '';
              final safeAvatar = validServerAv.isNotEmpty
                  ? validServerAv
                  : (validCurAv.isNotEmpty ? validCurAv : (_avatarCache[resolvedNick.toLowerCase()] ?? ''));
              _currentUser = uObj.copyWith(avatarUrl: safeAvatar);
              await _saveSession(_currentUser!);
            }
          }
          if (list.isNotEmpty) {
            _utenti.clear();
            _utenti.addAll(list);
            await _saveCachedUsersAndAvatars();
            return List.unmodifiable(_utenti);
          }
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList().timeout(const Duration(seconds: 8));
        final List<Utente> list = [];
        for (var d in docs) {
          final jsonMap = Map<String, dynamic>.from(d);
          jsonMap['id'] = d['_id']?.toHexString() ?? d['_id']?.toString() ?? '';
          final rawNome = (d['nome'] ?? '').toString().trim();
          final rawNick = (d['nickname'] ?? d['username'] ?? '').toString().trim();
          final resolvedNick = resolveNickname(rawNick.isNotEmpty ? rawNick : rawNome);
          jsonMap['nome'] = rawNome.isNotEmpty ? rawNome : resolvedNick;
          jsonMap['nickname'] = resolvedNick;
          jsonMap['username'] = resolvedNick;
          jsonMap['email'] = d['email'] ?? '';
          jsonMap['avatarUrl'] = d['avatarUrl'] ?? '';
          jsonMap['livello'] = d['livello'] ?? 1;
          jsonMap['xp'] = d['xp'] ?? 100;
          jsonMap['xpProssimoLivello'] = d['xpProssimoLivello'] ?? 1000;
          jsonMap['puntiTotali'] = d['puntiTotali'] ?? 0;
          jsonMap['badgeList'] = _extractAndHealBadgeList(d, db);
          jsonMap['storicoVoti'] = d['storicoVoti'] ?? [];
          jsonMap['codiceAmico'] = d['codiceAmico'] ?? '';
          jsonMap['amici'] = d['amici'] ?? [];
          jsonMap['richiesteAmicizia'] = d['richiesteAmicizia'] ?? [];
          jsonMap['badgeVincitore'] = d['badgeVincitore'] ?? [];
          jsonMap['countGiudice'] = d['countGiudice'] ?? 0;
          jsonMap['countReMalus'] = d['countReMalus'] ?? 0;
          jsonMap['countFantasma'] = d['countFantasma'] ?? 0;
          jsonMap['countSbirro'] = d['countSbirro'] ?? 0;
          jsonMap['countGiustiziere'] = d['countGiustiziere'] ?? 0;
          jsonMap['haVistoGuida'] = d['haVistoGuida'] == true;

          final rawServerAv = (jsonMap['avatarUrl'] ?? jsonMap['foto'] ?? '').toString().trim();
          final validServerAv = (rawServerAv.isNotEmpty && !rawServerAv.contains('pravatar') && !rawServerAv.contains('unsplash.com/photo-1535713875002'))
              ? rawServerAv
              : '';
          final uObj = Utente.fromJson(jsonMap).copyWith(avatarUrl: validServerAv);
          list.add(uObj);

          if (validServerAv.isNotEmpty) {
            _cacheSingleAvatar(uObj.nome, uObj.nickname, validServerAv);
          }

          if (_currentUser != null &&
              (isSamePerson(uObj.nickname, _currentUser!.nickname) ||
               isSamePerson(uObj.nome, _currentUser!.nome))) {
            final curAv = _currentUser!.avatarUrl;
            final validCurAv = (curAv.isNotEmpty && !curAv.contains('pravatar') && !curAv.contains('unsplash.com/photo-1535713875002'))
                ? curAv
                : '';
            final safeAvatar = validServerAv.isNotEmpty
                ? validServerAv
                : (validCurAv.isNotEmpty ? validCurAv : (_avatarCache[resolvedNick.toLowerCase()] ?? ''));
            _currentUser = uObj.copyWith(avatarUrl: safeAvatar);
            await _saveSession(_currentUser!);
          }
        }
        if (list.isNotEmpty) {
          _utenti.clear();
          _utenti.addAll(list);
          await _saveCachedUsersAndAvatars();
          return List.unmodifiable(_utenti);
        }
      }
    } catch (_) {}

    return List.unmodifiable(_utenti);
  }

  String getAvatarPerUtente(String nickname) {
    final clean = nickname.replaceAll(' ', '').trim().toLowerCase();
    final raw = nickname.trim().toLowerCase();
    if (clean.isEmpty) return '';

    bool isValid(String? s) => s != null && s.isNotEmpty && !s.contains('pravatar') && !s.contains('unsplash.com/photo-1535713875002');

    if (_currentUser != null) {
      final cName = _currentUser!.nome.replaceAll(' ', '').trim().toLowerCase();
      final cNick = _currentUser!.nickname.replaceAll(' ', '').trim().toLowerCase();
      final cRawName = _currentUser!.nome.trim().toLowerCase();
      final cRawNick = _currentUser!.nickname.trim().toLowerCase();
      if ((cName == clean || cNick == clean || cRawName == raw || cRawNick == raw) && isValid(_currentUser!.avatarUrl)) {
        return _currentUser!.avatarUrl;
      }
    }

    if (_avatarCache.containsKey(clean) && isValid(_avatarCache[clean])) {
      return _avatarCache[clean]!;
    }
    if (_avatarCache.containsKey(raw) && isValid(_avatarCache[raw])) {
      return _avatarCache[raw]!;
    }

    final u = getUtenteInMemoria(nickname);
    if (u != null && isValid(u.avatarUrl)) {
      _cacheSingleAvatar(u.nome, u.nickname, u.avatarUrl);
      return u.avatarUrl;
    }

    return '';
  }

  Future<String> fetchAvatarPerUtente(String nickname) async {
    final clean = nickname.trim().toLowerCase();
    for (String url in baseUrls) {
      try {
        final res = await http.get(
          Uri.parse('$url/utenti/avatar?utente=${Uri.encodeComponent(nickname)}'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final av = (data['avatarUrl'] ?? '').toString().trim();
          if (av.isNotEmpty && !av.contains('pravatar') && !av.contains('unsplash.com/photo-1535713875002')) {
            _avatarCache[clean] = av;
            if (clean == 'cloud') _avatarCache['claudio'] = av;
            if (clean == 'claudio') _avatarCache['cloud'] = av;
            if (_currentUser != null && (isSamePerson(clean, _currentUser!.nickname) || isSamePerson(clean, _currentUser!.nome))) {
              _currentUser = _currentUser!.copyWith(avatarUrl: av);
              await _saveSession(_currentUser!);
            }
            return av;
          }
        }
      } catch (_) {}
    }
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final isClaudio = clean == 'cloud' || clean == 'claudio';
        final selector = isClaudio
            ? where.eq('nickname', 'Cloud').or(where.eq('nome', 'Claudio'))
            : where.eq('nickname', nickname).or(where.eq('nome', nickname));
        final doc = await db.collection('Utenti').findOne(selector.fields(['avatarUrl', 'foto']));
        final av = (doc?['avatarUrl'] ?? doc?['foto'] ?? '').toString().trim();
        if (av.isNotEmpty && !av.contains('pravatar') && !av.contains('unsplash.com/photo-1535713875002')) {
          _avatarCache[clean] = av;
          if (clean == 'cloud') _avatarCache['claudio'] = av;
          if (clean == 'claudio') _avatarCache['cloud'] = av;
          if (_currentUser != null && (isSamePerson(clean, _currentUser!.nickname) || isSamePerson(clean, _currentUser!.nome))) {
            _currentUser = _currentUser!.copyWith(avatarUrl: av);
            await _saveSession(_currentUser!);
          }
          return av;
        }
      }
    } catch (_) {}
    return '';
  }

  Utente? getUtenteInMemoria(String nickname) {
    final clean = nickname.replaceAll(' ', '').trim().toLowerCase();
    if (_currentUser != null) {
      final cName = _currentUser!.nome.replaceAll(' ', '').trim().toLowerCase();
      final cNick = _currentUser!.nickname.replaceAll(' ', '').trim().toLowerCase();
      if (cName == clean || cNick == clean) return _currentUser;
    }
    for (var u in _utenti) {
      final uName = u.nome.replaceAll(' ', '').trim().toLowerCase();
      final uNick = u.nickname.replaceAll(' ', '').trim().toLowerCase();
      if (uName == clean || uNick == clean) {
        return u;
      }
    }
    return null;
  }

  DateTime? _lastReconciliationTime;

  /// Esegue la sanificazione e riconciliazione retroattiva di tutti gli eventi conclusi su MongoDB.
  /// Accredita badge vincitore, badge di partecipazione, titoli onorari e storico attività
  /// a tutti i partecipanti e vincitori (@Cloud, @Ugnom, @Pippoforte, ecc.).
  Future<void> sanificaERiconciliaEventiETitoli({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastReconciliationTime != null && now.difference(_lastReconciliationTime!).inSeconds < 60) {
      return;
    }
    _lastReconciliationTime = now;

    try {
      final db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) return;

      final evDocs = await db.collection('Evento').find().toList().timeout(const Duration(seconds: 4), onTimeout: () => []);
      final uDocs = await db.collection('Utenti').find().toList().timeout(const Duration(seconds: 4), onTimeout: () => []);
      final bmList = await db.collection('BonusMalus').find().toList().timeout(const Duration(seconds: 4), onTimeout: () => []);
      if (evDocs.isEmpty || uDocs.isEmpty) return;

      bool userDocsModified = false;

      final Map<String, int> reMalusTotali = {};
      final Map<String, int> avvocatoTotali = {};
      final Map<String, int> fantasmaTotali = {};
      final Map<String, int> sbirroTotali = {};
      final Map<String, int> giustiziereTotali = {};

      for (var ev in evDocs) {
        final evId = ev['_id']?.toHexString() ?? ev['_id']?.toString() ?? '';
        final evTitolo = (ev['titolo'] ?? ev['nome'] ?? 'Evento Fanta').toString().trim();
        final dtEndStr = ev['dataFine']?.toString() ?? ev['data']?.toString() ?? now.toIso8601String();
        final dtEnd = DateTime.tryParse(dtEndStr) ?? now;
        final bool isConcluso = ev['stato'] != 'annullato' && (now.isAfter(dtEnd) || ev['stato'] == 'concluso');

        if (!isConcluso || ev['stato'] == 'annullato') continue;

        final partecipanti = (ev['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final dateStr = '${dtEnd.day.toString().padLeft(2, '0')}/${dtEnd.month.toString().padLeft(2, '0')}/${dtEnd.year}';
        final partBadge = '🎉 Partecipato a "$evTitolo" ($dateStr)';

        // 1. Identifica o ricalcola il vincitore
        String? vincitoreNick = ev['titoliVincitori']?['campione']?.toString();
        int maxPoints = (ev['titoliVincitori']?['campionePunti'] as num?)?.toInt() ?? 0;

        if (vincitoreNick == null || vincitoreNick.isEmpty) {
          final evBm = bmList.where((b) {
            final bEvId = (b['eventoId'] ?? '').toString().trim().toLowerCase();
            return bEvId == evId.toLowerCase() || bEvId == evTitolo.toLowerCase();
          }).toList();

          final Map<String, int> punteggi = {for (var p in partecipanti) p: 0};
          for (var bm in evBm) {
            final bool approvato = bm['approvato'] == true || bm['stato'] == 'approvato';
            if (!approvato) continue;
            final ass = (bm['assegnatoA'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
            final pt = (bm['punti'] as num?)?.toInt() ?? 0;
            for (var u in ass) {
              punteggi[u] = (punteggi[u] ?? 0) + pt;
            }
          }
          if (punteggi.isNotEmpty) {
            final sorted = punteggi.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            vincitoreNick = sorted.first.key;
            maxPoints = sorted.first.value;
          }
        }

        if (vincitoreNick != null && vincitoreNick.isNotEmpty) {
          final resolvedWinner = resolveNickname(vincitoreNick);
          final badgeMap = {
            'titolo': '🏆 Vincitore Evento',
            'evento': evTitolo,
            'punti': maxPoints,
            'data': dtEnd.toIso8601String(),
          };

          for (var uDoc in uDocs) {
            if (matchesUserDoc(uDoc, resolvedWinner)) {
              final List<dynamic> currentBadgeVincitore = List.from(uDoc['badgeVincitore'] ?? []);
              final bool giaAssegnato = currentBadgeVincitore.any((b) => b['evento'] == evTitolo);
              if (!giaAssegnato) {
                currentBadgeVincitore.add(badgeMap);
                uDoc['badgeVincitore'] = currentBadgeVincitore;

                final List<dynamic> currentStorico = List.from(uDoc['storicoVoti'] ?? []);
                final logVoce = formattaVoceStorico('🏆 Vincitore dell\'evento "$evTitolo" ($maxPoints PT)');
                if (!currentStorico.any((s) => s.toString().contains('Vincitore dell\'evento "$evTitolo"'))) {
                  currentStorico.insert(0, logVoce);
                  uDoc['storicoVoti'] = currentStorico;
                }

                await db.collection('Utenti').update(
                  where.id(uDoc['_id'] as ObjectId),
                  modify.set('badgeVincitore', currentBadgeVincitore).set('storicoVoti', uDoc['storicoVoti']),
                );
                userDocsModified = true;
              }
            }
          }
        }

        // 2. Accredito Badge di Partecipazione
        for (var part in partecipanti) {
          for (var uDoc in uDocs) {
            if (matchesUserDoc(uDoc, part)) {
              final List<dynamic> currentBadgeList = List.from(uDoc['badgeList'] ?? []);
              if (!currentBadgeList.any((b) => b.toString().contains(evTitolo))) {
                currentBadgeList.add(partBadge);
                uDoc['badgeList'] = currentBadgeList;
                await db.collection('Utenti').update(
                  where.id(uDoc['_id'] as ObjectId),
                  modify.set('badgeList', currentBadgeList),
                );
                userDocsModified = true;
              }
            }
          }
        }

        // 3. Conteggio titoli maturati
        final titoli = ev['titoliVincitori'] as Map<String, dynamic>?;
        if (titoli != null) {
          final rm = titoli['reMalus']?.toString();
          if (rm != null && rm.isNotEmpty) {
            final resolved = resolveNickname(rm);
            reMalusTotali[resolved] = (reMalusTotali[resolved] ?? 0) + 1;
          }
          final avv = (titoli['avvocato'] ?? titoli['giudice'])?.toString();
          if (avv != null && avv.isNotEmpty) {
            final resolved = resolveNickname(avv);
            avvocatoTotali[resolved] = (avvocatoTotali[resolved] ?? 0) + 1;
          }
          final fts = titoli['fantasma']?.toString();
          if (fts != null && fts.isNotEmpty) {
            final resolved = resolveNickname(fts);
            fantasmaTotali[resolved] = (fantasmaTotali[resolved] ?? 0) + 1;
          }
          final sb = titoli['sbirro']?.toString();
          if (sb != null && sb.isNotEmpty) {
            final resolved = resolveNickname(sb);
            sbirroTotali[resolved] = (sbirroTotali[resolved] ?? 0) + 1;
          }
          final gst = titoli['giustiziere']?.toString();
          if (gst != null && gst.isNotEmpty) {
            final resolved = resolveNickname(gst);
            giustiziereTotali[resolved] = (giustiziereTotali[resolved] ?? 0) + 1;
          }
        }
      }

      // Applica i titoli ricalcolati agli utenti
      for (var uDoc in uDocs) {
        final uId = uDoc['_id'] as ObjectId;
        var mod = modify;
        bool shouldUpdate = false;

        void checkAndUpdateTitle(String field, Map<String, int> map) {
          int count = 0;
          for (var entry in map.entries) {
            if (matchesUserDoc(uDoc, entry.key)) {
              count += entry.value;
            }
          }
          final curVal = (uDoc[field] as num?)?.toInt() ?? 0;
          if (count > curVal) {
            mod = mod.set(field, count);
            uDoc[field] = count;
            shouldUpdate = true;
          }
        }

        checkAndUpdateTitle('countReMalus', reMalusTotali);
        checkAndUpdateTitle('countGiudice', avvocatoTotali);
        checkAndUpdateTitle('countAvvocato', avvocatoTotali);
        checkAndUpdateTitle('countFantasma', fantasmaTotali);
        checkAndUpdateTitle('countSbirro', sbirroTotali);
        checkAndUpdateTitle('countGiustiziere', giustiziereTotali);

        if (shouldUpdate) {
          await db.collection('Utenti').update(where.id(uId), mod);
          userDocsModified = true;
        }
      }

      if (userDocsModified && _currentUser != null) {
        final freshUsers = await getUtenti();
        final match = freshUsers.firstWhere(
          (u) => matchesUserDoc(u.toJson(), _currentUser!.nickname),
          orElse: () => _currentUser!,
        );
        _currentUser = match;
        await _saveSession(_currentUser!);
      }
    } catch (e) {
      debugPrint('Errore sanificaERiconciliaEventiETitoli: $e');
    }
  }

  // --- REPERIMENTO EVENTI REALI DA MONGODB ATLAS (CON MANTENIMENTO FINITI 7 GG E BADGE VINCITORE) ---
  Future<List<Evento>> getEventi({bool forceRefresh = false}) async {
    if (!forceRefresh && _lastFetchTime != null && DateTime.now().difference(_lastFetchTime!) < _cacheDuration && _eventi.isNotEmpty) {
      return List.unmodifiable(_eventi);
    }

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.get(
          Uri.parse('$url/eventi'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final List<dynamic> listJson = jsonDecode(res.body);
          final List<Evento> list = [];
          for (var item in listJson) {
            final jsonMap = Map<String, dynamic>.from(item as Map);
            list.add(Evento.fromJson(jsonMap));
          }
          _eventi.clear();
          _eventi.addAll(list);
          _lastFetchTime = DateTime.now();
          return List.unmodifiable(_eventi);
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        final docs = await db.collection('Evento').find().toList().timeout(const Duration(seconds: 4));

        final now = DateTime.now();
        final List<Evento> list = [];
        final List<ObjectId> oldExpiredIds = [];

        for (var d in docs) {
          final idStr = d['_id']?.toHexString() ?? d['_id']?.toString() ?? '';
          final dtStartStr = d['data']?.toString() ?? now.toIso8601String();
          final dtEndStr = d['dataFine']?.toString() ?? dtStartStr;

          DateTime dtStart = DateTime.tryParse(dtStartStr) ?? now;
          DateTime dtEnd = DateTime.tryParse(dtEndStr) ?? dtStart.add(const Duration(hours: 24));

          final partecipanti = (d['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          final rawCreatore = (d['propostoDa'] ?? d['creatore'] ?? '').toString().trim();
          final bool haAltriPartecipanti = partecipanti.any((p) => p.trim().isNotEmpty && !isSamePerson(p, rawCreatore));
          final bool rawIsAnnullato = (d['stato'] ?? '').toString().trim().toLowerCase() == 'annullato';

          // Anti-farming e gestione avvio evento:
          if (now.isAfter(dtStart) && !rawIsAnnullato) {
            if (!haAltriPartecipanti) {
              // Scattato orario di inizio ma nessun amico ha accettato: l'evento viene auto-annullato e non parte mai!
              if (d['_id'] is ObjectId) {
                try {
                  await db.collection('Evento').update(
                    where.id(d['_id'] as ObjectId),
                    modify.set('stato', 'annullato').set('xpCreatoreAssegnati', false),
                  );
                  d['stato'] = 'annullato';
                } catch (_) {}
              }
            } else {
              // L'evento parte regolarmente con almeno 2 partecipanti: accredita +100 XP una tantum al creatore
              if (d['xpCreatoreAssegnati'] != true && d['_id'] is ObjectId) {
                try {
                  await db.collection('Evento').update(
                    where.id(d['_id'] as ObjectId),
                    modify.set('xpCreatoreAssegnati', true),
                  );
                  d['xpCreatoreAssegnati'] = true;

                  final evTitolo = (d['titolo'] ?? d['nome'] ?? 'Evento Fanta').toString().trim();
                  final logVoce = formattaVoceStorico('🏆 Evento "$evTitolo" avviato con successo (+100 XP)');
                  final uDocsForXp = await db.collection('Utenti').find(where.excludeFields(['avatarUrl'])).toList();
                  for (var uDoc in uDocsForXp) {
                    if (matchesUserDoc(uDoc, rawCreatore)) {
                      final int curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
                      final int curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
                      final int curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);
                      final prog = XpProgression.aggiungiXp(
                        livelloAttuale: curLiv,
                        xpLivelloAttuale: curXp,
                        deltaXp: 100,
                        xpTotaliAttuali: curTot,
                      );
                      final List<dynamic> curStorico = List.from(uDoc['storicoVoti'] ?? []);
                      if (!curStorico.any((s) => s.toString().contains('Evento "$evTitolo" avviato con successo'))) {
                        curStorico.insert(0, logVoce);
                      }
                      await db.collection('Utenti').update(
                        where.id(uDoc['_id'] as ObjectId),
                        modify
                          .set('xp', prog.xp)
                          .set('livello', prog.livello)
                          .set('xpProssimoLivello', prog.xpProssimoLivello)
                          .set('xpTotali', prog.xpTotali)
                          .set('storicoVoti', curStorico),
                      );

                      if (_currentUser != null && matchesUserDoc(uDoc, _currentUser!.nickname)) {
                        _currentUser = _currentUser!.copyWith(
                          xp: prog.xp,
                          livello: prog.livello,
                          xpProssimoLivello: prog.xpProssimoLivello,
                          xpTotali: prog.xpTotali,
                          storicoVoti: [logVoce, ..._currentUser!.storicoVoti],
                        );
                      }
                    }
                  }
                } catch (_) {}
              }
            }
          }

          final bool isAnnullato = (d['stato'] ?? '').toString().trim().toLowerCase() == 'annullato';
          final bool isConcluso = !isAnnullato && (now.isAfter(dtEnd) || (d['stato'] == 'concluso'));
          final int giorniDaConclusione = isConcluso ? now.difference(dtEnd).inDays : 0;

          // Se l'evento e' finito da piu' di 7 giorni, archivialo dal DB
          if (isConcluso && giorniDaConclusione > 7) {
            if (d['_id'] is ObjectId) {
              oldExpiredIds.add(d['_id'] as ObjectId);
            }
            continue;
          }

          // Se l'evento e' appena finito (negli ultimi 7 giorni), assegna i premi/badge/titoli una sola volta
          if (isConcluso && (d['badgeVincitoreAssegnato'] != true || d['titoliAssegnati'] != true)) {
            try {
              final evTitolo = (d['titolo'] ?? d['nome'] ?? 'Evento Fanta').toString().trim();
              final dateStr = '${dtEnd.day.toString().padLeft(2, '0')}/${dtEnd.month.toString().padLeft(2, '0')}/${dtEnd.year}';
              final partBadge = '🎉 Partecipato a "$evTitolo" ($dateStr)';

              final bmList = await db.collection('BonusMalus').find(where.eq('eventoId', idStr)).toList();
              final allVotazioni = await db.collection('Votazioni').find().toList();
              final uDocs = await db.collection('Utenti').find(where.excludeFields(['avatarUrl'])).toList();

              final Map<String, int> punteggi = {for (var p in partecipanti) p: 0};
              final Map<String, int> malusPerUtente = {for (var p in partecipanti) p.trim().toLowerCase(): 0};
              final Map<String, int> attivitaPerUtente = {for (var p in partecipanti) p.trim().toLowerCase(): 0};
              final Map<String, int> azioniTotaliPerUtente = {for (var p in partecipanti) p.trim().toLowerCase(): 0};

              final Set<String> bmIds = {};
              for (var bm in bmList) {
                final bmIdStr = (bm['_id'] is ObjectId ? (bm['_id'] as ObjectId).toHexString() : bm['_id']?.toString() ?? bm['id']?.toString() ?? '').toLowerCase();
                if (bmIdStr.isNotEmpty) bmIds.add(bmIdStr);
                final nomeBm = (bm['nome'] ?? bm['titolo'] ?? '').toString().toLowerCase();
                if (nomeBm.isNotEmpty) bmIds.add(nomeBm);

                // Solo proposte genuine della community (escludendo sanzioni d'ufficio del VAR)
                final bool isVarSanzione = (bm['categoria'] ?? '').toString().toUpperCase() == 'VAR' ||
                    nomeBm.contains('falsa testimonianza') ||
                    (bm['descrizione'] ?? '').toString().toLowerCase().contains('sanzione per denuncia');

                final prop = (bm['propostoDa'] ?? '').toString().trim().toLowerCase();
                if (!isVarSanzione && prop.isNotEmpty && attivitaPerUtente.containsKey(prop)) {
                  attivitaPerUtente[prop] = (attivitaPerUtente[prop] ?? 0) + 1;
                  azioniTotaliPerUtente[prop] = (azioniTotaliPerUtente[prop] ?? 0) + 1;
                }

                final ass = (bm['assegnatoA'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                final pt = (bm['punti'] as num?)?.toInt() ?? 0;
                final bool approvato = bm['approvato'] == true || bm['stato'] == 'approvato';

                for (var u in ass) {
                  final uNorm = u.trim().toLowerCase();
                  if (azioniTotaliPerUtente.containsKey(uNorm)) {
                    azioniTotaliPerUtente[uNorm] = (azioniTotaliPerUtente[uNorm] ?? 0) + 1;
                  }
                  if (approvato) {
                    punteggi[u] = (punteggi[u] ?? 0) + pt;
                    if (pt < 0 && malusPerUtente.containsKey(uNorm)) {
                      malusPerUtente[uNorm] = (malusPerUtente[uNorm] ?? 0) + pt.abs();
                    }
                  }
                }
              }

              for (var v in allVotazioni) {
                final vEvId = (v['eventoId'] ?? v['bonusMalus']?['eventoId'] ?? '').toString().trim().toLowerCase();
                final vBonusId = (v['bonusId'] ?? v['votazioneId'] ?? '').toString().trim().toLowerCase();
                final vBonusTit = (v['bonusTitolo'] ?? '').toString().trim().toLowerCase();

                final bool isForThisEvent = (vEvId.isNotEmpty && (vEvId == idStr.toLowerCase() || vEvId == evTitolo.toLowerCase())) ||
                    (vBonusId.isNotEmpty && bmIds.contains(vBonusId)) ||
                    (vBonusTit.isNotEmpty && bmIds.contains(vBonusTit));

                if (!isForThisEvent) continue;

                if (v['utente'] != null) {
                  final voterNorm = v['utente'].toString().trim().toLowerCase();
                  if (attivitaPerUtente.containsKey(voterNorm)) {
                    attivitaPerUtente[voterNorm] = (attivitaPerUtente[voterNorm] ?? 0) + 1;
                    azioniTotaliPerUtente[voterNorm] = (azioniTotaliPerUtente[voterNorm] ?? 0) + 1;
                  }
                } else if (v['votiUtenti'] is Map) {
                  final votiMap = v['votiUtenti'] as Map<String, dynamic>;
                  for (var voter in votiMap.keys) {
                    final voterNorm = voter.trim().toLowerCase();
                    if (attivitaPerUtente.containsKey(voterNorm)) {
                      attivitaPerUtente[voterNorm] = (attivitaPerUtente[voterNorm] ?? 0) + 1;
                      azioniTotaliPerUtente[voterNorm] = (azioniTotaliPerUtente[voterNorm] ?? 0) + 1;
                    }
                  }
                }
              }

              // 1. Assegna badge al 1° in classifica
              String? vincitoreNick;
              if (punteggi.isNotEmpty) {
                final sorted = punteggi.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                vincitoreNick = sorted.first.key;
                final badgeMap = {
                  'titolo': '🏆 Vincitore Evento',
                  'evento': evTitolo,
                  'punti': sorted.first.value,
                  'data': DateTime.now().toIso8601String(),
                };

                for (var uDoc in uDocs) {
                  if (matchesUserDoc(uDoc, vincitoreNick)) {
                    final List<dynamic> currentBadgeVincitore = List.from(uDoc['badgeVincitore'] ?? []);
                    if (!currentBadgeVincitore.any((b) => b['evento'] == badgeMap['evento'])) {
                      currentBadgeVincitore.add(badgeMap);
                      final List<dynamic> currentStorico = List.from(uDoc['storicoVoti'] ?? []);
                      final logVoce = formattaVoceStorico('🏆 Vincitore dell\'evento "$evTitolo" (+${sorted.first.value} PT)');
                      currentStorico.insert(0, logVoce);
                      await db.collection('Utenti').update(
                        where.id(uDoc['_id'] as ObjectId),
                        modify
                          .set('badgeVincitore', currentBadgeVincitore)
                          .set('storicoVoti', currentStorico),
                      );
                    }
                  }
                }
              }

              // 2. Assegna Badge Partecipazione a TUTTI i partecipanti
              for (var part in partecipanti) {
                for (var uDoc in uDocs) {
                  if (matchesUserDoc(uDoc, part)) {
                    final List<dynamic> currentBadgeList = List.from(uDoc['badgeList'] ?? []);
                    if (!currentBadgeList.any((b) => b.toString().contains(evTitolo))) {
                      currentBadgeList.add(partBadge);
                      await db.collection('Utenti').update(
                        where.id(uDoc['_id'] as ObjectId),
                        modify.set('badgeList', currentBadgeList),
                      );
                    }
                  }
                }
              }

              // 3. Assegnazione Titoli Permanenti della Bacheca (Re dei Malus, L'Avvocato, Fantasma, Lo Sbirro, Il Giustiziere)
              if (d['titoliAssegnati'] != true) {
                int maxMalus = 0;
                String? bestMalusUser;
                malusPerUtente.forEach((k, v) {
                  if (v > maxMalus) {
                    maxMalus = v;
                    bestMalusUser = k;
                  }
                });

                int maxAtt = 0;
                String? bestGiudiceUser;
                attivitaPerUtente.forEach((k, v) {
                  if (v > maxAtt) {
                    maxAtt = v;
                    bestGiudiceUser = k;
                  }
                });

                String? bestFantasmaUser;
                int minAzioni = 0;
                if (partecipanti.length > 1) {
                  int lowestAz = 999999;
                  for (var p in partecipanti) {
                    final pNorm = p.trim().toLowerCase();
                    if (vincitoreNick != null && vincitoreNick.trim().toLowerCase() == pNorm) continue;
                    final az = azioniTotaliPerUtente[pNorm] ?? 0;
                    if (az < lowestAz) {
                      lowestAz = az;
                      minAzioni = az;
                      bestFantasmaUser = pNorm;
                    }
                  }
                }

                final String evIdStr = (d['_id'] is ObjectId ? (d['_id'] as ObjectId).toHexString() : d['_id']?.toString() ?? d['id']?.toString() ?? '');
                // Auto-scadenza richieste VAR pendenti ed eliminazione foto
                try {
                  await db.collection('RichiesteVar').update(
                    where.eq('eventoId', evIdStr).and(where.eq('stato', 'in_attesa')),
                    modify.set('stato', 'scaduta').unset('fotoBase64'),
                    multiUpdate: true,
                  );
                  await db.collection('RichiesteVar').update(
                    where.eq('eventoId', evIdStr),
                    modify.unset('fotoBase64'),
                    multiUpdate: true,
                  );
                } catch (_) {}

                // Calcolo Lo Sbirro e Il Giustiziere per questo evento
                final Map<String, int> sbirroPerUtente = {};
                final Map<String, int> giustizierePerUtente = {};
                try {
                  final varDocs = await db.collection('RichiesteVar').find(where.eq('eventoId', evIdStr)).toList();
                  for (var r in varDocs) {
                    final tipo = (r['tipo'] ?? '').toString().toLowerCase();
                    final req = (r['richiedente'] ?? '').toString().trim().toLowerCase();
                    if (r['stato'] == 'approvata') {
                      giustizierePerUtente[req] = (giustizierePerUtente[req] ?? 0) + 1;
                    }
                    if (tipo == 'malus') {
                      // Lo Sbirro premia chi fa più denunce/segnalazioni malus in assoluto
                      sbirroPerUtente[req] = (sbirroPerUtente[req] ?? 0) + 1;
                    }
                  }
                } catch (_) {}

                int maxSbirro = 0;
                String? bestSbirroUser;
                sbirroPerUtente.forEach((k, v) {
                  if (v > maxSbirro) {
                    maxSbirro = v;
                    bestSbirroUser = k;
                  }
                });

                int maxGiustiziere = 0;
                String? bestGiustiziereUser;
                giustizierePerUtente.forEach((k, v) {
                  if (v > maxGiustiziere) {
                    maxGiustiziere = v;
                    bestGiustiziereUser = k;
                  }
                });

                for (var uDoc in uDocs) {
                  final uId = uDoc['_id'] as ObjectId;
                  var mod = modify;
                  bool shouldUpdate = false;

                  if (bestMalusUser != null && matchesUserDoc(uDoc, bestMalusUser) && maxMalus > 0) {
                    final cur = (uDoc['countReMalus'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countReMalus', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestGiudiceUser != null && matchesUserDoc(uDoc, bestGiudiceUser) && maxAtt > 0) {
                    final cur = (uDoc['countGiudice'] as num?)?.toInt() ?? (uDoc['countAvvocato'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countGiudice', cur + 1).set('countAvvocato', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestFantasmaUser != null && matchesUserDoc(uDoc, bestFantasmaUser)) {
                    final cur = (uDoc['countFantasma'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countFantasma', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestSbirroUser != null && matchesUserDoc(uDoc, bestSbirroUser) && maxSbirro > 0) {
                    final cur = (uDoc['countSbirro'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countSbirro', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestGiustiziereUser != null && matchesUserDoc(uDoc, bestGiustiziereUser) && maxGiustiziere > 0) {
                    final cur = (uDoc['countGiustiziere'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countGiustiziere', cur + 1);
                    shouldUpdate = true;
                  }

                  if (shouldUpdate) {
                    await db.collection('Utenti').update(where.id(uId), mod);
                  }
                }

                // Salva i vincitori ufficiali dei titoli direttamente nell'Evento
                final Map<String, dynamic> titoliMap = {
                  'campione': vincitoreNick,
                  'campionePunti': (punteggi[vincitoreNick] ?? 0),
                  if (bestMalusUser != null && maxMalus > 0) ...{
                    'reMalus': bestMalusUser,
                    'reMalusPunti': maxMalus,
                  },
                  if (bestGiudiceUser != null && maxAtt > 0) ...{
                    'avvocato': bestGiudiceUser,
                    'avvocatoAzioni': maxAtt,
                  },
                  if (bestFantasmaUser != null) ...{
                    'fantasma': bestFantasmaUser,
                    'fantasmaAzioni': minAzioni,
                  },
                  if (bestSbirroUser != null && maxSbirro > 0) ...{
                    'sbirro': bestSbirroUser,
                    'sbirroDenunce': maxSbirro,
                  },
                  if (bestGiustiziereUser != null && maxGiustiziere > 0) ...{
                    'giustiziere': bestGiustiziereUser,
                    'giustiziereApprovate': maxGiustiziere,
                  },
                };

                if (d['_id'] is ObjectId) {
                  await db.collection('Evento').update(
                    where.id(d['_id'] as ObjectId),
                    modify
                      .set('badgeVincitoreAssegnato', true)
                      .set('titoliAssegnati', true)
                      .set('titoliVincitori', titoliMap)
                      .set('stato', 'concluso'),
                  );
                }
              }
            } catch (_) {}
          }

          final proposedBy = (d['propostoDa'] ?? d['creatore'] ?? 'Cloud').toString().trim().toLowerCase();
          final invitatiList = (d['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim().toLowerCase()).toList() ?? [];
          final partecipantiList = partecipanti.map((e) => e.trim().toLowerCase()).toList();

          if (_currentUser != null) {
            final myName = _currentUser!.nome.trim().toLowerCase();
            final myNick = _currentUser!.nickname.trim().toLowerCase();
            final myId = _currentUser!.id.trim().toLowerCase();

            final bool isCreatore = proposedBy == myName || proposedBy == myNick || proposedBy == myId;
            final bool isPartecipante = partecipantiList.contains(myName) || partecipantiList.contains(myNick) || partecipantiList.contains(myId);
            final bool isInvitato = invitatiList.contains(myName) || invitatiList.contains(myNick) || invitatiList.contains(myId);

            if (!isCreatore && !isPartecipante && !isInvitato) {
              continue;
            }

            // Se l'utente era solo un invitato e non ha confermato la partecipazione:
            // - se l'evento è concluso, viene escluso dal feed
            // - se l'evento è iniziato da più di 30 minuti, si auto-elimina dal feed!
            if (!isCreatore && !isPartecipante && isInvitato) {
              final bool isInizioPassatoDa30Min = now.isAfter(dtStart.add(const Duration(minutes: 30)));
              if (isConcluso || isInizioPassatoDa30Min) {
                continue;
              }
            }
          }

          final Map<String, dynamic> jsonMap = {
            'id': idStr,
            'titolo': d['titolo'] ?? d['nome'] ?? 'Evento',
            'descrizione': d['descrizione'] ?? '',
            'data': dtStartStr,
            'dataFine': dtEndStr,
            'luogo': d['luogo'] ?? '',
            'stato': isAnnullato ? 'annullato' : (isConcluso ? 'concluso' : (d['stato'] ?? 'in_programma')),
            'propostoDa': d['propostoDa'] ?? d['creatore'] ?? 'Cloud',
            'partecipanti': partecipanti,
            'invitati': (d['invitati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
            'copertinaUrl': d['copertinaUrl']?.toString(),
            'bonusMalusApplicati': [],
            'votazioniAttive': [],
            if (d['titoliVincitori'] != null) 'titoliVincitori': d['titoliVincitori'],
          };
          list.add(Evento.fromJson(jsonMap));
        }

        // Rimozione definitiva dal DB degli eventi scaduti da oltre 7 giorni
        for (var expId in oldExpiredIds) {
          try {
            final expIdStr = expId.toHexString();
            await db.collection('Evento').remove(where.id(expId));
            final bmDocs = await db.collection('BonusMalus').find(where.eq('eventoId', expIdStr)).toList();
            for (var bm in bmDocs) {
              final bmId = bm['_id']?.toHexString() ?? bm['_id']?.toString() ?? '';
              await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
            }
            await db.collection('BonusMalus').remove(where.eq('eventoId', expIdStr));
            await db.collection('Notifiche').remove(where.eq('eventoId', expIdStr));
          } catch (_) {}
        }

        _eventi.clear();
        _eventi.addAll(list);
        _lastFetchTime = DateTime.now();
        return list;
      }
    } catch (_) {
      markMongoDbDisconnected();
    }

    // 2. Fallback veloce HTTP (timeout 2s)
    for (String url in baseUrls) {
      try {
        final response = await http.get(Uri.parse('$url/eventi'), headers: defaultHeaders).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200 && !response.body.contains('<html>')) {
          final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
          final list = data.map((json) => Evento.fromJson(json as Map<String, dynamic>)).toList();
          if (_currentUser != null) {
            final myName = _currentUser!.nome.trim().toLowerCase();
            final myNick = _currentUser!.nickname.trim().toLowerCase();
            final myId = _currentUser!.id.trim().toLowerCase();
            final now = DateTime.now();

            list.removeWhere((ev) {
              final cleanCreator = ev.creatore.trim().toLowerCase();
              final bool isCreatore = cleanCreator == myName || cleanCreator == myNick || cleanCreator == myId;
              final bool isPartecipante = isCreatore || ev.partecipanti.any((p) {
                final pLow = p.trim().toLowerCase();
                return pLow == myName || pLow == myNick || pLow == myId;
              });
              final bool isInvitato = ev.invitati.any((i) {
                final iLow = i.trim().toLowerCase();
                return iLow == myName || iLow == myNick || iLow == myId;
              });

              if (!isCreatore && !isPartecipante && !isInvitato) return true;
              if (!isCreatore && !isPartecipante && isInvitato) {
                final bool isInizioPassatoDa30Min = now.isAfter(ev.data.add(const Duration(minutes: 30)));
                if (ev.isConcluso || isInizioPassatoDa30Min) return true;
              }
              return false;
            });
          }
          _eventi.clear();
          _eventi.addAll(list);
          return list;
        }
      } catch (_) {}
    }
    if (_eventi.isNotEmpty) {
      return List.unmodifiable(_eventi);
    }
    throw Exception('Impossibile recuperare gli eventi dal server. Verifica la tua connessione.');
  }

  // --- PARTECIPA AD UN EVENTO REALE SU MONGODB ATLAS (CON VERIFICA EVENTO IN PROGRAMMA) ---
  Future<void> partecipaAdEvento(String eventoId, String nicknameOrId) async {
    invalidateCache();
    bool directSuccess = false;

    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
        final evSelector = objId != null ? where.id(objId) : where.eq('_id', eventoId);
        final evDoc = await db.collection('Evento').findOne(evSelector);

        if (evDoc != null) {
          final stato = (evDoc['stato'] ?? 'in_programma').toString().toLowerCase();
          final dateStr = evDoc['data']?.toString() ?? '';
          final dtStart = DateTime.tryParse(dateStr);
          final now = DateTime.now();

          // Regola: quando l'evento è in corso o concluso non è più possibile iscriversi!
          if (stato == 'concluso' || stato == 'in_corso' || (dtStart != null && now.isAfter(dtStart))) {
            throw Exception('Le iscrizioni per questo evento sono chiuse (evento già in corso o concluso)!');
          }

          final pullList = {
            nicknameOrId,
            nicknameOrId.toLowerCase(),
            nicknameOrId.toUpperCase(),
            nicknameOrId.trim(),
            nicknameOrId.trim().toLowerCase(),
          }.toList();

          await db.collection('Evento').update(
            evSelector,
            modify
              .addToSet('partecipanti', nicknameOrId)
              .pullAll('invitati', pullList),
          );

          // Aggiornamento ISTANTANEO in-memory di _eventi (zero latenza per le card eventi)
          final evIdx = _eventi.indexWhere((e) => e.id == eventoId);
          if (evIdx != -1) {
            final ev = _eventi[evIdx];
            final updatedPart = List<String>.from(ev.partecipanti);
            final updatedInv = List<String>.from(ev.invitati);
            updatedInv.removeWhere((i) => i.trim().toLowerCase() == nicknameOrId.trim().toLowerCase());
            if (!updatedPart.any((p) => p.trim().toLowerCase() == nicknameOrId.trim().toLowerCase())) {
              updatedPart.add(nicknameOrId);
            }
            _eventi[evIdx] = ev.copyWith(partecipanti: updatedPart, invitati: updatedInv);
          }

          // Se c'era una notifica di invito per questo utente, segnalala come accettata
          try {
            await db.collection('Notifiche').update(
              where.eq('eventoId', eventoId).and(where.eq('destinatario', nicknameOrId)).and(where.eq('tipo', 'invito')),
              modify.set('stato', 'accettata'),
              multiUpdate: true,
            );
          } catch (_) {}

          directSuccess = true;
        }
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('iscrizioni per questo evento sono chiuse')) {
        rethrow;
      }
    }

    if (!directSuccess) {
      for (String url in baseUrls) {
        try {
          await http.post(
            Uri.parse('$url/eventi/partecipa'),
            headers: defaultHeaders,
            body: jsonEncode({
              'eventoId': eventoId,
              'utente': nicknameOrId,
            }),
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
    }
  }

  // --- INVITA ULTERIORI AMICI AD UN EVENTO IN PROGRAMMA (SOLO ORGANIZZATORE) ---
  Future<void> invitaAmiciAdEvento(String eventoId, List<String> nuoviInvitati) async {
    if (nuoviInvitati.isEmpty) return;
    invalidateCache();

    int maxAttempts = 2;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        Db? db = await _getSafeMongoDb();
        if (db == null || !db.isConnected) {
          markMongoDbDisconnected();
          db = await _getSafeMongoDb();
        }
        if (db == null || !db.isConnected) {
          throw Exception('Impossibile connettersi al database per inviare gli inviti.');
        }

        ObjectId? objId;
        try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
        final evSelector = objId != null ? where.id(objId) : where.eq('_id', eventoId);
        
        final evDoc = await db.collection('Evento').findOne(evSelector);
        if (evDoc == null) {
          throw Exception('Evento non trovato nel database.');
        }

        // Controllo sicurezza temporale e di stato: solo eventi IN PROGRAMMA
        final stato = (evDoc['stato'] ?? 'in_programma').toString().toLowerCase();
        final dateStr = evDoc['data']?.toString() ?? '';
        final dtStart = DateTime.tryParse(dateStr);
        final now = DateTime.now();

        if (stato == 'concluso' || stato == 'in_corso' || (dtStart != null && now.isAfter(dtStart))) {
          throw Exception('Non è più possibile invitare amici: l\'evento è già in corso o concluso!');
        }

        final rawCreatore = (evDoc['propostoDa'] ??
                evDoc['creatore'] ??
                (_currentUser?.nickname.isNotEmpty == true
                    ? _currentUser!.nickname
                    : (_currentUser?.nome ?? 'Cloud')))
            .toString()
            .trim();
        final creatore = resolveNickname(rawCreatore);
        final evTitolo = (evDoc['titolo'] ?? evDoc['nome'] ?? 'Evento').toString();

        final List<dynamic> currentInvitati = List.from(evDoc['invitati'] ?? []);
        final List<dynamic> currentPartecipanti = List.from(evDoc['partecipanti'] ?? []);

        final List<String> aggiuntiEffettivi = [];
        for (var amico in nuoviInvitati) {
          final resolvedAmico = resolveNickname(amico);
          final giaPart = currentPartecipanti.any((p) => isSamePerson(p.toString(), resolvedAmico));
          final giaInv = currentInvitati.any((i) => isSamePerson(i.toString(), resolvedAmico));

          if (!giaPart && !giaInv && !isSamePerson(resolvedAmico, creatore)) {
            currentInvitati.add(resolvedAmico);
            aggiuntiEffettivi.add(resolvedAmico);
          }
        }

        if (aggiuntiEffettivi.isEmpty) return;

        // Aggiorna l'elenco invitati nell'Evento su MongoDB
        await db.collection('Evento').update(
          evSelector,
          modify.set('invitati', currentInvitati),
        );

        // Invia notifiche individuali per ciascun nuovo amico invitato
        for (var amico in aggiuntiEffettivi) {
          await db.collection('Notifiche').insertOne({
            'mittente': creatore,
            'destinatario': amico,
            'titolo': 'Invito ad Evento: $evTitolo',
            'messaggio': '$creatore ti ha invitato a partecipare all\'evento "$evTitolo"!',
            'eventoId': eventoId,
            'tipo': 'invito',
            'stato': 'in_attesa',
            'letto': false,
            'data': DateTime.now().toIso8601String(),
          });
        }

        // Invia notifica push reale per la tendina di sistema
        try {
          await PushNotificationService.instance.inviaPushAUtenti(
            aggiuntiEffettivi,
            titolo: '🎉 Invito ad Evento: $evTitolo',
            messaggio: '$creatore ti ha invitato a partecipare all\'evento "$evTitolo"!',
            data: {
              'tipo': 'invito',
              'eventoId': eventoId,
            },
          ).timeout(const Duration(seconds: 4), onTimeout: () {});
        } catch (_) {}

        // Aggiorna istantaneamente anche lo stato in-memory di _eventi
        final evIdx = _eventi.indexWhere((e) => e.id == eventoId);
        if (evIdx != -1) {
          final ev = _eventi[evIdx];
          final updatedInv = List<String>.from(ev.invitati);
          for (var a in aggiuntiEffettivi) {
            if (!updatedInv.contains(a)) updatedInv.add(a);
          }
          _eventi[evIdx] = ev.copyWith(invitati: updatedInv);
        }

        break;
      } catch (e) {
        if (e is Exception && e.toString().contains('Non è più possibile invitare')) {
          rethrow;
        }
        markMongoDbDisconnected();
        if (attempt >= maxAttempts) {
          throw Exception('Impossibile connettersi al database per inviare gli inviti: $e');
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  // --- ELIMINA EVENTO DA MONGODB ATLAS (CON ELIMINAZIONE A CASCATA DEI BONUS E NOTIFICHE) ---
  Future<void> eliminaEvento(String eventoId, [String utente = 'Cloud']) async {
    invalidateCache();
    final cleanUser = utente.trim().toLowerCase();

    // Aggiornamento ISTANTANEO in-memory (zero latenza UI)
    _eventi.removeWhere((e) => e.id == eventoId);
    _bonusMalusList.removeWhere((b) => b.eventoId == eventoId || b.id == eventoId);
    _votazioniList.removeWhere((v) => v.bonusMalus?.eventoId == eventoId || v.id == eventoId);

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <300ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/eventi/elimina'),
          headers: defaultHeaders,
          body: jsonEncode({
            'eventoId': eventoId,
            'utente': utente,
          }),
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          return;
        }
      } catch (_) {}
    }

    bool directSuccess = false;

    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
        final evSelector = objId != null ? where.id(objId) : where.eq('_id', eventoId);
        
        final evDoc = await db.collection('Evento').findOne(evSelector);
        if (evDoc != null) {
          final creatore = (evDoc['propostoDa'] ?? evDoc['creatore'] ?? '').toString().trim().toLowerCase();
          if (creatore.isNotEmpty && creatore != cleanUser && cleanUser != 'cloud' && cleanUser != 'ugnom') {
            throw Exception('Solo il creatore dell\'evento ($creatore) può eliminarlo.');
          }

          final evTitolo = (evDoc['titolo'] ?? evDoc['nome'] ?? '').toString().toLowerCase();

          // 1. Rimuovi l'Evento
          await db.collection('Evento').remove(evSelector);

          // 2. Rimuovi tutti i Bonus/Malus e relative Votazioni associati a questo evento
          final bmDocs = await db.collection('BonusMalus').find(where.eq('eventoId', eventoId)).toList();
          for (var bm in bmDocs) {
            final bmId = bm['_id']?.toHexString() ?? bm['_id']?.toString() ?? '';
            await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
          }
          await db.collection('BonusMalus').remove(where.eq('eventoId', eventoId));

          // 3. Rimuovi tutte le Notifiche associate a questo evento
          await db.collection('Notifiche').remove(where.eq('eventoId', eventoId));

          // 4. Auto-pulizia dello storico voti attività per l'evento eliminato (I badge sbloccati rimangono intatti!)
          final uDocs = await db.collection('Utenti').find().toList();
          for (var uDoc in uDocs) {
            final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
            final newStorico = oldStorico.where((st) {
              final s = st.toString().toLowerCase();
              if (evTitolo.isNotEmpty && s.contains('"$evTitolo"')) return false;
              if (s.contains(eventoId.toLowerCase())) return false;
              return true;
            }).toList();

            await db.collection('Utenti').update(
              where.id(uDoc['_id'] as ObjectId),
              modify.set('storicoVoti', newStorico),
            );
          }

          if (_currentUser != null) {
            final newStorico = _currentUser!.storicoVoti.where((st) {
              final s = st.toLowerCase();
              if (evTitolo.isNotEmpty && s.contains('"$evTitolo"')) return false;
              if (s.contains(eventoId.toLowerCase())) return false;
              return true;
            }).toList();
            _currentUser = _currentUser!.copyWith(storicoVoti: newStorico);
          }
        }
        directSuccess = true;
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('Solo il creatore')) rethrow;
    }

    _eventi.removeWhere((e) => e.id == eventoId);
    _bonusMalusList.removeWhere((b) => b.eventoId == eventoId || b.id == eventoId);
    _votazioniList.removeWhere((v) => v.bonusMalus?.eventoId == eventoId || v.id == eventoId);

    // Fallback su Render (solo se l'eliminazione diretta su MongoDB non è riuscita)
    if (!directSuccess) {
      for (String url in baseUrls) {
        try {
          await http.post(
            Uri.parse('$url/eventi/elimina'),
            headers: defaultHeaders,
            body: jsonEncode({
              'eventoId': eventoId,
              'utente': utente,
            }),
          ).timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    }
  }

  // --- REPERIMENTO NOTIFICHE & INVITI (DEDUPLICAZIONE RIGIDA) ---
  Future<List<Map<String, dynamic>>> getNotifiche(String nickname) async {
    final cleanNick = resolveNickname(nickname).trim().toLowerCase();
    final List<Map<String, dynamic>> notificheList = [];

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <300ms)
    for (String url in baseUrls) {
      try {
        final res = await http.get(
          Uri.parse('$url/notifiche?utente=$cleanNick'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final List<dynamic> listJson = jsonDecode(res.body);
          final List<Map<String, dynamic>> resList = [];
          for (var item in listJson) {
            final m = Map<String, dynamic>.from(item as Map);
            resList.add(m);
          }
          return resList;
        }
      } catch (_) {}
    }

    // 2. Connessione DIRETTA di fallback a MongoDB Atlas
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        // Recupera eventi, votazioni e bonus/malus per pulizia intelligente e controllo stato voto
        final eventiDocs = await db.collection('Evento').find().toList();
        final votazioniDocs = await db.collection('Votazioni').find().toList();
        final bmDocs = await db.collection('BonusMalus').find().toList();
        final varDocs = await db.collection('RichiesteVar').find().toList();

        // Mappa delle RichiesteVar per ID hex / String
        final Map<String, Map<String, dynamic>> varMap = {};
        for (var v in varDocs) {
          final vIdHex = v['_id'] is ObjectId ? (v['_id'] as ObjectId).toHexString().toLowerCase() : '';
          final vIdStr = (v['_id']?.toString() ?? v['id']?.toString() ?? '').toLowerCase();
          final vClean = vIdStr.replaceAll(RegExp(r'[^a-f0-9]'), '');
          if (vIdHex.isNotEmpty) varMap[vIdHex] = v;
          if (vIdStr.isNotEmpty) varMap[vIdStr] = v;
          if (vClean.isNotEmpty) varMap[vClean] = v;
        }

        // Mappa degli eventi validi: Hex / String / Titolo -> Doc
        final Map<String, Map<String, dynamic>> validEvents = {};
        for (var ev in eventiDocs) {
          final eIdHex = ev['_id'] is ObjectId ? (ev['_id'] as ObjectId).toHexString().toLowerCase() : '';
          final eIdStr = (ev['_id']?.toString() ?? ev['id']?.toString() ?? '').toLowerCase();
          final eClean = eIdStr.replaceAll(RegExp(r'[^a-f0-9]'), '');
          if (eIdHex.isNotEmpty) validEvents[eIdHex] = ev;
          if (eIdStr.isNotEmpty) validEvents[eIdStr] = ev;
          if (eClean.isNotEmpty) validEvents[eClean] = ev;
          final eNome = (ev['nome'] ?? ev['titolo'] ?? '').toString().trim().toLowerCase();
          if (eNome.isNotEmpty) validEvents[eNome] = ev;
        }

        // Mappa dei BonusMalus per ID hex / Titolo
        final Map<String, Map<String, dynamic>> bonusMalusMap = {};
        for (var bm in bmDocs) {
          final bmIdHex = bm['_id'] is ObjectId ? (bm['_id'] as ObjectId).toHexString().toLowerCase() : (bm['_id']?.toString() ?? '').toLowerCase();
          if (bmIdHex.isNotEmpty) bonusMalusMap[bmIdHex] = bm;
          final bmNome = (bm['nome'] ?? bm['titolo'] ?? '').toString().trim().toLowerCase();
          if (bmNome.isNotEmpty) bonusMalusMap[bmNome] = bm;
          final bmTit = (bm['titolo'] ?? '').toString().trim().toLowerCase();
          if (bmTit.isNotEmpty) bonusMalusMap[bmTit] = bm;
        }

        // Mappa delle votazioni per bonusId / votazioneId / titolo
        final Map<String, Map<String, dynamic>> votazioniMap = {};
        for (var vot in votazioniDocs) {
          final vId = vot['_id']?.toHexString() ?? vot['_id']?.toString() ?? vot['id']?.toString() ?? vot['votazioneId']?.toString() ?? '';
          if (vId.isNotEmpty) votazioniMap[vId.toLowerCase()] = vot;
          final bmId = vot['bonusMalus']?['id']?.toString() ?? vot['bonusId']?.toString() ?? '';
          if (bmId.isNotEmpty) votazioniMap[bmId.toLowerCase()] = vot;
          final vTitolo = (vot['titolo'] ?? vot['bonusMalus']?['titolo'] ?? '').toString().trim().toLowerCase();
          if (vTitolo.isNotEmpty) votazioniMap[vTitolo] = vot;
        }

        final docs = await db.collection('Notifiche').find().toList();

        final matchDocs = docs.where((d) {
          final dDest = (d['destinatario'] ?? '').toString().trim();
          if (cleanNick.isEmpty) return true;
          return isSamePerson(dDest, cleanNick);
        }).toList();

        final Set<String> seenKeys = {};
        for (var d in matchDocs) {
          final idStr = d['_id']?.toHexString() ?? d['_id']?.toString() ?? d['notificaId']?.toString() ?? '';
          if (idStr.isEmpty || seenKeys.contains(idStr)) continue;

          final evId = (d['eventoId'] ?? '').toString().trim();
          final evIdLower = evId.toLowerCase();
          final evClean = evIdLower.replaceAll(RegExp(r'[^a-f0-9]'), '');
          final tipo = (d['tipo'] ?? '').toString().toLowerCase();

          // Auto-eliminazione notifiche se l'evento collegato è stato cancellato o è già terminato
          if (evId.isNotEmpty) {
            final evDoc = validEvents[evIdLower] ?? (evClean.isNotEmpty ? validEvents[evClean] : null);
            if (evDoc == null) {
              // L'evento NON esiste più nel DB (è stato eliminato): elimina notifica orfana
              if (d['_id'] is ObjectId) {
                try {
                  await db.collection('Notifiche').remove(where.id(d['_id'] as ObjectId));
                } catch (_) {}
              }
              continue;
            } else {
              // Verifica se l'evento è concluso/terminato (eventi in_programma o in_corso NON sono conclusi)
              final statoEv = (evDoc['stato'] ?? '').toString().toLowerCase();
              final dtFineStr = evDoc['dataFine']?.toString();
              DateTime? dtFine = dtFineStr != null ? DateTime.tryParse(dtFineStr) : null;
              final bool isEvConcluso = statoEv == 'concluso' ||
                  (statoEv != 'in_corso' && statoEv != 'in_programma' && dtFine != null && DateTime.now().isAfter(dtFine));

              // Se l'evento è concluso, le notifiche operative pendenti (inviti, proposte di votazione) non servono più
              final bool isOperativa = tipo == 'invito' || tipo.contains('proposta') || tipo == 'bonus_malus' || tipo.contains('var_');
              if (isEvConcluso && isOperativa) {
                if (d['_id'] is ObjectId) {
                  try {
                    await db.collection('Notifiche').remove(where.id(d['_id'] as ObjectId));
                  } catch (_) {}
                }
                continue;
              }
            }
          }

          // Controllo dello stato di voto per proposte / votazioni live
          bool haGiaVotato = false;
          String votoEspresso = (d['votoEspresso'] ?? '').toString();
          bool votazioneChiusa = false;
          String esitoVotazione = '';

          final bonusId = (d['bonusId'] ?? '').toString().trim().toLowerCase();
          final bonusTitolo = (d['bonusTitolo'] ?? '').toString().trim().toLowerCase();

          // 1. Controllo su BonusMalus collection (stato approvato/respinto e proponente)
          final matchedBm = (bonusId.isNotEmpty ? bonusMalusMap[bonusId] : null) ??
              (bonusTitolo.isNotEmpty ? bonusMalusMap[bonusTitolo] : null);

          if (matchedBm != null) {
            final propDa = (matchedBm['propostoDa'] ?? '').toString().trim();
            // Se chi visualizza la notifica è l'autore della proposta, ha già votato 'pro'
            if (propDa.isNotEmpty && isSamePerson(propDa, cleanNick)) {
              haGiaVotato = true;
              votoEspresso = 'pro';
            }
            final bmStato = (matchedBm['stato'] ?? '').toString().toLowerCase();
            if (bmStato == 'approvato' || bmStato == 'respinto') {
              votazioneChiusa = true;
              esitoVotazione = bmStato;
            }
          }

          // 2. Controllo voti individuali da Votazioni collection (MATCH ESATTO su ID o Titolo esatto + Evento)
          if (!haGiaVotato) {
            for (var vDoc in votazioniDocs) {
              final vUser = (vDoc['utente'] ?? '').toString().trim();
              if (!isSamePerson(vUser, cleanNick)) continue;

              final vId = (vDoc['votazioneId'] ?? vDoc['bonusId'] ?? '').toString().trim().toLowerCase();
              final vTit = (vDoc['bonusTitolo'] ?? '').toString().trim().toLowerCase();
              final vEvId = (vDoc['eventoId'] ?? '').toString().trim().toLowerCase();

              final bool idMatch = bonusId.isNotEmpty && (vId == bonusId);
              final bool titleMatch = bonusTitolo.isNotEmpty && vTit == bonusTitolo && (evIdLower.isEmpty || vEvId.isEmpty || vEvId == evIdLower);

              if (idMatch || titleMatch) {
                haGiaVotato = true;
                votoEspresso = (vDoc['voto']?.toString() ?? 'pro').toLowerCase();
                final vStato = (vDoc['stato'] ?? '').toString().toLowerCase();
                if (vStato == 'approvato' || vStato == 'respinto') {
                  votazioneChiusa = true;
                  esitoVotazione = vStato;
                }
                break;
              }
            }
          }

          // 3. Fallback controllo matchVotazione generico (SOLO MATCH ESATTO per ID o Titolo)
          if (!haGiaVotato || !votazioneChiusa) {
            Map<String, dynamic>? matchVotazione;
            if (bonusId.isNotEmpty && votazioniMap.containsKey(bonusId)) {
              matchVotazione = votazioniMap[bonusId];
            } else if (bonusTitolo.isNotEmpty && votazioniMap.containsKey(bonusTitolo)) {
              matchVotazione = votazioniMap[bonusTitolo];
            }

            if (matchVotazione != null) {
              final votiMap = matchVotazione['votiUtenti'] as Map? ?? {};
              for (var k in votiMap.keys) {
                if (isSamePerson(k.toString().trim(), cleanNick)) {
                  haGiaVotato = true;
                  votoEspresso = votiMap[k]?.toString() ?? 'votato';
                  break;
                }
              }
              final statoVot = (matchVotazione['stato'] ?? '').toString().toLowerCase();
              if (statoVot == 'approvato' || statoVot == 'respinto' || statoVot == 'scaduto' || statoVot == 'concluso') {
                votazioneChiusa = true;
                esitoVotazione = statoVot;
              }
            }
          }

          final evDoc = evId.isNotEmpty ? (validEvents[evIdLower] ?? (evClean.isNotEmpty ? validEvents[evClean] : null)) : null;
          final String evStato = evDoc != null ? (evDoc['stato'] ?? '').toString().toLowerCase() : '';
          final String evDataInizio = evDoc != null ? (evDoc['data'] ?? '').toString() : '';

          seenKeys.add(idStr);
          final rawMittente = (d['mittente'] ?? 'FantaEventi').toString();
          final resolvedMittente = resolveNickname(rawMittente);

          String rawMessaggio = (d['messaggio'] ?? '').toString();
          rawMessaggio = rawMessaggio
              .replaceAll('Filippo ha proposto', '$resolvedMittente ha proposto')
              .replaceAll('Claudio ha proposto', 'Cloud ha proposto')
              .replaceAll('Claude ha proposto', 'Cloud ha proposto')
              .replaceAll('Antonio ha proposto', 'Ugnom ha proposto')
              .replaceAll('Claudio ti ha invitato', 'Cloud ti ha invitato')
              .replaceAll('Claude ti ha invitato', 'Cloud ti ha invitato')
              .replaceAll('Filippo ti ha invitato', 'Pippoforte ti ha invitato')
              .replaceAll('Antonio ti ha invitato', 'Ugnom ti ha invitato')
              .replaceAll('Claudio ha ricevuto', 'Cloud ha ricevuto')
              .replaceAll('Claude ha ricevuto', 'Cloud ha ricevuto')
              .replaceAll(' a Claudio ', ' a Cloud ')
              .replaceAll(' a Claude ', ' a Cloud ');

          // Sincronizzazione automatica e self-healing dello stato VAR (solo per notifiche operative, NON per var_esito)
          final notVarId = (d['varId'] ?? '').toString().trim().toLowerCase();
          final notVarClean = notVarId.replaceAll(RegExp(r'[^a-f0-9]'), '');
          String finalStato = (d['stato'] ?? 'in_attesa').toString();
          bool finalLetto = d['letto'] == true;

          if (notVarId.isNotEmpty && tipo != 'var_esito') {
            final matchedVar = varMap[notVarId] ?? (notVarClean.isNotEmpty ? varMap[notVarClean] : null);
            if (matchedVar != null) {
              final vStato = (matchedVar['stato'] ?? '').toString().toLowerCase();
              if (vStato == 'approvata' || vStato == 'approvato') {
                finalStato = 'approvata';
                finalLetto = true;
              } else if (vStato == 'rifiutata' || vStato == 'rifiutato') {
                finalStato = 'rifiutata';
                finalLetto = true;
              }
              // Self-healing asincrono nel DB se ancora marcata come in_attesa
              if (d['_id'] is ObjectId && (d['stato'] == 'in_attesa' || d['stato'] == 'in_votazione') && (finalStato == 'approvata' || finalStato == 'rifiutata')) {
                try {
                  db.collection('Notifiche').update(
                    where.id(d['_id'] as ObjectId),
                    modify.set('stato', finalStato).set('letto', true),
                  );
                } catch (_) {}
              }
            }
          }

          notificheList.add({
            'id': idStr,
            'mittente': resolvedMittente,
            'destinatario': resolveNickname((d['destinatario'] ?? '').toString()),
            'titolo': d['titolo'] ?? 'Nuova Notifica',
            'messaggio': rawMessaggio,
            'eventoId': d['eventoId'] ?? '',
            'eventoStato': evStato,
            'eventoDataInizio': evDataInizio,
            'bonusId': d['bonusId'] ?? '',
            'bonusTitolo': d['bonusTitolo'] ?? '',
            'tipo': d['tipo'] ?? 'invito',
            'varId': d['varId'] ?? '',
            'stato': finalStato,
            'letto': finalLetto,
            'votoEspresso': votoEspresso,
            'haGiaVotato': haGiaVotato,
            'votazioneChiusa': votazioneChiusa,
            'esitoVotazione': esitoVotazione,
            'data': d['data']?.toString() ?? DateTime.now().toIso8601String(),
          });
        }

        return notificheList;
      }
    } catch (_) {}

    return notificheList;
  }

  // --- RISPONDI AD UN INVITO O NOTIFICA BONUS ---
  Future<void> rispondiNotifica(String notificaId, String azione, String utente) async {
    invalidateCache();
    final isPro = azione == 'accetta' || azione == 'pro' || azione == 'favorevole';
    final nuovoStato = isPro ? 'accettato' : 'rifiutato';
    final votoEspresso = isPro ? 'pro' : 'contro';

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/notifiche/rispondi'),
          headers: defaultHeaders,
          body: jsonEncode({
            'notificaId': notificaId,
            'azione': azione,
            'utente': utente,
          }),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          return;
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: aggiornamento DIRETTO su MongoDB Atlas
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
        final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);
        
        await db.collection('Notifiche').update(
          selector,
          modify.set('stato', nuovoStato).set('votoEspresso', votoEspresso).set('letto', true),
        );

        if (azione == 'accetta') {
          // Se accetta l'invito all'evento, iscrivilo nei partecipanti se l'evento non è già iniziato!
          final doc = await db.collection('Notifiche').findOne(selector);
          if (doc != null) {
            final evId = doc['eventoId']?.toString() ?? '';
            if (evId.isNotEmpty) {
              ObjectId? evObjId;
              try { evObjId = ObjectId.fromHexString(evId); } catch (_) {}
              final evSelector = evObjId != null ? where.id(evObjId) : where.eq('_id', evId);
              final evDoc = await db.collection('Evento').findOne(evSelector);
              if (evDoc != null) {
                final dateStr = evDoc['data']?.toString() ?? '';
                final dtStart = DateTime.tryParse(dateStr);
                final statoEv = (evDoc['stato'] ?? '').toString().toLowerCase();
                if (statoEv == 'in_corso' || statoEv == 'concluso' || (dtStart != null && DateTime.now().isAfter(dtStart))) {
                  throw Exception('Questo evento è già iniziato o concluso! L\'iscrizione è ormai chiusa.');
                }

                final pullList = {
                  utente,
                  utente.toLowerCase(),
                  utente.toUpperCase(),
                  utente.trim(),
                  utente.trim().toLowerCase(),
                }.toList();

                await db.collection('Evento').update(
                  evSelector,
                  modify
                    .addToSet('partecipanti', utente)
                    .pullAll('invitati', pullList),
                );

                // Aggiornamento ISTANTANEO in-memory di _eventi (zero latenza per le card eventi)
                final evIdx = _eventi.indexWhere((e) => e.id == evId);
                if (evIdx != -1) {
                  final ev = _eventi[evIdx];
                  final updatedPart = List<String>.from(ev.partecipanti);
                  final updatedInv = List<String>.from(ev.invitati);
                  updatedInv.removeWhere((i) => i.toLowerCase() == utente.toLowerCase());
                  if (!updatedPart.any((p) => p.toLowerCase() == utente.toLowerCase())) {
                    updatedPart.add(utente);
                  }
                  _eventi[evIdx] = ev.copyWith(partecipanti: updatedPart, invitati: updatedInv);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      if (e is Exception && (e.toString().contains('Questo evento è già iniziato') || e.toString().contains('iscrizione è ormai chiusa'))) {
        rethrow;
      }
    }
  }

  Future<Evento> creaEvento(Evento nuovoEvento, {bool awardXp = true}) async {
    invalidateCache();
    final rawCreatore = (_currentUser?.nickname.isNotEmpty == true
        ? _currentUser!.nickname
        : (nuovoEvento.propostoDa.isNotEmpty
            ? nuovoEvento.propostoDa
            : (_currentUser?.nome ?? 'Cloud'))).trim();
    final creatore = resolveNickname(rawCreatore);
    final List<String> invitati = nuovoEvento.partecipanti
        .where((p) => !isSamePerson(p, creatore))
        .map((p) => resolveNickname(p))
        .toList();

    final eventPayload = nuovoEvento.copyWith(
      propostoDa: creatore,
      partecipanti: [creatore],
      invitati: invitati,
    );

    final payloadMap = eventPayload.toJson();
    payloadMap['invitati'] = invitati;
    payloadMap['partecipanti'] = [creatore, ...invitati];

    String realEvId = eventPayload.id;

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/eventi/crea'),
          headers: defaultHeaders,
          body: jsonEncode({
            'titolo': nuovoEvento.titolo,
            'descrizione': nuovoEvento.descrizione,
            'data': nuovoEvento.data.toIso8601String(),
            'dataFine': nuovoEvento.dataFine.toIso8601String(),
            'luogo': nuovoEvento.luogo,
            'latitudine': nuovoEvento.latitudine,
            'longitudine': nuovoEvento.longitudine,
            'propostoDa': creatore,
            'partecipanti': [creatore],
            'invitati': invitati,
            'penalitaFalsaTestimonianza': nuovoEvento.penalitaFalsaTestimonianza,
          }),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final resData = jsonDecode(res.body) as Map<String, dynamic>;
          final insertedEvId = resData['id']?.toString() ?? '';
          final savedEvento = eventPayload.copyWith(id: insertedEvId.isNotEmpty ? insertedEvId : realEvId);
          _eventi.insert(0, savedEvento);

          // Invia notifica push reale per la tendina di sistema a tutti gli invitati
          if (invitati.isNotEmpty) {
            try {
              await PushNotificationService.instance.inviaPushAUtenti(
                invitati,
                titolo: '🎉 Invito ad Evento: ${nuovoEvento.titolo}',
                messaggio: '$creatore ti ha invitato a partecipare all\'evento "${nuovoEvento.titolo}"!',
                data: {
                  'tipo': 'invito',
                  'eventoId': insertedEvId.isNotEmpty ? insertedEvId : realEvId,
                },
              ).timeout(const Duration(seconds: 4), onTimeout: () {});
            } catch (_) {}
          }

          // Aggiungi voce storico al creatore
          if (_currentUser != null) {
            final logVoce = formattaVoceStorico('Creato evento "${nuovoEvento.titolo}" (in attesa di avvio)');
            _currentUser = _currentUser!.copyWith(
              storicoVoti: [
                logVoce,
                ..._currentUser!.storicoVoti,
              ],
            );
          }

          return savedEvento;
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: scrittura DIRETTA su MongoDB Atlas
    int maxAttempts = 2;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        Db? db = await _getSafeMongoDb();
        if (db == null || !db.isConnected) {
          markMongoDbDisconnected();
          db = await _getSafeMongoDb();
        }
        if (db == null || !db.isConnected) {
          throw Exception('Impossibile connettersi al database per creare l\'evento.');
        }

        final evRes = await db.collection('Evento').insertOne({
          'titolo': nuovoEvento.titolo,
          'nome': nuovoEvento.titolo,
          'descrizione': nuovoEvento.descrizione,
          'data': nuovoEvento.data.toIso8601String(),
          'dataFine': nuovoEvento.dataFine.toIso8601String(),
          'luogo': nuovoEvento.luogo,
          if (nuovoEvento.latitudine != null) 'latitudine': nuovoEvento.latitudine,
          if (nuovoEvento.longitudine != null) 'longitudine': nuovoEvento.longitudine,
          'stato': 'in_programma',
          'propostoDa': creatore,
          'creatore': creatore,
          'partecipanti': [creatore],
          'invitati': invitati,
          'copertinaUrl': nuovoEvento.copertinaUrl,
          'penalitaFalsaTestimonianza': nuovoEvento.penalitaFalsaTestimonianza,
          'xpCreatoreAssegnati': false,
        }).timeout(const Duration(seconds: 5));

        final insertedEvId = evRes.id?.toHexString() ?? '';
        if (insertedEvId.isNotEmpty) {
          realEvId = insertedEvId;
        }

        for (var invUser in invitati) {
          try {
            await db.collection('Notifiche').insertOne({
              'mittente': creatore,
              'destinatario': invUser,
              'titolo': 'Invito ad Evento: ${nuovoEvento.titolo}',
              'messaggio': '$creatore ti ha invitato a partecipare all\'evento "${nuovoEvento.titolo}"!',
              'eventoId': insertedEvId.isNotEmpty ? insertedEvId : realEvId,
              'tipo': 'invito',
              'stato': 'in_attesa',
              'letto': false,
              'data': DateTime.now().toIso8601String(),
            }).timeout(const Duration(seconds: 4));
          } catch (_) {}
        }

        // Invia notifica push reale per la tendina di sistema a tutti gli invitati
        if (invitati.isNotEmpty) {
          try {
            await PushNotificationService.instance.inviaPushAUtenti(
              invitati,
              titolo: '🎉 Invito ad Evento: ${nuovoEvento.titolo}',
              messaggio: '$creatore ti ha invitato a partecipare all\'evento "${nuovoEvento.titolo}"!',
              data: {
                'tipo': 'invito',
                'eventoId': insertedEvId.isNotEmpty ? insertedEvId : realEvId,
              },
            ).timeout(const Duration(seconds: 4), onTimeout: () {});
          } catch (_) {}
        }

        break;
      } catch (e) {
        markMongoDbDisconnected();
        if (attempt >= maxAttempts) {
          throw Exception('Errore di connessione a MongoDB durante la creazione dell\'evento: $e');
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    final savedEvento = eventPayload.copyWith(id: realEvId);
    _eventi.insert(0, savedEvento);

    // Protezione anti-farming: i 100 XP per la creazione dell'evento vengono assegnati
    // solo ed esclusivamente quando l'evento scatta 'in_corso' con almeno 1 altro partecipante!
    if (_currentUser != null) {
      final logVoce = formattaVoceStorico('Creato evento "${nuovoEvento.titolo}" (in attesa di avvio)');
      _currentUser = _currentUser!.copyWith(
        storicoVoti: [
          logVoce,
          ..._currentUser!.storicoVoti,
        ],
      );
      try {
        final db = await _getSafeMongoDb().timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (db != null && db.isConnected) {
          final uDocs = await db.collection('Utenti').find().toList().timeout(const Duration(seconds: 4));
          for (var uDoc in uDocs) {
            if (matchesUserDoc(uDoc, _currentUser!.nickname)) {
              final curStorico = List<dynamic>.from(uDoc['storicoVoti'] ?? []);
              curStorico.insert(0, logVoce);
              await db.collection('Utenti').update(
                where.id(uDoc['_id'] as ObjectId),
                modify.set('storicoVoti', curStorico),
              ).timeout(const Duration(seconds: 4));
            }
          }
        }
      } catch (_) {}
    }

    return savedEvento;
  }

  // --- AGGIORNA COPERTINA EVENTO SU MONGODB ATLAS & MEMORIA LOCALE ---
  Future<void> aggiornaCopertinaEvento(String eventoId, String newCopertinaUrl) async {
    final evIndex = _eventi.indexWhere((e) =>
        e.id.trim().toLowerCase() == eventoId.trim().toLowerCase() ||
        e.titolo.trim().toLowerCase() == eventoId.trim().toLowerCase());
    if (evIndex != -1) {
      _eventi[evIndex] = _eventi[evIndex].copyWith(copertinaUrl: newCopertinaUrl);
    }
    invalidateCache();

    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final evDocs = await db.collection('Evento').find().toList();
        for (var doc in evDocs) {
          final dId = (doc['_id']?.toHexString() ?? doc['_id']?.toString() ?? doc['id'] ?? '').toString().trim().toLowerCase();
          final dTit = (doc['titolo'] ?? doc['nome'] ?? '').toString().trim().toLowerCase();
          final target = eventoId.trim().toLowerCase();

          if (dId == target || dTit == target) {
            await db.collection('Evento').update(
              where.id(doc['_id'] as ObjectId),
              modify.set('copertinaUrl', newCopertinaUrl),
            );
            break;
          }
        }
      }
    } catch (_) {}
  }

  // --- PROPOSTA BONUS/MALUS LEGATA A UN EVENTO SPECIFICO ---
  Future<BonusMalus> proponiBonusMalusPerEvento(String eventoId, BonusMalus nuovoBonus, {bool awardXp = true}) async {
    final int safePunti = nuovoBonus.punti.clamp(-100, 100);
    nuovoBonus = nuovoBonus.copyWith(punti: safePunti == 0 ? 10 : safePunti);
    final rawAuthor = (_currentUser?.nickname.isNotEmpty == true
        ? _currentUser!.nickname
        : (nuovoBonus.propostoDa.trim().isNotEmpty
            ? nuovoBonus.propostoDa.trim()
            : (_currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud'))).trim();
    final String curUserNick = resolveNickname(rawAuthor);

    Evento evMatch = _eventi.firstWhere(
      (e) => e.id == eventoId || e.titolo.toLowerCase() == eventoId.toLowerCase(),
      orElse: () => Evento(
        id: eventoId,
        titolo: 'Evento Fanta',
        descrizione: '',
        data: DateTime.now(),
        luogo: '',
        stato: '',
        propostoDa: curUserNick,
        partecipanti: [],
        bonusMalusApplicati: [],
        votazioniAttive: [],
      ),
    );

    String bmHexId = 'bm_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/bonusmalus/crea'),
          headers: defaultHeaders,
          body: jsonEncode({
            'eventoId': eventoId,
            'eventoTitolo': evMatch.titolo,
            'nome': nuovoBonus.titolo,
            'titolo': nuovoBonus.titolo,
            'descrizione': nuovoBonus.descrizione,
            'punti': safePunti,
            'tipo': nuovoBonus.isBonus ? 'bonus' : 'malus',
            'categoria': nuovoBonus.categoria,
            'propostoDa': curUserNick,
            'utente': curUserNick,
            'riassegnabileMoltepliciVolte': nuovoBonus.riassegnabileMoltepliciVolte,
          }),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final resData = jsonDecode(res.body) as Map<String, dynamic>;
          final insertedBmId = resData['id']?.toString() ?? '';
          final finalBonus = nuovoBonus.copyWith(
            id: insertedBmId.isNotEmpty ? insertedBmId : nuovoBonus.id,
          );
          _bonusMalusList.insert(0, finalBonus);
          invalidateCache();

          // Invia notifica push reale per la tendina di sistema a tutti i partecipanti ed invitati
          final List<String> allCandidates = [
            ...evMatch.partecipanti,
            ...evMatch.invitati,
            evMatch.propostoDa,
            evMatch.creatore,
          ];
          final Set<String> uniqueDests = {};
          final rawBackendDests = (resData['destinatari'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          for (var b in rawBackendDests) {
            final clean = b.trim();
            if (clean.isNotEmpty && !isSamePerson(clean, curUserNick)) {
              uniqueDests.add(resolveNickname(clean));
            }
          }
          for (var c in allCandidates) {
            final clean = c.trim();
            if (clean.isNotEmpty && !isSamePerson(clean, curUserNick)) {
              uniqueDests.add(resolveNickname(clean));
            }
          }
          final String realEvTitolo = (resData['eventoTitolo']?.toString().isNotEmpty == true)
              ? resData['eventoTitolo'].toString()
              : evMatch.titolo;
          if (uniqueDests.isNotEmpty) {
            try {
              await PushNotificationService.instance.inviaPushAUtenti(
                uniqueDests.toList(),
                titolo: '⚡ Nuova Regola Proposta: ${nuovoBonus.titolo}',
                messaggio: '$curUserNick ha proposto "${nuovoBonus.titolo}" (${nuovoBonus.punti >= 0 ? "+${nuovoBonus.punti}" : nuovoBonus.punti} PT) in "$realEvTitolo". Entra a votare!',
                data: {
                  'tipo': 'votazione',
                  'eventoId': eventoId,
                  'bonusId': insertedBmId.isNotEmpty ? insertedBmId : nuovoBonus.id,
                },
              ).timeout(const Duration(seconds: 4), onTimeout: () {});
            } catch (_) {}
          }

          return finalBonus;
        } else if (res.statusCode == 400) {
          final resData = jsonDecode(res.body) as Map<String, dynamic>;
          if (resData['error']?.toString().contains('esiste già') == true) {
            throw Exception(resData['error'].toString());
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('esiste già')) rethrow;
      }
    }

    // 2. Rete di salvataggio: scrittura DIRETTA su MongoDB Atlas
    int maxAttempts = 2;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        Db? db = await _getSafeMongoDb();
        if (db == null || !db.isConnected) {
          markMongoDbDisconnected();
          db = await _getSafeMongoDb();
        }

        if (db == null || !db.isConnected) {
          throw Exception('Impossibile connettersi al database per inviare la proposta.');
        }

        // 1. Recupero SEMPRE fresco dell'evento da MongoDB Atlas per avere tutti i partecipanti reali
        ObjectId? evObjId;
        try { evObjId = ObjectId.fromHexString(eventoId); } catch (_) {}
        final evDoc = await db.collection('Evento').findOne(
          evObjId != null ? where.id(evObjId) : where.eq('_id', eventoId).or(where.eq('titolo', eventoId))
        ).timeout(const Duration(seconds: 5), onTimeout: () => null);

        if (evDoc != null) {
          evMatch = evMatch.copyWith(
            titolo: evDoc['titolo'] ?? evDoc['nome'] ?? evMatch.titolo,
            propostoDa: evDoc['propostoDa'] ?? evDoc['creatore'] ?? evMatch.propostoDa,
            stato: evDoc['stato'] ?? evMatch.stato,
            partecipanti: (evDoc['partecipanti'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? evMatch.partecipanti,
            invitati: (evDoc['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? evMatch.invitati,
          );
        }

        // Verifica che l'utente sia creatore o partecipante effettivo dell'evento
        final bool isCreator = isSamePerson(evMatch.propostoDa, curUserNick) || isSamePerson(evMatch.creatore, curUserNick);
        final bool isParticipant = isCreator || evMatch.partecipanti.any((p) => isSamePerson(p, curUserNick));

        if (!isParticipant) {
          throw Exception('Non puoi proporre bonus/malus per un evento a cui non partecipi!');
        }

        final statoEv = evMatch.stato.trim().toLowerCase();
        if (statoEv == 'concluso') {
          throw Exception('Non puoi proporre bonus/malus per un evento già concluso!');
        }

        // 2. Controllo anti-duplicazione: verifica se esiste già una proposta identica per lo stesso evento
        final existingBm = await db.collection('BonusMalus').findOne(
          where.eq('eventoId', eventoId).and(where.eq('nome', nuovoBonus.titolo))
        ).timeout(const Duration(seconds: 5), onTimeout: () => null);

        if (existingBm != null) {
          bmHexId = existingBm['_id'] is ObjectId
              ? (existingBm['_id'] as ObjectId).toHexString()
              : (existingBm['_id']?.toString() ?? bmHexId);

          // Assicura che propostoDa, stato e categoria siano aggiornati
          await db.collection('BonusMalus').update(
            where.id(existingBm['_id'] as ObjectId),
            modify
              .set('propostoDa', curUserNick)
              .set('stato', 'in_votazione')
              .set('categoria', nuovoBonus.categoria)
              .set('riassegnabileMoltepliciVolte', nuovoBonus.riassegnabileMoltepliciVolte),
          ).timeout(const Duration(seconds: 4));
        } else {
          final insertRes = await db.collection('BonusMalus').insertOne({
            'eventoId': eventoId,
            'nome': nuovoBonus.titolo,
            'descrizione': nuovoBonus.descrizione,
            'punti': nuovoBonus.punti,
            'categoria': nuovoBonus.categoria,
            'tipo': nuovoBonus.punti >= 0 ? 'bonus' : 'malus',
            'propostoDa': curUserNick,
            'stato': 'in_votazione',
            'riassegnabileMoltepliciVolte': nuovoBonus.riassegnabileMoltepliciVolte,
          }).timeout(const Duration(seconds: 5));

          if (insertRes.id is ObjectId) {
            bmHexId = (insertRes.id as ObjectId).toHexString();
          }
        }

        // 3. Registra esplicitamente il voto 'pro' del proponente in Votazioni su MongoDB Atlas
        try {
          final existingVote = await db.collection('Votazioni').findOne(
            where.eq('votazioneId', bmHexId).and(
              where.eq('utente', curUserNick)
            )
          ).timeout(const Duration(seconds: 4), onTimeout: () => null);

          if (existingVote == null) {
            await db.collection('Votazioni').insertOne({
              'votazioneId': bmHexId,
              'bonusId': bmHexId,
              'eventoId': eventoId,
              'bonusTitolo': nuovoBonus.titolo,
              'utente': curUserNick,
              'voto': 'pro',
              'stato': 'in_votazione',
              'data': DateTime.now().toIso8601String(),
            }).timeout(const Duration(seconds: 4));
          }
        } catch (_) {}

        // 4. Inserimento notifiche a TUTTI i partecipanti ed invitati dell'evento (escluso il proponente)
        final Map<String, String> uniqueDestMap = {};
        final List<String> allCandidates = [
          ...evMatch.partecipanti,
          ...evMatch.invitati,
          evMatch.propostoDa,
          evMatch.creatore,
        ];
        if (evDoc != null) {
          final docParts = (evDoc['partecipanti'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
          final docInvs = (evDoc['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
          final docCreator = (evDoc['propostoDa'] ?? evDoc['creatore'] ?? '').toString().trim();
          allCandidates.addAll(docParts);
          allCandidates.addAll(docInvs);
          if (docCreator.isNotEmpty) allCandidates.add(docCreator);
        }

        for (var d in allCandidates) {
          final cleanD = d.trim();
          if (cleanD.isEmpty) continue;
          final dResolved = resolveNickname(cleanD);
          final bool isRecipientMyself = isSamePerson(cleanD, curUserNick) ||
              isSamePerson(cleanD, _currentUser?.nickname) ||
              isSamePerson(cleanD, _currentUser?.nome);

          if (!isRecipientMyself) {
            uniqueDestMap[dResolved.toLowerCase()] = dResolved;
          }
        }

        for (var destUser in uniqueDestMap.values) {
          try {
            final existingNot = await db.collection('Notifiche').findOne(
              where.eq('destinatario', destUser).and(where.eq('bonusId', bmHexId))
            ).timeout(const Duration(seconds: 3), onTimeout: () => null);

            if (existingNot == null) {
              await db.collection('Notifiche').insertOne({
                'mittente': curUserNick,
                'destinatario': destUser,
                'titolo': '⭐ Nuova Proposta: ${nuovoBonus.titolo}',
                'messaggio': '$curUserNick ha proposto il ${nuovoBonus.punti >= 0 ? "bonus" : "malus"} "${nuovoBonus.titolo}" (${nuovoBonus.punti >= 0 ? "+${nuovoBonus.punti}" : nuovoBonus.punti} PT) per l\'evento "${evMatch.titolo}"!',
                'eventoId': eventoId,
                'bonusId': bmHexId,
                'bonusTitolo': nuovoBonus.titolo,
                'tipo': 'bonus_malus',
                'stato': 'in_attesa',
                'letto': false,
                'data': DateTime.now().toIso8601String(),
              }).timeout(const Duration(seconds: 4));
            }
          } catch (_) {}
        }

        // Invia notifica push reale per la tendina di sistema a tutti i partecipanti
        if (uniqueDestMap.isNotEmpty) {
          try {
            await PushNotificationService.instance.inviaPushAUtenti(
              uniqueDestMap.values.toList(),
              titolo: '⚡ Nuova Regola Proposta: ${nuovoBonus.titolo}',
              messaggio: '$curUserNick ha proposto "${nuovoBonus.titolo}" (${nuovoBonus.punti >= 0 ? "+${nuovoBonus.punti}" : nuovoBonus.punti} PT) in "${evMatch.titolo}". Entra a votare!',
              data: {
                'tipo': 'votazione',
                'eventoId': eventoId,
                'bonusId': bmHexId,
              },
            ).timeout(const Duration(seconds: 4), onTimeout: () {});
          } catch (_) {}
        }

        // Operazione completata con successo, esce dal loop di retry
        break;
      } catch (e) {
        markMongoDbDisconnected();
        if (attempt >= maxAttempts) {
          throw Exception('Impossibile connettersi al database per inviare la proposta. Controlla la connessione internet e riprova.');
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    final index = _eventi.indexWhere((e) => e.id == eventoId);
    final BonusMalus bonusConcluso = nuovoBonus.copyWith(
      id: bmHexId,
      propostoDa: curUserNick,
      stato: 'in_votazione',
      approvato: false,
    );

    if (index != -1) {
      final ev = _eventi[index];
      final numPartecipanti = ev.partecipanti.length >= 2 ? ev.partecipanti.length : 3;
      final quorumCalcolato = (numPartecipanti / 2).floor() + 1;

      final meVotazione = Votazione(
        id: bmHexId,
        titolo: 'Votazione per "${ev.titolo}": ${nuovoBonus.titolo}',
        descrizione: 'Proposto da $curUserNick: ${nuovoBonus.descrizione} (${nuovoBonus.punti > 0 ? "+${nuovoBonus.punti}" : nuovoBonus.punti} pt)',
        bonusMalus: bonusConcluso,
        votiFavorevoli: 1,
        votiContrari: 0,
        quorum: quorumCalcolato,
        stato: 'in_corso',
        scadenza: DateTime.now().add(const Duration(hours: 24)),
        votiUtenti: {
          curUserNick: 'pro',
          curUserNick.toLowerCase(): 'pro',
        },
      );

      final votazioniAggiornate = [
        meVotazione,
        ...ev.votazioniAttive.where((v) => v.id != bmHexId && v.titolo != meVotazione.titolo),
      ];
      _eventi[index] = ev.copyWith(votazioniAttive: votazioniAggiornate);
      _votazioniList.removeWhere((v) => v.id == bmHexId || v.titolo == meVotazione.titolo);
      _votazioniList.insert(0, meVotazione);
    }

    // Se approvato subito, inseriscilo in _bonusMalusList, altrimenti rimane solo nelle Votazioni Live
    if (bonusConcluso.approvato || bonusConcluso.stato == 'approvato') {
      _bonusMalusList.insert(0, bonusConcluso);
    }

    if (_currentUser != null && awardXp) {
      final prog = XpProgression.aggiungiXp(
        livelloAttuale: _currentUser!.livello,
        xpLivelloAttuale: _currentUser!.xp,
        deltaXp: 50,
        xpTotaliAttuali: _currentUser!.xpTotali,
      );
      final logVoce = formattaVoceStorico('Proposto ${nuovoBonus.isBonus ? "Bonus" : "Malus"} "${nuovoBonus.titolo}" (+50 XP)');
      _currentUser = _currentUser!.copyWith(
        xp: prog.xp,
        livello: prog.livello,
        xpProssimoLivello: prog.xpProssimoLivello,
        xpTotali: prog.xpTotali,
        storicoVoti: [
          logVoce,
          ..._currentUser!.storicoVoti,
        ],
      );
      try {
        final db = await _getSafeMongoDb().timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (db != null && db.isConnected) {
          final uDocs = await db.collection('Utenti').find().toList().timeout(const Duration(seconds: 4));
          for (var uDoc in uDocs) {
            if (matchesUserDoc(uDoc, _currentUser!.nickname)) {
              final curStorico = List<dynamic>.from(uDoc['storicoVoti'] ?? []);
              curStorico.insert(0, logVoce);
              await db.collection('Utenti').update(
                where.id(uDoc['_id'] as ObjectId),
                modify
                  .set('xp', prog.xp)
                  .set('livello', prog.livello)
                  .set('xpProssimoLivello', prog.xpProssimoLivello)
                  .set('xpTotali', prog.xpTotali)
                  .set('storicoVoti', curStorico),
              ).timeout(const Duration(seconds: 4));
            }
          }
        }
      } catch (_) {
        markMongoDbDisconnected();
      }
    }

    return bonusConcluso;
  }

  // --- ELIMINA PROPOSTA BONUS/MALUS DA MONGODB ATLAS ---
  Future<void> eliminaBonusMalus(String bonusMalusId) async {
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(bonusMalusId); } catch (_) {}
        final selector = objId != null ? where.id(objId) : where.eq('_id', bonusMalusId);

        await db.collection('BonusMalus').remove(selector);
        await db.collection('Votazioni').remove(where.eq('votazioneId', bonusMalusId));
      }
    } catch (_) {}

    _bonusMalusList.removeWhere((b) => b.id == bonusMalusId || b.titolo.contains(bonusMalusId));
    _votazioniList.removeWhere((v) => v.id == bonusMalusId || (v.bonusMalus != null && v.bonusMalus!.id == bonusMalusId) || v.titolo.contains(bonusMalusId));
    
    // Rimuovi anche dalle votazioni attive degli eventi
    for (int i = 0; i < _eventi.length; i++) {
      final ev = _eventi[i];
      final vAggiornate = ev.votazioniAttive.where((v) => v.id != bonusMalusId && (v.bonusMalus == null || v.bonusMalus!.id != bonusMalusId) && !v.titolo.contains(bonusMalusId)).toList();
      _eventi[i] = ev.copyWith(votazioniAttive: vAggiornate);
    }
  }

  // --- ASSEGNA BONUS/MALUS AD UN PARTECIPANTE DA PARTE DELL'ORGANIZZATORE ---
  Future<void> assegnaBonusMalusAPartecipante({
    required String eventoId,
    required String bonusId,
    required String utenteDestinatario,
    required int punti,
    required String eventoTitolo,
    required String bonusTitolo,
  }) async {
    invalidateCache();
    final rawMittente = _currentUser?.nickname.isNotEmpty == true
        ? _currentUser!.nickname
        : (_currentUser?.nome ?? 'Organizzatore');
    final mittente = rawMittente.trim().toLowerCase() == 'claudio' ? 'Cloud' : rawMittente.trim();
    final cleanDest = utenteDestinatario.trim().toLowerCase();
    final ptStr = punti >= 0 ? '+$punti' : '$punti';
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final logText = '🏆 Ricevuto ${punti >= 0 ? "Bonus" : "Malus"} "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo" ($timeStr)';

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/bonusmalus/assegna'),
          headers: defaultHeaders,
          body: jsonEncode({
            'eventoId': eventoId,
            'bonusId': bonusId,
            'utenteDestinatario': utenteDestinatario,
            'punti': punti,
            'eventoTitolo': eventoTitolo,
            'bonusTitolo': bonusTitolo,
            'mittente': mittente,
          }),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          // Aggiorna la memoria locale in-memory
          for (int i = 0; i < _bonusMalusList.length; i++) {
            if (_bonusMalusList[i].id == bonusId || _bonusMalusList[i].titolo.toLowerCase() == bonusTitolo.toLowerCase()) {
              final List<String> list = List.from(_bonusMalusList[i].assegnatoA);
              final isMulti = _bonusMalusList[i].riassegnabileMoltepliciVolte;
              if (isMulti || !list.any((u) => u.trim().toLowerCase() == cleanDest)) {
                list.add(utenteDestinatario);
              }
              _bonusMalusList[i] = _bonusMalusList[i].copyWith(assegnatoA: list);
            }
          }

          final bool isBonus = punti >= 0;
          final String notificaTipo = isBonus ? 'assegnazione_bonus' : 'assegnazione_malus';
          final String notificaTitolo = isBonus ? '🏆 Bonus Assegnato!' : '💀 Malus Assegnato!';

          // 1. Notifica push mirata con SUONO DEDICATO al destinatario che riceve il bonus o malus
          try {
            await PushNotificationService.instance.inviaPushAUtenti(
              [utenteDestinatario],
              titolo: notificaTitolo,
              messaggio: 'Hai ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
              data: {
                'tipo': notificaTipo,
                'eventoId': eventoId,
              },
            ).timeout(const Duration(seconds: 4), onTimeout: () {});
          } catch (_) {}

          // 2. Notifica push broadcast a TUTTI gli altri partecipanti dell\'evento
          final List<String> destList = [];
          if (res.body.isNotEmpty && !res.body.contains('<html>')) {
            try {
              final resData = jsonDecode(res.body) as Map<String, dynamic>;
              final rawDests = resData['destinatari'] as List<dynamic>? ?? [];
              for (var d in rawDests) {
                final s = d.toString().trim();
                if (s.isNotEmpty && !destList.any((x) => x.toLowerCase() == s.toLowerCase())) {
                  destList.add(s);
                }
              }
            } catch (_) {}
          }
          int evMatchIdx = _eventi.indexWhere((e) => e.id.toLowerCase() == eventoId.toLowerCase());
          if (evMatchIdx == -1 && eventoTitolo.isNotEmpty) {
            evMatchIdx = _eventi.indexWhere((e) => e.titolo.toLowerCase() == eventoTitolo.toLowerCase());
          }
          if (evMatchIdx != -1) {
            final evMatch = _eventi[evMatchIdx];
            final creatore = evMatch.propostoDa.trim();
            if (creatore.isNotEmpty) {
              final r = resolveNickname(creatore);
              if (!destList.any((d) => d.toLowerCase() == r.toLowerCase())) destList.add(r);
            }
            for (var item in [...evMatch.partecipanti, ...evMatch.invitati]) {
              final s = item.trim();
              if (s.isNotEmpty) {
                final r = resolveNickname(s);
                if (!destList.any((d) => d.toLowerCase() == r.toLowerCase())) {
                  destList.add(r);
                }
              }
            }
          }
          final cleanDestUser = resolveNickname(utenteDestinatario);
          final altriPartecipanti = destList.where((d) => !isSamePerson(d, cleanDestUser)).toList();
          if (altriPartecipanti.isNotEmpty) {
            try {
              await PushNotificationService.instance.inviaPushAUtenti(
                altriPartecipanti,
                titolo: notificaTitolo,
                messaggio: '$cleanDestUser ha ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
                data: {
                  'tipo': notificaTipo,
                  'eventoId': eventoId,
                },
              ).timeout(const Duration(seconds: 4), onTimeout: () {});
            } catch (_) {}
          }

          return;
        } else if (res.statusCode == 400) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          throw Exception(data['error']?.toString() ?? 'Impossibile assegnare il punteggio.');
        }
      } catch (e) {
        if (e is Exception && (e.toString().contains('disponibile solo') || e.toString().contains('è concluso') || e.toString().contains('Impossibile assegnare'))) {
          rethrow;
        }
      }
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    // 0. Controllo di sicurezza: l'assegnazione è permessa ESCLUSIVAMENTE quando l'evento è in corso
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? evObjId;
        try { evObjId = ObjectId.fromHexString(eventoId); } catch (_) {}
        final evSelector = evObjId != null ? where.id(evObjId) : where.eq('_id', eventoId);
        final evDoc = await db.collection('Evento').findOne(evSelector);
        if (evDoc != null) {
          final stato = (evDoc['stato'] ?? 'in_programma').toString().toLowerCase();
          final dataStr = evDoc['data']?.toString() ?? '';
          final dataFineStr = evDoc['dataFine']?.toString() ?? '';
          final dtStart = DateTime.tryParse(dataStr);
          final dtEnd = DateTime.tryParse(dataFineStr);
          final checkNow = DateTime.now();
          final bool isConcluso = stato == 'concluso' || (dtEnd != null && checkNow.isAfter(dtEnd));
          final bool isInCorso = !isConcluso && (stato == 'in_corso' || (dtStart != null && checkNow.isAfter(dtStart) && (dtEnd == null || checkNow.isBefore(dtEnd))));
          if (!isInCorso) {
            throw Exception(isConcluso
                ? 'Questo evento è concluso: le assegnazioni dei punti sono chiuse!'
                : 'L\'assegnazione dei punti è disponibile solo quando l\'evento è in corso!');
          }
        }
      }
    } catch (e) {
      if (e is Exception && (e.toString().contains('disponibile solo') || e.toString().contains('è concluso'))) {
        rethrow;
      }
    }

    // 1. Aggiorna la memoria in-memory del BonusMalus inserendo utenteDestinatario in assegnatoA
    for (int i = 0; i < _bonusMalusList.length; i++) {
      if (_bonusMalusList[i].id == bonusId || _bonusMalusList[i].titolo.toLowerCase() == bonusTitolo.toLowerCase()) {
        final List<String> list = List.from(_bonusMalusList[i].assegnatoA);
        final isMulti = _bonusMalusList[i].riassegnabileMoltepliciVolte;
        if (isMulti || !list.any((u) => u.trim().toLowerCase() == cleanDest)) {
          list.add(utenteDestinatario);
        }
        _bonusMalusList[i] = _bonusMalusList[i].copyWith(assegnatoA: list);
      }
    }

    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        // 2. Aggiorna il documento BonusMalus nel DB inserendo utenteDestinatario in assegnatoA
        ObjectId? bmObjId;
        try { bmObjId = ObjectId.fromHexString(bonusId); } catch (_) {}
        final bmSelector = bmObjId != null ? where.id(bmObjId) : where.eq('_id', bonusId);
        var bmDoc = await db.collection('BonusMalus').findOne(bmSelector);
        if (bmDoc == null) {
          bmDoc = await db.collection('BonusMalus').findOne(where.eq('nome', bonusTitolo));
        }
        if (bmDoc == null) {
          bmDoc = await db.collection('BonusMalus').findOne(where.eq('titolo', bonusTitolo));
        }
        if (bmDoc != null) {
          final List<dynamic> assList = List.from(bmDoc['assegnatoA'] ?? []);
          final bool isMulti = bmDoc['riassegnabileMoltepliciVolte'] == true;
          if (isMulti || !assList.any((u) => u.toString().trim().toLowerCase() == cleanDest)) {
            assList.add(utenteDestinatario);
          }
          await db.collection('BonusMalus').update(
            where.id(bmDoc['_id'] as ObjectId),
            modify.set('assegnatoA', assList),
          );
        }

        // 3. Aggiorna i punti e lo storico dell'utente destinatario nel DB
        final uDocs = await db.collection('Utenti').find().toList();
        for (var uDoc in uDocs) {
          if (matchesUserDoc(uDoc, cleanDest)) {
            final oldPunti = (uDoc['puntiTotali'] ?? 0) as int;
            final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
            final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
            final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);

            // Formula punti * 10 XP con tetto massimo di sicurezza a 100 punti (+1000 XP max)
            final safePt = punti.clamp(-100, 100);
            final deltaXp = safePt > 0 ? (safePt * 10) : 0;
            final prog = XpProgression.aggiungiXp(
              livelloAttuale: curLiv,
              xpLivelloAttuale: curXp,
              deltaXp: deltaXp,
              xpTotaliAttuali: curTot,
            );

            final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
            final formattedLog = formattaVoceStorico(logText);
            oldStorico.insert(0, formattedLog);

            ObjectId? uObjId;
            try {
              uObjId = uDoc['_id'] is ObjectId ? uDoc['_id'] as ObjectId : ObjectId.fromHexString(uDoc['_id'].toString());
            } catch (_) {}
            final uSelector = uObjId != null ? where.id(uObjId) : where.eq('_id', uDoc['_id']);

            await db.collection('Utenti').update(
              uSelector,
              modify
                  .set('puntiTotali', oldPunti + punti)
                  .set('xp', prog.xp)
                  .set('livello', prog.livello)
                  .set('xpProssimoLivello', prog.xpProssimoLivello)
                  .set('xpTotali', prog.xpTotali)
                  .set('storicoVoti', oldStorico),
            );

            if (_currentUser != null && matchesUserDoc(uDoc, _currentUser!.nickname)) {
              _currentUser = _currentUser!.copyWith(
                puntiTotali: oldPunti + punti,
                xp: prog.xp,
                livello: prog.livello,
                xpProssimoLivello: prog.xpProssimoLivello,
                xpTotali: prog.xpTotali,
                storicoVoti: oldStorico.map((e) => e.toString()).toList(),
              );
              await _saveSession(_currentUser!);
            }
          }
        }

        // 4. Invia notifica BROADCAST a TUTTI i partecipanti dell'evento (con ID e Timestamp univoco, MATCH ESATTO PER ID)
        final evDocs = await db.collection('Evento').find().toList();
        final cleanEvId = eventoId.trim().toLowerCase();
        final cleanEvHex = cleanEvId.replaceAll(RegExp(r'[^a-f0-9]'), '');
        Map<String, dynamic> evMatch = evDocs.firstWhere(
          (e) {
            final hex = e['_id'] is ObjectId ? (e['_id'] as ObjectId).toHexString().toLowerCase() : '';
            final str = (e['_id']?.toString() ?? e['id']?.toString() ?? '').toLowerCase();
            final cleanStr = str.replaceAll(RegExp(r'[^a-f0-9]'), '');
            return (hex.isNotEmpty && hex == cleanEvId) ||
                   (cleanStr.isNotEmpty && cleanStr == cleanEvHex) ||
                   str == cleanEvId;
          },
          orElse: () => <String, dynamic>{},
        );
        if (evMatch.isEmpty && eventoTitolo.isNotEmpty) {
          evMatch = evDocs.firstWhere(
            (e) => ((e['nome'] ?? e['titolo'] ?? '').toString().toLowerCase() == eventoTitolo.toLowerCase()),
            orElse: () => <String, dynamic>{},
          );
        }

        final List<String> destList = [];
        if (evMatch.isNotEmpty) {
          final creatore = (evMatch['propostoDa'] ?? evMatch['creatore'] ?? '').toString().trim();
          if (creatore.isNotEmpty) {
            final r = resolveNickname(creatore);
            if (!destList.any((d) => d.toLowerCase() == r.toLowerCase())) destList.add(r);
          }
          final List<dynamic> pList = List.from(evMatch['partecipanti'] ?? []);
          final List<dynamic> iList = List.from(evMatch['invitati'] ?? []);
          for (var item in [...pList, ...iList]) {
            final s = item.toString().trim();
            if (s.isNotEmpty) {
              final r = resolveNickname(s);
              if (!destList.any((d) => d.toLowerCase() == r.toLowerCase())) {
                destList.add(r);
              }
            }
          }
        }
        final cleanDestUser = resolveNickname(utenteDestinatario);
        if (destList.isEmpty) {
          destList.add(cleanDestUser);
        }

        final bool isBonus = punti >= 0;
        final String notificaTipo = isBonus ? 'assegnazione_bonus' : 'assegnazione_malus';
        final String notificaTitolo = isBonus ? '🏆 Bonus Assegnato!' : '💀 Malus Assegnato!';

        final int ts = now.millisecondsSinceEpoch;
        for (var d in destList) {
          await db.collection('Notifiche').insertOne({
            'notificaId': 'bm_ass_${ts}_${d.toLowerCase()}',
            'mittente': mittente,
            'destinatario': d,
            'titolo': notificaTitolo,
            'messaggio': '$cleanDestUser ha ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
            'eventoId': cleanEvId,
            'tipo': notificaTipo,
            'stato': 'consegnato',
            'letto': false,
            'votoEspresso': 'pro',
            'data': now.toIso8601String(),
          });
        }

        // 1. Invia notifica push mirata con SUONO DEDICATO al destinatario che riceve il bonus o malus
        try {
          await PushNotificationService.instance.inviaPushAUtenti(
            [cleanDestUser],
            titolo: notificaTitolo,
            messaggio: 'Hai ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
            data: {
              'tipo': notificaTipo,
              'eventoId': cleanEvId,
            },
          ).timeout(const Duration(seconds: 4), onTimeout: () {});
        } catch (_) {}

        // 2. Invia notifica broadcast a TUTTI gli altri partecipanti dell'evento (incluso chi ha assegnato)
        final altriPartecipanti = destList.where((d) => !isSamePerson(d, cleanDestUser)).toList();
        if (altriPartecipanti.isNotEmpty) {
          try {
            await PushNotificationService.instance.inviaPushAUtenti(
              altriPartecipanti,
              titolo: isBonus ? '🏆 Bonus Assegnato!' : '💀 Malus Assegnato!',
              messaggio: '$cleanDestUser ha ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
              data: {
                'tipo': notificaTipo,
                'eventoId': cleanEvId,
              },
            ).timeout(const Duration(seconds: 4), onTimeout: () {});
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> segnaNotificheComeLette(String nickname) async {
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        final cleanNick = nickname.trim().toLowerCase();
        final docs = await db.collection('Notifiche').find().toList();
        for (var d in docs) {
          final dest = (d['destinatario'] ?? '').toString().trim().toLowerCase();
          if (dest == cleanNick || cleanNick.isEmpty) {
            await db.collection('Notifiche').update(
              where.id(d['_id'] as ObjectId),
              modify.set('letto', true),
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> segnaSingolaNotificaComeLetta(String notificaId) async {
    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/notifiche/segna-letta'),
          headers: defaultHeaders,
          body: jsonEncode({'notificaId': notificaId}),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          return;
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        ObjectId? objId;
        try {
          objId = ObjectId.fromHexString(notificaId);
        } catch (_) {}
        final selector = objId != null ? where.id(objId) : where.eq('notificaId', notificaId);
        await db.collection('Notifiche').update(
          selector,
          modify.set('letto', true),
        );
      }
    } catch (_) {}
  }

  Future<void> eliminaNotifica(String notificaId) async {
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
        final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);
        await db.collection('Notifiche').remove(selector);
      }
    } catch (_) {}
  }

  Future<void> eliminaNotificheMultiple(List<String> notificaIds) async {
    if (notificaIds.isEmpty) return;
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        for (var id in notificaIds) {
          ObjectId? objId;
          try {
            objId = ObjectId.fromHexString(id);
          } catch (_) {}
          final selector = objId != null
              ? where.id(objId)
              : where.eq('notificaId', id).or(where.eq('_id', id));
          await db.collection('Notifiche').remove(selector);
        }
      }
    } catch (_) {}
  }

  Future<void> eliminaTutteNotifiche({required String destinatario, bool soloLette = false}) async {
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        final cleanNick = destinatario.trim().toLowerCase();
        final docs = await db.collection('Notifiche').find().toList();
        for (var d in docs) {
          final dest = (d['destinatario'] ?? '').toString().trim().toLowerCase();
          final bool isLetto = d['letto'] == true;
          if (dest == cleanNick || cleanNick.isEmpty) {
            if (!soloLette || isLetto) {
              if (d['_id'] is ObjectId) {
                await db.collection('Notifiche').remove(where.id(d['_id'] as ObjectId));
              } else {
                await db.collection('Notifiche').remove(where.eq('_id', d['_id']));
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<List<BonusMalus>> getBonusMalusList() async {
    await getVotazioni();
    return List.unmodifiable(_bonusMalusList);
  }

  Future<List<Votazione>> getVotazioni() async {
    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final resBm = await http.get(
          Uri.parse('$url/bonusmalus'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 8));

        final resVot = await http.get(
          Uri.parse('$url/votazioni'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 8));

        if (resBm.statusCode == 200 && resVot.statusCode == 200 &&
            !resBm.body.contains('<html>') && !resVot.body.contains('<html>')) {
          final List<dynamic> bmListJson = jsonDecode(resBm.body);
          final List<dynamic> votListJson = jsonDecode(resVot.body);

          _bonusMalusList.clear();
          for (var item in bmListJson) {
            _bonusMalusList.add(BonusMalus.fromJson(Map<String, dynamic>.from(item as Map)));
          }

          final List<Votazione> list = [];
          for (var item in votListJson) {
            list.add(Votazione.fromJson(Map<String, dynamic>.from(item as Map)));
          }

          _votazioniList.clear();
          _votazioniList.addAll(list);
          return List.unmodifiable(_votazioniList);
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: fallback silenzioso su MongoDB Atlas
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        final bmDocs = await db.collection('BonusMalus').find().toList().timeout(const Duration(seconds: 6));
        final votiDocs = await db.collection('Votazioni').find().toList().timeout(const Duration(seconds: 6));

        final List<Votazione> list = [];
        _bonusMalusList.clear();

        for (var bm in bmDocs) {
          final bmId = bm['_id']?.toHexString() ?? bm['_id']?.toString() ?? '';
          final evId = bm['eventoId']?.toString() ?? '';
          final nomeBM = bm['nome']?.toString() ?? 'Bonus';
          final descBM = bm['descrizione']?.toString() ?? '';
          final puntiBM = (bm['punti'] as num?)?.toInt() ?? 0;
          final tipoBM = bm['tipo']?.toString() ?? (puntiBM >= 0 ? 'bonus' : 'malus');
          final propDa = (bm['propostoDa'] ?? '').toString().trim();
          String effectivePropDa = propDa;
          if (effectivePropDa.isEmpty && descBM.toLowerCase().contains('proposto da ')) {
            final idx = descBM.toLowerCase().indexOf('proposto da ');
            effectivePropDa = descBM.substring(idx + 'proposto da '.length).split(RegExp(r'[:\(\n,]'))[0].trim();
          }
          if (effectivePropDa.isEmpty) {
            for (var vDoc in votiDocs) {
              final vId = (vDoc['votazioneId'] ?? vDoc['bonusId'] ?? '').toString().trim().toLowerCase();
              final bTit = (vDoc['bonusTitolo'] ?? '').toString().trim().toLowerCase();
              final val = (vDoc['voto']?.toString() ?? '').toLowerCase();
              final isMatch = (vId == bmId.toLowerCase()) ||
                              (bTit.isNotEmpty && bTit == nomeBM.toLowerCase()) ||
                              (vId.isNotEmpty && vId == nomeBM.toLowerCase());
              if (isMatch && (val == 'pro' || val == 'accetta' || val == 'favorevole')) {
                final u = (vDoc['utente'] ?? '').toString().trim();
                if (u.isNotEmpty) {
                  effectivePropDa = u;
                  break;
                }
              }
            }
          }

          effectivePropDa = resolveNickname(effectivePropDa);

          final List<String> assList = (bm['assegnatoA'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];

          // Conversione sicura in oggetto BonusMalus
          final Map<String, String> votiUtenti = {
            if (effectivePropDa.isNotEmpty) effectivePropDa: 'pro',
            if (effectivePropDa.isNotEmpty) effectivePropDa.toLowerCase(): 'pro',
          };

          for (var vDoc in votiDocs) {
            final vId = (vDoc['votazioneId'] ?? vDoc['bonusId'] ?? '').toString().trim().toLowerCase();
            final bTit = (vDoc['bonusTitolo'] ?? '').toString().trim().toLowerCase();
            final rawU = (vDoc['utente'] ?? '').toString().trim();
            final val = (vDoc['voto']?.toString() ?? '').toLowerCase();

            final isMatch = (vId == bmId.toLowerCase()) ||
                            (bTit.isNotEmpty && bTit == nomeBM.toLowerCase()) ||
                            (vId.isNotEmpty && vId == nomeBM.toLowerCase());

            if (isMatch && rawU.isNotEmpty) {
              final voteStr = (val == 'pro' || val == 'accetta' || val == 'favorevole') ? 'pro' : 'contro';
              final u = resolveNickname(rawU);
              votiUtenti[u] = voteStr;
              votiUtenti[u.toLowerCase()] = voteStr;
            }
          }

          final evMatch = _eventi.firstWhere(
            (e) => e.id.trim().toLowerCase() == evId.trim().toLowerCase() ||
                e.titolo.trim().toLowerCase() == evId.trim().toLowerCase(),
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

          int effectiveParticipants = evMatch.partecipanti.length;
          if (effectiveParticipants < 2) {
            final evInList = _eventi.firstWhere(
              (e) => e.partecipanti.length >= 2 &&
                  (e.id == evId || e.titolo.toLowerCase() == evId.toLowerCase()),
              orElse: () => evMatch,
            );
            effectiveParticipants = evInList.partecipanti.length;
          }
          final numPartecipanti = effectiveParticipants >= 2 ? effectiveParticipants : 3;
          final int quorumCalcolato = (numPartecipanti / 2).floor() + 1;

          final Set<String> countedUsers = {};
          int fav = 0;
          int cont = 0;
          votiUtenti.forEach((user, vote) {
            String normUser = resolveNickname(user).trim().toLowerCase();
            if (!countedUsers.contains(normUser)) {
              countedUsers.add(normUser);
              if (vote == 'pro') fav++;
              if (vote == 'contro') cont++;
            }
          });

          final bool isPropostaUtente = effectivePropDa.isNotEmpty;
          final bool giaApprovatoDaDb = !isPropostaUtente && (bm['approvato'] == true ||
              bm['stato'] == 'approvato' ||
              bm['stato'] == 'confermato');
          final bool giaRespintoDaDb = !isPropostaUtente && (bm['approvato'] == false && bm['stato'] == 'respinto');

          final totalVotiEspressi = fav + cont;
          bool isApprovato = giaApprovatoDaDb || (fav >= quorumCalcolato);
          bool isRespinto = (!giaApprovatoDaDb && (giaRespintoDaDb || (cont >= quorumCalcolato)));

          bool paritaDecisaDaOrganizzatore = false;
          final rawNomeOrg = evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa;
          final nomeOrganizzatore = resolveNickname(rawNomeOrg);

          // Parità: si attiva ESCLUSIVAMENTE se TUTTI i partecipanti hanno votato,
          // il numero di partecipanti è pari, e nessuno ha raggiunto il quorum perché fav == cont.
          if (!isApprovato && !isRespinto && (numPartecipanti % 2 == 0) && (totalVotiEspressi >= numPartecipanti) && (fav == cont)) {
            final creatoreVoteKey = votiUtenti.keys.firstWhere(
              (k) => isSamePerson(k, nomeOrganizzatore),
              orElse: () => '',
            );
            if (creatoreVoteKey.isNotEmpty) {
              final creatoreVote = votiUtenti[creatoreVoteKey];
              if (creatoreVote == 'pro') {
                isApprovato = true;
                paritaDecisaDaOrganizzatore = true;
              } else if (creatoreVote == 'contro') {
                isRespinto = true;
                paritaDecisaDaOrganizzatore = true;
              }
            }
          }

          final statoVot = isApprovato ? 'approvato' : (isRespinto ? 'respinto' : 'in_corso');
          final bool riassegnabile = bm['riassegnabileMoltepliciVolte'] == true;
          final rawCat = bm['categoria']?.toString().trim();
          final catBM = (rawCat != null && rawCat.isNotEmpty) ? rawCat : (tipoBM == 'bonus' ? 'Bonus' : 'Malus');

          final bmObj = BonusMalus(
            id: bmId,
            eventoId: evId,
            titolo: nomeBM,
            descrizione: descBM,
            punti: puntiBM,
            categoria: catBM,
            propostoDa: effectivePropDa.isNotEmpty ? effectivePropDa : propDa,
            approvato: isApprovato,
            stato: statoVot,
            assegnatoA: assList,
            riassegnabileMoltepliciVolte: riassegnabile,
          );

          if (isApprovato) {
            final bool isVarSanzione = catBM == 'VAR' || nomeBM.contains('Falsa Testimonianza');
            if (isVarSanzione) {
              final existingIdx = _bonusMalusList.indexWhere((b) =>
                  (b.categoria == 'VAR' || b.titolo.contains('Falsa Testimonianza')) &&
                  (b.eventoId.trim().toLowerCase() == evId.trim().toLowerCase() ||
                   (evMatch.titolo.isNotEmpty && b.eventoId.trim().toLowerCase() == evMatch.titolo.trim().toLowerCase())));
              if (existingIdx != -1) {
                final mergedAss = List<String>.from(_bonusMalusList[existingIdx].assegnatoA)..addAll(assList);
                _bonusMalusList[existingIdx] = _bonusMalusList[existingIdx].copyWith(
                  assegnatoA: mergedAss,
                  riassegnabileMoltepliciVolte: true,
                );
              } else {
                _bonusMalusList.add(bmObj);
              }
            } else {
              _bonusMalusList.add(bmObj);
            }
          }

          final votazione = Votazione(
            id: bmId,
            titolo: nomeBM,
            descrizione: descBM.isNotEmpty ? descBM : '$nomeBM (${puntiBM >= 0 ? "+$puntiBM" : puntiBM} PT) - Proposto da ${effectivePropDa.isNotEmpty ? effectivePropDa : propDa}',
            bonusMalus: bmObj,
            votiFavorevoli: fav,
            votiContrari: cont,
            quorum: quorumCalcolato,
            stato: statoVot,
            scadenza: DateTime.now().add(const Duration(days: 7)),
            votiUtenti: votiUtenti,
            paritaDecisaDaOrganizzatore: paritaDecisaDaOrganizzatore,
            nomeOrganizzatore: nomeOrganizzatore,
          );

          list.add(votazione);
        }

        _votazioniList.clear();
        _votazioniList.addAll(list);

        return list;
      }
    } catch (_) {
      markMongoDbDisconnected();
    }

    return List.unmodifiable(_votazioniList);
  }

  Future<Votazione> vota(String idOrEventoId, bool aFavore) async {
    final rawUserNick = (_currentUser?.nickname.isNotEmpty == true
        ? _currentUser!.nickname
        : (_currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud')).trim();
    final userNick = resolveNickname(rawUserNick);

    int index = _votazioniList.indexWhere((v) =>
        v.id == idOrEventoId ||
        v.bonusMalus?.id == idOrEventoId ||
        (v.bonusMalus != null && v.bonusMalus!.titolo.toLowerCase() == idOrEventoId.toLowerCase()) ||
        v.titolo.toLowerCase().contains(idOrEventoId.toLowerCase()));

    Votazione v;
    if (index != -1) {
      v = _votazioniList[index];
    } else {
      v = Votazione(
        id: idOrEventoId,
        titolo: 'Proposta Bonus/Malus',
        descrizione: 'Votazione da Notifica',
        votiFavorevoli: 1,
        votiContrari: 0,
        quorum: 2,
        stato: 'attiva',
        scadenza: DateTime.now().add(const Duration(days: 7)),
        votiUtenti: {'Ugnom': 'pro'},
      );
      _votazioniList.add(v);
      index = _votazioniList.length - 1;
    }

    final giaVotato = v.votiUtenti.keys.any((k) => isSamePerson(k, userNick));
    final nuoviVotiUtenti = Map<String, String>.from(v.votiUtenti);
    nuoviVotiUtenti[userNick] = aFavore ? 'pro' : 'contro';
    nuoviVotiUtenti[userNick.toLowerCase()] = aFavore ? 'pro' : 'contro';

    final Set<String> countedUsers = {};
    int fav = 0;
    int cont = 0;
    nuoviVotiUtenti.forEach((key, vote) {
      String normUser = resolveNickname(key).trim().toLowerCase();
      if (!countedUsers.contains(normUser)) {
        countedUsers.add(normUser);
        if (vote == 'pro') fav++;
        if (vote == 'contro') cont++;
      }
    });

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

    int effectiveParticipants = evMatch.partecipanti.length;
    if (effectiveParticipants < 2) {
      final evInList = _eventi.firstWhere(
        (e) => e.partecipanti.length >= 2 &&
            (e.id == evId || e.titolo.toLowerCase() == evId.toLowerCase()),
        orElse: () => evMatch,
      );
      effectiveParticipants = evInList.partecipanti.length;
    }
    final numPartecipanti = effectiveParticipants >= 2 ? effectiveParticipants : 3;
    final int quorumCalcolato = (numPartecipanti / 2).floor() + 1;
    final int totalVotiEspressi = fav + cont;

    bool isApprovato = (fav >= quorumCalcolato);
    bool isRespinto = (cont >= quorumCalcolato);
    bool paritaDecisaDaOrganizzatore = false;
    final rawNomeOrg = evMatch.creatore.isNotEmpty
        ? evMatch.creatore
        : (evMatch.propostoDa.isNotEmpty ? evMatch.propostoDa : (v.nomeOrganizzatore ?? ''));
    final nomeOrganizzatore = resolveNickname(rawNomeOrg);

    // Tie-breaker: si attiva SOLO SE tutti i partecipanti hanno votato,
    // il numero di partecipanti è pari, e nessuno ha raggiunto il quorum perché fav == cont.
    if (!isApprovato && !isRespinto && (numPartecipanti % 2 == 0) && (totalVotiEspressi >= numPartecipanti) && (fav == cont)) {
      final creatoreVoteKey = nuoviVotiUtenti.keys.firstWhere(
        (k) => isSamePerson(k, nomeOrganizzatore),
        orElse: () => '',
      );
      if (creatoreVoteKey.isNotEmpty) {
        final creatoreVote = nuoviVotiUtenti[creatoreVoteKey];
        if (creatoreVote == 'pro') {
          isApprovato = true;
          paritaDecisaDaOrganizzatore = true;
        } else if (creatoreVote == 'contro') {
          isRespinto = true;
          paritaDecisaDaOrganizzatore = true;
        }
      }
    }

    String nuovoStato = isApprovato ? 'approvato' : (isRespinto ? 'respinto' : 'in_corso');

    final votazioneAggiornata = v.copyWith(
      votiFavorevoli: fav,
      votiContrari: cont,
      quorum: quorumCalcolato,
      stato: nuovoStato,
      votiUtenti: nuoviVotiUtenti,
      paritaDecisaDaOrganizzatore: paritaDecisaDaOrganizzatore,
      nomeOrganizzatore: nomeOrganizzatore,
    );

    _votazioniList[index] = votazioneAggiornata;

    // Scrittura DIRETTA del voto su MongoDB Atlas E aggiornamento sincronizzato Notifiche
    try {
      Db? db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) {
        markMongoDbDisconnected();
        db = await _getSafeMongoDb();
      }
      if (db != null && db.isConnected) {
        final targetBmId = v.bonusMalus?.id ?? v.id;
        final targetBmTitle = v.bonusMalus?.titolo ?? v.titolo;
        final targetEvId = (v.bonusMalus?.eventoId != null && v.bonusMalus!.eventoId.isNotEmpty)
            ? v.bonusMalus!.eventoId
            : idOrEventoId;

        await db.collection('Votazioni').insertOne({
          'votazioneId': targetBmId,
          'bonusId': targetBmId,
          'eventoId': targetEvId,
          'bonusTitolo': targetBmTitle,
          'utente': userNick,
          'voto': aFavore ? 'pro' : 'contro',
          'stato': nuovoStato,
          'data': DateTime.now().toIso8601String(),
        });

        // Sincronizza lo stato anche sul centro notifiche dell'utente
        final notDocs = await db.collection('Notifiche').find().toList();
        for (var notDoc in notDocs) {
          final dest = (notDoc['destinatario'] ?? '').toString().trim().toLowerCase();
          final bId = (notDoc['bonusId'] ?? '').toString().trim().toLowerCase();
          final notId = notDoc['_id']?.toHexString() ?? notDoc['_id']?.toString() ?? '';
          final bool isBonusMatch = (bId.isNotEmpty && (bId == targetBmId.toLowerCase() || bId == idOrEventoId.toLowerCase())) ||
              (targetBmTitle.isNotEmpty && notDoc['bonusTitolo']?.toString().trim().toLowerCase() == targetBmTitle.toLowerCase());
          if (isSamePerson(dest, userNick) && (isBonusMatch || notId == idOrEventoId)) {
            await db.collection('Notifiche').update(
              where.id(notDoc['_id'] as ObjectId),
              modify.set('stato', aFavore ? 'accettato' : 'rifiutato').set('votoEspresso', aFavore ? 'pro' : 'contro').set('letto', true),
            );
          }
        }

        if (nuovoStato == 'approvato') {
          ObjectId? bmObjId;
          try { bmObjId = ObjectId.fromHexString(targetBmId); } catch (_) {}
          final bmSelector = bmObjId != null ? where.id(bmObjId) : where.eq('_id', targetBmId);
          var bmDoc = await db.collection('BonusMalus').findOne(bmSelector);
          if (bmDoc == null) {
            bmDoc = await db.collection('BonusMalus').findOne(where.eq('nome', targetBmTitle));
          }
          if (bmDoc != null) {
            await db.collection('BonusMalus').update(
              where.id(bmDoc['_id'] as ObjectId),
              modify.set('stato', 'approvato').set('approvato', true),
            );
          }

          // Invia notifica push broadcast per regola approvata
          final Set<String> allParticipants = {};
          final evMatchApprovaIdx = _eventi.indexWhere(
            (e) => e.id == targetEvId || e.titolo.toLowerCase() == targetEvId.toLowerCase(),
          );
          if (evMatchApprovaIdx != -1) {
            final evMatchApprova = _eventi[evMatchApprovaIdx];
            allParticipants.addAll(evMatchApprova.partecipanti);
            allParticipants.addAll(evMatchApprova.invitati);
          }
          if (allParticipants.isNotEmpty) {
            try {
              await PushNotificationService.instance.inviaPushAUtenti(
                allParticipants.toList(),
                titolo: '🎉 Nuova Regola Approvata: $targetBmTitle',
                messaggio: 'La regola "$targetBmTitle" ha raggiunto il quorum ed è ora attiva nel catalogo!',
                data: {
                  'tipo': 'bonus_approvato',
                  'eventoId': targetEvId,
                  'bonusId': targetBmId,
                },
              ).timeout(const Duration(seconds: 4), onTimeout: () {});
            } catch (_) {}
          }
        } else if (nuovoStato == 'respinto') {
          ObjectId? bmObjId;
          try { bmObjId = ObjectId.fromHexString(targetBmId); } catch (_) {}
          final bmSelector = bmObjId != null ? where.id(bmObjId) : where.eq('_id', targetBmId);
          var bmDoc = await db.collection('BonusMalus').findOne(bmSelector);
          if (bmDoc == null) {
            bmDoc = await db.collection('BonusMalus').findOne(where.eq('nome', targetBmTitle));
          }
          if (bmDoc != null) {
            await db.collection('BonusMalus').update(
              where.id(bmDoc['_id'] as ObjectId),
              modify.set('stato', 'respinto').set('approvato', false),
            );
          }
        }
      }
    } catch (_) {}

    invalidateCache();
    await getVotazioni();

    if (_currentUser != null && !giaVotato) {
      final prog = XpProgression.aggiungiXp(
        livelloAttuale: _currentUser!.livello,
        xpLivelloAttuale: _currentUser!.xp,
        deltaXp: 25,
        xpTotaliAttuali: _currentUser!.xpTotali,
      );
      final logVoce = formattaVoceStorico('Votato ${aFavore ? "FAVOREVOLE" : "CONTRARIO"} a "${v.titolo}" (+25 XP)');
      _currentUser = _currentUser!.copyWith(
        xp: prog.xp,
        livello: prog.livello,
        xpProssimoLivello: prog.xpProssimoLivello,
        xpTotali: prog.xpTotali,
        storicoVoti: [
          logVoce,
          ..._currentUser!.storicoVoti,
        ],
      );
      try {
        final db = await _getSafeMongoDb().timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (db != null && db.isConnected) {
          final uDocs = await db.collection('Utenti').find().toList().timeout(const Duration(seconds: 4));
          for (var uDoc in uDocs) {
            if (matchesUserDoc(uDoc, _currentUser!.nickname)) {
              final curStorico = List<dynamic>.from(uDoc['storicoVoti'] ?? []);
              curStorico.insert(0, logVoce);
              await db.collection('Utenti').update(
                where.id(uDoc['_id'] as ObjectId),
                modify
                  .set('xp', prog.xp)
                  .set('livello', prog.livello)
                  .set('xpProssimoLivello', prog.xpProssimoLivello)
                  .set('xpTotali', prog.xpTotali)
                  .set('storicoVoti', curStorico),
              ).timeout(const Duration(seconds: 4));
            }
          }
        }
      } catch (_) {}
    }

    final updatedFromList = _votazioniList.firstWhere(
      (item) =>
          item.id == v.id ||
          (v.bonusMalus != null && item.bonusMalus?.id == v.bonusMalus!.id) ||
          item.titolo.toLowerCase() == v.titolo.toLowerCase(),
      orElse: () => votazioneAggiornata,
    );

    return updatedFromList;
  }

  // --- ANNULLA ASSEGNAZIONE BONUS (ROLLBACK PER IL CREATORE DELL'EVENTO) ---
  Future<void> annullaAssegnazioneBonus({
    required String eventoId,
    required String bonusId,
    required String utenteDestinatario,
    required int punti,
  }) async {
    invalidateCache();
    final cleanDest = utenteDestinatario.trim().toLowerCase();

    // 0. Controllo di sicurezza: blocco assoluto di storno per bonus/malus o sanzioni originate dal VAR
    for (var bm in _bonusMalusList) {
      if (bm.id == bonusId || bm.titolo.toLowerCase() == bonusId.toLowerCase()) {
        final bool isVarCat = bm.categoria.toUpperCase() == 'VAR' ||
            bm.titolo.contains('VAR') ||
            bm.titolo.contains('Falsa Testimonianza');
        if (isVarCat) {
          throw Exception('Non è possibile stornare un bonus/malus o sanzione assegnata tramite sentenza VAR.');
        }
      }
    }

    // 1. In-memory update (rimuove SOLO la singola istanza in caso di assegnazioni multiple)
    for (int i = 0; i < _bonusMalusList.length; i++) {
      if (_bonusMalusList[i].id == bonusId || _bonusMalusList[i].titolo.toLowerCase() == bonusId.toLowerCase()) {
        final List<String> list = List.from(_bonusMalusList[i].assegnatoA);
        final idx = list.indexWhere((u) => u.trim().toLowerCase() == cleanDest);
        if (idx != -1) {
          list.removeAt(idx);
        }
        _bonusMalusList[i] = _bonusMalusList[i].copyWith(assegnatoA: list);
      }
    }

    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? bmObjId;
        try { bmObjId = ObjectId.fromHexString(bonusId); } catch (_) {}
        final bmSelector = bmObjId != null ? where.id(bmObjId) : where.eq('_id', bonusId);
        var bmDoc = await db.collection('BonusMalus').findOne(bmSelector);
        if (bmDoc != null) {
          final bmCat = (bmDoc['categoria'] ?? '').toString().toUpperCase();
          final bmTit = (bmDoc['titolo'] ?? bmDoc['nome'] ?? '').toString();
          if (bmCat == 'VAR' || bmTit.contains('VAR') || bmTit.contains('Falsa Testimonianza')) {
            throw Exception('Non è possibile stornare un bonus/malus o sanzione assegnata tramite sentenza VAR.');
          }
          final realBmId = bmDoc['_id']?.toHexString() ?? bmDoc['_id']?.toString() ?? bonusId;
          final approvedVar = await db.collection('RichiesteVar').findOne(
            where.eq('eventoId', eventoId)
                .and(where.eq('stato', 'approvata'))
                .and(where.eq('bonusMalusId', realBmId)),
          );
          if (approvedVar != null) {
            throw Exception('Non è possibile stornare un bonus/malus convalidato tramite VAR.');
          }

          final List<dynamic> assList = List.from(bmDoc['assegnatoA'] ?? []);
          final idx = assList.indexWhere((u) => u.toString().trim().toLowerCase() == cleanDest);
          if (idx != -1) {
            assList.removeAt(idx);
          }
          await db.collection('BonusMalus').update(
            where.id(bmDoc['_id'] as ObjectId),
            modify.set('assegnatoA', assList),
          );
        }

        // Storna i punti dall'utente
        final uDocs = await db.collection('Utenti').find().toList();
        for (var uDoc in uDocs) {
          if (matchesUserDoc(uDoc, cleanDest)) {
            final oldPunti = (uDoc['puntiTotali'] ?? 0) as int;
            final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
            final now = DateTime.now();
            final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
            final logVoce = formattaVoceStorico('⚠️ Annullata assegnazione bonus (-$punti PT) (ore $timeStr)');
            oldStorico.insert(0, logVoce);

            ObjectId? uObjId;
            try {
              uObjId = uDoc['_id'] is ObjectId ? uDoc['_id'] as ObjectId : ObjectId.fromHexString(uDoc['_id'].toString());
            } catch (_) {}
            final uSelector = uObjId != null ? where.id(uObjId) : where.eq('_id', uDoc['_id']);

            final newPunti = (oldPunti - punti).clamp(0, 999999);

            // Nota di Game Design: L'XP guadagnato dal giocatore è esperienza permanente e non viene de-livellato
            await db.collection('Utenti').update(
              uSelector,
              modify
                  .set('puntiTotali', newPunti)
                  .set('storicoVoti', oldStorico),
            );

            if (_currentUser != null && matchesUserDoc(uDoc, _currentUser!.nickname)) {
              _currentUser = _currentUser!.copyWith(
                puntiTotali: newPunti,
                storicoVoti: oldStorico.map((e) => e.toString()).toList(),
              );
              await _saveSession(_currentUser!);
            }
          }
        }
      }
    } catch (_) {}
  }

  // --- SISTEMA DI GESTIONE AMICIZIE ---

  Future<void> inviaRichiestaAmicizia(String codiceAmico) async {
    final cleanCode = codiceAmico.trim().toUpperCase();
    final curUser = _currentUser;
    if (curUser == null) throw Exception('Utente non autenticato');
    if (cleanCode == curUser.codiceAmico.toUpperCase()) {
      throw Exception('Non puoi inviare una richiesta di amicizia a te stesso!');
    }

    final db = await _getMongoDb();
    if (db != null && db.isConnected) {
      final docs = await db.collection('Utenti').find().toList();
      Utente? targetUser;
      for (var d in docs) {
        final u = Utente.fromJson(d);
        if (u.codiceAmico.toUpperCase() == cleanCode || u.nickname.toLowerCase() == cleanCode.toLowerCase()) {
          targetUser = u;
          break;
        }
      }

      if (targetUser == null) {
        throw Exception('Nessun utente trovato con il codice "$cleanCode"');
      }

      if (curUser.amici.any((a) => a.toLowerCase() == targetUser!.nickname.toLowerCase())) {
        throw Exception('Siete già amici!');
      }

      await db.collection('Notifiche').insertOne({
        'mittente': curUser.nickname,
        'destinatario': targetUser.nickname,
        'titolo': '👥 Nuova Richiesta di Amicizia',
        'messaggio': '${curUser.nickname} vuole aggiungerti agli amici!',
        'eventoId': '',
        'tipo': 'richiesta_amicizia',
        'stato': 'in_attesa',
        'codiceAmico': curUser.codiceAmico,
        'data': DateTime.now().toIso8601String(),
      });

      try {
        await PushNotificationService.instance.inviaPushAUtenti(
          [targetUser.nickname],
          titolo: '👥 Nuova Richiesta di Amicizia',
          messaggio: '${curUser.nickname} vuole aggiungerti agli amici!',
          data: {'tipo': 'amicizia'},
        ).timeout(const Duration(seconds: 4), onTimeout: () {});
      } catch (_) {}
    }
  }

  Future<void> rispondiRichiestaAmicizia(String notificaId, String mittente, bool accetta) async {
    final curUser = _currentUser;
    if (curUser == null) return;
    final db = await _getMongoDb();
    if (db != null && db.isConnected) {
      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);

      await db.collection('Notifiche').update(
        selector,
        modify.set('stato', accetta ? 'accettato' : 'rifiutato').set('letto', true),
      );

      if (accetta) {
        final docs = await db.collection('Utenti').find().toList();
        for (var d in docs) {
          final uNick = (d['nickname'] ?? d['username'] ?? '').toString().trim().toLowerCase();
          final uName = (d['nome'] ?? '').toString().trim().toLowerCase();
          final isCurUser = (uNick == curUser.nickname.toLowerCase() || uName == curUser.nickname.toLowerCase());
          final isMittente = (uNick == mittente.toLowerCase() || uName == mittente.toLowerCase());

          ObjectId? uObjId;
          try {
            uObjId = d['_id'] is ObjectId ? d['_id'] as ObjectId : ObjectId.fromHexString(d['_id'].toString());
          } catch (_) {}
          final uSelector = uObjId != null ? where.id(uObjId) : where.eq('_id', d['_id']);

          if (isCurUser) {
            final List<dynamic> amici = List.from(d['amici'] ?? []);
            if (!amici.any((a) => a.toString().toLowerCase() == mittente.toLowerCase())) {
              amici.add(mittente);
              await db.collection('Utenti').update(uSelector, modify.set('amici', amici));
            }
          }
          if (isMittente) {
            final List<dynamic> amici = List.from(d['amici'] ?? []);
            if (!amici.any((a) => a.toString().toLowerCase() == curUser.nickname.toLowerCase())) {
              amici.add(curUser.nickname);
              await db.collection('Utenti').update(uSelector, modify.set('amici', amici));
            }
          }
        }

        final updatedAmici = List<String>.from(curUser.amici);
        if (!updatedAmici.any((a) => a.toLowerCase() == mittente.toLowerCase())) {
          updatedAmici.add(mittente);
          _currentUser = _currentUser!.copyWith(amici: updatedAmici);
          await _saveSession(_currentUser!);
        }

        await db.collection('Notifiche').insertOne({
          'mittente': curUser.nickname,
          'destinatario': mittente,
          'titolo': '👥 Richiesta di Amicizia Accettata!',
          'messaggio': '${curUser.nickname} ha accettato la tua richiesta di amicizia! Ora siete amici.',
          'eventoId': '',
          'tipo': 'amicizia_accettata',
          'stato': 'consegnato',
          'data': DateTime.now().toIso8601String(),
        });

        try {
          await PushNotificationService.instance.inviaPushAUtenti(
            [mittente],
            titolo: '👥 Richiesta di Amicizia Accettata!',
            messaggio: '${curUser.nickname} ha accettato la tua richiesta di amicizia! Ora siete amici.',
            data: {'tipo': 'amicizia'},
          ).timeout(const Duration(seconds: 4), onTimeout: () {});
        } catch (_) {}
      }
    }
  }

  // Restituisce ESCLUSIVAMENTE gli utenti presenti nella lista amici di _currentUser per l'invito agli eventi
  Future<List<Utente>> getGiocatoriInvitabili() async {
    final curUser = _currentUser;
    if (curUser == null) return [];
    final tutti = await getUtenti();
    final bloccatiLower = curUser.utentiBloccati.map((b) => resolveNickname(b).toLowerCase()).toSet();
    final amiciLower = curUser.amici
        .map((a) => resolveNickname(a).toLowerCase())
        .where((a) => !bloccatiLower.contains(a))
        .toSet();

    return tutti.where((u) {
      if (isSamePerson(u.nickname, curUser.nickname) || isSamePerson(u.nome, curUser.nome)) {
        return false;
      }
      final uNick = resolveNickname(u.nickname).toLowerCase();
      final uNome = resolveNickname(u.nome).toLowerCase();
      return amiciLower.contains(uNick) || amiciLower.contains(uNome);
    }).toList();
  }

  // ==========================================
  // BLOCCO & SBLOCCO UTENTI (Apple UGC 1.2)
  // ==========================================

  Future<bool> bloccaUtente(String targetNick) async {
    final curUser = _currentUser;
    if (curUser == null) return false;
    final curNick = curUser.nickname.isNotEmpty ? curUser.nickname : curUser.nome;
    final cleanTarget = targetNick.trim();

    // 1. Chiamata primaria su Backend REST Render Starter
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/utenti/blocca'),
          headers: defaultHeaders,
          body: jsonEncode({
            'utente': curNick,
            'target': cleanTarget,
          }),
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final currentBloccati = List<String>.from(curUser.utentiBloccati);
          if (!currentBloccati.any((b) => b.toLowerCase() == cleanTarget.toLowerCase())) {
            currentBloccati.add(cleanTarget);
          }
          final currentAmici = List<String>.from(curUser.amici);
          currentAmici.removeWhere((a) => a.toLowerCase() == cleanTarget.toLowerCase());
          _currentUser = curUser.copyWith(utentiBloccati: currentBloccati, amici: currentAmici);
          await _saveSession(_currentUser!);

          unawaited(PushNotificationService.instance.inviaPushAUtenti(
            [cleanTarget],
            titolo: '🚫 Sei stato bloccato',
            messaggio: '$curNick ti ha bloccato. Momentaneamente non siete più amici fino a quando $curNick non ti sbloccherà.',
            data: {'tipo': 'blocco_utente'},
          ));
          return true;
        }
      } catch (_) {}
    }

    // 2. Fallback trasparente su MongoDB Atlas
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final uDocs = await db.collection('Utenti').find().toList();
        final cleanCurUser = resolveNickname(curNick);
        final cleanTargetUser = resolveNickname(cleanTarget);

        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (isSamePerson(uNick, cleanCurUser)) {
            final uId = uDoc['_id'] as ObjectId;
            final currentBloccati = List<String>.from((uDoc['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
            if (!currentBloccati.any((b) => isSamePerson(b, cleanTargetUser))) {
              currentBloccati.add(cleanTargetUser);
            }
            final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
            currentAmici.removeWhere((a) => isSamePerson(a, cleanTargetUser));

            await db.collection('Utenti').update(
              where.id(uId),
              modify.set('utentiBloccati', currentBloccati).set('amici', currentAmici),
            );
            break;
          }
        }

        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (isSamePerson(uNick, cleanTargetUser)) {
            final uId = uDoc['_id'] as ObjectId;
            final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
            currentAmici.removeWhere((a) => isSamePerson(a, cleanCurUser));

            await db.collection('Utenti').update(
              where.id(uId),
              modify.set('amici', currentAmici),
            );
            break;
          }
        }

        try {
          final nots = await db.collection('Notifiche').find(where.eq('tipo', 'richiesta_amicizia')).toList();
          for (var n in nots) {
            final m = (n['mittente'] ?? '').toString().trim();
            final d = (n['destinatario'] ?? '').toString().trim();
            if ((isSamePerson(m, cleanCurUser) && isSamePerson(d, cleanTargetUser)) ||
                (isSamePerson(m, cleanTargetUser) && isSamePerson(d, cleanCurUser))) {
              await db.collection('Notifiche').remove(where.id(n['_id'] as ObjectId));
            }
          }
        } catch (_) {}

        await db.collection('Notifiche').insertOne({
          'tipo': 'blocco_utente',
          'titolo': '🚫 Sei stato bloccato',
          'messaggio': '$cleanCurUser ti ha bloccato. Momentaneamente non siete più amici fino a quando $cleanCurUser non ti sbloccherà.',
          'mittente': cleanCurUser,
          'destinatario': cleanTargetUser,
          'timestamp': DateTime.now().toIso8601String(),
          'letto': false,
        });

        final currentBloccati = List<String>.from(curUser.utentiBloccati);
        if (!currentBloccati.any((b) => b.toLowerCase() == cleanTarget.toLowerCase())) {
          currentBloccati.add(cleanTarget);
        }
        final currentAmici = List<String>.from(curUser.amici);
        currentAmici.removeWhere((a) => a.toLowerCase() == cleanTarget.toLowerCase());
        _currentUser = curUser.copyWith(utentiBloccati: currentBloccati, amici: currentAmici);
        await _saveSession(_currentUser!);

        unawaited(PushNotificationService.instance.inviaPushAUtenti(
          [cleanTarget],
          titolo: '🚫 Sei stato bloccato',
          messaggio: '$cleanCurUser ti ha bloccato. Momentaneamente non siete più amici fino a quando $cleanCurUser non ti sbloccherà.',
          data: {'tipo': 'blocco_utente'},
        ));
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<bool> sbloccaUtente(String targetNick) async {
    final curUser = _currentUser;
    if (curUser == null) return false;
    final curNick = curUser.nickname.isNotEmpty ? curUser.nickname : curUser.nome;
    final cleanTarget = targetNick.trim();

    // 1. Chiamata primaria su Backend REST Render Starter
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/utenti/sblocca'),
          headers: defaultHeaders,
          body: jsonEncode({
            'utente': curNick,
            'target': cleanTarget,
          }),
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final currentBloccati = List<String>.from(curUser.utentiBloccati);
          currentBloccati.removeWhere((b) => b.toLowerCase() == cleanTarget.toLowerCase());
          final currentAmici = List<String>.from(curUser.amici);
          if (!currentAmici.any((a) => a.toLowerCase() == cleanTarget.toLowerCase())) {
            currentAmici.add(cleanTarget);
          }
          _currentUser = curUser.copyWith(utentiBloccati: currentBloccati, amici: currentAmici);
          await _saveSession(_currentUser!);

          unawaited(PushNotificationService.instance.inviaPushAUtenti(
            [cleanTarget],
            titolo: '🤝 Sei stato sbloccato',
            messaggio: '$curNick ti ha sbloccato. Siete di nuovo amici!',
            data: {'tipo': 'sblocco_utente'},
          ));
          return true;
        }
      } catch (_) {}
    }

    // 2. Fallback trasparente su MongoDB Atlas
    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final uDocs = await db.collection('Utenti').find().toList();
        final cleanCurUser = resolveNickname(curNick);
        final cleanTargetUser = resolveNickname(cleanTarget);

        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (isSamePerson(uNick, cleanCurUser)) {
            final uId = uDoc['_id'] as ObjectId;
            final currentBloccati = List<String>.from((uDoc['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
            currentBloccati.removeWhere((b) => isSamePerson(b, cleanTargetUser));

            final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
            if (!currentAmici.any((a) => isSamePerson(a, cleanTargetUser))) {
              currentAmici.add(cleanTargetUser);
            }

            await db.collection('Utenti').update(
              where.id(uId),
              modify.set('utentiBloccati', currentBloccati).set('amici', currentAmici),
            );
            break;
          }
        }

        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (isSamePerson(uNick, cleanTargetUser)) {
            final uId = uDoc['_id'] as ObjectId;
            final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
            if (!currentAmici.any((a) => isSamePerson(a, cleanCurUser))) {
              currentAmici.add(cleanCurUser);
            }

            await db.collection('Utenti').update(
              where.id(uId),
              modify.set('amici', currentAmici),
            );
            break;
          }
        }

        await db.collection('Notifiche').insertOne({
          'tipo': 'sblocco_utente',
          'titolo': '🤝 Sei stato sbloccato',
          'messaggio': '$cleanCurUser ti ha sbloccato. Siete di nuovo amici!',
          'mittente': cleanCurUser,
          'destinatario': cleanTargetUser,
          'timestamp': DateTime.now().toIso8601String(),
          'letto': false,
        });

        final currentBloccati = List<String>.from(curUser.utentiBloccati);
        currentBloccati.removeWhere((b) => b.toLowerCase() == cleanTarget.toLowerCase());
        final currentAmici = List<String>.from(curUser.amici);
        if (!currentAmici.any((a) => a.toLowerCase() == cleanTarget.toLowerCase())) {
          currentAmici.add(cleanTarget);
        }
        _currentUser = curUser.copyWith(utentiBloccati: currentBloccati, amici: currentAmici);
        await _saveSession(_currentUser!);

        unawaited(PushNotificationService.instance.inviaPushAUtenti(
          [cleanTarget],
          titolo: '🤝 Sei stato sbloccato',
          messaggio: '$cleanCurUser ti ha sbloccato. Siete di nuovo amici!',
          data: {'tipo': 'sblocco_utente'},
        ));
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<List<String>> getUtentiBloccati() async {
    final curUser = _currentUser;
    if (curUser == null) return [];
    return List<String>.from(curUser.utentiBloccati);
  }

  // ==========================================
  // SEGNALAZIONI & MODERAZIONE (Apple UGC 1.2)
  // ==========================================

  Future<bool> inviaSegnalazione({
    required String segnalato,
    required String motivo,
    String dettagli = '',
  }) async {
    final curUser = _currentUser;
    final curNick = (curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome) ?? 'Cloud';

    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/segnalazioni/crea'),
          headers: defaultHeaders,
          body: jsonEncode({
            'segnalatore': curNick,
            'segnalato': segnalato,
            'motivo': motivo,
            'dettagli': dettagli,
          }),
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) return true;
      } catch (_) {}
    }

    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        await db.collection('Segnalazioni').insertOne({
          'segnalatore': curNick,
          'segnalato': segnalato,
          'motivo': motivo,
          'dettagli': dettagli,
          'timestamp': DateTime.now().toIso8601String(),
          'stato': 'in_attesa',
        });
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<List<Map<String, dynamic>>> getSegnalazioni() async {
    final curUser = _currentUser;
    final curNick = (curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome) ?? 'Cloud';

    for (String url in baseUrls) {
      try {
        final res = await http.get(
          Uri.parse('$url/segnalazioni?utente=$curNick'),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final List<dynamic> listJson = jsonDecode(res.body);
          return listJson.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }

    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Segnalazioni').find(where.sortBy('timestamp', descending: true)).toList();
        return docs.map((d) {
          final idStr = d['_id'] is ObjectId ? (d['_id'] as ObjectId).oid : d['_id']?.toString() ?? '';
          return {
            'id': idStr,
            'segnalatore': d['segnalatore'] ?? '',
            'segnalato': d['segnalato'] ?? '',
            'motivo': d['motivo'] ?? '',
            'dettagli': d['dettagli'] ?? '',
            'timestamp': d['timestamp'] ?? '',
            'stato': d['stato'] ?? 'in_attesa',
          };
        }).toList();
      }
    } catch (_) {}

    return [];
  }

  Future<bool> gestisciSegnalazione({
    required String segnalazioneId,
    required String azione, // 'ammonisci' | 'banna' | 'archivia'
    required String segnalato,
  }) async {
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/segnalazioni/gestisci'),
          headers: defaultHeaders,
          body: jsonEncode({
            'segnalazioneId': segnalazioneId,
            'azione': azione,
            'segnalato': segnalato,
          }),
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          if (azione == 'ammonisci') {
            unawaited(PushNotificationService.instance.inviaPushAUtenti(
              [segnalato],
              titolo: '⚠️ Richiamo di Moderazione',
              messaggio: 'Sei stato segnalato per comportamenti non conformi al regolamento di FantaEventi. Ti invitiamo al rispetto delle regole della community.',
              data: {'tipo': 'ammonizione_utente'},
            ));
          }
          return true;
        }
      } catch (_) {}
    }

    try {
      final db = await _getSafeMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? sObjId;
        try { sObjId = ObjectId.fromHexString(segnalazioneId); } catch (_) {}
        final sSelector = sObjId != null ? where.id(sObjId) : where.eq('_id', segnalazioneId);

        if (azione == 'ammonisci') {
          await db.collection('Segnalazioni').update(sSelector, modify.set('stato', 'ammonito'));
          await db.collection('Notifiche').insertOne({
            'tipo': 'ammonizione_utente',
            'titolo': '⚠️ Richiamo di Moderazione',
            'messaggio': 'Sei stato segnalato per comportamenti non conformi al regolamento di FantaEventi. Ti invitiamo al rispetto delle regole della community.',
            'destinatario': segnalato,
            'timestamp': DateTime.now().toIso8601String(),
            'letto': false,
          });
          unawaited(PushNotificationService.instance.inviaPushAUtenti(
            [segnalato],
            titolo: '⚠️ Richiamo di Moderazione',
            messaggio: 'Sei stato segnalato per comportamenti non conformi al regolamento di FantaEventi. Ti invitiamo al rispetto delle regole della community.',
            data: {'tipo': 'ammonizione_utente'},
          ));
          return true;
        } else if (azione == 'banna') {
          await db.collection('Segnalazioni').update(sSelector, modify.set('stato', 'bannato'));
          final uDocs = await db.collection('Utenti').find().toList();
          for (var uDoc in uDocs) {
            final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
            if (isSamePerson(uNick, segnalato)) {
              final uId = uDoc['_id'] as ObjectId;
              await db.collection('Utenti').update(where.id(uId), modify.set('isBanned', true));
              break;
            }
          }
          return true;
        } else if (azione == 'archivia') {
          await db.collection('Segnalazioni').update(sSelector, modify.set('stato', 'archiviata'));
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  // ==========================================
  // SEZIONE VAR (VERIFICA ASSISTITA DA REGIA)
  // ==========================================

  Future<String?> inviaRichiestaVar({
    required String eventoId,
    required String eventoTitolo,
    required String tipo, // 'bonus' o 'malus'
    required String bonusMalusId,
    required String bonusMalusTitolo,
    required int punti,
    required String richiedente,
    required String bersaglio,
    required String descrizione,
    String? fotoBase64,
    required List<String> testimoni,
    required String giudice,
    int penalitaPunti = -10,
  }) async {
    // Accesso diretto ultra-rapido a MongoDB Atlas
    try {
      final db = await _getMongoDb();
      if (db == null || !db.isConnected) return null;

      final now = DateTime.now();
      final varDoc = {
        'eventoId': eventoId,
        'eventoTitolo': eventoTitolo,
        'tipo': tipo,
        'bonusMalusId': bonusMalusId,
        'bonusMalusTitolo': bonusMalusTitolo,
        'punti': punti,
        'richiedente': richiedente,
        'bersaglio': bersaglio,
        'descrizione': descrizione,
        if (fotoBase64 != null && fotoBase64.isNotEmpty) 'fotoBase64': fotoBase64,
        'testimoni': testimoni,
        'votiTestimoni': <String, bool>{},
        'giudice': giudice,
        'stato': 'in_attesa',
        'dataCreazione': now.toIso8601String(),
        'sanzioneApplicata': false,
        'penalitaPunti': penalitaPunti,
      };

      final result = await db.collection('RichiesteVar').insertOne(varDoc);
      final varId = (varDoc['_id'] as ObjectId?)?.toHexString() ??
          (result.id is ObjectId ? (result.id as ObjectId).toHexString() : result.id.toString());

      final ts = now.millisecondsSinceEpoch;

      // 1. Notifica all'arbitro (Giudice)
      final ptSign = punti >= 0 ? '+$punti' : '$punti';
      final msgGiudice = tipo == 'bonus'
          ? '$richiedente ha richiesto la verifica VAR per il bonus "$bonusMalusTitolo" ($ptSign PT).'
          : '$richiedente ha denunciato $bersaglio al VAR per il malus "$bonusMalusTitolo" ($ptSign PT).';

      await db.collection('Notifiche').insertOne({
        'notificaId': 'var_g_${ts}_${giudice.toLowerCase()}',
        'mittente': richiedente,
        'destinatario': giudice,
        'titolo': '📺 VAR: Richiesta da Esaminare!',
        'messaggio': msgGiudice,
        'eventoId': eventoId,
        'varId': varId,
        'tipo': 'var_richiesta_giudice',
        'stato': 'in_attesa',
        'letto': false,
        'data': now.toIso8601String(),
      });

      // 2. Notifica a ciascun testimone
      for (var t in testimoni) {
        await db.collection('Notifiche').insertOne({
          'notificaId': 'var_t_${ts}_${t.toLowerCase()}',
          'mittente': richiedente,
          'destinatario': t,
          'titolo': '👀 Chiamata a Testimoniare al VAR',
          'messaggio': '$richiedente ti ha indicato come testimone per "$bonusMalusTitolo". Confermi l\'accaduto?',
          'eventoId': eventoId,
          'varId': varId,
          'tipo': 'var_testimone',
          'stato': 'in_attesa',
          'letto': false,
          'data': now.toIso8601String(),
        });
      }

      // Invia notifiche push per la tendina al Giudice e ai Testimoni
      try {
        await PushNotificationService.instance.inviaPushAUtenti(
          [giudice],
          titolo: '📺 VAR: Richiesta da Esaminare!',
          messaggio: msgGiudice,
          data: {'tipo': 'var_richiesta_giudice', 'eventoId': eventoId, 'varId': varId},
        ).timeout(const Duration(seconds: 4), onTimeout: () {});
      } catch (_) {}
      if (testimoni.isNotEmpty) {
        try {
          await PushNotificationService.instance.inviaPushAUtenti(
            testimoni,
            titolo: '👀 Chiamata a Testimoniare al VAR',
            messaggio: '$richiedente ti ha indicato come testimone per "$bonusMalusTitolo". Confermi l\'accaduto?',
            data: {'tipo': 'var_testimone', 'eventoId': eventoId, 'varId': varId},
          ).timeout(const Duration(seconds: 4), onTimeout: () {});
        } catch (_) {}
      }

      invalidateCache();
      return varId;
    } catch (_) {
      return null;
    }
  }

  Future<RichiestaVar?> getRichiestaVar(String id) async {
    try {
      final db = await _getMongoDb();
      if (db == null || !db.isConnected) return null;

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(id);
      } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', id);
      final doc = await db.collection('RichiesteVar').findOne(selector);
      if (doc != null) {
        return RichiestaVar.fromJson(doc);
      }
    } catch (_) {}
    return null;
  }

  Future<List<RichiestaVar>> getRichiesteVarEvento(String eventoId) async {
    try {
      final db = await _getMongoDb();
      if (db == null || !db.isConnected) return [];

      final docs = await db.collection('RichiesteVar').find(
        where.eq('eventoId', eventoId).excludeFields(['fotoBase64']),
      ).toList();
      return docs.map((d) => RichiestaVar.fromJson(d)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<RichiestaVar>> getRichiesteVarInSospesoPerGiudice(String giudiceNick) async {
    try {
      final db = await _getMongoDb();
      if (db == null || !db.isConnected) return [];

      final docs = await db.collection('RichiesteVar').find(
        where.eq('stato', 'in_attesa').excludeFields(['fotoBase64']),
      ).toList();

      final cleanGiudice = giudiceNick.trim().toLowerCase();
      return docs
          .where((d) => (d['giudice'] ?? '').toString().trim().toLowerCase() == cleanGiudice)
          .map((d) => RichiestaVar.fromJson(d))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> votaTestimonianzaVar({
    required String varId,
    required String testimoneNick,
    required bool conferma,
  }) async {
    try {
      final db = await _getMongoDb();
      if (db == null || !db.isConnected) return false;

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(varId);
      } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', varId);

      final doc = await db.collection('RichiesteVar').findOne(selector);
      if (doc == null) return false;
      if (doc['stato'] != 'in_attesa') return false; // Già decisa!

      final cleanNick = testimoneNick.trim().toLowerCase();
      await db.collection('RichiesteVar').update(
        selector,
        modify.set('votiTestimoni.$cleanNick', conferma),
      );

      // Aggiorna notifica testimone a stato votato
      final notDocs = await db.collection('Notifiche').find(where.eq('varId', varId).and(where.eq('tipo', 'var_testimone'))).toList();
      for (var nDoc in notDocs) {
        final dDest = (nDoc['destinatario'] ?? '').toString();
        if (isSamePerson(dDest, testimoneNick)) {
          ObjectId? nId;
          try {
            nId = nDoc['_id'] is ObjectId ? nDoc['_id'] as ObjectId : ObjectId.fromHexString(nDoc['_id'].toString());
          } catch (_) {}
          final nSel = nId != null ? where.id(nId) : where.eq('_id', nDoc['_id']);
          await db.collection('Notifiche').update(
            nSel,
            modify.set('stato', conferma ? 'confermato' : 'negato').set('letto', true),
          );
        }
      }

      invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> decidiRichiestaVar({
    required String varId,
    required String giudiceNick,
    required bool approva,
    bool sanzionaFalsaTestimonianza = false,
  }) async {
    invalidateCache();

    // 1. Chiamata primaria su Backend REST Render Starter (Ultra-rapida <800ms)
    for (String url in baseUrls) {
      try {
        final res = await http.post(
          Uri.parse('$url/var/decidi'),
          headers: defaultHeaders,
          body: jsonEncode({
            'varId': varId,
            'giudice': giudiceNick,
            'giudiceNick': giudiceNick,
            'approva': approva,
            'sanzionaFalsaTestimonianza': sanzionaFalsaTestimonianza,
          }),
        ).timeout(const Duration(seconds: 7));

        if ((res.statusCode == 200 || res.statusCode == 201) && !res.body.contains('<html>')) {
          final resData = jsonDecode(res.body) as Map<String, dynamic>;
          final richiedente = (resData['richiedente'] ?? '').toString();
          final bersaglio = (resData['bersaglio'] ?? '').toString();
          final evId = (resData['eventoId'] ?? '').toString();
          final evTitolo = (resData['eventoTitolo'] ?? 'Evento').toString();
          final bmTitolo = (resData['bonusMalusTitolo'] ?? 'VAR').toString();
          final int punti = (resData['punti'] as num?)?.toInt() ?? 0;
          final bool isSanzionato = resData['sanzionato'] == true;
          final List<dynamic> rawDests = resData['destinatari'] as List<dynamic>? ?? [];
          final List<String> broadcastDests = rawDests.map((e) => e.toString()).toList();

          // Invio Push Notification di sistema
          if (approva) {
            final cleanBersaglio = resolveNickname(bersaglio);
            final cleanRichiedente = resolveNickname(richiedente);
            final bool isBonus = punti >= 0;
            final String notificaTitolo = isBonus ? '🏆 Bonus Assegnato!' : '💀 Malus Assegnato!';
            final String ptSign = punti >= 0 ? '+$punti' : '$punti';

            // 1. Push di esito VAR al richiedente
            if (cleanRichiedente.isNotEmpty) {
              try {
                await PushNotificationService.instance.inviaPushAUtenti(
                  [cleanRichiedente],
                  titolo: '📺 VAR: Richiesta Approvata! ✅',
                  messaggio: 'Il Giudice ha convalidato la tua segnalazione per "$bmTitolo". I punti sono stati assegnati.',
                  data: {'tipo': 'var_esito', 'eventoId': evId, 'varId': varId},
                ).timeout(const Duration(seconds: 4), onTimeout: () {});
              } catch (_) {}
            }

            // 2. Push assegnazione bonus mirata al bersaglio
            if (cleanBersaglio.isNotEmpty) {
              try {
                await PushNotificationService.instance.inviaPushAUtenti(
                  [cleanBersaglio],
                  titolo: notificaTitolo,
                  messaggio: 'Hai ricevuto "$bmTitolo" ($ptSign PT) per l\'evento "$evTitolo"!',
                  data: {'tipo': isBonus ? 'assegnazione_bonus' : 'assegnazione_malus', 'eventoId': evId, 'varId': varId},
                ).timeout(const Duration(seconds: 4), onTimeout: () {});
              } catch (_) {}
            }

            // 3. Push broadcast a TUTTI gli altri partecipanti (INCLUSO IL GIUDICE CLOUD)
            final otherDests = broadcastDests.where((d) =>
              !isSamePerson(d, cleanBersaglio)
            ).toList();
            if (otherDests.isNotEmpty) {
              try {
                await PushNotificationService.instance.inviaPushAUtenti(
                  otherDests,
                  titolo: notificaTitolo,
                  messaggio: '$cleanBersaglio ha ricevuto "$bmTitolo" ($ptSign PT) per l\'evento "$evTitolo"!',
                  data: {'tipo': isBonus ? 'assegnazione_bonus' : 'assegnazione_malus', 'eventoId': evId, 'varId': varId},
                ).timeout(const Duration(seconds: 4), onTimeout: () {});
              } catch (_) {}
            }
          } else {
            // Respinta
            if (richiedente.isNotEmpty) {
              try {
                await PushNotificationService.instance.inviaPushAUtenti(
                  [richiedente],
                  titolo: isSanzionato ? '🚨 VAR: Denuncia Respinta e Sanzionata! ❌' : '📺 VAR: Segnalazione Respinta ❌',
                  messaggio: isSanzionato
                      ? 'La tua denuncia per "$bmTitolo" è stata respinta come infondata. Sanzione applicata!'
                      : 'La verifica per "$bmTitolo" non è stata convalidata dal Giudice.',
                  data: {'tipo': 'var_esito', 'eventoId': evId, 'varId': varId},
                ).timeout(const Duration(seconds: 4), onTimeout: () {});
              } catch (_) {}
            }

            if (bersaglio.isNotEmpty && !isSamePerson(bersaglio, richiedente)) {
              try {
                await PushNotificationService.instance.inviaPushAUtenti(
                  [bersaglio],
                  titolo: '📺 VAR: Segnalazione Respinta',
                  messaggio: 'La segnalazione contro di te per "$bmTitolo" è stata esaminata e respinta dal Giudice.',
                  data: {'tipo': 'var_esito', 'eventoId': evId, 'varId': varId},
                ).timeout(const Duration(seconds: 4), onTimeout: () {});
              } catch (_) {}
            }
          }

          invalidateCache();
          return true;
        } else if (res.statusCode == 400 && res.body.contains('già stata decisa')) {
          // Richiesta già processata
          return true;
        }
      } catch (_) {}
    }

    // 2. Rete di salvataggio: scrittura DIRETTA su MongoDB Atlas
    try {
      final db = await _getSafeMongoDb();
      if (db == null || !db.isConnected) return false;

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(varId);
      } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', varId);

      final doc = await db.collection('RichiesteVar').findOne(selector);
      if (doc == null) return false;
      if (doc['stato'] != 'in_attesa') return true; // Già decisa

      final richiesta = RichiestaVar.fromJson(doc);
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;
      final targetStato = approva ? 'approvata' : 'rifiutata';

      final updateClaim = await db.collection('RichiesteVar').update(
        selector.and(where.eq('stato', 'in_attesa')),
        modify
            .set('stato', targetStato)
            .set('dataDecisione', now.toIso8601String())
            .set('giudiceEffettivo', giudiceNick)
            .set('sanzioneApplicata', !approva && sanzionaFalsaTestimonianza && richiesta.tipo == 'malus')
            .unset('fotoBase64'),
      );
      final int nModified = (updateClaim['nModified'] as num?)?.toInt() ??
          ((updateClaim['n'] as num?)?.toInt() ?? 0);
      if (nModified == 0) return true;

      if (approva) {
        try {
          await assegnaBonusMalusAPartecipante(
            eventoId: richiesta.eventoId,
            bonusId: richiesta.bonusMalusId,
            utenteDestinatario: richiesta.bersaglio,
            punti: richiesta.punti,
            eventoTitolo: richiesta.eventoTitolo,
            bonusTitolo: richiesta.bonusMalusTitolo,
          );
        } catch (_) {}

        if (richiesta.tipo == 'malus') {
          try {
            final uDocs = await db.collection('Utenti').find().toList();
            for (var uDoc in uDocs) {
              if (matchesUserDoc(uDoc, richiesta.richiedente)) {
                final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
                final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
                final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);
                final prog = XpProgression.aggiungiXp(
                  livelloAttuale: curLiv,
                  xpLivelloAttuale: curXp,
                  deltaXp: 25,
                  xpTotaliAttuali: curTot,
                );
                ObjectId? uObjId;
                try {
                  uObjId = uDoc['_id'] is ObjectId ? uDoc['_id'] as ObjectId : ObjectId.fromHexString(uDoc['_id'].toString());
                } catch (_) {}
                final uSel = uObjId != null ? where.id(uObjId) : where.eq('_id', uDoc['_id']);
                await db.collection('Utenti').update(
                  uSel,
                  modify
                    .set('xp', prog.xp)
                    .set('livello', prog.livello)
                    .set('xpProssimoLivello', prog.xpProssimoLivello)
                    .set('xpTotali', prog.xpTotali),
                );
                break;
              }
            }
          } catch (_) {}
        }

        try {
          await db.collection('Notifiche').insertOne({
            'notificaId': 'var_res_${ts}_${richiesta.richiedente.toLowerCase()}',
            'mittente': giudiceNick,
            'destinatario': richiesta.richiedente,
            'titolo': '📺 VAR: Richiesta Approvata! ✅',
            'messaggio': 'Il Giudice ha convalidato la tua segnalazione per "${richiesta.bonusMalusTitolo}". I punti sono stati assegnati.',
            'eventoId': richiesta.eventoId,
            'varId': varId,
            'tipo': 'var_esito',
            'stato': 'approvata',
            'letto': false,
            'data': now.toIso8601String(),
          });
        } catch (_) {}

        if (!isSamePerson(richiesta.bersaglio, richiesta.richiedente)) {
          try {
            final ptSign = richiesta.punti >= 0 ? '+${richiesta.punti}' : '${richiesta.punti}';
            await db.collection('Notifiche').insertOne({
              'notificaId': 'var_target_${ts}_${richiesta.bersaglio.toLowerCase()}',
              'mittente': giudiceNick,
              'destinatario': richiesta.bersaglio,
              'titolo': '📺 VAR: Sentenza Convalidata! ⚖️',
              'messaggio': 'Il Giudice ha convalidato "${richiesta.bonusMalusTitolo}" ($ptSign PT) a tuo nome per l\'evento "${richiesta.eventoTitolo}".',
              'eventoId': richiesta.eventoId,
              'varId': varId,
              'tipo': 'var_esito',
              'stato': 'approvata',
              'letto': false,
              'data': now.toIso8601String(),
            });
          } catch (_) {}
        }

        try {
          await PushNotificationService.instance.inviaPushAUtenti(
            [richiesta.richiedente],
            titolo: '📺 VAR: Richiesta Approvata! ✅',
            messaggio: 'Il Giudice ha convalidato la tua segnalazione per "${richiesta.bonusMalusTitolo}". I punti sono stati assegnati.',
            data: {'tipo': 'var_esito', 'eventoId': richiesta.eventoId, 'varId': varId},
          ).timeout(const Duration(seconds: 4), onTimeout: () {});
        } catch (_) {}
      } else {
        // Rigettata diretta fallback
        final bool doSanzione = sanzionaFalsaTestimonianza && richiesta.tipo == 'malus';
        if (doSanzione) {
          final penalty = (richiesta.penalitaPunti != 0 ? richiesta.penalitaPunti.abs() : 10) * -1;
          final cleanRichiedente = richiesta.richiedente.trim();
          try {
            final uDocs = await db.collection('Utenti').find().toList();
            for (var uDoc in uDocs) {
              if (matchesUserDoc(uDoc, cleanRichiedente)) {
                final curPts = (uDoc['puntiTotali'] as num?)?.toInt() ?? 0;
                final curStorico = List<String>.from(uDoc['storicoVoti'] ?? []);
                final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                final logVoce = formattaVoceStorico('🚨 Sanzione VAR: Falsa Testimonianza ($penalty PT) per l\'evento "${richiesta.eventoTitolo}" ($timeStr)');
                curStorico.insert(0, logVoce);
                await db.collection('Utenti').update(
                  where.id(uDoc['_id'] as ObjectId),
                  modify.set('puntiTotali', curPts + penalty).set('storicoVoti', curStorico),
                );
                break;
              }
            }
          } catch (_) {}

          try {
            await db.collection('Notifiche').insertOne({
              'notificaId': 'var_res_${ts}_${richiesta.richiedente.toLowerCase()}',
              'mittente': giudiceNick,
              'destinatario': richiesta.richiedente,
              'titolo': '🚨 VAR: Denuncia Respinta e Sanzionata! ❌',
              'messaggio': 'La tua denuncia per "${richiesta.bonusMalusTitolo}" è stata respinta come infondata. Sanzione applicata: $penalty PT!',
              'eventoId': richiesta.eventoId,
              'varId': varId,
              'tipo': 'var_esito',
              'stato': 'sanzionato',
              'letto': false,
              'data': now.toIso8601String(),
            });
            await PushNotificationService.instance.inviaPushAUtenti(
              [richiesta.richiedente],
              titolo: '🚨 VAR: Denuncia Respinta e Sanzionata! ❌',
              messaggio: 'La tua denuncia per "${richiesta.bonusMalusTitolo}" è stata respinta come infondata. Sanzione applicata: $penalty PT!',
              data: {'tipo': 'var_esito', 'eventoId': richiesta.eventoId, 'varId': varId},
            ).timeout(const Duration(seconds: 4), onTimeout: () {});
          } catch (_) {}
        } else {
          try {
            await db.collection('Notifiche').insertOne({
              'notificaId': 'var_res_${ts}_${richiesta.richiedente.toLowerCase()}',
              'mittente': giudiceNick,
              'destinatario': richiesta.richiedente,
              'titolo': '📺 VAR: Richiesta Non Convalidata ❌',
              'messaggio': 'La verifica per "${richiesta.bonusMalusTitolo}" non è stata convalidata dal Giudice.',
              'eventoId': richiesta.eventoId,
              'varId': varId,
              'tipo': 'var_esito',
              'stato': 'rifiutata',
              'letto': false,
              'data': now.toIso8601String(),
            });
            await PushNotificationService.instance.inviaPushAUtenti(
              [richiesta.richiedente],
              titolo: '📺 VAR: Richiesta Non Convalidata ❌',
              messaggio: 'La verifica per "${richiesta.bonusMalusTitolo}" non è stata convalidata dal Giudice.',
              data: {'tipo': 'var_esito', 'eventoId': richiesta.eventoId, 'varId': varId},
            ).timeout(const Duration(seconds: 4), onTimeout: () {});
          } catch (_) {}
        }
      }

      // Aggiornamento sicuro delle notifiche per il giudice (tramite _id, senza multiUpdate)
      try {
        final notDocs = await db.collection('Notifiche').find(
          where.eq('varId', varId),
        ).toList();
        for (var nDoc in notDocs) {
          if (nDoc['_id'] is ObjectId) {
            final dDest = (nDoc['destinatario'] ?? '').toString().trim();
            final dTipo = (nDoc['tipo'] ?? '').toString();
            if (dTipo == 'var_richiesta_giudice' && isSamePerson(dDest, giudiceNick)) {
              await db.collection('Notifiche').update(
                where.id(nDoc['_id'] as ObjectId),
                modify.set('stato', approva ? 'approvata' : 'rifiutata').set('letto', true),
              );
            } else if (dTipo == 'var_testimone' && nDoc['stato'] == 'in_attesa') {
              await db.collection('Notifiche').update(
                where.id(nDoc['_id'] as ObjectId),
                modify.set('stato', 'concluso').set('letto', true),
              );
            }
          }
        }
      } catch (_) {}

      invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }
}
