import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
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
  String toString() =>
      'Questo account non ha ancora una password impostata. Impostala ora per proteggere il profilo!';
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
          if (diffHours > 168) continue;
          if (maxGiorni == 1 && diffHours > 24) continue;
          if (maxGiorni == 3 && diffHours > 72) continue;
          if (maxGiorni == 7 && diffHours > 168) continue;
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
  static const String _kSavedAuthTokenKey = 'saved_auth_token_jwt_v1';
  final Map<String, String> _avatarCache = {};
  String _authToken = '';

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
      final savedTok = prefs.getString(_kSavedAuthTokenKey);
      if (savedTok != null && savedTok.isNotEmpty) {
        _authToken = savedTok;
      }

      final avStr = prefs.getString(_kCachedAvatarsKey);
      if (avStr != null && avStr.isNotEmpty) {
        final Map<String, dynamic> map = jsonDecode(avStr);
        map.forEach((k, v) {
          if (v is String &&
              v.isNotEmpty &&
              !v.contains('pravatar') &&
              !v.contains('unsplash.com/photo-1535713875002')) {
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
          if (u.avatarUrl.isNotEmpty &&
              !u.avatarUrl.contains('pravatar') &&
              !u.avatarUrl.contains('unsplash.com/photo-1535713875002')) {
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

  final List<String> baseUrls = [
    'https://fantaeventi-backend-2-0.onrender.com/api',
  ];

  Map<String, String> get defaultHeaders => {
        'content-type': 'application/json',
        'bypass-tunnel-reminder': 'true',
        'User-Agent': 'FantaEventiApp',
        if (_authToken.isNotEmpty) 'Authorization': 'Bearer $_authToken',
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

  Utente getCurrentUser({bool forceRefresh = false}) {
    if (forceRefresh) {
      unawaited(syncCurrentUserFromDb());
    }
    return _currentUser ??
        Utente(
          id: '1',
          nome: 'Cloud',
          nickname: 'Cloud',
          email: '',
          avatarUrl: _avatarCache['cloud'] ?? '',
          livello: 1,
          xp: 100,
          xpProssimoLivello: 2000,
          puntiTotali: 0,
          badgeList: const ['🎉 Partecipante FantaEventi'],
          storicoVoti: const [],
          codiceAmico: 'FE-CLO1000',
          amici: const [],
          richiesteAmicizia: const [],
          badgeVincitore: const [],
        );
  }

  static String hashPassword(String password) {
    const salt = 'FantaEventi2026_Secure_Salt_#99';
    final bytes = utf8.encode('$password$salt');
    return sha256.convert(bytes).toString();
  }

  bool _rememberMeSession = false;

  Future<void> _saveSession(Utente utente, {bool? rememberMe, String? token}) async {
    final shouldRemember = rememberMe ?? _rememberMeSession;
    if (token != null && token.isNotEmpty) {
      _authToken = token;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_authToken.isNotEmpty) {
        await prefs.setString(_kSavedAuthTokenKey, _authToken);
      }
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

  /// Registra il token FCM sul backend.
  /// Ritorna `true` se accettato, `false` se il backend segnala `tokenInvalid == true` (HTTP 409 UNREGISTERED),
  /// permettendo a PushNotificationService di rigenerare un nuovo token fresco.
  Future<bool> salvaFcmToken(String token) async {
    final cur = _currentUser;
    final cleanToken = token.trim();
    if (cur == null || cleanToken.isEmpty) return true;

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/fcm-token'),
              headers: defaultHeaders,
              body: jsonEncode({
                'utente': cur.nickname.isNotEmpty ? cur.nickname : cur.nome,
                'token': cleanToken,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 409) {
          // Il server ha verificato con Google FCM che questo token è UNREGISTERED!
          if (_currentUser != null && _currentUser!.fcmTokens.contains(cleanToken)) {
            final cleaned = List<String>.from(_currentUser!.fcmTokens)..remove(cleanToken);
            _currentUser = _currentUser!.copyWith(fcmTokens: cleaned);
            await _saveSession(_currentUser!);
          }
          return false;
        }
        if (res.statusCode == 200) {
          if (_currentUser != null && !_currentUser!.fcmTokens.contains(cleanToken)) {
            _currentUser = _currentUser!.copyWith(
              fcmTokens: [..._currentUser!.fcmTokens, cleanToken],
            );
            await _saveSession(_currentUser!);
          }
          return true;
        }
      } catch (_) {}
    }

    return true;
  }

  Future<void> rimuoviFcmToken(String token) async {
    await rimuoviFcmTokenGlobale(token);
  }

  Future<void> rimuoviFcmTokenGlobale(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/fcm-token/rimuovi'),
              headers: defaultHeaders,
              body: jsonEncode({
                'token': cleanToken,
              }),
            )
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          break;
        }
      } catch (_) {}
    }
  }

  /// Risolve rigorosamente qualsiasi nome o alias nel NICKNAME ufficiale del giocatore.
  String resolveNickname(String? candidate) {
    if (candidate == null) return _currentUser?.nickname ?? 'Cloud';
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return _currentUser?.nickname ?? 'Cloud';
    final lower = trimmed.toLowerCase();

    if (lower == 'claudio' || lower == 'cloud' || lower == 'claude') return 'Cloud';
    if (lower == 'filippo' || lower == 'pippoforte' || lower == 'pippo forte') return 'Pippoforte';
    if (lower == 'antonio' || lower == 'ugnom' || lower == 'ugnome') return 'Ugnom';

    for (var u in _utenti) {
      if (u.nickname.isNotEmpty) {
        if (u.nickname.toLowerCase() == lower) return u.nickname;
        if (u.nome.isNotEmpty && u.nome.toLowerCase() == lower) return u.nickname;
        if (u.cognome.isNotEmpty && '${u.nome} ${u.cognome}'.toLowerCase() == lower) return u.nickname;
        if (u.username.isNotEmpty && u.username.toLowerCase() == lower) return u.nickname;
      }
    }

    if (_currentUser != null && _currentUser!.nickname.isNotEmpty) {
      if (_currentUser!.nome.toLowerCase() == lower ||
          _currentUser!.username.toLowerCase() == lower ||
          _currentUser!.nickname.toLowerCase() == lower) {
        return _currentUser!.nickname;
      }
    }

    return trimmed;
  }

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
    return [];
  }

  Future<void> logout() async {
    try {
      unawaited(PushNotificationService.instance.unregisterCurrentDeviceToken());
    } catch (_) {}
    _currentUser = null;
    _authToken = '';
    _rememberMeSession = false;
    _cachedTutorialPremioRiscattato = null;
    clearUserSessionCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_json');
      await prefs.remove('saved_user_nickname');
      await prefs.remove('has_password_auth_v2');
      await prefs.remove('remember_me_enabled');
      await prefs.remove(_kSavedAuthTokenKey);
    } catch (_) {}
  }

  Future<bool> eliminaAccount({String? utenteId, String? nickname, String? nome}) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/elimina-account'),
              headers: defaultHeaders,
              body: jsonEncode({
                'utenteId': utenteId,
                'nickname': nickname,
                'nome': nome,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          await logout();
          invalidateCache();
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static void Function()? onCurrentUserBanned;

  Future<Utente?> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasPasswordAuth = prefs.getBool('has_password_auth_v2') ?? false;
      final rememberMe = prefs.getBool('remember_me_enabled') ?? false;
      final savedTok = prefs.getString(_kSavedAuthTokenKey);
      if (savedTok != null && savedTok.isNotEmpty) {
        _authToken = savedTok;
      }

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
        if (_currentUser != null && _currentUser!.isBanned) {
          await prefs.remove('saved_user_json');
          await prefs.remove('saved_user_nickname');
          _currentUser = null;
          _rememberMeSession = false;
          return null;
        }
        if (_currentUser != null &&
            (_currentUser!.avatarUrl.contains('pravatar') ||
                _currentUser!.avatarUrl.contains('unsplash.com/photo-1535713875002'))) {
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

        for (String url in baseUrls) {
          try {
            final res = await http
                .post(
                  Uri.parse('$url/utenti/completa-guida'),
                  headers: defaultHeaders,
                  body: jsonEncode({
                    'utente': curUser.nickname.isNotEmpty ? curUser.nickname : curUser.nome,
                    'awardXp': shouldActuallyAward,
                  }),
                )
                .timeout(const Duration(seconds: 8));
            if (res.statusCode == 200) {
              break;
            }
          } catch (_) {}
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
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/notifiche/benvenuto'),
              headers: defaultHeaders,
              body: jsonEncode({'nickname': nickname}),
            )
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) return;
      } catch (_) {}
    }
  }

  // --- LOGIN TRAMITE BACKEND REST RENDER ---
  Future<Utente> login(String identifier, String password, {bool rememberMe = true}) async {
    clearUserSessionCache();
    _rememberMeSession = rememberMe;
    final cleanIdentifier = identifier.trim();
    final cleanPassword = password.trim();

    if (cleanIdentifier.isEmpty) {
      throw Exception('Inserisci il tuo Nickname o la tua Email');
    }

    for (String url in baseUrls) {
      try {
        final response = await http
            .post(
              Uri.parse('$url/login'),
              headers: defaultHeaders,
              body: jsonEncode({
                'username': cleanIdentifier,
                'email': cleanIdentifier,
                'nickname': cleanIdentifier,
                'password': cleanPassword,
              }),
            )
            .timeout(const Duration(seconds: 12));

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
          final tok = data['token']?.toString() ?? '';
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          if (_currentUser!.isBanned) {
            clearUserSessionCache();
            throw Exception(
              'Account sospeso. Questo profilo è stato bloccato per violazione delle linee guida della community.',
            );
          }
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe, token: tok);
          return _currentUser!;
        } else if (response.statusCode == 403 || response.statusCode == 401) {
          throw Exception(data['error']?.toString() ?? 'Password non corretta. Riprova!');
        } else if (response.statusCode == 404 || data['notFound'] == true) {
          throw Exception('Nessun utente trovato nel database per "$cleanIdentifier". Registrati prima di accedere!');
        } else if (data.containsKey('error')) {
          throw Exception(data['error'].toString());
        }
      } catch (e) {
        if (e is NeedsPasswordSetupException) rethrow;
        if (e is Exception &&
            (e.toString().contains('Nessun utente trovato') ||
                e.toString().contains('Password non corretta') ||
                e.toString().contains('Inserisci la tua password') ||
                e.toString().contains('Inserisci la password') ||
                e.toString().contains('sospeso') ||
                e.toString().contains('bloccato'))) {
          rethrow;
        }
      }
    }

    throw Exception('Impossibile connettersi al server. Verifica la tua connessione internet e riprova.');
  }

  // --- IMPOSTAZIONE PASSWORD AL PRIMO ACCESSO ---
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

    for (String url in baseUrls) {
      try {
        final response = await http
            .post(
              Uri.parse('$url/utenti/imposta-password'),
              headers: defaultHeaders,
              body: jsonEncode({
                'username': username.trim(),
                'password': cleanPass,
              }),
            )
            .timeout(const Duration(seconds: 12));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 200 && data.containsKey('utente')) {
          final tok = data['token']?.toString() ?? '';
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe, token: tok);
          return _currentUser!;
        } else if (data.containsKey('error')) {
          throw Exception(data['error'].toString());
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) rethrow;
      }
    }

    throw Exception('Impossibile salvare la nuova password. Verifica la connessione di rete.');
  }

  List<String> generaSuggerimentiNickname(String baseNick, Set<String> existingLowerNicks) {
    final clean = baseNick.trim();
    final List<String> candidates = [
      '${clean}1234',
      '${clean}2026',
      '${clean}99',
      '${clean}7',
      '${clean}_fanta',
      'il_$clean',
      '${clean}_pro',
      '${clean}_real',
    ];
    if (clean.isNotEmpty) {
      final lastChar = clean[clean.length - 1];
      if (RegExp(r'[a-zA-Z]').hasMatch(lastChar)) {
        candidates.insert(4, '$clean$lastChar');
      }
    }
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

  Future<NicknameCheckResult> verificaDisponibilitaNickname(String nickname) async {
    final cleanNick = nickname.trim();
    if (cleanNick.length < 3) {
      return const NicknameCheckResult(
        disponibile: false,
        messaggio: 'Il nickname deve contenere almeno 3 caratteri.',
        suggerimenti: [],
      );
    }

    for (String url in baseUrls) {
      try {
        final res = await http
            .get(
              Uri.parse('$url/utenti/check-nickname?nick=${Uri.encodeComponent(cleanNick)}'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final bool disp = data['disponibile'] == true;
          final List<String> sugg =
              (data['suggerimenti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          return NicknameCheckResult(
            disponibile: disp,
            messaggio: data['messaggio']?.toString(),
            suggerimenti: sugg,
          );
        }
      } catch (_) {}
    }

    return const NicknameCheckResult(
      disponibile: true,
      messaggio: null,
      suggerimenti: [],
    );
  }

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
    final cleanEmail = email.trim();
    String? lastError;

    for (String url in baseUrls) {
      try {
        final response = await http
            .post(
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
            )
            .timeout(const Duration(seconds: 15));

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (response.statusCode == 200 && data.containsKey('utente')) {
          final tok = data['token']?.toString() ?? '';
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe, token: tok);
          return _currentUser!;
        } else if (data['suggerimenti'] != null) {
          final sugg = (data['suggerimenti'] as List<dynamic>).map((e) => e.toString()).toList();
          throw NicknameAlreadyTakenException(
            nickname: cleanNick,
            suggerimenti: sugg,
          );
        } else if (data.containsKey('error')) {
          lastError = data['error'].toString();
          throw Exception(lastError);
        }
      } catch (e) {
        if (e is NicknameAlreadyTakenException) rethrow;
        if (e is Exception && e.toString().contains('esiste già')) rethrow;
        lastError ??= 'Impossibile contattare il server backend: $e';
      }
    }

    throw Exception(lastError ?? 'Errore durante la registrazione del nuovo utente.');
  }

  Future<Map<String, String>> richiediCodiceReset(String identifier) async {
    final cleanIdent = identifier.trim().toLowerCase();
    if (cleanIdent.isEmpty) {
      throw Exception('Inserisci il tuo Nickname o la tua Email.');
    }

    for (String url in baseUrls) {
      try {
        final response = await http
            .post(
              Uri.parse('$url/utenti/richiedi-reset-password'),
              headers: defaultHeaders,
              body: jsonEncode({'identifier': cleanIdent}),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return {
            'email': data['email']?.toString() ?? '',
            'maskedEmail': data['maskedEmail']?.toString() ?? '',
            'username': data['username']?.toString() ?? '',
          };
        } else {
          final data = jsonDecode(response.body);
          if (data is Map && data.containsKey('error')) {
            throw Exception(data['error']);
          }
        }
      } catch (e) {
        if (e is Exception &&
            (e.toString().contains('Nessun account trovato') ||
                e.toString().contains('Nessuna email associata') ||
                e.toString().contains('Errore durante l\'invio'))) {
          rethrow;
        }
      }
    }

    throw Exception('Impossibile inviare il codice in questo momento. Verifica la connessione di rete.');
  }

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

    for (String url in baseUrls) {
      try {
        final response = await http
            .post(
              Uri.parse('$url/utenti/conferma-reset-password'),
              headers: defaultHeaders,
              body: jsonEncode({
                'email': cleanEmail,
                'codice': cleanCode,
                'nuovaPassword': cleanPass,
              }),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          return;
        } else {
          final data = jsonDecode(response.body);
          if (data is Map && data.containsKey('error')) {
            throw Exception(data['error']);
          }
        }
      } catch (e) {
        if (e is Exception &&
            (e.toString().contains('Codice di verifica') ||
                e.toString().contains('scaduto') ||
                e.toString().contains('tentativi') ||
                e.toString().contains('Nessuna richiesta'))) {
          rethrow;
        }
      }
    }

    throw Exception('Impossibile verificare il codice in questo momento. Verifica la connessione di rete.');
  }

  int _avatarUpdateEpoch = 0;
  DateTime? _lastLocalAvatarUpdateTime;
  String? _lastLocalAvatarValue;

  Future<Utente?> syncCurrentUserFromDb() async {
    if (_currentUser == null) return null;
    final int epochAtStart = _avatarUpdateEpoch;
    try {
      final utenti = await getUtenti();
      final liveCurUser = _currentUser;
      if (liveCurUser == null) return null;

      final match = utenti.firstWhere(
        (u) =>
            (liveCurUser.id.isNotEmpty && u.id == liveCurUser.id) ||
            u.nickname.trim().toLowerCase() == liveCurUser.nickname.trim().toLowerCase() ||
            u.nome.trim().toLowerCase() == liveCurUser.nome.trim().toLowerCase(),
        orElse: () => liveCurUser,
      );

      final bool hasRecentLocalAvatar = _lastLocalAvatarValue != null &&
          _lastLocalAvatarValue!.isNotEmpty &&
          (_avatarUpdateEpoch != epochAtStart ||
              (_lastLocalAvatarUpdateTime != null &&
                  DateTime.now().difference(_lastLocalAvatarUpdateTime!).inSeconds < 30));

      String finalAvatar;
      if (hasRecentLocalAvatar) {
        finalAvatar = _lastLocalAvatarValue!;
      } else if (match.avatarUrl.isNotEmpty) {
        finalAvatar = match.avatarUrl;
      } else if (liveCurUser.avatarUrl.isNotEmpty) {
        finalAvatar = liveCurUser.avatarUrl;
      } else {
        finalAvatar = _avatarCache[liveCurUser.nickname.toLowerCase()] ?? '';
      }

      if (finalAvatar.isEmpty) {
        finalAvatar = await fetchAvatarPerUtente(liveCurUser.nickname);
      }

      _currentUser = match.copyWith(avatarUrl: finalAvatar);
      await _saveSession(_currentUser!);
      return _currentUser;
    } catch (_) {
      return _currentUser;
    }
  }

  Future<void> aggiornaAvatarUtente(String username, String newAvatarUrl) async {
    _avatarUpdateEpoch++;
    _lastLocalAvatarUpdateTime = DateTime.now();
    _lastLocalAvatarValue = newAvatarUrl;

    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(avatarUrl: newAvatarUrl);
      await _saveSession(_currentUser!);
    }

    for (int i = 0; i < _utenti.length; i++) {
      final u = _utenti[i];
      if (isSamePerson(u.nickname, username) || isSamePerson(u.nome, username)) {
        _utenti[i] = u.copyWith(avatarUrl: newAvatarUrl);
      }
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

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/avatar'),
              headers: defaultHeaders,
              body: jsonEncode({
                'utente': username,
                'avatarUrl': newAvatarUrl,
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          break;
        }
      } catch (_) {}
    }
  }

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
    final int epochAtStart = _avatarUpdateEpoch;
    final curNick = (_currentUser?.nickname.isNotEmpty == true ? _currentUser!.nickname : _currentUser?.nome) ?? '';
    for (String url in baseUrls) {
      try {
        final uri = curNick.isNotEmpty
            ? Uri.parse('$url/utenti?utente=${Uri.encodeComponent(curNick)}')
            : Uri.parse('$url/utenti');
        final res = await http.get(uri, headers: defaultHeaders).timeout(const Duration(seconds: 8));

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
            final validServerAv = (rawServerAv.isNotEmpty &&
                    !rawServerAv.contains('pravatar') &&
                    !rawServerAv.contains('unsplash.com/photo-1535713875002'))
                ? rawServerAv
                : '';
            var uObj = Utente.fromJson(jsonMap).copyWith(avatarUrl: validServerAv);

            final bool isCurrentUserRow = _currentUser != null &&
                (isSamePerson(uObj.nickname, _currentUser!.nickname) ||
                    isSamePerson(uObj.nome, _currentUser!.nome));

            if (isCurrentUserRow) {
              final bool hasRecentLocalAvatar = _lastLocalAvatarValue != null &&
                  _lastLocalAvatarValue!.isNotEmpty &&
                  (_avatarUpdateEpoch != epochAtStart ||
                      (_lastLocalAvatarUpdateTime != null &&
                          DateTime.now().difference(_lastLocalAvatarUpdateTime!).inSeconds < 30));

              final curAv = _currentUser!.avatarUrl;
              final validCurAv = (curAv.isNotEmpty &&
                      !curAv.contains('pravatar') &&
                      !curAv.contains('unsplash.com/photo-1535713875002'))
                  ? curAv
                  : '';

              final String safeAvatar;
              if (hasRecentLocalAvatar) {
                safeAvatar = _lastLocalAvatarValue!;
              } else if (validServerAv.isNotEmpty) {
                safeAvatar = validServerAv;
              } else if (validCurAv.isNotEmpty) {
                safeAvatar = validCurAv;
              } else {
                safeAvatar = _avatarCache[resolvedNick.toLowerCase()] ?? '';
              }

              uObj = uObj.copyWith(avatarUrl: safeAvatar);
              if (safeAvatar.isNotEmpty) {
                _cacheSingleAvatar(uObj.nome, uObj.nickname, safeAvatar);
              }
              _currentUser = uObj;
              await _saveSession(_currentUser!);
              if (uObj.isBanned) {
                onCurrentUserBanned?.call();
              }
            } else {
              final cachedAv = _avatarCache[resolvedNick.toLowerCase()] ?? '';
              final effectiveAv = validServerAv.isNotEmpty ? validServerAv : cachedAv;
              if (effectiveAv.isNotEmpty) {
                uObj = uObj.copyWith(avatarUrl: effectiveAv);
                _cacheSingleAvatar(uObj.nome, uObj.nickname, effectiveAv);
              }
            }

            list.add(uObj);
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

    return List.unmodifiable(_utenti);
  }

  String getAvatarPerUtente(String nickname) {
    final clean = nickname.replaceAll(' ', '').trim().toLowerCase();
    final raw = nickname.trim().toLowerCase();
    if (clean.isEmpty) return '';

    bool isValid(String? s) =>
        s != null &&
        s.isNotEmpty &&
        !s.contains('pravatar') &&
        !s.contains('unsplash.com/photo-1535713875002');

    if (_currentUser != null) {
      final cName = _currentUser!.nome.replaceAll(' ', '').trim().toLowerCase();
      final cNick = _currentUser!.nickname.replaceAll(' ', '').trim().toLowerCase();
      final cRawName = _currentUser!.nome.trim().toLowerCase();
      final cRawNick = _currentUser!.nickname.trim().toLowerCase();
      if ((cName == clean || cNick == clean || cRawName == raw || cRawNick == raw) &&
          isValid(_currentUser!.avatarUrl)) {
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
        final res = await http
            .get(
              Uri.parse('$url/utenti/avatar?utente=${Uri.encodeComponent(nickname)}'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final av = (data['avatarUrl'] ?? '').toString().trim();
          if (av.isNotEmpty &&
              !av.contains('pravatar') &&
              !av.contains('unsplash.com/photo-1535713875002')) {
            _avatarCache[clean] = av;
            if (clean == 'cloud') _avatarCache['claudio'] = av;
            if (clean == 'claudio') _avatarCache['cloud'] = av;
            if (_currentUser != null &&
                (isSamePerson(clean, _currentUser!.nickname) || isSamePerson(clean, _currentUser!.nome))) {
              _currentUser = _currentUser!.copyWith(avatarUrl: av);
              await _saveSession(_currentUser!);
            }
            return av;
          }
        }
      } catch (_) {}
    }
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

  Future<void> sanificaERiconciliaEventiETitoli({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastReconciliationTime != null && now.difference(_lastReconciliationTime!).inSeconds < 60) {
      return;
    }
    _lastReconciliationTime = now;

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/eventi/riconcilia'),
              headers: defaultHeaders,
              body: jsonEncode({}),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['modified'] == true && _currentUser != null) {
            await syncCurrentUserFromDb();
          }
          return;
        }
      } catch (_) {}
    }
  }

  // --- REPERIMENTO EVENTI TRAMITE BACKEND REST RENDER ---
  Future<List<Evento>> getEventi({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration &&
        _eventi.isNotEmpty) {
      return List.unmodifiable(_eventi);
    }

    final curNickQuery = Uri.encodeComponent(
      (_currentUser?.nickname.isNotEmpty == true ? _currentUser!.nickname : _currentUser?.nome) ?? '',
    );
    for (String url in baseUrls) {
      try {
        final res = await http
            .get(
              Uri.parse(curNickQuery.isNotEmpty ? '$url/eventi?utente=$curNickQuery' : '$url/eventi'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final List<dynamic> listJson = jsonDecode(res.body);
          final List<Evento> list = [];
          final now = DateTime.now();
          for (var item in listJson) {
            final jsonMap = Map<String, dynamic>.from(item as Map);
            final ev = Evento.fromJson(jsonMap);
            if (ev.isConcluso && now.difference(ev.dataFine).inDays >= 5) {
              continue;
            }
            if (_currentUser != null) {
              final myName = _currentUser!.nome.trim();
              final myNick = _currentUser!.nickname.trim();
              final myId = _currentUser!.id.trim().toLowerCase();

              final cleanCreator = ev.creatore.trim();
              final bool isCreatore = isSamePerson(cleanCreator, myNick) ||
                  isSamePerson(cleanCreator, myName) ||
                  (myId.isNotEmpty && cleanCreator.toLowerCase() == myId);
              final bool isPartecipante = isCreatore ||
                  ev.partecipanti.any((p) {
                    final pTrim = p.trim();
                    return isSamePerson(pTrim, myNick) ||
                        isSamePerson(pTrim, myName) ||
                        (myId.isNotEmpty && pTrim.toLowerCase() == myId);
                  });
              final bool isInvitato = ev.invitati.any((i) {
                final iTrim = i.trim();
                return isSamePerson(iTrim, myNick) ||
                    isSamePerson(iTrim, myName) ||
                    (myId.isNotEmpty && iTrim.toLowerCase() == myId);
              });

              if (!isCreatore && !isPartecipante && !isInvitato) {
                continue;
              }
              if (!isCreatore && !isPartecipante && isInvitato) {
                final bool isInizioPassatoDa30Min = now.isAfter(ev.data.add(const Duration(minutes: 30)));
                if (ev.isConcluso || isInizioPassatoDa30Min) {
                  continue;
                }
              }
            }
            list.add(ev);
          }
          _eventi.clear();
          _eventi.addAll(list);
          _lastFetchTime = DateTime.now();
          return List.unmodifiable(_eventi);
        }
      } catch (_) {}
    }

    if (_eventi.isNotEmpty) {
      return List.unmodifiable(_eventi);
    }
    throw Exception('Impossibile recuperare gli eventi dal server. Verifica la tua connessione.');
  }

  Future<void> partecipaAdEvento(String eventoId, String nicknameOrId) async {
    invalidateCache();
    final resolvedNick = resolveNickname(nicknameOrId);

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/eventi/partecipa'),
              headers: defaultHeaders,
              body: jsonEncode({
                'eventoId': eventoId,
                'utente': resolvedNick,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final evIdx = _eventi.indexWhere((e) => e.id == eventoId);
          if (evIdx != -1) {
            final ev = _eventi[evIdx];
            final updatedPart = List<String>.from(ev.partecipanti);
            final updatedInv = List<String>.from(ev.invitati);
            updatedInv.removeWhere((i) => isSamePerson(i, resolvedNick));
            if (!updatedPart.any((p) => isSamePerson(p, resolvedNick))) {
              updatedPart.add(resolvedNick);
            }
            _eventi[evIdx] = ev.copyWith(partecipanti: updatedPart, invitati: updatedInv);
          }
          return;
        } else {
          final data = jsonDecode(res.body);
          if (data is Map && data['error'] != null) {
            throw Exception(data['error'].toString());
          }
        }
      } catch (e) {
        if (e is Exception &&
            (e.toString().contains('iscrizioni') || e.toString().contains('Non sei nella lista'))) {
          rethrow;
        }
      }
    }
  }

  Future<void> invitaAmiciAdEvento(String eventoId, List<String> nuoviInvitati) async {
    if (nuoviInvitati.isEmpty) return;
    invalidateCache();

    final curNick = (_currentUser?.nickname.isNotEmpty == true ? _currentUser!.nickname : _currentUser?.nome) ?? 'Cloud';

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/eventi/invita'),
              headers: defaultHeaders,
              body: jsonEncode({
                'eventoId': eventoId,
                'nuoviInvitati': nuoviInvitati.map((a) => resolveNickname(a)).toList(),
                'utente': resolveNickname(curNick),
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final aggiunti = (data['aggiuntiEffettivi'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          final evTitolo = (data['eventoTitolo'] ?? 'Evento').toString();
          final creatore = (data['creatore'] ?? resolveNickname(curNick)).toString();

          final evIdx = _eventi.indexWhere((e) => e.id == eventoId);
          if (evIdx != -1 && aggiunti.isNotEmpty) {
            final ev = _eventi[evIdx];
            final updatedInv = List<String>.from(ev.invitati);
            for (var a in aggiunti) {
              if (!updatedInv.contains(a)) updatedInv.add(a);
            }
            _eventi[evIdx] = ev.copyWith(invitati: updatedInv);
          }

          if (aggiunti.isNotEmpty) {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                aggiunti,
                titolo: '🎉 Invito ad Evento: $evTitolo',
                messaggio: '$creatore ti ha invitato a partecipare all\'evento "$evTitolo"!',
                data: {
                  'tipo': 'invito',
                  'eventoId': eventoId,
                },
              ),
            );
          }
          return;
        } else {
          final data = jsonDecode(res.body);
          if (data is Map && data['error'] != null) {
            throw Exception(data['error'].toString());
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Non è più possibile invitare')) {
          rethrow;
        }
      }
    }
    throw Exception('Impossibile inviare gli inviti. Verifica la connessione di rete.');
  }

  Future<void> eliminaEvento(String eventoId, [String utente = 'Cloud']) async {
    invalidateCache();

    _eventi.removeWhere((e) => e.id == eventoId);
    _bonusMalusList.removeWhere((b) => b.eventoId == eventoId || b.id == eventoId);
    _votazioniList.removeWhere((v) => v.bonusMalus?.eventoId == eventoId || v.id == eventoId);

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/eventi/elimina'),
              headers: defaultHeaders,
              body: jsonEncode({
                'eventoId': eventoId,
                'utente': resolveNickname(utente),
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          return;
        } else if (res.statusCode == 403) {
          final data = jsonDecode(res.body);
          if (data is Map && data['error'] != null) {
            throw Exception(data['error'].toString());
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Solo il creatore')) rethrow;
      }
    }
  }

  Future<List<Map<String, dynamic>>> getNotifiche(String nickname) async {
    final cleanNick = resolveNickname(nickname).trim().toLowerCase();

    for (String url in baseUrls) {
      try {
        final res = await http
            .get(
              Uri.parse('$url/notifiche?utente=${Uri.encodeComponent(cleanNick)}'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final List<dynamic> listJson = jsonDecode(res.body);
          final List<Map<String, dynamic>> resList = [];

          for (var item in listJson) {
            final m = Map<String, dynamic>.from(item as Map);
            final rawMittente = (m['mittente'] ?? 'FantaEventi').toString();
            final resolvedMittente = resolveNickname(rawMittente);
            m['mittente'] = resolvedMittente;
            m['destinatario'] = resolveNickname((m['destinatario'] ?? '').toString());

            final evId = (m['eventoId'] ?? '').toString().trim().toLowerCase();
            if (evId.isNotEmpty) {
              for (final e in _eventi) {
                if (e.id.toLowerCase() == evId || e.titolo.toLowerCase() == evId) {
                  m['eventoStato'] ??= e.stato.toLowerCase();
                  m['eventoDataInizio'] ??= e.data.toIso8601String();
                  break;
                }
              }
            }

            final bonusId = (m['bonusId'] ?? '').toString().trim().toLowerCase();
            final bonusTitolo = (m['bonusTitolo'] ?? '').toString().trim().toLowerCase();
            if (bonusId.isNotEmpty || bonusTitolo.isNotEmpty) {
              for (final v in _votazioniList) {
                final vBmId = (v.bonusMalus?.id ?? v.id).trim().toLowerCase();
                final vTit = (v.bonusMalus?.titolo ?? v.titolo).trim().toLowerCase();
                if ((bonusId.isNotEmpty && vBmId == bonusId) ||
                    (bonusTitolo.isNotEmpty && vTit == bonusTitolo)) {
                  for (final k in v.votiUtenti.keys) {
                    if (isSamePerson(k, cleanNick)) {
                      m['haGiaVotato'] = true;
                      m['votoEspresso'] = v.votiUtenti[k] ?? 'pro';
                      break;
                    }
                  }
                  final stVot = v.stato.toLowerCase();
                  if (stVot == 'approvato' || stVot == 'respinto' || stVot == 'concluso') {
                    m['votazioneChiusa'] = true;
                    m['esitoVotazione'] = stVot;
                  }
                  break;
                }
              }
            }

            resList.add(m);
          }
          return resList;
        }
      } catch (_) {}
    }

    return [];
  }

  Future<void> rispondiNotifica(String notificaId, String azione, String utente) async {
    invalidateCache();
    final resolvedNick = resolveNickname(utente);

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/notifiche/rispondi'),
              headers: defaultHeaders,
              body: jsonEncode({
                'notificaId': notificaId,
                'azione': azione,
                'utente': resolvedNick,
              }),
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          return;
        }
      } catch (_) {}
    }
  }

  Future<Evento> creaEvento(Evento nuovoEvento, {bool awardXp = true}) async {
    invalidateCache();
    final rawCreatore = (_currentUser?.nickname.isNotEmpty == true
            ? _currentUser!.nickname
            : (nuovoEvento.propostoDa.isNotEmpty ? nuovoEvento.propostoDa : (_currentUser?.nome ?? 'Cloud')))
        .trim();
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

    String realEvId = eventPayload.id;

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
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
                'copertinaUrl': nuovoEvento.copertinaUrl,
                'penalitaFalsaTestimonianza': nuovoEvento.penalitaFalsaTestimonianza,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final resData = jsonDecode(res.body) as Map<String, dynamic>;
          final insertedEvId = resData['id']?.toString() ?? '';
          final savedEvento = eventPayload.copyWith(id: insertedEvId.isNotEmpty ? insertedEvId : realEvId);
          _eventi.insert(0, savedEvento);

          if (invitati.isNotEmpty) {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                invitati,
                titolo: '🎉 Invito ad Evento: ${nuovoEvento.titolo}',
                messaggio: '$creatore ti ha invitato a partecipare all\'evento "${nuovoEvento.titolo}"!',
                data: {
                  'tipo': 'invito',
                  'eventoId': insertedEvId.isNotEmpty ? insertedEvId : realEvId,
                },
              ),
            );
          }

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

    throw Exception('Impossibile creare l\'evento sul server. Verifica la connessione internet e riprova.');
  }

  Future<void> aggiornaCopertinaEvento(String eventoId, String newCopertinaUrl) async {
    final evIndex = _eventi.indexWhere(
      (e) =>
          e.id.trim().toLowerCase() == eventoId.trim().toLowerCase() ||
          e.titolo.trim().toLowerCase() == eventoId.trim().toLowerCase(),
    );
    if (evIndex != -1) {
      _eventi[evIndex] = _eventi[evIndex].copyWith(copertinaUrl: newCopertinaUrl);
    }
    invalidateCache();

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/eventi/copertina'),
              headers: defaultHeaders,
              body: jsonEncode({
                'eventoId': eventoId,
                'copertinaUrl': newCopertinaUrl,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) return;
      } catch (_) {}
    }
  }

  Future<BonusMalus> proponiBonusMalusPerEvento(
    String eventoId,
    BonusMalus nuovoBonus, {
    bool awardXp = true,
  }) async {
    final int safePunti = nuovoBonus.punti.clamp(-100, 100);
    nuovoBonus = nuovoBonus.copyWith(punti: safePunti == 0 ? 10 : safePunti);
    final rawAuthor = (_currentUser?.nickname.isNotEmpty == true
            ? _currentUser!.nickname
            : (nuovoBonus.propostoDa.trim().isNotEmpty
                ? nuovoBonus.propostoDa.trim()
                : (_currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud')))
        .trim();
    final String curUserNick = resolveNickname(rawAuthor);

    final Evento evMatch = _eventi.firstWhere(
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

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
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
                'awardXp': awardXp,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final resData = jsonDecode(res.body) as Map<String, dynamic>;
          final insertedBmId = resData['id']?.toString() ?? '';
          final finalBonus = nuovoBonus.copyWith(
            id: insertedBmId.isNotEmpty ? insertedBmId : nuovoBonus.id,
            eventoId: eventoId,
          );
          if (finalBonus.approvato || finalBonus.stato == 'approvato') {
            _bonusMalusList.removeWhere((b) => b.id == finalBonus.id);
            _bonusMalusList.insert(0, finalBonus);
          }

          final numParticipants = evMatch.partecipanti.length >= 2 ? evMatch.partecipanti.length : 2;
          final int quorum = (numParticipants / 2).floor() + 1;
          final newVotazione = Votazione(
            id: finalBonus.id,
            titolo: nuovoBonus.titolo,
            descrizione: nuovoBonus.descrizione.isNotEmpty ? nuovoBonus.descrizione : 'Proposta da $curUserNick',
            bonusMalus: finalBonus,
            votiFavorevoli: 1,
            votiContrari: 0,
            quorum: quorum,
            stato: 'in_corso',
            scadenza: DateTime.now().add(const Duration(days: 7)),
            votiUtenti: {
              curUserNick: 'pro',
              curUserNick.toLowerCase(): 'pro',
            },
            nomeOrganizzatore: evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa,
          );
          _votazioniList.removeWhere((v) => v.id == newVotazione.id);
          _votazioniList.insert(0, newVotazione);

          final evIdx = _eventi.indexWhere((e) => e.id == eventoId || e.titolo.toLowerCase() == eventoId.toLowerCase());
          if (evIdx != -1) {
            final ev = _eventi[evIdx];
            final votAttive = [
              newVotazione,
              ...ev.votazioniAttive.where((v) => v.id != newVotazione.id && v.titolo != newVotazione.titolo),
            ];
            _eventi[evIdx] = ev.copyWith(votazioniAttive: votAttive);
          }

          if (_currentUser != null && awardXp) {
            final prog = XpProgression.aggiungiXp(
              livelloAttuale: _currentUser!.livello,
              xpLivelloAttuale: _currentUser!.xp,
              deltaXp: 50,
              xpTotaliAttuali: _currentUser!.xpTotali,
            );
            final logVoce = formattaVoceStorico(
              'Proposto ${nuovoBonus.isBonus ? "Bonus" : "Malus"} "${nuovoBonus.titolo}" (+50 XP)',
            );
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
            await _saveSession(_currentUser!);
          }

          invalidateCache();

          final List<String> allCandidates = [
            ...evMatch.partecipanti,
            ...evMatch.invitati,
            evMatch.propostoDa,
            evMatch.creatore,
          ];
          final Set<String> uniqueDests = {};
          final rawBackendDests =
              (resData['destinatari'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
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
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                uniqueDests.toList(),
                titolo: '⚡ Nuova Regola Proposta: ${nuovoBonus.titolo}',
                messaggio:
                    '$curUserNick ha proposto "${nuovoBonus.titolo}" (${nuovoBonus.punti >= 0 ? "+${nuovoBonus.punti}" : nuovoBonus.punti} PT) in "$realEvTitolo". Entra a votare!',
                data: {
                  'tipo': 'votazione',
                  'eventoId': eventoId,
                  'bonusId': insertedBmId.isNotEmpty ? insertedBmId : nuovoBonus.id,
                },
              ),
            );
          }

          return finalBonus;
        } else if (res.statusCode == 400) {
          final resData = jsonDecode(res.body) as Map<String, dynamic>;
          if (resData['error'] != null) {
            throw Exception(resData['error'].toString());
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('esiste già')) rethrow;
      }
    }

    throw Exception('Impossibile inviare la proposta. Controlla la connessione internet e riprova.');
  }

  Future<void> eliminaBonusMalus(String bonusMalusId) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/bonusmalus/elimina'),
              headers: defaultHeaders,
              body: jsonEncode({'bonusId': bonusMalusId, 'id': bonusMalusId}),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) break;
      } catch (_) {}
    }

    _bonusMalusList.removeWhere((b) => b.id == bonusMalusId || b.titolo.contains(bonusMalusId));
    _votazioniList.removeWhere(
      (v) =>
          v.id == bonusMalusId ||
          (v.bonusMalus != null && v.bonusMalus!.id == bonusMalusId) ||
          v.titolo.contains(bonusMalusId),
    );

    for (int i = 0; i < _eventi.length; i++) {
      final ev = _eventi[i];
      final vAggiornate = ev.votazioniAttive
          .where(
            (v) =>
                v.id != bonusMalusId &&
                (v.bonusMalus == null || v.bonusMalus!.id != bonusMalusId) &&
                !v.titolo.contains(bonusMalusId),
          )
          .toList();
      _eventi[i] = ev.copyWith(votazioniAttive: vAggiornate);
    }
  }

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
    final mittente = resolveNickname(rawMittente);
    final cleanDest = utenteDestinatario.trim().toLowerCase();
    final ptStr = punti >= 0 ? '+$punti' : '$punti';

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
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
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          for (int i = 0; i < _bonusMalusList.length; i++) {
            if (_bonusMalusList[i].id == bonusId ||
                _bonusMalusList[i].titolo.toLowerCase() == bonusTitolo.toLowerCase()) {
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

          unawaited(
            PushNotificationService.instance.inviaPushAUtenti(
              [utenteDestinatario],
              titolo: notificaTitolo,
              messaggio: 'Hai ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
              data: {
                'tipo': notificaTipo,
                'eventoId': eventoId,
              },
            ),
          );

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
          final cleanDestUser = resolveNickname(utenteDestinatario);
          final altriPartecipanti = destList.where((d) => !isSamePerson(d, cleanDestUser)).toList();
          if (altriPartecipanti.isNotEmpty) {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                altriPartecipanti,
                titolo: notificaTitolo,
                messaggio: '$cleanDestUser ha ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
                data: {
                  'tipo': notificaTipo,
                  'eventoId': eventoId,
                },
              ),
            );
          }

          return;
        } else if (res.statusCode == 400) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          throw Exception(data['error']?.toString() ?? 'Impossibile assegnare il punteggio.');
        }
      } catch (e) {
        if (e is Exception &&
            (e.toString().contains('disponibile solo') ||
                e.toString().contains('è concluso') ||
                e.toString().contains('Impossibile assegnare'))) {
          rethrow;
        }
      }
    }
  }

  Future<void> segnaNotificheComeLette(String nickname) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/notifiche/segna-tutte-lette'),
              headers: defaultHeaders,
              body: jsonEncode({'destinatario': resolveNickname(nickname)}),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) return;
      } catch (_) {}
    }
  }

  Future<void> segnaSingolaNotificaComeLetta(String notificaId) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/notifiche/segna-letta'),
              headers: defaultHeaders,
              body: jsonEncode({'notificaId': notificaId}),
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> eliminaNotifica(String notificaId) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/notifiche/elimina'),
              headers: defaultHeaders,
              body: jsonEncode({'notificaId': notificaId}),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) return;
      } catch (_) {}
    }
  }

  Future<void> eliminaNotificheMultiple(List<String> notificaIds) async {
    if (notificaIds.isEmpty) return;
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/notifiche/elimina-multiple'),
              headers: defaultHeaders,
              body: jsonEncode({'notificaIds': notificaIds}),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) return;
      } catch (_) {}
    }
  }

  Future<void> eliminaTutteNotifiche({required String destinatario, bool soloLette = false}) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/notifiche/elimina-tutte'),
              headers: defaultHeaders,
              body: jsonEncode({
                'destinatario': resolveNickname(destinatario),
                'soloLette': soloLette,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) return;
      } catch (_) {}
    }
  }

  Future<List<BonusMalus>> getBonusMalusList() async {
    await getVotazioni();
    return List.unmodifiable(_bonusMalusList);
  }

  Future<List<Votazione>> getVotazioni() async {
    for (String url in baseUrls) {
      try {
        final resBm = await http
            .get(
              Uri.parse('$url/bonusmalus'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));

        final resVot = await http
            .get(
              Uri.parse('$url/votazioni'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));

        if (resBm.statusCode == 200 &&
            resVot.statusCode == 200 &&
            !resBm.body.contains('<html>') &&
            !resVot.body.contains('<html>')) {
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

    return List.unmodifiable(_votazioniList);
  }

  Future<Votazione> vota(String idOrEventoId, bool aFavore) async {
    final rawUserNick = (_currentUser?.nickname.isNotEmpty == true
            ? _currentUser!.nickname
            : (_currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud'))
        .trim();
    final userNick = resolveNickname(rawUserNick);

    int index = _votazioniList.indexWhere(
      (v) =>
          v.id == idOrEventoId ||
          v.bonusMalus?.id == idOrEventoId ||
          (v.bonusMalus != null && v.bonusMalus!.titolo.toLowerCase() == idOrEventoId.toLowerCase()) ||
          v.titolo.toLowerCase().contains(idOrEventoId.toLowerCase()),
    );

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
        votiUtenti: {userNick: aFavore ? 'pro' : 'contro'},
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
      final normUser = resolveNickname(key).trim().toLowerCase();
      if (!countedUsers.contains(normUser)) {
        countedUsers.add(normUser);
        if (vote == 'pro') fav++;
        if (vote == 'contro') cont++;
      }
    });

    final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
    final evMatch = _eventi.firstWhere(
      (e) => evId.isNotEmpty && (e.id.trim().toLowerCase() == evId || e.titolo.trim().toLowerCase() == evId),
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

    final int numPartecipanti = evMatch.partecipanti.length >= 2 ? evMatch.partecipanti.length : 3;
    final int quorumCalcolato = (numPartecipanti / 2).floor() + 1;
    final int totalVotiEspressi = fav + cont;

    bool isApprovato = (fav >= quorumCalcolato);
    bool isRespinto = (cont >= quorumCalcolato);
    bool paritaDecisaDaOrganizzatore = false;
    final rawNomeOrg = evMatch.creatore.isNotEmpty
        ? evMatch.creatore
        : (evMatch.propostoDa.isNotEmpty ? evMatch.propostoDa : (v.nomeOrganizzatore ?? ''));
    final nomeOrganizzatore = resolveNickname(rawNomeOrg);

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

    final String nuovoStato = isApprovato ? 'approvato' : (isRespinto ? 'respinto' : 'in_corso');
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

    final targetBmId = v.bonusMalus?.id ?? v.id;
    final targetBmTitle = v.bonusMalus?.titolo ?? v.titolo;
    final targetEvId = (v.bonusMalus?.eventoId != null && v.bonusMalus!.eventoId.isNotEmpty)
        ? v.bonusMalus!.eventoId
        : idOrEventoId;

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/votazioni/vota'),
              headers: defaultHeaders,
              body: jsonEncode({
                'id': targetBmId,
                'votazioneId': targetBmId,
                'bonusId': targetBmId,
                'aFavore': aFavore,
                'voto': aFavore ? 'pro' : 'contro',
                'utente': userNick,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          break;
        }
      } catch (_) {}
    }

    if (nuovoStato == 'approvato') {
      final Set<String> allParticipants = {};
      if (evMatch.id.isNotEmpty) {
        allParticipants.addAll(evMatch.partecipanti);
        allParticipants.addAll(evMatch.invitati);
      }
      if (allParticipants.isNotEmpty) {
        unawaited(
          PushNotificationService.instance.inviaPushAUtenti(
            allParticipants.toList(),
            titolo: '🎉 Nuova Regola Approvata: $targetBmTitle',
            messaggio: 'La regola "$targetBmTitle" ha raggiunto il quorum ed è ora attiva nel catalogo!',
            data: {
              'tipo': 'bonus_approvato',
              'eventoId': targetEvId,
              'bonusId': targetBmId,
            },
          ),
        );
      }
    }

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
      await _saveSession(_currentUser!);
    }

    return _votazioniList.firstWhere(
      (item) =>
          item.id == v.id ||
          (v.bonusMalus != null && item.bonusMalus?.id == v.bonusMalus!.id) ||
          item.titolo.toLowerCase() == v.titolo.toLowerCase(),
      orElse: () => votazioneAggiornata,
    );
  }

  Future<void> annullaAssegnazioneBonus({
    required String eventoId,
    required String bonusId,
    required String utenteDestinatario,
    required int punti,
  }) async {
    invalidateCache();
    final cleanDest = utenteDestinatario.trim().toLowerCase();

    for (var bm in _bonusMalusList) {
      if (bm.id == bonusId || bm.titolo.toLowerCase() == bonusId.toLowerCase()) {
        final bool isVarCat =
            bm.categoria.toUpperCase() == 'VAR' || bm.titolo.contains('VAR') || bm.titolo.contains('Falsa Testimonianza');
        if (isVarCat) {
          throw Exception('Non è possibile stornare un bonus/malus o sanzione assegnata tramite sentenza VAR.');
        }
      }
    }

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/bonusmalus/annulla-assegnazione'),
              headers: defaultHeaders,
              body: jsonEncode({
                'eventoId': eventoId,
                'bonusId': bonusId,
                'utenteDestinatario': utenteDestinatario,
                'punti': punti,
              }),
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          for (int i = 0; i < _bonusMalusList.length; i++) {
            if (_bonusMalusList[i].id == bonusId ||
                _bonusMalusList[i].titolo.toLowerCase() == bonusId.toLowerCase()) {
              final List<String> list = List.from(_bonusMalusList[i].assegnatoA);
              final idx = list.indexWhere((u) => u.trim().toLowerCase() == cleanDest);
              if (idx != -1) {
                list.removeAt(idx);
              }
              _bonusMalusList[i] = _bonusMalusList[i].copyWith(assegnatoA: list);
            }
          }
          return;
        } else {
          final data = jsonDecode(res.body);
          if (data is Map && data['error'] != null) {
            throw Exception(data['error'].toString());
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('VAR')) rethrow;
      }
    }
  }

  // --- SISTEMA DI GESTIONE AMICIZIE ---
  Future<void> inviaRichiestaAmicizia(String codiceAmico) async {
    final cleanCode = codiceAmico.trim().toUpperCase();
    final curUser = _currentUser;
    if (curUser == null) throw Exception('Utente non autenticato');
    if (cleanCode == curUser.codiceAmico.toUpperCase()) {
      throw Exception('Non puoi inviare una richiesta di amicizia a te stesso!');
    }

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/amicizia/richiedi'),
              headers: defaultHeaders,
              body: jsonEncode({
                'mittente': curUser.nickname,
                'codiceAmico': cleanCode,
              }),
            )
            .timeout(const Duration(seconds: 8));

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (res.statusCode == 200) {
          final targetNick = (data['targetNickname'] ?? '').toString();
          if (targetNick.isNotEmpty) {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                [targetNick],
                titolo: '👥 Nuova Richiesta di Amicizia',
                messaggio: '${curUser.nickname} vuole aggiungerti agli amici!',
                data: {'tipo': 'amicizia'},
              ),
            );
          }
          return;
        } else if (data['error'] != null) {
          throw Exception(data['error'].toString());
        }
      } catch (e) {
        if (e is Exception &&
            (e.toString().contains('Nessun utente trovato') ||
                e.toString().contains('Siete già amici') ||
                e.toString().contains('a te stesso'))) {
          rethrow;
        }
      }
    }

    throw Exception('Impossibile inviare la richiesta di amicizia. Verifica la connessione.');
  }

  Future<void> rispondiRichiestaAmicizia(String notificaId, String mittente, bool accetta) async {
    final curUser = _currentUser;
    if (curUser == null) return;

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/amicizia/rispondi'),
              headers: defaultHeaders,
              body: jsonEncode({
                'notificaId': notificaId,
                'mittente': mittente,
                'destinatario': curUser.nickname,
                'accetta': accetta,
              }),
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          if (accetta) {
            final updatedAmici = List<String>.from(curUser.amici);
            if (!updatedAmici.any((a) => isSamePerson(a, mittente))) {
              updatedAmici.add(resolveNickname(mittente));
              _currentUser = _currentUser!.copyWith(amici: updatedAmici);
              await _saveSession(_currentUser!);
            }
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                [mittente],
                titolo: '👥 Richiesta di Amicizia Accettata!',
                messaggio: '${curUser.nickname} ha accettato la tua richiesta di amicizia! Ora siete amici.',
                data: {'tipo': 'amicizia'},
              ),
            );
          }
          return;
        }
      } catch (_) {}
    }
  }

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

  Future<String?> verificaEventoAttivoInComune(String targetNick) async {
    final curUser = _currentUser;
    if (curUser == null) return null;
    final curNick = curUser.nickname.isNotEmpty ? curUser.nickname : curUser.nome;
    final cleanTarget = targetNick.trim();
    if (cleanTarget.isEmpty) return null;

    List<Evento> listaEventi = _eventi;
    if (listaEventi.isEmpty) {
      try {
        listaEventi = await getEventi(forceRefresh: true);
      } catch (_) {}
    }

    final now = DateTime.now();
    for (final ev in listaEventi) {
      if (ev.isConcluso || ev.isAnnullato) continue;

      bool isUserInEv(String candidate) {
        if (isSamePerson(ev.creatore, candidate)) return true;
        if (ev.partecipanti.any((p) => isSamePerson(p, candidate))) return true;
        if (!now.isAfter(ev.data) && ev.invitati.any((i) => isSamePerson(i, candidate))) return true;
        return false;
      }

      if (isUserInEv(curNick) && isUserInEv(cleanTarget)) {
        return ev.titolo.isNotEmpty ? ev.titolo : 'Evento';
      }
    }
    return null;
  }

  Future<bool> bloccaUtente(String targetNick) async {
    final curUser = _currentUser;
    if (curUser == null) return false;
    final curNick = curUser.nickname.isNotEmpty ? curUser.nickname : curUser.nome;
    final cleanTarget = targetNick.trim();

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/blocca'),
              headers: defaultHeaders,
              body: jsonEncode({
                'utente': curNick,
                'target': cleanTarget,
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final currentBloccati = List<String>.from(curUser.utentiBloccati);
          if (!currentBloccati.any((b) => b.toLowerCase() == cleanTarget.toLowerCase())) {
            currentBloccati.add(cleanTarget);
          }
          final currentAmici = List<String>.from(curUser.amici);
          currentAmici.removeWhere((a) => a.toLowerCase() == cleanTarget.toLowerCase());
          _currentUser = curUser.copyWith(utentiBloccati: currentBloccati, amici: currentAmici);
          await _saveSession(_currentUser!);

          unawaited(
            PushNotificationService.instance.inviaPushAUtenti(
              [cleanTarget],
              titolo: '🚫 Sei stato bloccato',
              messaggio:
                  '$curNick ti ha bloccato. Momentaneamente non siete più amici fino a quando $curNick non ti sbloccherà.',
              data: {'tipo': 'blocco_utente'},
            ),
          );
          return true;
        } else if (res.statusCode == 409 || (res.statusCode >= 400 && res.statusCode < 500)) {
          final data = jsonDecode(res.body);
          if (data is Map && data['error'] != null) {
            throw Exception(data['error'].toString());
          }
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('nello stesso evento')) {
          rethrow;
        }
      }
    }

    return false;
  }

  Future<bool> sbloccaUtente(String targetNick) async {
    final curUser = _currentUser;
    if (curUser == null) return false;
    final curNick = curUser.nickname.isNotEmpty ? curUser.nickname : curUser.nome;
    final cleanTarget = targetNick.trim();

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/utenti/sblocca'),
              headers: defaultHeaders,
              body: jsonEncode({
                'utente': curNick,
                'target': cleanTarget,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final currentBloccati = List<String>.from(curUser.utentiBloccati);
          currentBloccati.removeWhere((b) => b.toLowerCase() == cleanTarget.toLowerCase());
          final currentAmici = List<String>.from(curUser.amici);
          if (!currentAmici.any((a) => a.toLowerCase() == cleanTarget.toLowerCase())) {
            currentAmici.add(cleanTarget);
          }
          _currentUser = curUser.copyWith(utentiBloccati: currentBloccati, amici: currentAmici);
          await _saveSession(_currentUser!);

          unawaited(
            PushNotificationService.instance.inviaPushAUtenti(
              [cleanTarget],
              titolo: '🤝 Sei stato sbloccato',
              messaggio: '$curNick ti ha sbloccato. Siete di nuovo amici!',
              data: {'tipo': 'sblocco_utente'},
            ),
          );
          return true;
        }
      } catch (_) {}
    }

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
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await http
              .post(
                Uri.parse('$url/segnalazioni/crea'),
                headers: defaultHeaders,
                body: jsonEncode({
                  'segnalatore': curNick,
                  'segnalato': segnalato,
                  'motivo': motivo,
                  'dettagli': dettagli,
                }),
              )
              .timeout(const Duration(seconds: 12));
          if (res.statusCode == 200) {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                ['Cloud'],
                titolo: '🛡️ Nuova Segnalazione Community',
                messaggio: '@$curNick ha segnalato @$segnalato per "$motivo". Apri il Centro Moderazione nel tuo Profilo.',
                data: {'tipo': 'segnalazione_utente'},
              ),
            );
            return true;
          }
          if (res.statusCode >= 500 && attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 700));
            continue;
          }
          break;
        } catch (_) {
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 700));
            continue;
          }
        }
      }
    }

    return false;
  }

  Future<List<Map<String, dynamic>>> getSegnalazioni() async {
    final curUser = _currentUser;
    final curNick = (curUser?.nickname.isNotEmpty == true ? curUser!.nickname : curUser?.nome) ?? 'Cloud';

    for (String url in baseUrls) {
      try {
        final res = await http
            .get(
              Uri.parse('$url/segnalazioni?utente=${Uri.encodeComponent(curNick)}'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final List<dynamic> listJson = jsonDecode(res.body);
          return listJson.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }

    return [];
  }

  bool haAmmonizioneAttiva(String targetNick, List<Map<String, dynamic>> segnalazioni, {String? excludeId}) {
    for (var item in segnalazioni) {
      if (excludeId != null && item['id'] == excludeId) continue;
      final itemTarget = (item['segnalato'] ?? '').toString();
      if (!isSamePerson(itemTarget, targetNick)) continue;
      final st = (item['stato'] ?? '').toString().toLowerCase();
      if (st == 'bannato' || st == 'riabilitato') {
        return false;
      }
      if (st == 'ammonito') {
        if (item['ammonizioneScontata'] == true) return false;
        return true;
      }
    }
    for (var item in segnalazioni) {
      if (isSamePerson((item['segnalato'] ?? '').toString(), targetNick)) {
        return item['giaAmmonito'] == true;
      }
    }
    return false;
  }

  Future<bool> gestisciSegnalazione({
    required String segnalazioneId,
    required String azione, // 'ammonisci' | 'banna_seconda_ammonizione' | 'banna' | 'sbanna' | 'archivia' | 'elimina'
    required String segnalato,
  }) async {
    final cleanTarget = resolveNickname(segnalato);
    final bool isSecondaAmmonizione = azione == 'banna_seconda_ammonizione';
    final String serverAzione = isSecondaAmmonizione ? 'banna' : azione;

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/segnalazioni/gestisci'),
              headers: defaultHeaders,
              body: jsonEncode({
                'segnalazioneId': segnalazioneId,
                'azione': serverAzione,
                'segnalato': cleanTarget,
                'secondaAmmonizione': isSecondaAmmonizione,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          if (azione == 'ammonisci') {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                [cleanTarget],
                titolo: '⚠️ Richiamo Ufficiale di Moderazione (1/2)',
                messaggio:
                    'Sei stato ammonito dall\'Amministrazione per comportamenti non conformi al regolamento di FantaEventi. Attenzione: alla prossima ammonizione il tuo account verrà automaticamente sospeso.',
                data: {'tipo': 'ammonizione_utente'},
              ),
            );
          } else if (azione == 'banna' || isSecondaAmmonizione) {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                [cleanTarget],
                titolo: isSecondaAmmonizione ? '⛔ Account Sospeso (2ª Ammonizione)' : '⛔ Account Sospeso',
                messaggio: isSecondaAmmonizione
                    ? 'Hai ricevuto una seconda ammonizione ufficiale dall\'Amministrazione. Per somma di ammonizioni il tuo account su FantaEventi è stato sospeso.'
                    : 'Il tuo account è stato sospeso dall\'Amministrazione per violazione del regolamento della community di FantaEventi.',
                data: {'tipo': 'ban_utente'},
              ),
            );
          } else if (azione == 'sbanna' || azione == 'riabilita') {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                [cleanTarget],
                titolo: '✅ Account Riabilitato',
                messaggio:
                    'La sospensione del tuo account è stata revocata dall\'Amministrazione. Puoi tornare a utilizzare FantaEventi!',
                data: {'tipo': 'riabilita_utente'},
              ),
            );
          }
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  // ==========================================
  // SEZIONE VAR (VERIFICA ASSISTITA DA REGIA)
  // ==========================================

  Future<String?> inviaRichiestaVar({
    required String eventoId,
    required String eventoTitolo,
    required String tipo,
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
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/var/crea'),
              headers: defaultHeaders,
              body: jsonEncode({
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
                'giudice': giudice,
                'penalitaPunti': penalitaPunti,
              }),
            )
            .timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final varId = (data['varId'] ?? data['id'] ?? '').toString();
          final ptSign = punti >= 0 ? '+$punti' : '$punti';
          final msgGiudice = tipo == 'bonus'
              ? '$richiedente ha richiesto la verifica VAR per il bonus "$bonusMalusTitolo" ($ptSign PT).'
              : '$richiedente ha denunciato $bersaglio al VAR per il malus "$bonusMalusTitolo" ($ptSign PT).';

          unawaited(
            PushNotificationService.instance.inviaPushAUtenti(
              [giudice],
              titolo: '📺 VAR: Richiesta da Esaminare!',
              messaggio: msgGiudice,
              data: {'tipo': 'var_richiesta_giudice', 'eventoId': eventoId, 'varId': varId},
            ),
          );
          if (testimoni.isNotEmpty) {
            unawaited(
              PushNotificationService.instance.inviaPushAUtenti(
                testimoni,
                titolo: '👀 Chiamata a Testimoniare al VAR',
                messaggio:
                    '$richiedente ti ha indicato come testimone per "$bonusMalusTitolo". Confermi l\'accaduto?',
                data: {'tipo': 'var_testimone', 'eventoId': eventoId, 'varId': varId},
              ),
            );
          }
          invalidateCache();
          return varId;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<RichiestaVar?> getRichiestaVar(String id) async {
    if (id.isEmpty) return null;

    for (String url in baseUrls) {
      try {
        final res = await http
            .get(
              Uri.parse('$url/var/dettaglio?id=${Uri.encodeComponent(id)}'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          return RichiestaVar.fromJson(data);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<RichiestaVar>> getRichiesteVarEvento(String eventoId) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .get(
              Uri.parse('$url/var/evento?eventoId=${Uri.encodeComponent(eventoId)}'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final List<dynamic> list = jsonDecode(res.body);
          return list.map((d) => RichiestaVar.fromJson(Map<String, dynamic>.from(d as Map))).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  Future<List<RichiestaVar>> getRichiesteVarInSospesoPerGiudice(String giudiceNick) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .get(
              Uri.parse('$url/var/giudice?giudice=${Uri.encodeComponent(giudiceNick)}'),
              headers: defaultHeaders,
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && !res.body.contains('<html>')) {
          final List<dynamic> list = jsonDecode(res.body);
          return list.map((d) => RichiestaVar.fromJson(Map<String, dynamic>.from(d as Map))).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  Future<bool> votaTestimonianzaVar({
    required String varId,
    required String testimoneNick,
    required bool conferma,
  }) async {
    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/var/vota-testimone'),
              headers: defaultHeaders,
              body: jsonEncode({
                'varId': varId,
                'testimone': testimoneNick,
                'testimoneNick': testimoneNick,
                'conferma': conferma,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          invalidateCache();
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<bool> decidiRichiestaVar({
    required String varId,
    required String giudiceNick,
    required bool approva,
    bool sanzionaFalsaTestimonianza = false,
  }) async {
    invalidateCache();

    for (String url in baseUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$url/var/decidi'),
              headers: defaultHeaders,
              body: jsonEncode({
                'varId': varId,
                'giudice': giudiceNick,
                'giudiceNick': giudiceNick,
                'approva': approva,
                'sanzionaFalsaTestimonianza': sanzionaFalsaTestimonianza,
              }),
            )
            .timeout(const Duration(seconds: 10));

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

          if (approva) {
            final cleanBersaglio = resolveNickname(bersaglio);
            final cleanRichiedente = resolveNickname(richiedente);
            final bool isBonus = punti >= 0;
            final String notificaTitolo = isBonus ? '🏆 Bonus Assegnato!' : '💀 Malus Assegnato!';
            final String ptSign = punti >= 0 ? '+$punti' : '$punti';

            if (cleanRichiedente.isNotEmpty) {
              unawaited(
                PushNotificationService.instance.inviaPushAUtenti(
                  [cleanRichiedente],
                  titolo: '📺 VAR: Richiesta Approvata! ✅',
                  messaggio: 'Il Giudice ha convalidato la tua segnalazione per "$bmTitolo". I punti sono stati assegnati.',
                  data: {'tipo': 'var_esito', 'eventoId': evId, 'varId': varId},
                ),
              );
            }

            if (cleanBersaglio.isNotEmpty) {
              unawaited(
                PushNotificationService.instance.inviaPushAUtenti(
                  [cleanBersaglio],
                  titolo: notificaTitolo,
                  messaggio: 'Hai ricevuto "$bmTitolo" ($ptSign PT) per l\'evento "$evTitolo"!',
                  data: {
                    'tipo': isBonus ? 'assegnazione_bonus' : 'assegnazione_malus',
                    'eventoId': evId,
                    'varId': varId,
                  },
                ),
              );
            }

            final otherDests = broadcastDests.where((d) => !isSamePerson(d, cleanBersaglio)).toList();
            if (otherDests.isNotEmpty) {
              unawaited(
                PushNotificationService.instance.inviaPushAUtenti(
                  otherDests,
                  titolo: notificaTitolo,
                  messaggio: '$cleanBersaglio ha ricevuto "$bmTitolo" ($ptSign PT) per l\'evento "$evTitolo"!',
                  data: {
                    'tipo': isBonus ? 'assegnazione_bonus' : 'assegnazione_malus',
                    'eventoId': evId,
                    'varId': varId,
                  },
                ),
              );
            }
          } else {
            if (richiedente.isNotEmpty) {
              unawaited(
                PushNotificationService.instance.inviaPushAUtenti(
                  [richiedente],
                  titolo: isSanzionato
                      ? '🚨 VAR: Denuncia Respinta e Sanzionata! ❌'
                      : '📺 VAR: Segnalazione Respinta ❌',
                  messaggio: isSanzionato
                      ? 'La tua denuncia per "$bmTitolo" è stata respinta come infondata. Sanzione applicata!'
                      : 'La verifica per "$bmTitolo" non è stata convalidata dal Giudice.',
                  data: {'tipo': 'var_esito', 'eventoId': evId, 'varId': varId},
                ),
              );
            }

            if (bersaglio.isNotEmpty && !isSamePerson(bersaglio, richiedente)) {
              unawaited(
                PushNotificationService.instance.inviaPushAUtenti(
                  [bersaglio],
                  titolo: '📺 VAR: Segnalazione Respinta',
                  messaggio:
                      'La segnalazione contro di te per "$bmTitolo" è stata esaminata e respinta dal Giudice.',
                  data: {'tipo': 'var_esito', 'eventoId': evId, 'varId': varId},
                ),
              );
            }
          }

          invalidateCache();
          return true;
        } else if (res.statusCode == 400 && res.body.contains('già stata decisa')) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }
}
