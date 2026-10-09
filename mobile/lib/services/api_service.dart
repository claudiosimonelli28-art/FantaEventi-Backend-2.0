import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../models/utente.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../models/votazione.dart';
import '../models/richiesta_var.dart';

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
      // Gli elementi senza data valida (legacy) vengono scartati per non mostrare elementi di settimane/mesi fa
    }
    return result;
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static String get _mongoUri {
    const envUri = String.fromEnvironment('MONGODB_URI');
    if (envUri.isNotEmpty) return envUri;
    return utf8.decode(base64.decode(
        'bW9uZ29kYitzcnY6Ly9Mb3JlbnpvOmNsYXVkaW9zaW1vbmVsbGlAY2x1c3RlcjAuemJicWZjci5tb25nb2RiLm5ldC9GYW50YUV2ZW50aT9yZXRyeVdyaXRlcz10cnVlJnc9bWFqb3JpdHkmYXBwTmFtZT1DbHVzdGVyMA=='));
  }


  static String get _brevoKey {
    const envKey = String.fromEnvironment('BREVO_API_KEY');
    if (envKey.isNotEmpty) return envKey;
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
      await newDb.open().timeout(const Duration(seconds: 8));
      _db = newDb;
      completer.complete(_db);
      return _db;
    } catch (_) {
      try {
        final newDb = await Db.create(_mongoUri);
        await newDb.open().timeout(const Duration(seconds: 10));
        _db = newDb;
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
    Db? db = await _getMongoDb();
    if (db == null || !db.isConnected) {
      markMongoDbDisconnected();
      db = await _getMongoDb();
    }
    return db;
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
  static const Duration _cacheDuration = Duration(seconds: 3);

  void invalidateCache() {
    _lastFetchTime = null;
  }

  void clearUserSessionCache() {
    _lastFetchTime = null;
    _cachedTutorialPremioRiscattato = null;
    _eventi.clear();
    _bonusMalusList.clear();
    _votazioniList.clear();
    _utenti.clear();
    _richiesteVar.clear();
  }

  Utente? get currentUser => _currentUser;
  List<Evento> get eventi => List.unmodifiable(_eventi);

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

  Future<void> logout() async {
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
        _rememberMeSession = true;
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
        
        final newXp = shouldActuallyAward ? (curUser.xp + 100) : curUser.xp;
        _currentUser = curUser.copyWith(
          haVistoGuida: true,
          xp: newXp,
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
            .addToSet('badgeList', badge);

          if (shouldActuallyAward) {
            mod = mod.inc('xp', 100);
          }

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

    // 1. Prova PRIMA la connessione DIRETTA a MongoDB Atlas (Istantanea <30ms)
    try {
      final db = await _getMongoDb().timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList().timeout(const Duration(seconds: 4));
        bool casingMismatch = false;
        String suggestedCasing = '';

        for (var d in docs) {
          final actualUsername = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim();
          final actualEmail = (d['email'] ?? '').toString().trim();
          final isClaudioAlias = (cleanIdentifierLower == 'claudio' && (actualUsername.toLowerCase() == 'cloud' || actualEmail.toLowerCase().contains('claudio.simonelli')));

          bool isMatch = false;

          if (isEmailLogin) {
            // Accesso con Email: case-insensitive
            if (actualEmail.toLowerCase() == cleanIdentifierLower) {
              isMatch = true;
            }
          } else {
            // Accesso con Nickname: case-sensitive esatto!
            if (actualUsername == rawIdentifier || isClaudioAlias) {
              isMatch = true;
            } else if (actualUsername.toLowerCase() == cleanIdentifierLower) {
              casingMismatch = true;
              suggestedCasing = actualUsername;
            }
          }

          if (isMatch) {
            final existingPasswordHash = (d['password'] ?? d['passwordHash'] ?? '').toString().trim();

            // Riconoscimento al primo accesso: utente esistente ma senza password impostata
            if (existingPasswordHash.isEmpty) {
              throw NeedsPasswordSetupException(
                username: actualUsername,
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

            final jsonMap = {
              'id': d['_id']?.toHexString() ?? d['_id']?.toString() ?? '',
              'nome': actualUsername,
              'username': actualUsername,
              'nickname': actualUsername,
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
            };
            _currentUser = Utente.fromJson(jsonMap);
            clearUserSessionCache();
            await _saveSession(_currentUser!, rememberMe: rememberMe);
            return _currentUser!;
          }
        }

        if (casingMismatch) {
          throw Exception('Attenzione alle maiuscole/minuscole! Il tuo nome utente è registrato come "$suggestedCasing".');
        }

        throw Exception(
          isEmailLogin
              ? 'Nessun utente trovato con l\'email "$rawIdentifier". Registrati prima di accedere!'
              : 'Nessun utente trovato con il nickname "$rawIdentifier". Registrati prima di accedere!',
        );
      }
    } catch (e) {
      markMongoDbDisconnected();
      if (e is NeedsPasswordSetupException) rethrow;
      if (e is Exception && (e.toString().contains('Nessun utente trovato') || e.toString().contains('Password non corretta') || e.toString().contains('Inserisci la password') || e.toString().contains('Attenzione alle maiuscole/minuscole'))) {
        rethrow;
      }
    }

    String? lastError;

    // 2. Fallback HTTP su backend Render
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
        ).timeout(const Duration(seconds: 4));

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
          clearUserSessionCache();
          await _saveSession(_currentUser!, rememberMe: rememberMe);
          return _currentUser!;
        } else if (response.statusCode == 403 || response.statusCode == 401) {
          throw Exception(data['error']?.toString() ?? 'Password non corretta. Riprova!');
        } else if (response.statusCode == 404 || data['notFound'] == true) {
          throw Exception('Nessun utente trovato nel database per "$cleanIdentifier". Registrati prima di accedere!');
        } else if (data.containsKey('error')) {
          lastError = data['error'].toString();
        }
      } catch (e) {
        if (e is NeedsPasswordSetupException) rethrow;
        if (e is Exception && (e.toString().contains('Nessun utente trovato') || e.toString().contains('Password non corretta') || e.toString().contains('Inserisci la password'))) {
          rethrow;
        }
        lastError = 'Connessione al server non disponibile o server in riavvio. Riprova tra pochi istanti! 🔄';
      }
    }

    throw Exception(lastError ?? 'Nessun utente trovato con questo Nickname o Email nel database.');
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
          final uName = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim().toLowerCase();
          final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
          final isClaudioAlias = (cleanUser == 'claudio' && (uName == 'cloud' || uEmail.contains('claudio.simonelli')));
          if (uName == cleanUser || uEmail == cleanUser || isClaudioAlias) {
            ObjectId? objId;
            try {
              objId = d['_id'] is ObjectId ? d['_id'] as ObjectId : ObjectId.fromHexString(d['_id'].toString());
            } catch (_) {}
            final selector = objId != null ? where.id(objId) : where.eq('_id', d['_id']);

            await db.collection('Utenti').update(
              selector,
              modify.set('password', hashedPassword).set('passwordHash', hashedPassword),
            );

            final actualUsername = (d['nome'] ?? d['username'] ?? d['nickname'] ?? 'Utente').toString();
            final actualEmail = (d['email'] ?? '').toString();

            final jsonMap = {
              'id': objId?.toHexString() ?? d['_id']?.toString() ?? '',
              'nome': actualUsername,
              'username': actualUsername,
              'nickname': actualUsername,
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

    try {
      final db = await _getMongoDb().timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        final existingLower = <String>{};
        for (var d in docs) {
          final uName = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim().toLowerCase();
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

    // 1. Inserimento DIRETTO in MongoDB Atlas (<30ms)
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        final existingLower = <String>{};

        for (var d in docs) {
          final uName = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim().toLowerCase();
          final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
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

        final newDoc = {
          'nome': cleanNick,
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
          final uName = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim().toLowerCase();
          final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
          final isClaudioAlias = (cleanIdent == 'claudio' && (uName == 'cloud' || uEmail.contains('claudio.simonelli')));
          if (uName == cleanIdent || uEmail == cleanIdent || isClaudioAlias) {
            targetDoc = d;
            break;
          }
        }

        if (targetDoc == null) {
          throw Exception('Nessun account trovato per "$identifier". Verifica il Nickname o l\'Email.');
        }

        final email = (targetDoc['email'] ?? '').toString().trim();
        final username = (targetDoc['nome'] ?? targetDoc['username'] ?? targetDoc['nickname'] ?? 'Utente').toString();

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
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        // Self-healing automatico: Sincronizza ed allinea le amicizie da tutte le notifiche accettate
        final cleanNick = curUser.nickname.trim().toLowerCase();
        final nots = await db.collection('Notifiche').find(where.eq('tipo', 'richiesta_amicizia').eq('stato', 'accettato')).toList();
        final Set<String> amiciDaNotifiche = {};
        for (var n in nots) {
          final m = (n['mittente'] ?? '').toString().trim();
          final d = (n['destinatario'] ?? '').toString().trim();
          if (m.toLowerCase() == cleanNick && d.isNotEmpty) {
            amiciDaNotifiche.add(d);
          } else if (d.toLowerCase() == cleanNick && m.isNotEmpty) {
            amiciDaNotifiche.add(m);
          }
        }

        if (amiciDaNotifiche.isNotEmpty) {
          final uDocs = await db.collection('Utenti').find().toList();
          for (var uDoc in uDocs) {
            final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
            if (uName == cleanNick) {
              final List<dynamic> currentAmici = List.from(uDoc['amici'] ?? []);
              bool changed = false;
              for (var a in amiciDaNotifiche) {
                if (!currentAmici.any((existing) => existing.toString().trim().toLowerCase() == a.toLowerCase())) {
                  currentAmici.add(a);
                  changed = true;
                }
              }
              if (changed) {
                ObjectId? uObjId;
                try {
                  uObjId = uDoc['_id'] is ObjectId ? uDoc['_id'] as ObjectId : ObjectId.fromHexString(uDoc['_id'].toString());
                } catch (_) {}
                final uSelector = uObjId != null ? where.id(uObjId) : where.eq('_id', uDoc['_id']);
                await db.collection('Utenti').update(uSelector, modify.set('amici', currentAmici));
              }
            }
          }
        }
      }

      final utenti = await getUtenti();
      final match = utenti.firstWhere(
        (u) => u.nome.trim().toLowerCase() == curUser.nome.trim().toLowerCase(),
        orElse: () => curUser,
      );
      _currentUser = match;
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

    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final uDocs = await db.collection('Utenti').find().toList();
        for (var uDoc in uDocs) {
          final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
          if (uName == username.trim().toLowerCase()) {
            await db.collection('Utenti').update(
              where.id(uDoc['_id'] as ObjectId),
              modify.set('avatarUrl', newAvatarUrl),
            );
          }
        }
      }
    } catch (_) {}
  }

  // --- REPERIMENTO UTENTI REALI DAL DB (MONGODB ATLAS DIRETTO) ---
  Future<List<Utente>> getUtenti() async {
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        final List<Utente> list = [];
        for (var d in docs) {
          final jsonMap = Map<String, dynamic>.from(d);
          jsonMap['id'] = d['_id']?.toHexString() ?? d['_id']?.toString() ?? '';
          jsonMap['nome'] = d['nome'] ?? d['username'] ?? d['nickname'] ?? 'Utente';
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

          final uObj = Utente.fromJson(jsonMap);
          list.add(uObj);

          if (_currentUser != null && uObj.nome.trim().toLowerCase() == _currentUser!.nome.trim().toLowerCase()) {
            _currentUser = uObj;
            await _saveSession(_currentUser!);
          }
        }
        if (list.isNotEmpty) {
          _utenti.clear();
          _utenti.addAll(list);
          return List.unmodifiable(_utenti);
        }
      }
    } catch (_) {}

    return List.unmodifiable(_utenti);
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

  // --- REPERIMENTO EVENTI REALI DA MONGODB ATLAS (CON MANTENIMENTO FINITI 7 GG E BADGE VINCITORE) ---
  Future<List<Evento>> getEventi({bool forceRefresh = false}) async {
    if (!forceRefresh && _lastFetchTime != null && DateTime.now().difference(_lastFetchTime!) < _cacheDuration && _eventi.isNotEmpty) {
      return List.unmodifiable(_eventi);
    }

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
          final bool isConcluso = now.isAfter(dtEnd);
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
              final uDocs = await db.collection('Utenti').find().toList();

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
                  final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
                  if (uName == vincitoreNick.toLowerCase()) {
                    final List<dynamic> currentBadgeVincitore = List.from(uDoc['badgeVincitore'] ?? []);
                    if (!currentBadgeVincitore.any((b) => b['evento'] == badgeMap['evento'])) {
                      currentBadgeVincitore.add(badgeMap);
                      await db.collection('Utenti').update(
                        where.id(uDoc['_id'] as ObjectId),
                        modify.set('badgeVincitore', currentBadgeVincitore),
                      );
                    }
                  }
                }
              }

              // 2. Assegna Badge Partecipazione a TUTTI i partecipanti
              for (var part in partecipanti) {
                final partNorm = part.trim().toLowerCase();
                for (var uDoc in uDocs) {
                  final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
                  if (uName == partNorm) {
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
                  final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
                  final uId = uDoc['_id'] as ObjectId;
                  var mod = modify;
                  bool shouldUpdate = false;

                  if (bestMalusUser != null && uName == bestMalusUser && maxMalus > 0) {
                    final cur = (uDoc['countReMalus'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countReMalus', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestGiudiceUser != null && uName == bestGiudiceUser && maxAtt > 0) {
                    final cur = (uDoc['countGiudice'] as num?)?.toInt() ?? (uDoc['countAvvocato'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countGiudice', cur + 1).set('countAvvocato', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestFantasmaUser != null && uName == bestFantasmaUser) {
                    final cur = (uDoc['countFantasma'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countFantasma', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestSbirroUser != null && uName == bestSbirroUser && maxSbirro > 0) {
                    final cur = (uDoc['countSbirro'] as num?)?.toInt() ?? 0;
                    mod = mod.set('countSbirro', cur + 1);
                    shouldUpdate = true;
                  }
                  if (bestGiustiziereUser != null && uName == bestGiustiziereUser && maxGiustiziere > 0) {
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
          }

          final Map<String, dynamic> jsonMap = {
            'id': idStr,
            'titolo': d['titolo'] ?? d['nome'] ?? 'Evento',
            'descrizione': d['descrizione'] ?? '',
            'data': dtStartStr,
            'dataFine': dtEndStr,
            'luogo': d['luogo'] ?? '',
            'stato': isConcluso ? 'concluso' : (d['stato'] ?? 'in_programma'),
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
          _eventi.clear();
          _eventi.addAll(list);
          return list;
        }
      } catch (_) {}
    }
    return List.unmodifiable(_eventi);
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

          final List<dynamic> part = List.from(evDoc['partecipanti'] ?? []);
          final List<dynamic> inv = List.from(evDoc['invitati'] ?? []);
          inv.removeWhere((i) => i.toString().trim().toLowerCase() == nicknameOrId.trim().toLowerCase());
          if (!part.any((p) => p.toString().trim().toLowerCase() == nicknameOrId.trim().toLowerCase())) {
            part.add(nicknameOrId);
          }

          await db.collection('Evento').update(
            evSelector,
            modify.set('partecipanti', part).set('invitati', inv),
          );

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

        final creatore = (evDoc['propostoDa'] ?? evDoc['creatore'] ?? _currentUser?.nome ?? 'Cloud').toString();
        final evTitolo = (evDoc['titolo'] ?? evDoc['nome'] ?? 'Evento').toString();

        final List<dynamic> currentInvitati = List.from(evDoc['invitati'] ?? []);
        final List<dynamic> currentPartecipanti = List.from(evDoc['partecipanti'] ?? []);

        final List<String> aggiuntiEffettivi = [];
        for (var amico in nuoviInvitati) {
          final aNorm = amico.trim().toLowerCase();
          final giaPart = currentPartecipanti.any((p) => p.toString().trim().toLowerCase() == aNorm);
          final giaInv = currentInvitati.any((i) => i.toString().trim().toLowerCase() == aNorm);

          if (!giaPart && !giaInv) {
            currentInvitati.add(amico);
            aggiuntiEffettivi.add(amico);
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
    _bonusMalusList.removeWhere((b) => b.id == eventoId);
    _votazioniList.removeWhere((v) => v.id == eventoId);

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
    final cleanNick = nickname.trim().toLowerCase();
    final List<Map<String, dynamic>> notificheList = [];

    // Connessione DIRETTA e ROBUSTA a MongoDB Atlas (Singola Fonte di Verità)
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
          final bmNome = (bm['nome'] ?? '').toString().trim().toLowerCase();
          if (bmNome.isNotEmpty) bonusMalusMap[bmNome] = bm;
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
          final dDest = (d['destinatario'] ?? '').toString().trim().toLowerCase();
          return dDest == cleanNick || cleanNick.isEmpty;
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

          final bonusId = (d['bonusId'] ?? '').toString().toLowerCase();
          final notTitolo = (d['titolo'] ?? '').toString().toLowerCase();
          final notMsg = (d['messaggio'] ?? '').toString().toLowerCase();

          // 1. Controllo su BonusMalus collection (proponente e stato approvato/respinto)
          final matchedBm = bonusMalusMap[bonusId] ??
              bonusMalusMap[notTitolo] ??
              (idStr.isNotEmpty ? bonusMalusMap[idStr.toLowerCase()] : null);
          if (matchedBm != null) {
            final propDa = (matchedBm['propostoDa'] ?? '').toString().trim().toLowerCase();
            if (propDa.isNotEmpty && propDa == cleanNick) {
              haGiaVotato = true;
              votoEspresso = 'pro';
            }
            final bmStato = (matchedBm['stato'] ?? '').toString().toLowerCase();
            if (bmStato == 'approvato' || bmStato == 'respinto') {
              votazioneChiusa = true;
              esitoVotazione = bmStato;
            }
          }

          // 2. Controllo voti individuali da Votazioni collection
          for (var vDoc in votazioniDocs) {
            final vUser = (vDoc['utente'] ?? '').toString().trim().toLowerCase();
            if (vUser != cleanNick) continue;

            final vId = (vDoc['votazioneId'] ?? vDoc['bonusId'] ?? '').toString().trim().toLowerCase();
            final vTit = (vDoc['bonusTitolo'] ?? '').toString().trim().toLowerCase();
            final bool isMatch = (bonusId.isNotEmpty && (vId == bonusId || vTit == bonusId)) ||
                (vId.isNotEmpty && vId == idStr.toLowerCase()) ||
                (vTit.isNotEmpty && (notTitolo.contains(vTit) || notMsg.contains(vTit)));

            if (isMatch) {
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

          // 3. Fallback controllo matchVotazione generico
          if (!haGiaVotato || !votazioneChiusa) {
            Map<String, dynamic>? matchVotazione;
            if (bonusId.isNotEmpty && votazioniMap.containsKey(bonusId)) {
              matchVotazione = votazioniMap[bonusId];
            } else if (votazioniMap.containsKey(idStr.toLowerCase())) {
              matchVotazione = votazioniMap[idStr.toLowerCase()];
            } else {
              for (var entry in votazioniMap.entries) {
                if (entry.key.isNotEmpty && (notTitolo.contains(entry.key) || notMsg.contains(entry.key))) {
                  matchVotazione = entry.value;
                  break;
                }
              }
            }

            if (matchVotazione != null) {
              final votiMap = matchVotazione['votiUtenti'] as Map? ?? {};
              for (var k in votiMap.keys) {
                if (k.toString().trim().toLowerCase() == cleanNick) {
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

          seenKeys.add(idStr);
          notificheList.add({
            'id': idStr,
            'mittente': d['mittente'] ?? 'FantaEventi',
            'destinatario': d['destinatario'] ?? '',
            'titolo': d['titolo'] ?? 'Nuova Notifica',
            'messaggio': d['messaggio'] ?? '',
            'eventoId': d['eventoId'] ?? '',
            'bonusId': d['bonusId'] ?? '',
            'bonusTitolo': d['bonusTitolo'] ?? '',
            'tipo': d['tipo'] ?? 'invito',
            'varId': d['varId'] ?? '',
            'stato': d['stato'] ?? 'in_attesa',
            'letto': d['letto'] == true,
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

    // Aggiornamento DIRETTO su MongoDB Atlas
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
                if (dtStart != null && DateTime.now().isAfter(dtStart)) {
                  throw Exception('Questo evento è già iniziato! L\'iscrizione è ormai chiusa.');
                }

                final List<dynamic> part = List.from(evDoc['partecipanti'] ?? []);
                final List<dynamic> inv = List.from(evDoc['invitati'] ?? []);
                inv.removeWhere((i) => i.toString().toLowerCase() == utente.toLowerCase());
                if (!part.any((p) => p.toString().toLowerCase() == utente.toLowerCase())) {
                  part.add(utente);
                }
                await db.collection('Evento').update(
                  evSelector,
                  modify.set('partecipanti', part).set('invitati', inv),
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
      if (e is Exception && e.toString().contains('Questo evento è già iniziato')) {
        rethrow;
      }
    }
  }

  Future<Evento> creaEvento(Evento nuovoEvento, {bool awardXp = true}) async {
    invalidateCache();
    final creatore = nuovoEvento.propostoDa.isNotEmpty ? nuovoEvento.propostoDa : (_currentUser?.nome ?? 'Cloud');
    final List<String> invitati = nuovoEvento.partecipanti
        .where((p) => p.trim().toLowerCase() != creatore.trim().toLowerCase())
        .toList();

    final eventPayload = nuovoEvento.copyWith(
      propostoDa: creatore,
      partecipanti: [creatore],
      invitati: invitati,
    );

    final payloadMap = eventPayload.toJson();
    payloadMap['invitati'] = invitati;
    payloadMap['partecipanti'] = [creatore, ...invitati];

    // Scrittura DIRETTA e RESILIENTE dell'evento e delle notifiche su MongoDB Atlas (Singola Scrittura Infallibile)
    String realEvId = eventPayload.id;
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

    if (_currentUser != null && awardXp) {
      final nuoviXp = _currentUser!.xp + 100;
      final nuovoLivello = (nuoviXp / 1000).floor() + 1;
      _currentUser = _currentUser!.copyWith(
        xp: nuoviXp,
        livello: nuovoLivello,
        storicoVoti: [
          'Creato evento "${nuovoEvento.titolo}" (+100 XP)',
          ..._currentUser!.storicoVoti,
        ],
      );
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
    final curUserNick = _currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud';
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

    // Scrittura DIRETTA e RESILIENTE su MongoDB Atlas con Transient Failure Retry
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
            partecipanti: (evDoc['partecipanti'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? evMatch.partecipanti,
            invitati: (evDoc['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? evMatch.invitati,
          );
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
            where.eq('votazioneId', bmHexId).and(where.eq('utente', curUserNick))
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
          final cleanD = d.trim().toLowerCase();
          if (cleanD.isNotEmpty && cleanD != curUserNick.trim().toLowerCase()) {
            uniqueDestMap[cleanD] = d.trim();
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
        votiUtenti: {curUserNick: 'pro', curUserNick.toLowerCase(): 'pro'},
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
      final nuoviXp = _currentUser!.xp + 50;
      _currentUser = _currentUser!.copyWith(
        xp: nuoviXp,
        storicoVoti: [
          'Proposto ${nuovoBonus.isBonus ? "Bonus" : "Malus"} "${nuovoBonus.titolo}" (+50 XP)',
          ..._currentUser!.storicoVoti,
        ],
      );
      try {
        final db = await _getMongoDb().timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (db != null && db.isConnected) {
          final uDocs = await db.collection('Utenti').find().toList().timeout(const Duration(seconds: 4));
          for (var uDoc in uDocs) {
            final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
            if (uName == _currentUser!.nome.trim().toLowerCase()) {
              await db.collection('Utenti').update(
                where.id(uDoc['_id'] as ObjectId),
                modify.set('xp', _currentUser!.xp).set('storicoVoti', _currentUser!.storicoVoti),
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
    final mittente = _currentUser?.nome ?? 'Organizzatore';
    final cleanDest = utenteDestinatario.trim().toLowerCase();
    final ptStr = punti >= 0 ? '+$punti' : '$punti';
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final logText = '🏆 Ricevuto ${punti >= 0 ? "Bonus" : "Malus"} "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo" ($timeStr)';

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
          final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
          if (uName == cleanDest) {
            final oldPunti = (uDoc['puntiTotali'] ?? 0) as int;
            final oldXp = (uDoc['xp'] ?? 100) as int;
            final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
            final now = DateTime.now();
            final String timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
            final String dateTag = '[${now.toIso8601String().substring(0, 10)} $timeStr]';
            final String formattedLog = logText.startsWith('[') ? logText : '$dateTag $logText';
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
                  .set('xp', oldXp + (punti > 0 ? punti * 10 : 0))
                  .set('storicoVoti', oldStorico),
            );

            if (_currentUser != null && _currentUser!.nome.trim().toLowerCase() == cleanDest) {
              _currentUser = _currentUser!.copyWith(
                puntiTotali: oldPunti + punti,
                xp: oldXp + (punti > 0 ? punti * 10 : 0),
                storicoVoti: oldStorico.map((e) => e.toString()).toList(),
              );
            }
          }
        }

        // 4. Invia notifica BROADCAST a TUTTI i partecipanti dell'evento (con ID e Timestamp univoco)
        final evDocs = await db.collection('Evento').find().toList();
        final evMatch = evDocs.firstWhere(
          (e) => (e['_id']?.toHexString() == eventoId || e['_id']?.toString() == eventoId || (e['titolo'] ?? '').toString().toLowerCase() == eventoTitolo.toLowerCase()),
          orElse: () => <String, dynamic>{},
        );

        final List<String> destList = [];
        if (evMatch.isNotEmpty) {
          final List<dynamic> pList = List.from(evMatch['partecipanti'] ?? []);
          final List<dynamic> iList = List.from(evMatch['invitati'] ?? []);
          for (var item in [...pList, ...iList]) {
            final s = item.toString().trim();
            if (s.isNotEmpty && !destList.any((d) => d.toLowerCase() == s.toLowerCase())) {
              destList.add(s);
            }
          }
        }
        if (destList.isEmpty) {
          destList.add(utenteDestinatario);
        }

        final int ts = now.millisecondsSinceEpoch;
        for (var d in destList) {
          await db.collection('Notifiche').insertOne({
            'notificaId': 'bm_ass_${ts}_${d.toLowerCase()}',
            'mittente': mittente,
            'destinatario': d,
            'titolo': '🏆 Bonus/Malus Assegnato!',
            'messaggio': '$utenteDestinatario ha ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
            'eventoId': eventoId,
            'tipo': 'assegnazione_bonus',
            'stato': 'consegnato',
            'letto': false,
            'votoEspresso': 'pro',
            'data': now.toIso8601String(),
          });
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

  Future<List<BonusMalus>> getBonusMalusList() async {
    await getVotazioni();
    return List.unmodifiable(_bonusMalusList);
  }

  Future<List<Votazione>> getVotazioni() async {
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
            final u = (vDoc['utente'] ?? '').toString().trim();
            final val = (vDoc['voto']?.toString() ?? '').toLowerCase();

            final isMatch = (vId == bmId.toLowerCase()) ||
                            (bTit.isNotEmpty && bTit == nomeBM.toLowerCase()) ||
                            (vId.isNotEmpty && vId == nomeBM.toLowerCase());

            if (isMatch && u.isNotEmpty) {
              final voteStr = (val == 'pro' || val == 'accetta' || val == 'favorevole') ? 'pro' : 'contro';
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

          final numPartecipanti = evMatch.partecipanti.length >= 2 ? evMatch.partecipanti.length : 3;
          final int quorumCalcolato = (numPartecipanti / 2).floor() + 1;

          final Set<String> countedUsers = {};
          int fav = 0;
          int cont = 0;
          votiUtenti.forEach((user, vote) {
            final uLow = user.trim().toLowerCase();
            if (!countedUsers.contains(uLow)) {
              countedUsers.add(uLow);
              if (vote == 'pro') fav++;
              if (vote == 'contro') cont++;
            }
          });

          final bool giaApprovatoDaDb = bm['approvato'] == true ||
              bm['stato'] == 'approvato' ||
              bm['stato'] == 'confermato';
          final bool giaRespintoDaDb = bm['approvato'] == false && bm['stato'] == 'respinto';

          final totalVotiEspressi = fav + cont;
          bool isApprovato = giaApprovatoDaDb || (fav >= quorumCalcolato);
          bool isRespinto = (!giaApprovatoDaDb && (giaRespintoDaDb || (cont >= quorumCalcolato)));

          bool paritaDecisaDaOrganizzatore = false;
          final nomeOrganizzatore = evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa;

          if (!isApprovato && !isRespinto && (numPartecipanti % 2 == 0) && (totalVotiEspressi >= numPartecipanti) && (fav == cont)) {
            final cleanCreatore = nomeOrganizzatore.trim().toLowerCase();
            final creatoreVoteKey = votiUtenti.keys.firstWhere(
              (k) => k.trim().toLowerCase() == cleanCreatore,
              orElse: () => '',
            );
            if (creatoreVoteKey.isNotEmpty) {
              final creatoreVote = votiUtenti[creatoreVoteKey];
              if (creatoreVote == 'pro') {
                isApprovato = true;
                paritaDecisaDaOrganizzatore = true;
              }
              if (creatoreVote == 'contro') {
                isRespinto = true;
                paritaDecisaDaOrganizzatore = true;
              }
            } else if (cleanCreatore.isNotEmpty && cleanCreatore == effectivePropDa.trim().toLowerCase()) {
              isApprovato = true;
              paritaDecisaDaOrganizzatore = true;
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
    final userNick = _currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud';

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

    final giaVotato = v.votiUtenti.containsKey(userNick);
    final nuoviVotiUtenti = Map<String, String>.from(v.votiUtenti);
    nuoviVotiUtenti[userNick] = aFavore ? 'pro' : 'contro';

    int fav = 0;
    int cont = 0;
    nuoviVotiUtenti.forEach((_, vote) {
      if (vote == 'pro') fav++;
      if (vote == 'contro') cont++;
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

    final numPartecipanti = evMatch.partecipanti.length >= 2
        ? evMatch.partecipanti.length
        : (v.quorum > 0 ? (v.quorum - 1) * 2 : 3);
    final int quorumCalcolato = (numPartecipanti / 2).floor() + 1;
    final int totalVotiEspressi = fav + cont;

    bool isApprovato = (fav >= quorumCalcolato);
    bool isRespinto = (cont >= quorumCalcolato);
    bool paritaDecisaDaOrganizzatore = false;
    final nomeOrganizzatore = evMatch.creatore.isNotEmpty
        ? evMatch.creatore
        : (evMatch.propostoDa.isNotEmpty ? evMatch.propostoDa : (v.nomeOrganizzatore ?? ''));

    final propDa = v.bonusMalus?.propostoDa ?? '';

    if (!isApprovato && !isRespinto && (numPartecipanti % 2 == 0) && (totalVotiEspressi >= numPartecipanti) && (fav == cont)) {
      final cleanCreatore = nomeOrganizzatore.trim().toLowerCase();
      final creatoreVoteKey = nuoviVotiUtenti.keys.firstWhere(
        (k) => k.trim().toLowerCase() == cleanCreatore,
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
      } else if (cleanCreatore.isNotEmpty && cleanCreatore == propDa.trim().toLowerCase()) {
        isApprovato = true;
        paritaDecisaDaOrganizzatore = true;
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
          final evId = (notDoc['eventoId'] ?? '').toString().trim().toLowerCase();
          final bId = (notDoc['bonusId'] ?? '').toString().trim().toLowerCase();
          final notId = notDoc['_id']?.toHexString() ?? notDoc['_id']?.toString() ?? '';
          if (dest == userNick.toLowerCase() && (evId == idOrEventoId.toLowerCase() || bId == idOrEventoId.toLowerCase() || notId == idOrEventoId)) {
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
      final nuoviXp = _currentUser!.xp + 25;
      final nuovoLivello = (nuoviXp / 1000).floor() + 1;
      _currentUser = _currentUser!.copyWith(
        xp: nuoviXp,
        livello: nuovoLivello,
        storicoVoti: [
          'Votato ${aFavore ? "FAVOREVOLE" : "CONTRARIO"} a "${v.titolo}" (+25 XP)',
          ..._currentUser!.storicoVoti,
        ],
      );
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
          final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
          if (uName == cleanDest) {
            final oldPunti = (uDoc['puntiTotali'] ?? 0) as int;
            final oldXp = (uDoc['xp'] ?? 100) as int;
            final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
            final now = DateTime.now();
            final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
            final dateTag = '[${now.toIso8601String().substring(0, 10)} $timeStr]';
            oldStorico.insert(0, '$dateTag ⚠️ Annullata assegnazione bonus (-$punti PT) (ore $timeStr)');

            ObjectId? uObjId;
            try {
              uObjId = uDoc['_id'] is ObjectId ? uDoc['_id'] as ObjectId : ObjectId.fromHexString(uDoc['_id'].toString());
            } catch (_) {}
            final uSelector = uObjId != null ? where.id(uObjId) : where.eq('_id', uDoc['_id']);

            final newPunti = (oldPunti - punti).clamp(0, 999999);
            final newXp = (oldXp - (punti > 0 ? punti * 10 : 0)).clamp(100, 999999);

            await db.collection('Utenti').update(
              uSelector,
              modify
                  .set('puntiTotali', newPunti)
                  .set('xp', newXp)
                  .set('storicoVoti', oldStorico),
            );

            if (_currentUser != null && _currentUser!.nome.trim().toLowerCase() == cleanDest) {
              _currentUser = _currentUser!.copyWith(
                puntiTotali: newPunti,
                xp: newXp,
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
          final uName = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim().toLowerCase();
          ObjectId? uObjId;
          try {
            uObjId = d['_id'] is ObjectId ? d['_id'] as ObjectId : ObjectId.fromHexString(d['_id'].toString());
          } catch (_) {}
          final uSelector = uObjId != null ? where.id(uObjId) : where.eq('_id', d['_id']);

          if (uName == curUser.nickname.toLowerCase()) {
            final List<dynamic> amici = List.from(d['amici'] ?? []);
            if (!amici.any((a) => a.toString().toLowerCase() == mittente.toLowerCase())) {
              amici.add(mittente);
              await db.collection('Utenti').update(uSelector, modify.set('amici', amici));
            }
          }
          if (uName == mittente.toLowerCase()) {
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
      }
    }
  }

  // Restituisce ESCLUSIVAMENTE gli utenti presenti nella lista amici di _currentUser per l'invito agli eventi
  Future<List<Utente>> getGiocatoriInvitabili() async {
    final curUser = _currentUser;
    if (curUser == null) return [];
    final tutti = await getUtenti();
    final amiciLower = curUser.amici.map((a) => a.toLowerCase()).toSet();
    return tutti.where((u) => amiciLower.contains(u.nickname.toLowerCase())).toList();
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
      await db.collection('Notifiche').update(
        where.eq('varId', varId).and(where.eq('destinatario', testimoneNick)),
        modify.set('stato', conferma ? 'confermato' : 'negato').set('letto', true),
      );

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
      if (doc['stato'] != 'in_attesa') return false; // Già processata

      final richiesta = RichiestaVar.fromJson(doc);
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;

      if (approva) {
        // 1. Assegna punti al bersaglio
        await assegnaBonusMalusAPartecipante(
          eventoId: richiesta.eventoId,
          bonusId: richiesta.bonusMalusId,
          utenteDestinatario: richiesta.bersaglio,
          punti: richiesta.punti,
          eventoTitolo: richiesta.eventoTitolo,
          bonusTitolo: richiesta.bonusMalusTitolo,
        );

        // 2. Se era una denuncia Malus, assegna +25 XP al richiedente per merito civico
        if (richiesta.tipo == 'malus') {
          final uDocs = await db.collection('Utenti').find().toList();
          for (var uDoc in uDocs) {
            final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
            if (uName == richiesta.richiedente.trim().toLowerCase()) {
              final curXp = (uDoc['xp'] as num?)?.toInt() ?? ((uDoc['puntiEsperienza'] as num?)?.toInt() ?? 100);
              await db.collection('Utenti').update(
                where.id(uDoc['_id'] as ObjectId),
                modify.set('xp', curXp + 25).set('puntiEsperienza', curXp + 25),
              );
              break;
            }
          }
        }

        // 3. Aggiorna stato RichiestaVar ed ELIMINA la foto dal DB
        await db.collection('RichiesteVar').update(
          selector,
          modify
              .set('stato', 'approvata')
              .set('dataDecisione', now.toIso8601String())
              .unset('fotoBase64'),
        );

        // 4. Invia notifica di successo al richiedente
        await db.collection('Notifiche').insertOne({
          'notificaId': 'var_res_${ts}_${richiesta.richiedente.toLowerCase()}',
          'mittente': giudiceNick,
          'destinatario': richiesta.richiedente,
          'titolo': '📺 VAR: Richiesta Approvata! ✅',
          'messaggio': 'Il Giudice ha convalidato la tua segnalazione per "${richiesta.bonusMalusTitolo}". I punti sono stati assegnati.',
          'eventoId': richiesta.eventoId,
          'varId': varId,
          'tipo': 'var_esito',
          'stato': 'approvato',
          'letto': false,
          'data': now.toIso8601String(),
        });
      } else {
        // Rigettata
        final bool doSanzione = sanzionaFalsaTestimonianza && richiesta.tipo == 'malus';

        if (doSanzione) {
          final penalty = (richiesta.penalitaPunti != 0 ? richiesta.penalitaPunti.abs() : 10) * -1; // Garantisce numero negativo

          // Applica decurtazione punti al denunciante nel DB Utenti
          final cleanRichiedente = richiesta.richiedente.trim();
          final cleanEvId = richiesta.eventoId.trim();
          final uDocs = await db.collection('Utenti').find().toList();
          for (var uDoc in uDocs) {
            final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
            if (uName == cleanRichiedente.toLowerCase()) {
              final curPts = (uDoc['puntiTotali'] as num?)?.toInt() ?? 0;
              final curStorico = List<String>.from(uDoc['storicoVoti'] ?? []);
              final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              curStorico.add('🚨 Sanzione VAR: Falsa Testimonianza ($penalty PT) per l\'evento "${richiesta.eventoTitolo}" ($timeStr)');

              await db.collection('Utenti').update(
                where.id(uDoc['_id'] as ObjectId),
                modify.set('puntiTotali', curPts + penalty).set('storicoVoti', curStorico),
              );

              if (_currentUser != null && _currentUser!.nome.trim().toLowerCase() == cleanRichiedente.toLowerCase()) {
                _currentUser = _currentUser!.copyWith(
                  puntiTotali: curPts + penalty,
                  storicoVoti: curStorico,
                );
                await _saveSession(_currentUser!);
              }
              break;
            }
          }

          // Inserisce o aggiorna il Malus formale unico in BonusMalus così viene conteggiato nella Classifica Live Evento
          final evTitle = richiesta.eventoTitolo.trim();
          var existingBmDoc = await db.collection('BonusMalus').findOne(
            where.eq('eventoId', cleanEvId).and(
              where.eq('nome', '🚨 Falsa Testimonianza VAR').or(where.eq('titolo', '🚨 Falsa Testimonianza VAR'))
            ),
          );
          if (existingBmDoc == null && evTitle.isNotEmpty) {
            existingBmDoc = await db.collection('BonusMalus').findOne(
              where.eq('eventoId', evTitle).and(
                where.eq('nome', '🚨 Falsa Testimonianza VAR').or(where.eq('titolo', '🚨 Falsa Testimonianza VAR'))
              ),
            );
          }

          String sanzioneBmId;
          if (existingBmDoc != null) {
            // Aggiorna l'elenco assegnatoA del malus unico già esistente
            sanzioneBmId = (existingBmDoc['_id'] as ObjectId?)?.oid ?? existingBmDoc['_id'].toString();
            final List<dynamic> curAss = List.from(existingBmDoc['assegnatoA'] ?? []);
            curAss.add(cleanRichiedente);
            await db.collection('BonusMalus').update(
              where.id(existingBmDoc['_id'] as ObjectId),
              modify.set('assegnatoA', curAss).set('punti', penalty).set('riassegnabileMoltepliciVolte', true),
            );

            // Aggiorna l'istanza in memoria in _bonusMalusList
            final memIdx = _bonusMalusList.indexWhere((b) =>
                (b.id == sanzioneBmId || b.titolo == '🚨 Falsa Testimonianza VAR') &&
                (b.eventoId.trim().toLowerCase() == cleanEvId.toLowerCase() ||
                 b.eventoId.trim().toLowerCase() == evTitle.toLowerCase()));
            if (memIdx != -1) {
              final updatedAss = List<String>.from(_bonusMalusList[memIdx].assegnatoA)..add(cleanRichiedente);
              _bonusMalusList[memIdx] = _bonusMalusList[memIdx].copyWith(
                assegnatoA: updatedAss,
                punti: penalty,
                riassegnabileMoltepliciVolte: true,
              );
            } else {
              _bonusMalusList.add(BonusMalus(
                id: sanzioneBmId,
                eventoId: cleanEvId,
                titolo: '🚨 Falsa Testimonianza VAR',
                descrizione: 'Sanzione per denuncia infondata',
                punti: penalty,
                categoria: 'VAR',
                propostoDa: giudiceNick,
                approvato: true,
                stato: 'approvato',
                assegnatoA: curAss.map((e) => e.toString()).toList(),
                riassegnabileMoltepliciVolte: true,
              ));
            }
          } else {
            // Non esiste ancora: crealo una sola volta come malus ufficiale riassegnabile
            final sanzioneBmDoc = {
              'eventoId': cleanEvId,
              'eventoTitolo': evTitle,
              'nome': '🚨 Falsa Testimonianza VAR',
              'titolo': '🚨 Falsa Testimonianza VAR',
              'descrizione': 'Sanzione per denuncia infondata su "${richiesta.bonusMalusTitolo}"',
              'punti': penalty,
              'categoria': 'VAR',
              'tipo': 'malus',
              'propostoDa': giudiceNick,
              'stato': 'approvato',
              'approvato': true,
              'assegnatoA': [cleanRichiedente],
              'riassegnabileMoltepliciVolte': true,
            };
            final insertRes = await db.collection('BonusMalus').insertOne(sanzioneBmDoc);
            sanzioneBmId = (sanzioneBmDoc['_id'] as ObjectId?)?.oid ??
                (insertRes.id is ObjectId ? (insertRes.id as ObjectId).oid : insertRes.id?.toString() ?? 'sanzione_var_$ts');

            _bonusMalusList.add(BonusMalus(
              id: sanzioneBmId,
              eventoId: cleanEvId,
              titolo: '🚨 Falsa Testimonianza VAR',
              descrizione: 'Sanzione per denuncia infondata su "${richiesta.bonusMalusTitolo}"',
              punti: penalty,
              categoria: 'VAR',
              propostoDa: giudiceNick,
              approvato: true,
              stato: 'approvato',
              assegnatoA: [cleanRichiedente],
              riassegnabileMoltepliciVolte: true,
            ));
          }

          // Aggiunge o aggiorna la voce di sanzione nei bonus/malus applicati dell'evento nel DB
          ObjectId? evObjId;
          try {
            evObjId = ObjectId.fromHexString(cleanEvId);
          } catch (_) {}
          final evDoc = await db.collection('Evento').findOne(
            evObjId != null
                ? where.id(evObjId)
                : where.eq('_id', cleanEvId).or(where.eq('titolo', evTitle)),
          );
          if (evDoc != null) {
            final List<dynamic> applied = List.from(evDoc['bonusMalusApplicati'] ?? []);
            final existingAppIdx = applied.indexWhere((a) =>
                (a['id'] == sanzioneBmId || a['titolo'] == '🚨 Falsa Testimonianza VAR' || a['nome'] == '🚨 Falsa Testimonianza VAR'));
            if (existingAppIdx != -1) {
              final Map<String, dynamic> appMap = Map<String, dynamic>.from(applied[existingAppIdx]);
              final List<dynamic> assList = List.from(appMap['assegnatoA'] ?? []);
              assList.add(cleanRichiedente);
              appMap['assegnatoA'] = assList;
              applied[existingAppIdx] = appMap;
            } else {
              applied.add({
                'id': sanzioneBmId,
                'titolo': '🚨 Falsa Testimonianza VAR',
                'nome': '🚨 Falsa Testimonianza VAR',
                'descrizione': 'Denuncia infondata per "${richiesta.bonusMalusTitolo}"',
                'punti': penalty,
                'categoria': 'VAR',
                'assegnatoA': [cleanRichiedente],
                'propostoDa': giudiceNick,
                'eventoId': cleanEvId,
              });
            }
            await db.collection('Evento').update(
              where.id(evDoc['_id'] as ObjectId),
              modify.set('bonusMalusApplicati', applied),
            );
          }

          // Aggiorna anche l'evento in memoria
          final evIdx = _eventi.indexWhere((e) =>
              e.id.toLowerCase() == cleanEvId.toLowerCase() ||
              e.titolo.toLowerCase() == richiesta.eventoTitolo.trim().toLowerCase());
          if (evIdx != -1) {
            final updatedPartecipanti = List<String>.from(_eventi[evIdx].partecipanti);
            if (!updatedPartecipanti.any((p) => p.trim().toLowerCase() == cleanRichiedente.toLowerCase())) {
              updatedPartecipanti.add(cleanRichiedente);
            }
            _eventi[evIdx] = _eventi[evIdx].copyWith(
              partecipanti: updatedPartecipanti,
            );
          }

          // Notifica rossa al denunciante sanzionato
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
        } else {
          // Rifiutata senza sanzione (es. bonus non confermato)
          await db.collection('Notifiche').insertOne({
            'notificaId': 'var_res_${ts}_${richiesta.richiedente.toLowerCase()}',
            'mittente': giudiceNick,
            'destinatario': richiesta.richiedente,
            'titolo': '📺 VAR: Richiesta Non Convalidata ❌',
            'messaggio': 'La verifica per "${richiesta.bonusMalusTitolo}" non è stata convalidata dal Giudice.',
            'eventoId': richiesta.eventoId,
            'varId': varId,
            'tipo': 'var_esito',
            'stato': 'rifiutato',
            'letto': false,
            'data': now.toIso8601String(),
          });
        }

        // Aggiorna stato ed ELIMINA la foto dal DB
        await db.collection('RichiesteVar').update(
          selector,
          modify
              .set('stato', 'rifiutata')
              .set('dataDecisione', now.toIso8601String())
              .set('sanzioneApplicata', doSanzione)
              .unset('fotoBase64'),
        );
      }

      // Aggiorna anche la notifica del giudice su 'decisa'
      await db.collection('Notifiche').update(
        where.eq('varId', varId).and(where.eq('destinatario', giudiceNick)),
        modify.set('stato', approva ? 'approvato' : 'rifiutato').set('letto', true),
      );

      invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }
}
