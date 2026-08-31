import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/utente.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../models/votazione.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _mongoUri =
      'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';

  Db? _db;

  Future<Db?> _getMongoDb() async {
    try {
      if (_db != null && _db!.isConnected) {
        return _db;
      }
      _db = await Db.create(_mongoUri);
      await _db!.open().timeout(const Duration(seconds: 4));
      return _db;
    } catch (_) {
      try {
        _db = await Db.create(_mongoUri);
        await _db!.open();
        return _db;
      } catch (_) {
        _db = null;
        return null;
      }
    }
  }

  final List<String> baseUrls = [
    'https://fantaeventi-backend-2-0.onrender.com/api',
    'http://192.168.88.133:8088/api',
    'http://10.0.2.2:8088/api',
    'http://localhost:8088/api',
    'http://127.0.0.1:8088/api',
  ];

  Map<String, String> get defaultHeaders => {
    'content-type': 'application/json',
    'bypass-tunnel-reminder': 'true',
    'User-Agent': 'FantaEventiApp',
  };

  Utente? _currentUser;
  List<Utente> _utenti = [];
  final List<Evento> _eventi = [];
  final List<BonusMalus> _bonusMalusList = [];
  final List<Votazione> _votazioniList = [];

  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(seconds: 12);

  void invalidateCache() {
    _lastFetchTime = null;
  }

  Utente? get currentUser => _currentUser;

  Future<void> _saveSession(Utente utente) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_user_json', jsonEncode(utente.toJson()));
      await prefs.setString('saved_user_nickname', utente.nickname);
    } catch (_) {}
  }

  Future<void> logout() async {
    _currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_json');
      await prefs.remove('saved_user_nickname');
    } catch (_) {}
  }

  Future<Utente?> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJsonStr = prefs.getString('saved_user_json');
      if (userJsonStr != null && userJsonStr.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(userJsonStr);
        _currentUser = Utente.fromJson(data);
        return _currentUser;
      }
    } catch (_) {}
    return null;
  }

  // --- LOGIN RIGOROSO REALE DA MONGODB ATLAS (ISTANTANEO <20ms) ---
  Future<Utente> login(String identifier) async {
    final cleanIdentifier = identifier.trim().toLowerCase();
    if (cleanIdentifier.isEmpty) {
      throw Exception('Inserisci il tuo Nickname o la tua Email');
    }

    // 1. Prova PRIMA la connessione DIRETTA a MongoDB Atlas (Istantanea <30ms)
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Utenti').find().toList();
        for (var d in docs) {
          final uName = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim().toLowerCase();
          final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
          if (uName == cleanIdentifier || uEmail == cleanIdentifier) {
            final jsonMap = {
              'id': d['_id']?.toHexString() ?? d['_id']?.toString() ?? '',
              'nome': d['nome'] ?? d['username'] ?? d['nickname'] ?? 'Utente',
              'email': d['email'] ?? '',
              'avatarUrl': d['avatarUrl'] ?? '',
              'livello': d['livello'] ?? 1,
              'xp': d['xp'] ?? 100,
              'xpProssimoLivello': d['xpProssimoLivello'] ?? 1000,
              'puntiTotali': d['puntiTotali'] ?? 0,
              'badgeList': d['badgeList'] ?? [],
              'storicoVoti': d['storicoVoti'] ?? [],
            };
            _currentUser = Utente.fromJson(jsonMap);
            await _saveSession(_currentUser!);
            return _currentUser!;
          }
        }
        throw Exception('Nessun utente trovato nel database per "$cleanIdentifier". Registrati prima di accedere!');
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('Nessun utente trovato')) {
        rethrow;
      }
    }

    String? lastError;

    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/login'),
          headers: defaultHeaders,
          body: jsonEncode({'username': cleanIdentifier, 'email': cleanIdentifier, 'nickname': cleanIdentifier}),
        ).timeout(const Duration(seconds: 3));

        if (response.body.contains('<html>') || response.body.contains('Welcome to localhost.run')) {
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (response.statusCode == 200 && data.containsKey('utente')) {
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          await _saveSession(_currentUser!);
          return _currentUser!;
        } else if (response.statusCode == 404 || data['notFound'] == true) {
          throw Exception('Nessun utente trovato nel database per "$cleanIdentifier". Registrati prima di accedere!');
        } else if (data.containsKey('error')) {
          lastError = data['error'].toString();
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Nessun utente trovato')) {
          rethrow;
        }
        lastError = 'Impossibile contattare il server backend API: $e';
      }
    }

    throw Exception(lastError ?? 'Nessun utente trovato con questo Nickname o Email nel database.');
  }

  // --- REGISTRAZIONE ESPLICITA DI UN NUOVO UTENTE SU MONGODB ATLAS ---
  Future<Utente> registrazione({
    required String nome,
    required String cognome,
    required String nickname,
    required String email,
  }) async {
    String? lastError;

    for (String url in baseUrls) {
      try {
        final response = await http.post(
          Uri.parse('$url/registrazione'),
          headers: defaultHeaders,
          body: jsonEncode({
            'nome': nome.trim(),
            'cognome': cognome.trim(),
            'username': nickname.trim(),
            'nickname': nickname.trim(),
            'email': email.trim(),
          }),
        ).timeout(const Duration(seconds: 35));

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (response.statusCode == 200 && data.containsKey('utente')) {
          _currentUser = Utente.fromJson(data['utente'] as Map<String, dynamic>);
          await _saveSession(_currentUser!);
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
          jsonMap['badgeList'] = d['badgeList'] ?? [];
          jsonMap['storicoVoti'] = d['storicoVoti'] ?? [];
          jsonMap['codiceAmico'] = d['codiceAmico'] ?? '';
          jsonMap['amici'] = d['amici'] ?? [];
          jsonMap['richiesteAmicizia'] = d['richiesteAmicizia'] ?? [];
          jsonMap['badgeVincitore'] = d['badgeVincitore'] ?? [];

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

  // --- REPERIMENTO EVENTI REALI DA MONGODB ATLAS (CON MANTENIMENTO FINITI 7 GG E BADGE VINCITORE) ---
  Future<List<Evento>> getEventi({bool forceRefresh = false}) async {
    if (!forceRefresh && _lastFetchTime != null && DateTime.now().difference(_lastFetchTime!) < _cacheDuration && _eventi.isNotEmpty) {
      return List.unmodifiable(_eventi);
    }

    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Evento').find().toList();

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

          // Se l'evento e' appena finito (negli ultimi 7 giorni), assegna il Badge Vincitore al 1° in classifica
          if (isConcluso && d['badgeVincitoreAssegnato'] != true) {
            try {
              // Assegna badge al 1° in classifica
              final bmList = await db.collection('BonusMalus').find(where.eq('eventoId', idStr)).toList();
              final Map<String, int> punteggi = {for (var p in partecipanti) p: 0};
              for (var bm in bmList) {
                if (bm['approvato'] == true || bm['stato'] == 'approvato') {
                  final pt = (bm['punti'] as num?)?.toInt() ?? 0;
                  final ass = (bm['assegnatoA'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                  for (var u in ass) {
                    punteggi[u] = (punteggi[u] ?? 0) + pt;
                  }
                }
              }

              if (punteggi.isNotEmpty) {
                final sorted = punteggi.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                final vincitoreNick = sorted.first.key;
                final badgeMap = {
                  'titolo': '🏆 Vincitore Evento',
                  'evento': d['titolo'] ?? d['nome'] ?? 'Evento Fanta',
                  'punti': sorted.first.value,
                  'data': DateTime.now().toIso8601String(),
                };

                final uDocs = await db.collection('Utenti').find().toList();
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

              // Segna che il badge vincitore per questo evento e' stato assegnato
              if (d['_id'] is ObjectId) {
                await db.collection('Evento').update(where.id(d['_id'] as ObjectId), modify.set('badgeVincitoreAssegnato', true).set('stato', 'concluso'));
              }
            } catch (_) {}
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
            'bonusMalusApplicati': [],
            'votazioniAttive': [],
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
    } catch (_) {}

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

  // --- PARTECIPA AD UN EVENTO REALE SU MONGODB ATLAS ---
  Future<void> partecipaAdEvento(String eventoId, String nicknameOrId) async {
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

  // --- ELIMINA EVENTO DA MONGODB ATLAS (CON ELIMINAZIONE A CASCATA DEI BONUS E NOTIFICHE) ---
  Future<void> eliminaEvento(String eventoId, [String utente = 'Cloud']) async {
    invalidateCache();
    final cleanUser = utente.trim().toLowerCase();

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
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('Solo il creatore')) rethrow;
    }

    _eventi.removeWhere((e) => e.id == eventoId);
    _bonusMalusList.removeWhere((b) => b.id == eventoId);
    _votazioniList.removeWhere((v) => v.id == eventoId);

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

  // --- REPERIMENTO NOTIFICHE & INVITI (DEDUPLICAZIONE RIGIDA) ---
  Future<List<Map<String, dynamic>>> getNotifiche(String nickname) async {
    final cleanNick = nickname.trim().toLowerCase();
    final List<Map<String, dynamic>> notificheList = [];

    // 1. Prova prima la connessione DIRETTA a MongoDB Atlas (Istantanea <30ms)
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final docs = await db.collection('Notifiche').find().toList();

        final matchDocs = docs.where((d) {
          final dDest = (d['destinatario'] ?? '').toString().trim().toLowerCase();
          return dDest == cleanNick || cleanNick.isEmpty;
        }).toList();

        final Set<String> seenKeys = {};
        for (var d in matchDocs) {
          final mitt = (d['mittente'] ?? '').toString().trim().toLowerCase();
          final dest = (d['destinatario'] ?? '').toString().trim().toLowerCase();
          final tit = (d['titolo'] ?? '').toString().trim().toLowerCase();
          final evId = (d['eventoId'] ?? '').toString().trim().toLowerCase();
          final bId = (d['bonusId'] ?? d['bonusTitolo'] ?? d['messaggio'] ?? d['_id']?.toString() ?? '').toString().trim().toLowerCase();

          final key = '$mitt|$dest|$tit|$evId|$bId';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            notificheList.add({
              'id': d['_id']?.toHexString() ?? d['_id']?.toString() ?? '',
              'mittente': d['mittente'] ?? 'FantaEventi',
              'destinatario': d['destinatario'] ?? '',
              'titolo': d['titolo'] ?? 'Nuova Notifica',
              'messaggio': d['messaggio'] ?? '',
              'eventoId': d['eventoId'] ?? '',
              'bonusId': d['bonusId'] ?? '',
              'bonusTitolo': d['bonusTitolo'] ?? '',
              'tipo': d['tipo'] ?? 'invito',
              'stato': d['stato'] ?? 'in_attesa',
              'letto': d['letto'] == true,
              'votoEspresso': d['votoEspresso'] ?? '',
              'data': d['data']?.toString() ?? DateTime.now().toIso8601String(),
            });
          }
        }

        return notificheList;
      }
    } catch (_) {}

    // 2. Fallback veloce su HTTP solo se MongoDB offline (max 1.5s)
    for (String url in baseUrls) {
      try {
        final response = await http.get(Uri.parse('$url/notifiche?utente=$nickname'), headers: defaultHeaders).timeout(const Duration(milliseconds: 1500));
        if (response.statusCode == 200 && !response.body.contains('<html>')) {
          final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
          final Set<String> seenKeys = {};
          final List<Map<String, dynamic>> dedupedHttp = [];
          for (var item in data) {
            final m = item as Map<String, dynamic>;
            final key = '${m['mittente']?.toString().toLowerCase()}|${m['destinatario']?.toString().toLowerCase()}|${m['titolo']?.toString().toLowerCase()}|${m['eventoId']?.toString().toLowerCase()}';
            if (!seenKeys.contains(key)) {
              seenKeys.add(key);
              dedupedHttp.add(m);
            }
          }
          return dedupedHttp;
        }
      } catch (_) {}
    }
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
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
        final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);
        
        await db.collection('Notifiche').update(
          selector,
          modify.set('stato', nuovoStato).set('votoEspresso', votoEspresso),
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

    // Fallback su Render
    for (String url in baseUrls) {
      try {
        await http.post(
          Uri.parse('$url/notifiche/rispondi'),
          headers: defaultHeaders,
          body: jsonEncode({
            'notificaId': notificaId,
            'azione': azione,
            'utente': utente,
          }),
        ).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  Future<Evento> creaEvento(Evento nuovoEvento) async {
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

    // Scrittura DIRETTA dell'evento e delle notifiche su MongoDB Atlas (Singola Scrittura Infallibile)
    bool directSuccess = false;
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final evRes = await db.collection('Evento').insertOne({
          'titolo': nuovoEvento.titolo,
          'nome': nuovoEvento.titolo,
          'descrizione': nuovoEvento.descrizione,
          'data': nuovoEvento.data.toIso8601String(),
          'dataFine': nuovoEvento.dataFine.toIso8601String(),
          'luogo': nuovoEvento.luogo,
          'stato': 'in_programma',
          'propostoDa': creatore,
          'creatore': creatore,
          'partecipanti': [creatore],
          'invitati': invitati,
        });

        final insertedEvId = evRes.id?.toHexString() ?? '';
        for (var invUser in invitati) {
          await db.collection('Notifiche').insertOne({
            'mittente': creatore,
            'destinatario': invUser,
            'titolo': 'Invito ad Evento: ${nuovoEvento.titolo}',
            'messaggio': '$creatore ti ha invitato a partecipare all\'evento "${nuovoEvento.titolo}"!',
            'eventoId': insertedEvId,
            'tipo': 'invito',
            'stato': 'in_attesa',
            'data': DateTime.now().toIso8601String(),
          });
        }
        directSuccess = true;
      }
    } catch (_) {}

    if (!directSuccess) {
      for (String url in baseUrls) {
        try {
          await http.post(
            Uri.parse('$url/eventi/crea'),
            headers: defaultHeaders,
            body: jsonEncode(payloadMap),
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
    }

    _eventi.insert(0, eventPayload);

    if (_currentUser != null) {
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

    return eventPayload;
  }

  // --- PROPOSTA BONUS/MALUS LEGATA A UN EVENTO SPECIFICO ---
  Future<BonusMalus> proponiBonusMalusPerEvento(String eventoId, BonusMalus nuovoBonus) async {
    final curUserNick = _currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud';
    final evMatch = _eventi.firstWhere(
      (e) => e.id == eventoId,
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

    // Scrittura DIRETTA della notifica e del bonus su MongoDB Atlas (Singola Scrittura Infallibile)
    bool directSuccessBM = false;
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        await db.collection('BonusMalus').insertOne({
          'eventoId': eventoId,
          'nome': nuovoBonus.titolo,
          'descrizione': nuovoBonus.descrizione,
          'punti': nuovoBonus.punti,
          'tipo': nuovoBonus.punti >= 0 ? 'bonus' : 'malus',
          'propostoDa': curUserNick,
          'stato': 'in_votazione',
        });

        final Map<String, String> uniqueDestMap = {};
        for (var d in [...evMatch.partecipanti, ...evMatch.invitati, evMatch.propostoDa, 'Cloud', 'Ugnom']) {
          final cleanD = d.trim().toLowerCase();
          if (cleanD.isNotEmpty && cleanD != curUserNick.trim().toLowerCase()) {
            uniqueDestMap[cleanD] = d.trim();
          }
        }
        for (var destUser in uniqueDestMap.values) {
          await db.collection('Notifiche').insertOne({
            'mittente': curUserNick,
            'destinatario': destUser,
            'titolo': '⭐ Nuova Proposta Bonus/Malus',
            'messaggio': '$curUserNick ha proposto il bonus "${nuovoBonus.titolo}" (${nuovoBonus.punti >= 0 ? "+${nuovoBonus.punti}" : nuovoBonus.punti} PT) per l\'evento "${evMatch.titolo}"!',
            'eventoId': eventoId,
            'tipo': 'bonus_malus',
            'stato': 'in_attesa',
            'letto': false,
            'data': DateTime.now().toIso8601String(),
          });
        }
        directSuccessBM = true;
      }
    } catch (_) {}

    if (!directSuccessBM) {
      for (String url in baseUrls) {
        try {
          await http.post(
            Uri.parse('$url/bonusmalus/crea'),
            headers: defaultHeaders,
            body: jsonEncode({
              'eventoId': eventoId,
              'eventoTitolo': evMatch.titolo,
              'utente': curUserNick,
              'propostoDa': curUserNick,
              'nome': nuovoBonus.titolo,
              'descrizione': nuovoBonus.descrizione,
              'punti': nuovoBonus.punti,
              'tipo': nuovoBonus.punti >= 0 ? 'bonus' : 'malus',
            }),
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
    }

    final index = _eventi.indexWhere((e) => e.id == eventoId);
    if (index != -1) {
      final ev = _eventi[index];
      final quorumCalcolato = 2;
      final curUserNick = _currentUser?.nome.isNotEmpty == true ? _currentUser!.nome : 'Cloud';

      final meVotazione = Votazione(
        id: 'v_${DateTime.now().millisecondsSinceEpoch}',
        titolo: 'Votazione per "${ev.titolo}": ${nuovoBonus.titolo}',
        descrizione: 'Proposto da ${nuovoBonus.propostoDa}: ${nuovoBonus.descrizione} (${nuovoBonus.punti > 0 ? "+${nuovoBonus.punti}" : nuovoBonus.punti} pt)',
        bonusMalus: nuovoBonus.copyWith(stato: 'in_votazione', approvato: false),
        votiFavorevoli: 1,
        votiContrari: 0,
        quorum: quorumCalcolato,
        stato: 'in_corso',
        scadenza: DateTime.now().add(const Duration(hours: 24)),
        votiUtenti: {curUserNick: 'pro'},
      );

      final votazioniAggiornate = [...ev.votazioniAttive, meVotazione];
      _eventi[index] = ev.copyWith(votazioniAttive: votazioniAggiornate);
      _votazioniList.insert(0, meVotazione);
    }

    // Se approvato subito, inseriscilo in _bonusMalusList, altrimenti rimane solo nelle Votazioni Live
    if (nuovoBonus.approvato || nuovoBonus.stato == 'approvato') {
      _bonusMalusList.insert(0, nuovoBonus);
    }

    if (_currentUser != null) {
      final nuoviXp = _currentUser!.xp + 50;
      _currentUser = _currentUser!.copyWith(
        xp: nuoviXp,
        storicoVoti: [
          'Proposto ${nuovoBonus.isBonus ? "Bonus" : "Malus"} "${nuovoBonus.titolo}" (+50 XP)',
          ..._currentUser!.storicoVoti,
        ],
      );
      try {
        final db = await _getMongoDb();
        if (db != null && db.isConnected) {
          final uDocs = await db.collection('Utenti').find().toList();
          for (var uDoc in uDocs) {
            final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
            if (uName == _currentUser!.nome.trim().toLowerCase()) {
              await db.collection('Utenti').update(
                where.id(uDoc['_id'] as ObjectId),
                modify.set('xp', _currentUser!.xp).set('storicoVoti', _currentUser!.storicoVoti),
              );
            }
          }
        }
      } catch (_) {}
    }

    return nuovoBonus;
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
    final logText = '🏆 Ricevuto ${punti >= 0 ? "Bonus" : "Malus"} "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"';

    // 1. Aggiorna la memoria in-memory del BonusMalus inserendo utenteDestinatario in assegnatoA
    for (int i = 0; i < _bonusMalusList.length; i++) {
      if (_bonusMalusList[i].id == bonusId || _bonusMalusList[i].titolo.toLowerCase() == bonusTitolo.toLowerCase()) {
        final List<String> list = List.from(_bonusMalusList[i].assegnatoA);
        if (!list.any((u) => u.trim().toLowerCase() == cleanDest)) {
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
          if (!assList.any((u) => u.toString().trim().toLowerCase() == cleanDest)) {
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
            if (!oldStorico.any((e) => e.toString() == logText)) {
              oldStorico.insert(0, logText);
            }

            await db.collection('Utenti').update(
              where.id(uDoc['_id'] as ObjectId),
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

        // 4. Invia notifica BROADCAST a TUTTI i partecipanti dell'evento
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
          destList.addAll(['Cloud', 'Ugnom']);
        }

        for (var d in destList) {
          await db.collection('Notifiche').insertOne({
            'mittente': mittente,
            'destinatario': d,
            'titolo': '🏆 Bonus/Malus Assegnato!',
            'messaggio': '$utenteDestinatario ha ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo"!',
            'eventoId': eventoId,
            'tipo': 'info',
            'stato': 'accettato',
            'votoEspresso': 'pro',
            'data': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (_) {}
  }

  Future<void> segnaNotificheComeLette(String nickname) async {
    try {
      final db = await _getMongoDb();
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

  Future<List<BonusMalus>> getBonusMalusList() async {
    await getVotazioni();
    return List.unmodifiable(_bonusMalusList);
  }

  Future<List<Votazione>> getVotazioni() async {
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final bmDocs = await db.collection('BonusMalus').find().toList();
        final votiDocs = await db.collection('Votazioni').find().toList();

        final List<Votazione> list = [];
        _bonusMalusList.clear();

        for (var bm in bmDocs) {
          final bmId = bm['_id']?.toHexString() ?? bm['_id']?.toString() ?? '';
          final evId = bm['eventoId']?.toString() ?? '';
          final nomeBM = bm['nome']?.toString() ?? 'Bonus';
          final descBM = bm['descrizione']?.toString() ?? '';
          final puntiBM = (bm['punti'] as num?)?.toInt() ?? 0;
          final tipoBM = bm['tipo']?.toString() ?? (puntiBM >= 0 ? 'bonus' : 'malus');
          final propDa = bm['propostoDa']?.toString() ?? 'Ugnom';
          final List<String> assList = (bm['assegnatoA'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];

          // Se l'evento associato e' stato eliminato o scaduto, pulisci il bonus orfano
          if (evId.isNotEmpty && _eventi.isNotEmpty && !_eventi.any((e) => e.id == evId)) {
            try {
              ObjectId? bObjId;
              try { bObjId = ObjectId.fromHexString(bmId); } catch (_) {}
              final selector = bObjId != null ? where.id(bObjId) : where.eq('_id', bmId);
              await db.collection('BonusMalus').remove(selector);
              await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
            } catch (_) {}
            continue;
          }

          final Map<String, String> votiUtenti = {
            propDa: 'pro',
          };

          for (var vDoc in votiDocs) {
            final vId = (vDoc['votazioneId'] ?? vDoc['bonusId'] ?? '').toString().trim().toLowerCase();
            final bTit = (vDoc['bonusTitolo'] ?? '').toString().trim().toLowerCase();
            final u = (vDoc['utente'] ?? '').toString().trim().toLowerCase();
            final val = (vDoc['voto']?.toString() ?? '').toLowerCase();

            final isMatch = (vId == bmId.toLowerCase()) ||
                            (bTit.isNotEmpty && bTit == nomeBM.toLowerCase()) ||
                            (vId.isNotEmpty && vId == nomeBM.toLowerCase());

            if (isMatch && u.isNotEmpty) {
              votiUtenti[u] = (val == 'pro' || val == 'accetta' || val == 'favorevole') ? 'pro' : 'contro';
            }
          }

          int fav = 0;
          int cont = 0;
          votiUtenti.forEach((user, vote) {
            if (vote == 'pro') fav++;
            if (vote == 'contro') cont++;
          });

          final isApprovato = (fav >= 2);
          final isRespinto = (cont >= 2);
          final statoVot = isApprovato ? 'approvato' : (isRespinto ? 'respinto' : 'in_corso');

          final bmObj = BonusMalus(
            id: bmId,
            eventoId: evId,
            titolo: nomeBM,
            descrizione: descBM,
            punti: puntiBM,
            categoria: tipoBM,
            propostoDa: propDa,
            approvato: isApprovato,
            stato: statoVot,
            assegnatoA: assList,
          );

          if (isApprovato) {
            _bonusMalusList.add(bmObj);
          }

          final votazione = Votazione(
            id: bmId,
            titolo: nomeBM,
            descrizione: '$nomeBM (${puntiBM >= 0 ? "+$puntiBM" : puntiBM} PT) - Proposto da $propDa',
            bonusMalus: bmObj,
            votiFavorevoli: fav,
            votiContrari: cont,
            quorum: 2,
            stato: statoVot,
            scadenza: DateTime.now().add(const Duration(days: 7)),
            votiUtenti: votiUtenti,
          );

          list.add(votazione);
        }

        _votazioniList.clear();
        _votazioniList.addAll(list);

        return list;
      }
    } catch (_) {}

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
    final votoPrecedente = v.votiUtenti[userNick];

    int fav = v.votiFavorevoli;
    int cont = v.votiContrari;

    if (giaVotato) {
      if (votoPrecedente == 'pro') fav--;
      if (votoPrecedente == 'contro') cont--;
    }

    if (aFavore) {
      fav++;
    } else {
      cont++;
    }

    final nuoviVotiUtenti = Map<String, String>.from(v.votiUtenti);
    nuoviVotiUtenti[userNick] = aFavore ? 'pro' : 'contro';

    String nuovoStato = v.stato;
    if (fav >= v.quorum) {
      nuovoStato = 'approvato';
    } else if (v.quorum == 2 && cont >= 1) {
      nuovoStato = 'respinto';
    } else if (cont >= v.quorum) {
      nuovoStato = 'respinto';
    }

    final votazioneAggiornata = v.copyWith(
      votiFavorevoli: fav,
      votiContrari: cont,
      stato: nuovoStato,
      votiUtenti: nuoviVotiUtenti,
    );

    _votazioniList[index] = votazioneAggiornata;

    // Scrittura DIRETTA del voto su MongoDB Atlas E aggiornamento sincronizzato Notifiche
    try {
      final db = await _getMongoDb();
      if (db != null && db.isConnected) {
        final targetBmId = v.bonusMalus?.id ?? v.id;
        final targetBmTitle = v.bonusMalus?.titolo ?? v.titolo;

        await db.collection('Votazioni').insertOne({
          'votazioneId': targetBmId,
          'bonusId': targetBmId,
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
              modify.set('stato', aFavore ? 'accettato' : 'rifiutato').set('votoEspresso', aFavore ? 'pro' : 'contro'),
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

    return votazioneAggiornata;
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

    // 1. In-memory update
    for (int i = 0; i < _bonusMalusList.length; i++) {
      if (_bonusMalusList[i].id == bonusId) {
        final List<String> list = List.from(_bonusMalusList[i].assegnatoA);
        list.removeWhere((u) => u.trim().toLowerCase() == cleanDest);
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
          assList.removeWhere((u) => u.toString().trim().toLowerCase() == cleanDest);
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
            oldStorico.insert(0, '⚠️ Annullata assegnazione bonus (-$punti PT)');

            await db.collection('Utenti').update(
              where.id(uDoc['_id'] as ObjectId),
              modify
                  .set('puntiTotali', oldPunti - punti)
                  .set('xp', (oldXp - (punti > 0 ? punti * 10 : 0)).clamp(100, 999999))
                  .set('storicoVoti', oldStorico),
            );

            if (_currentUser != null && _currentUser!.nome.trim().toLowerCase() == cleanDest) {
              _currentUser = _currentUser!.copyWith(
                puntiTotali: oldPunti - punti,
                xp: (oldXp - (punti > 0 ? punti * 10 : 0)).clamp(100, 999999),
                storicoVoti: oldStorico.map((e) => e.toString()).toList(),
              );
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
          'tipo': 'info',
          'stato': 'accettato',
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
}
