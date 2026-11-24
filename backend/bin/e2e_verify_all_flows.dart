import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';
import 'package:backend/db/db_service.dart';

void _assert(bool condition, String message) {
  if (!condition) {
    throw StateError('ASSERTION FAILED: $message');
  }
  print('  ✅ $message');
}

Future<Map<String, dynamic>> _postJson(String baseUrl, String path, Map<String, dynamic> body) async {
  final res = await http.post(
    Uri.parse('$baseUrl$path'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw StateError('POST $path failed (${res.statusCode}): ${res.body}');
  }
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<dynamic> _getJson(String baseUrl, String path) async {
  final res = await http.get(Uri.parse('$baseUrl$path'));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw StateError('GET $path failed (${res.statusCode}): ${res.body}');
  }
  return jsonDecode(res.body);
}

Future<void> main(List<String> args) async {
  String baseUrl = 'http://localhost:18088/api';
  bool spawnLocal = true;
  for (final arg in args) {
    if (arg.startsWith('--url=')) {
      baseUrl = arg.substring('--url='.length);
      spawnLocal = false;
    }
  }

  Process? serverProc;
  final String ts = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
  final String playerA = 'E2E_Alpha_$ts';
  final String playerB = 'E2E_Beta_$ts';
  String? createdEventId;
  String? createdBmBonusId;
  String? createdBmMalusId;
  String? createdVarId;

  try {
    if (spawnLocal) {
      print('🚀 Avvio server locale su porta 18088 per collaudo E2E completo...');
      serverProc = await Process.start(
        'dart',
        ['run', 'bin/server.dart'],
        workingDirectory: Directory.current.path,
        environment: {...Platform.environment, 'PORT': '18088'},
      );
      final readyCompleter = Completer<void>();
      serverProc.stdout.transform(utf8.decoder).listen((chunk) {
        if (chunk.contains('Server avviato in ascolto') && !readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      });
      serverProc.stderr.transform(utf8.decoder).listen((chunk) {
        stderr.write('[SERVER ERR] $chunk');
      });
      await readyCompleter.future.timeout(const Duration(seconds: 25));
      print('✅ Server locale pronto su $baseUrl');
    } else {
      print('🌐 Esecuzione collaudo E2E contro server remoto: $baseUrl');
    }

    // =========================================================================
    // TEST 1: BURST CONCORRENTE (Simulazione HomeViewModel.loadData() parallelo)
    // =========================================================================
    print('\n--- TEST 1: Burst concorrente (18 richieste GET parallele come HomeView) ---');
    for (int round = 1; round <= 3; round++) {
      final responses = await Future.wait([
        _getJson(baseUrl, '/eventi?utente=Cloud'),
        _getJson(baseUrl, '/utenti?utente=Cloud'),
        _getJson(baseUrl, '/votazioni'),
        _getJson(baseUrl, '/notifiche?utente=Cloud'),
        _getJson(baseUrl, '/bonusmalus'),
        _getJson(baseUrl, '/segnalazioni'),
      ]);
      _assert(responses.length == 6, 'Round $round: tutte le 6 chiamate concorrenti hanno risposto 200 OK senza ConnectionException');
    }

    // =========================================================================
    // TEST 2: FOTO PROFILO CLOUD & GUARDIA NOTIFICA BENVENUTO VETERANO
    // =========================================================================
    print('\n--- TEST 2: Foto profilo Cloud e guardia notifica benvenuto ---');
    final utentiInit = (await _getJson(baseUrl, '/utenti?utente=Cloud')) as List<dynamic>;
    final cloudMap = utentiInit.firstWhere((u) => u['nickname'] == 'Cloud') as Map<String, dynamic>;
    final ugnomMap = utentiInit.firstWhere((u) => u['nickname'] == 'Ugnom') as Map<String, dynamic>;
    final pippoMap = utentiInit.firstWhere((u) => u['nickname'] == 'Pippoforte') as Map<String, dynamic>;

    final origCloudAvatar = (cloudMap['avatarUrl'] ?? '').toString();
    _assert(origCloudAvatar.isNotEmpty, 'GET /api/utenti restituisce avatarUrl reale per Cloud (${origCloudAvatar.length} chars)');
    _assert((ugnomMap['avatarUrl'] ?? '').toString().isNotEmpty, 'GET /api/utenti restituisce avatarUrl reale per Ugnom');
    _assert((pippoMap['avatarUrl'] ?? '').toString().isNotEmpty, 'GET /api/utenti restituisce avatarUrl reale per Pippoforte');

    const testB64 = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';
    await _postJson(baseUrl, '/utenti/avatar', {'utente': 'Cloud', 'avatarUrl': testB64});

    final utentiAfterAv = (await _getJson(baseUrl, '/utenti?utente=Cloud')) as List<dynamic>;
    final cloudAfterAv = utentiAfterAv.firstWhere((u) => u['nickname'] == 'Cloud') as Map<String, dynamic>;
    final directAv = (await _getJson(baseUrl, '/utenti/avatar?utente=Cloud')) as Map<String, dynamic>;
    _assert(cloudAfterAv['avatarUrl'] == testB64, 'GET /api/utenti restituisce istantaneamente la nuova foto profilo di Cloud');
    _assert(directAv['avatarUrl'] == testB64, 'GET /api/utenti/avatar restituisce istantaneamente la nuova foto profilo di Cloud');

    // Ripristino immediato foto originale di Cloud
    await _postJson(baseUrl, '/utenti/avatar', {'utente': 'Cloud', 'avatarUrl': origCloudAvatar});
    final directRestored = (await _getJson(baseUrl, '/utenti/avatar?utente=Cloud')) as Map<String, dynamic>;
    _assert(directRestored['avatarUrl'] == origCloudAvatar, 'Foto profilo originale di Cloud ripristinata al 100%');

    // Verifica guardia notifica di benvenuto su utente veterano Cloud
    final welcomeCloud = await _postJson(baseUrl, '/notifiche/benvenuto', {'nickname': 'Cloud'});
    _assert(welcomeCloud['skippedVeterano'] == true, 'POST /api/notifiche/benvenuto blocca la creazione per utente veterano Cloud');
    final cloudNots = (await _getJson(baseUrl, '/notifiche?utente=Cloud')) as List<dynamic>;
    final hasSpuriousWelcome = cloudNots.any((n) => n['tipo'] == 'benvenuto' || (n['titolo'] ?? '').toString().contains('Benvenuto'));
    _assert(!hasSpuriousWelcome, 'Cloud ha 0 notifiche di benvenuto nel Centro Notifiche');

    // =========================================================================
    // TEST 3: REGISTRAZIONE, NOTIFICA BENVENUTO NUOVO UTENTE, TUTORIAL +100 XP, AMICIZIA
    // =========================================================================
    print('\n--- TEST 3: Registrazione, Benvenuto nuovo iscritto, Tutorial +100 XP e Amicizia ---');
    final regA = await _postJson(baseUrl, '/registrazione', {
      'username': playerA,
      'email': '${playerA.toLowerCase()}@fantaeventi.test',
      'password': 'Password123!',
    });
    final regB = await _postJson(baseUrl, '/registrazione', {
      'username': playerB,
      'email': '${playerB.toLowerCase()}@fantaeventi.test',
      'password': 'Password123!',
    });
    _assert((regA['token'] ?? '').toString().isNotEmpty, 'Registrazione $playerA ha restituito JWT token valido');
    final codeB = (regB['utente']['codiceAmico'] ?? '').toString();
    _assert(codeB.startsWith('FE-'), 'Registrazione $playerB ha generato codiceAmico: $codeB');

    await _postJson(baseUrl, '/notifiche/benvenuto', {'nickname': playerA});
    final notsA1 = (await _getJson(baseUrl, '/notifiche?utente=$playerA')) as List<dynamic>;
    final welcomeA = notsA1.firstWhere((n) => n['tipo'] == 'benvenuto', orElse: () => null);
    _assert(welcomeA != null && welcomeA['letto'] == false && welcomeA['stato'] == 'in_attesa',
        'Nuovo iscritto $playerA riceve notifica di benvenuto con stato=in_attesa e letto=false (visibile sul campanellino)');

    final guidaRes = await _postJson(baseUrl, '/utenti/completa-guida', {'utente': playerA, 'awardXp': true});
    _assert(guidaRes['utente']['xp'] == 200 && guidaRes['utente']['haVistoGuida'] == true,
        'Completamento tutorial accredita +100 XP (100 -> 200 XP) e imposta haVistoGuida=true');

    await _postJson(baseUrl, '/notifiche/elimina', {'notificaId': welcomeA['id']});
    final welcomeA2 = await _postJson(baseUrl, '/notifiche/benvenuto', {'nickname': playerA});
    _assert(welcomeA2['skippedVeterano'] == true,
        'Dopo aver completato la guida, la notifica di benvenuto non viene mai più rigenerata');

    final reqFriend = await _postJson(baseUrl, '/utenti/amicizia/richiedi', {
      'mittente': playerA,
      'codiceAmico': codeB,
    });
    _assert(reqFriend['success'] == true, '$playerA ha inviato richiesta amicizia a $playerB tramite codice $codeB');

    final notsB1 = (await _getJson(baseUrl, '/notifiche?utente=$playerB')) as List<dynamic>;
    final friendNot = notsB1.firstWhere((n) => n['tipo'] == 'richiesta_amicizia', orElse: () => null);
    _assert(friendNot != null, '$playerB ha ricevuto la notifica di richiesta amicizia');

    await _postJson(baseUrl, '/utenti/amicizia/rispondi', {
      'notificaId': friendNot['id'],
      'mittente': playerA,
      'destinatario': playerB,
      'accetta': true,
    });
    final utentiAfterFriend = (await _getJson(baseUrl, '/utenti')) as List<dynamic>;
    final pADoc = utentiAfterFriend.firstWhere((u) => u['nickname'] == playerA) as Map<String, dynamic>;
    _assert((pADoc['amici'] as List).contains(playerB), '$playerA e $playerB sono ora amici confermati');

    // =========================================================================
    // TEST 4: CREAZIONE EVENTO, INVITO, PARTECIPAZIONE, PROPOSTA (+50 XP), VOTO (+25 XP)
    // =========================================================================
    print('\n--- TEST 4: Evento, Invito, Proposta Bonus/Malus (+50 XP) e Votazione Live (+25 XP) ---');
    final now = DateTime.now();
    final dtStart = now.add(const Duration(seconds: 5));
    final dtEnd = now.add(const Duration(seconds: 11));

    final evRes = await _postJson(baseUrl, '/eventi/crea', {
      'titolo': 'Evento_Collaudo_E2E_$ts',
      'descrizione': 'Test automatico ciclo completo',
      'data': dtStart.toIso8601String(),
      'dataFine': dtEnd.toIso8601String(),
      'luogo': 'Arena Test',
      'propostoDa': playerA,
      'invitati': [playerB],
      'penalitaFalsaTestimonianza': -10,
    });
    createdEventId = evRes['id']?.toString();
    _assert(createdEventId != null && createdEventId.isNotEmpty, 'Evento creato con ID: $createdEventId');

    await _postJson(baseUrl, '/eventi/partecipa', {
      'eventoId': createdEventId,
      'utente': playerB,
    });

    final bmBonusRes = await _postJson(baseUrl, '/bonusmalus/crea', {
      'eventoId': createdEventId,
      'eventoTitolo': 'Evento_Collaudo_E2E_$ts',
      'nome': 'Gol Vittoria E2E',
      'descrizione': 'Bonus test +30 PT',
      'punti': 30,
      'categoria': 'Goliardia',
      'utente': playerA,
    });
    createdBmBonusId = bmBonusRes['id']?.toString();

    final utentiAfterProp = (await _getJson(baseUrl, '/utenti')) as List<dynamic>;
    final pAAfterProp = utentiAfterProp.firstWhere((u) => u['nickname'] == playerA) as Map<String, dynamic>;
    _assert(pAAfterProp['xp'] == 250, 'Proposta Bonus accredita subito +50 XP a $playerA (200 -> 250 XP)');

    final notsBBeforeVote = (await _getJson(baseUrl, '/notifiche?utente=$playerB')) as List<dynamic>;
    final propNotB = notsBBeforeVote.firstWhere((n) => n['bonusId'] == createdBmBonusId, orElse: () => null);
    _assert(propNotB != null && propNotB['haGiaVotato'] == false && propNotB['votazioneChiusa'] == false,
        'Notifica proposta arricchita per $playerB: haGiaVotato=false, votazioneChiusa=false');

    await _postJson(baseUrl, '/votazioni/vota', {
      'id': createdBmBonusId,
      'utente': playerB,
      'aFavore': true,
    });

    final utentiAfterVote = (await _getJson(baseUrl, '/utenti')) as List<dynamic>;
    final pBAfterVote = utentiAfterVote.firstWhere((u) => u['nickname'] == playerB) as Map<String, dynamic>;
    _assert(pBAfterVote['xp'] == 125, 'Voto su proposta accredita subito +25 XP a $playerB (100 -> 125 XP)');

    final notsBAfterVote = (await _getJson(baseUrl, '/notifiche?utente=$playerB')) as List<dynamic>;
    final propNotBAfter = notsBAfterVote.firstWhere((n) => n['bonusId'] == createdBmBonusId, orElse: () => null);
    _assert(
        propNotBAfter != null &&
            propNotBAfter['haGiaVotato'] == true &&
            propNotBAfter['votoEspresso'] == 'pro' &&
            propNotBAfter['votazioneChiusa'] == true &&
            propNotBAfter['esitoVotazione'] == 'approvato',
        'Notifica proposta arricchita dopo il voto: haGiaVotato=true, votazioneChiusa=true, esitoVotazione=approvato');

    // Seconda proposta (Malus -15 PT) per testare il VAR
    final bmMalusRes = await _postJson(baseUrl, '/bonusmalus/crea', {
      'eventoId': createdEventId,
      'eventoTitolo': 'Evento_Collaudo_E2E_$ts',
      'nome': 'Fallo Tattico E2E',
      'descrizione': 'Malus test -15 PT',
      'punti': -15,
      'categoria': 'Goliardia',
      'utente': playerA,
    });
    createdBmMalusId = bmMalusRes['id']?.toString();
    await _postJson(baseUrl, '/votazioni/vota', {
      'id': createdBmMalusId,
      'utente': playerB,
      'aFavore': true,
    });

    // =========================================================================
    // TEST 5: AVVIO EVENTO IN CORSO (+100 XP CREATORE), ASSEGNAZIONE, STORNO, VAR
    // =========================================================================
    print('\n--- TEST 5: Avvio Evento in_corso (+100 XP), Assegnazione, Storno e Sentenza VAR ---');
    final waitInCorsoMs = dtStart.difference(DateTime.now()).inMilliseconds + 800;
    if (waitInCorsoMs > 0) {
      await Future.delayed(Duration(milliseconds: waitInCorsoMs));
    }

    final evInCorsoList = (await _getJson(baseUrl, '/eventi?utente=$playerA')) as List<dynamic>;
    final evInCorso = evInCorsoList.firstWhere((e) => e['id'] == createdEventId) as Map<String, dynamic>;
    _assert(evInCorso['stato'] == 'in_corso', 'Evento transitato automaticamente a in_corso');

    final utentiInCorso = (await _getJson(baseUrl, '/utenti')) as List<dynamic>;
    final pAInCorso = utentiInCorso.firstWhere((u) => u['nickname'] == playerA) as Map<String, dynamic>;
    _assert(pAInCorso['xp'] == 400, 'Avvio evento con partecipanti accredita +100 XP al creatore $playerA (300 -> 400 XP)');

    // Assegna Bonus +30 PT a playerA
    await _postJson(baseUrl, '/bonusmalus/assegna', {
      'eventoId': createdEventId,
      'bonusId': createdBmBonusId,
      'utenteDestinatario': playerA,
      'eventoTitolo': 'Evento_Collaudo_E2E_$ts',
      'bonusTitolo': 'Gol Vittoria E2E',
      'mittente': playerA,
      'punti': 30,
    });
    var uCheck = (await _getJson(baseUrl, '/utenti')) as List<dynamic>;
    var pACheck = uCheck.firstWhere((u) => u['nickname'] == playerA) as Map<String, dynamic>;
    _assert(pACheck['puntiTotali'] == 30 && pACheck['xp'] == 700,
        'Assegnazione Bonus +30 PT aggiorna puntiTotali=30 e +300 XP (400 -> 700 XP)');

    // Storna Bonus +30 PT e verifica che punti tornino a 0 ma XP restino 700
    await _postJson(baseUrl, '/bonusmalus/annulla-assegnazione', {
      'eventoId': createdEventId,
      'bonusId': createdBmBonusId,
      'utenteDestinatario': playerA,
      'punti': 30,
    });
    uCheck = (await _getJson(baseUrl, '/utenti')) as List<dynamic>;
    pACheck = uCheck.firstWhere((u) => u['nickname'] == playerA) as Map<String, dynamic>;
    _assert(pACheck['puntiTotali'] == 0 && pACheck['xp'] == 700,
        'Storno assegnazione riporta puntiTotali=0 preservando gli XP permanenti (700 XP)');

    // Riassegna Bonus +30 PT a playerA per la vittoria finale
    await _postJson(baseUrl, '/bonusmalus/assegna', {
      'eventoId': createdEventId,
      'bonusId': createdBmBonusId,
      'utenteDestinatario': playerA,
      'eventoTitolo': 'Evento_Collaudo_E2E_$ts',
      'bonusTitolo': 'Gol Vittoria E2E',
      'mittente': playerA,
      'punti': 30,
    });

    // Crea denuncia VAR Malus (-15 PT) di playerA contro playerB
    final varRes = await _postJson(baseUrl, '/var/crea', {
      'eventoId': createdEventId,
      'eventoTitolo': 'Evento_Collaudo_E2E_$ts',
      'tipo': 'malus',
      'bonusMalusId': createdBmMalusId,
      'bonusMalusTitolo': 'Fallo Tattico E2E',
      'punti': -15,
      'richiedente': playerA,
      'bersaglio': playerB,
      'descrizione': 'Fallo netto documentato',
      'fotoBase64': testB64,
      'testimoni': [playerA],
      'giudice': playerA,
      'penalitaPunti': -10,
    });
    createdVarId = varRes['varId']?.toString();
    _assert(createdVarId != null && createdVarId.isNotEmpty, 'Richiesta VAR creata con ID: $createdVarId');

    await _postJson(baseUrl, '/var/vota-testimone', {
      'varId': createdVarId,
      'testimone': playerA,
      'conferma': true,
    });

    await _postJson(baseUrl, '/var/decidi', {
      'varId': createdVarId,
      'giudice': playerA,
      'approva': true,
      'sanzionaFalsaTestimonianza': false,
    });

    // Verifica che una sentenza VAR non possa essere stornata
    final rollbackVarRes = await http.post(
      Uri.parse('$baseUrl/bonusmalus/annulla-assegnazione'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'eventoId': createdEventId,
        'bonusId': createdBmMalusId,
        'utenteDestinatario': playerB,
        'punti': -15,
      }),
    );
    _assert(rollbackVarRes.statusCode == 400, 'Storno di un Malus convalidato dal VAR viene correttamente bloccato (HTTP 400)');

    // =========================================================================
    // TEST 6: CONCLUSIONE EVENTO -> TROFEO, BADGE PARTECIPAZIONE, 5 TITOLI HALL OF FAME
    // =========================================================================
    print('\n--- TEST 6: Conclusione Evento, Trofeo 1° Classificato, Badge e 5 Titoli Hall of Fame ---');
    final waitFineMs = dtEnd.difference(DateTime.now()).inMilliseconds + 1000;
    if (waitFineMs > 0) {
      await Future.delayed(Duration(milliseconds: waitFineMs));
    }

    final evConclusoList = (await _getJson(baseUrl, '/eventi?utente=$playerA')) as List<dynamic>;
    final evConcluso = evConclusoList.firstWhere((e) => e['id'] == createdEventId) as Map<String, dynamic>;
    _assert(evConcluso['stato'] == 'concluso', 'Evento transitato automaticamente a concluso');
    _assert(evConcluso['badgeVincitoreAssegnato'] == true && evConcluso['titoliAssegnati'] == true,
        'Evento ha calcolato e salvato badgeVincitoreAssegnato=true e titoliAssegnati=true');

    final utentiFinal = (await _getJson(baseUrl, '/utenti')) as List<dynamic>;
    final pAFinal = utentiFinal.firstWhere((u) => u['nickname'] == playerA) as Map<String, dynamic>;
    final pBFinal = utentiFinal.firstWhere((u) => u['nickname'] == playerB) as Map<String, dynamic>;

    _assert((pAFinal['badgeVincitore'] as List).isNotEmpty,
        '$playerA ha ricevuto il trofeo 🏆 Vincitore Evento in badgeVincitore');
    _assert((pAFinal['badgeList'] as List).any((b) => b.toString().contains('Evento_Collaudo_E2E_$ts')),
        '$playerA ha ricevuto il badge di partecipazione all\'evento');
    _assert((pBFinal['badgeList'] as List).any((b) => b.toString().contains('Evento_Collaudo_E2E_$ts')),
        '$playerB ha ricevuto il badge di partecipazione all\'evento');

    _assert(pAFinal['countGiudice'] == 1 && pAFinal['countSbirro'] == 1 && pAFinal['countGiustiziere'] == 1,
        '$playerA ha ricevuto i titoli L\'Avvocato (1), Lo Sbirro (1) e Il Giustiziere (1)');
    _assert(pBFinal['countReMalus'] == 1 && pBFinal['countFantasma'] == 1,
        '$playerB ha ricevuto i titoli Re dei Malus (1) e Il Fantasma (1)');

    print('\n🎉 TUTTI I TEST END-TO-END SONO PASSATI AL 100% SENZA ALCUN ERRORE!');
  } finally {
    print('\n🧹 Pulizia completa dati temporanei di test ($playerA, $playerB, evento $createdEventId)...');
    try {
      if (createdEventId != null && createdEventId.isNotEmpty) {
        await http.post(
          Uri.parse('$baseUrl/eventi/elimina'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'eventoId': createdEventId, 'utente': playerA}),
        );
      }
      if (createdVarId != null && createdVarId.isNotEmpty) {
        await DbService.instance.ensureConnected();
        ObjectId? vObj;
        try {
          vObj = ObjectId.fromHexString(createdVarId);
        } catch (_) {}
        if (vObj != null) {
          await DbService.instance.richiesteVarCollection.remove(where.id(vObj));
        }
        await DbService.instance.notificheCollection.remove(where.eq('varId', createdVarId));
      }
      if (createdBmBonusId != null) {
        await DbService.instance.ensureConnected();
        await DbService.instance.votazioniCollection.remove(where.eq('votazioneId', createdBmBonusId));
      }
      if (createdBmMalusId != null) {
        await DbService.instance.ensureConnected();
        await DbService.instance.votazioniCollection.remove(where.eq('votazioneId', createdBmMalusId));
      }
      await http.post(
        Uri.parse('$baseUrl/utenti/elimina-account'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nickname': playerA}),
      );
      await http.post(
        Uri.parse('$baseUrl/utenti/elimina-account'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nickname': playerB}),
      );
      await DbService.instance.close();
      print('✅ Pulizia DB completata: zero dati di test residui.');
    } catch (e) {
      print('⚠️ Nota durante pulizia: $e');
    }
    serverProc?.kill();
  }
}
