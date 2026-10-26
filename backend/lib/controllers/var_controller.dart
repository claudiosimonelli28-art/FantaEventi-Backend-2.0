import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/richiesta_var.dart';
import '../models/utente.dart';
import '../utils/nickname_helper.dart';

class VarController {
  // Helper per risposte JSON
  Response _jsonResponse(dynamic data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _errorResponse(String message, {int statusCode = 400}) {
    return Response(
      statusCode,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }

  // POST /api/var/crea
  Future<Response> creaRichiestaVar(Request request) async {
    try {
      final body = await request.readAsString();
      if (body.isEmpty) return _errorResponse('Body richiesta mancante');
      final data = jsonDecode(body) as Map<String, dynamic>;

      final eventoId = data['eventoId']?.toString() ?? '';
      final eventoTitolo = data['eventoTitolo']?.toString() ?? '';
      final tipo = data['tipo']?.toString() ?? 'bonus';
      final bonusMalusId = data['bonusMalusId']?.toString() ?? '';
      final bonusMalusTitolo = data['bonusMalusTitolo']?.toString() ?? '';
      final punti = (data['punti'] as num?)?.toInt() ?? 0;
      final richiedente = data['richiedente']?.toString() ?? '';
      final bersaglio = data['bersaglio']?.toString() ?? richiedente;
      final descrizione = data['descrizione']?.toString() ?? '';
      final fotoBase64 = data['fotoBase64'] as String?;
      final testimoni = (data['testimoni'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final giudice = data['giudice']?.toString() ?? '';
      final penalitaPunti = (data['penalitaPunti'] as num?)?.toInt() ?? -10;

      if (eventoId.isEmpty || richiedente.isEmpty || giudice.isEmpty) {
        return _errorResponse('Campi obbligatori mancanti: eventoId, richiedente o giudice');
      }

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

      final result = await DbService.instance.richiesteVarCollection.insertOne(varDoc);
      final varId = (varDoc['_id'] as ObjectId?)?.oid ??
          (result.id is ObjectId ? (result.id as ObjectId).oid : result.id.toString());

      final ts = now.millisecondsSinceEpoch;

      // 1. Notifica al Giudice
      final ptSign = punti >= 0 ? '+$punti' : '$punti';
      final msgGiudice = tipo == 'bonus'
          ? '$richiedente ha richiesto la verifica VAR per il bonus "$bonusMalusTitolo" ($ptSign PT).'
          : '$richiedente ha denunciato $bersaglio al VAR per il malus "$bonusMalusTitolo" ($ptSign PT).';

      await DbService.instance.notificheCollection.insertOne({
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

      // 2. Notifiche ai Testimoni
      for (var t in testimoni) {
        await DbService.instance.notificheCollection.insertOne({
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

      print('📺 [VAR] Nuova richiesta creata con ID $varId da $richiedente (Giudice: $giudice)');
      return _jsonResponse({'success': true, 'id': varId, 'varId': varId});
    } catch (e) {
      print('❌ [VAR] Errore creazione richiesta: $e');
      return _errorResponse(e.toString(), statusCode: 500);
    }
  }

  // GET /api/var/dettaglio?id=...
  Future<Response> getRichiestaVar(Request request) async {
    try {
      final id = request.url.queryParameters['id'] ?? '';
      if (id.isEmpty) return _errorResponse('Parametro id mancante');

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(id);
      } catch (_) {}

      final selector = objId != null ? where.id(objId) : where.eq('_id', id);
      final doc = await DbService.instance.richiesteVarCollection.findOne(selector);
      if (doc == null) {
        return _errorResponse('Richiesta VAR non trovata', statusCode: 404);
      }

      final resMap = Map<String, dynamic>.from(doc);
      if (resMap['_id'] is ObjectId) {
        resMap['_id'] = (resMap['_id'] as ObjectId).oid;
      }
      return _jsonResponse(resMap);
    } catch (e) {
      return _errorResponse(e.toString(), statusCode: 500);
    }
  }

  // GET /api/var/evento?eventoId=...
  Future<Response> getRichiesteVarEvento(Request request) async {
    try {
      final eventoId = request.url.queryParameters['eventoId'] ?? '';
      if (eventoId.isEmpty) return _errorResponse('Parametro eventoId mancante');

      final docs = await DbService.instance.richiesteVarCollection.find(
        where.eq('eventoId', eventoId).excludeFields(['fotoBase64']),
      ).toList();

      final list = docs.map((d) {
        final map = Map<String, dynamic>.from(d);
        if (map['_id'] is ObjectId) {
          map['_id'] = (map['_id'] as ObjectId).oid;
        }
        return map;
      }).toList();

      return _jsonResponse(list);
    } catch (e) {
      return _errorResponse(e.toString(), statusCode: 500);
    }
  }

  // GET /api/var/giudice?giudice=...
  Future<Response> getRichiesteVarGiudice(Request request) async {
    try {
      final giudice = request.url.queryParameters['giudice'] ?? '';
      if (giudice.isEmpty) return _errorResponse('Parametro giudice mancante');

      final docs = await DbService.instance.richiesteVarCollection.find(
        where.eq('stato', 'in_attesa').excludeFields(['fotoBase64']),
      ).toList();

      final uDocs = await DbService.instance.utentiCollection.find().toList();
      final cleanGiudice = NicknameHelper.resolve(giudice, uDocs);

      final filtered = docs.where((d) {
        final dGiudice = (d['giudice'] ?? '').toString().trim();
        return NicknameHelper.isSame(dGiudice, cleanGiudice, uDocs);
      }).map((d) {
        final map = Map<String, dynamic>.from(d);
        if (map['_id'] is ObjectId) {
          map['_id'] = (map['_id'] as ObjectId).oid;
        }
        return map;
      }).toList();

      return _jsonResponse(filtered);
    } catch (e) {
      return _errorResponse(e.toString(), statusCode: 500);
    }
  }

  // POST /api/var/vota-testimone
  Future<Response> votaTestimonianza(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final varId = data['varId']?.toString() ?? '';
      final testimone = data['testimone']?.toString() ?? data['testimoneNick']?.toString() ?? '';
      final conferma = data['conferma'] == true || data['conferma']?.toString() == 'true';

      if (varId.isEmpty || testimone.isEmpty) {
        return _errorResponse('Campi varId o testimone mancanti');
      }

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(varId);
      } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', varId);

      final doc = await DbService.instance.richiesteVarCollection.findOne(selector);
      if (doc == null) return _errorResponse('Richiesta VAR non trovata', statusCode: 404);
      if (doc['stato'] != 'in_attesa') {
        return _errorResponse('Questa richiesta VAR è già stata decisa');
      }

      final uDocs = await DbService.instance.utentiCollection.find().toList();
      final cleanNick = NicknameHelper.resolve(testimone, uDocs);

      await DbService.instance.richiesteVarCollection.update(
        selector,
        modify.set('votiTestimoni.${cleanNick.toLowerCase()}', conferma),
      );

      // Aggiorna notifica testimone a stato votato in modo sicuro tramite _id
      final notDocs = await DbService.instance.notificheCollection.find(
        where.eq('varId', varId),
      ).toList();
      for (var nDoc in notDocs) {
        if (nDoc['_id'] is ObjectId) {
          final dDest = (nDoc['destinatario'] ?? '').toString().trim();
          final dTipo = (nDoc['tipo'] ?? '').toString();
          if (dTipo == 'var_testimone' && NicknameHelper.isSame(dDest, cleanNick, uDocs)) {
            await DbService.instance.notificheCollection.update(
              where.id(nDoc['_id'] as ObjectId),
              modify.set('stato', conferma ? 'confermato' : 'negato').set('letto', true),
            );
          }
        }
      }

      print('👀 [VAR] Voto testimonianza registrato per $cleanNick su VAR $varId: $conferma');
      return _jsonResponse({'success': true});
    } catch (e) {
      return _errorResponse(e.toString(), statusCode: 500);
    }
  }

  // POST /api/var/decidi
  Future<Response> decidiRichiesta(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final varId = data['varId']?.toString() ?? '';
      final giudice = data['giudice']?.toString() ?? data['giudiceNick']?.toString() ?? '';
      final approva = data['approva'] == true || data['approva']?.toString() == 'true';
      final sanzionaFalsaTestimonianza = data['sanzionaFalsaTestimonianza'] == true ||
          data['sanzionaFalsaTestimonianza']?.toString() == 'true';

      if (varId.isEmpty || giudice.isEmpty) {
        return _errorResponse('Campi varId o giudice mancanti');
      }

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(varId);
      } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', varId);

      final doc = await DbService.instance.richiesteVarCollection.findOne(selector);
      if (doc == null) return _errorResponse('Richiesta VAR non trovata', statusCode: 404);
      if (doc['stato'] != 'in_attesa') {
        return _errorResponse('Questa richiesta VAR è già stata decisa in precedenza');
      }

      final richiesta = RichiestaVar.fromMap(doc);
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;
      final uDocs = await DbService.instance.utentiCollection.find().toList();
      final ptStr = richiesta.punti >= 0 ? '+${richiesta.punti}' : '${richiesta.punti}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      // Reperimento partecipanti all'evento per broadcast
      final evDocs = await DbService.instance.eventiCollection.find().toList();
      final targetEv = evDocs.firstWhere(
        (e) => (e['_id']?.toString() == richiesta.eventoId ||
                (e['_id'] is ObjectId && (e['_id'] as ObjectId).oid == richiesta.eventoId) ||
                e['id']?.toString() == richiesta.eventoId ||
                e['titolo']?.toString().toLowerCase() == richiesta.eventoTitolo.toLowerCase()),
        orElse: () => <String, dynamic>{},
      );
      final Set<String> eventParticipants = {};
      if (targetEv.isNotEmpty) {
        final pList = List.from(targetEv['partecipanti'] ?? []);
        final iList = List.from(targetEv['invitati'] ?? []);
        final cUser = (targetEv['propostoDa'] ?? targetEv['creatore'] ?? '').toString().trim();
        if (cUser.isNotEmpty) eventParticipants.add(NicknameHelper.resolve(cUser, uDocs));
        for (var p in [...pList, ...iList]) {
          final s = p.toString().trim();
          if (s.isNotEmpty) eventParticipants.add(NicknameHelper.resolve(s, uDocs));
        }
      }

      final cleanRichiedente = NicknameHelper.resolve(richiesta.richiedente, uDocs);
      final cleanBersaglio = NicknameHelper.resolve(richiesta.bersaglio, uDocs);
      final cleanGiudice = NicknameHelper.resolve(giudice, uDocs);
      bool isSanzionato = false;
      int penaltyApplied = 0;

      if (approva) {
        // 1. Assegna punti al bersaglio
        final logText = '📺 VAR: Ricevuto ${richiesta.punti >= 0 ? "Bonus" : "Malus"} "${richiesta.bonusMalusTitolo}" ($ptStr PT) per l\'evento "${richiesta.eventoTitolo}" ($timeStr)';

        for (var uDoc in uDocs) {
          if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['nome'] ?? '', cleanBersaglio, uDocs)) {
            final curPts = (uDoc['puntiTotali'] as num?)?.toInt() ?? 0;
            final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
            final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
            final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);
            final prog = XpProgression.aggiungiXp(
              livelloAttuale: curLiv,
              xpLivelloAttuale: curXp,
              deltaXp: richiesta.punti > 0 ? richiesta.punti * 2 : 0,
              xpTotaliAttuali: curTot,
            );
            final curStorico = List<String>.from(uDoc['storicoVoti'] ?? []);
            curStorico.insert(0, logText);
            await DbService.instance.utentiCollection.update(
              where.id(uDoc['_id'] as ObjectId),
              modify
                .set('puntiTotali', curPts + richiesta.punti)
                .set('xp', prog.xp)
                .set('livello', prog.livello)
                .set('xpProssimoLivello', prog.xpProssimoLivello)
                .set('xpTotali', prog.xpTotali)
                .set('storicoVoti', curStorico),
            );
            break;
          }
        }

        // Aggiorna BonusMalus corrispondente
        ObjectId? bmObjId;
        try {
          bmObjId = ObjectId.fromHexString(richiesta.bonusMalusId);
        } catch (_) {}
        final bmSelector = bmObjId != null ? where.id(bmObjId) : where.eq('_id', richiesta.bonusMalusId);
        final bmDoc = await DbService.instance.bonusMalusCollection.findOne(bmSelector);
        if (bmDoc != null) {
          final curAss = List<dynamic>.from(bmDoc['assegnatoA'] ?? []);
          final bool isMulti = bmDoc['riassegnabileMoltepliciVolte'] == true;
          if (isMulti || !curAss.any((u) => NicknameHelper.isSame(u.toString(), cleanBersaglio, uDocs))) {
            curAss.add(cleanBersaglio);
          }
          await DbService.instance.bonusMalusCollection.update(
            where.id(bmDoc['_id'] as ObjectId),
            modify.set('assegnatoA', curAss),
          );
        }

        // 2. Se era una denuncia Malus, assegna +25 XP al richiedente per merito civico
        if (richiesta.tipo == 'malus') {
          for (var uDoc in uDocs) {
            if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['nome'] ?? '', cleanRichiedente, uDocs)) {
              final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
              final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
              final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);
              final prog = XpProgression.aggiungiXp(
                livelloAttuale: curLiv,
                xpLivelloAttuale: curXp,
                deltaXp: 25,
                xpTotaliAttuali: curTot,
              );
              await DbService.instance.utentiCollection.update(
                where.id(uDoc['_id'] as ObjectId),
                modify
                  .set('xp', prog.xp)
                  .set('livello', prog.livello)
                  .set('xpProssimoLivello', prog.xpProssimoLivello)
                  .set('xpTotali', prog.xpTotali),
              );
              break;
            }
          }
        }

        // 3. Aggiorna stato RichiestaVar ed ELIMINA la foto dal DB
        await DbService.instance.richiesteVarCollection.update(
          selector,
          modify
              .set('stato', 'approvata')
              .set('dataDecisione', now.toIso8601String())
              .set('giudiceEffettivo', cleanGiudice)
              .unset('fotoBase64'),
        );

        // 4. Invia notifica al richiedente
        await DbService.instance.notificheCollection.insertOne({
          'notificaId': 'var_res_${ts}_${cleanRichiedente.toLowerCase()}',
          'mittente': cleanGiudice,
          'destinatario': cleanRichiedente,
          'titolo': '📺 VAR: Richiesta Approvata! ✅',
          'messaggio': 'Il Giudice ha convalidato la tua segnalazione per "${richiesta.bonusMalusTitolo}". I punti sono stati assegnati.',
          'eventoId': richiesta.eventoId,
          'varId': varId,
          'tipo': 'var_esito',
          'stato': 'approvata',
          'letto': false,
          'data': now.toIso8601String(),
        });

        // 5. Se il bersaglio è diverso dal richiedente, notifica al bersaglio
        if (!NicknameHelper.isSame(cleanBersaglio, cleanRichiedente, uDocs)) {
          await DbService.instance.notificheCollection.insertOne({
            'notificaId': 'var_target_${ts}_${cleanBersaglio.toLowerCase()}',
            'mittente': cleanGiudice,
            'destinatario': cleanBersaglio,
            'titolo': '📺 VAR: Sentenza Convalidata! ⚖️',
            'messaggio': 'Il Giudice ha convalidato "${richiesta.bonusMalusTitolo}" ($ptStr PT) a tuo nome per l\'evento "${richiesta.eventoTitolo}".',
            'eventoId': richiesta.eventoId,
            'varId': varId,
            'tipo': 'var_esito',
            'stato': 'approvata',
            'letto': false,
            'data': now.toIso8601String(),
          });
        }

        // 6. Notifica broadcast agli altri partecipanti
        for (var p in eventParticipants) {
          if (NicknameHelper.isSame(p, cleanRichiedente, uDocs) ||
              NicknameHelper.isSame(p, cleanBersaglio, uDocs) ||
              NicknameHelper.isSame(p, cleanGiudice, uDocs)) {
            continue;
          }
          await DbService.instance.notificheCollection.insertOne({
            'notificaId': 'var_bcast_${ts}_${p.toLowerCase()}',
            'mittente': cleanGiudice,
            'destinatario': p,
            'titolo': '📺 VAR: Sentenza Convalidata',
            'messaggio': 'Il Giudice ha convalidato "${richiesta.bonusMalusTitolo}" ($ptStr PT) a $cleanBersaglio per "${richiesta.eventoTitolo}".',
            'eventoId': richiesta.eventoId,
            'varId': varId,
            'tipo': 'var_esito',
            'stato': 'approvata',
            'letto': false,
            'data': now.toIso8601String(),
          });
        }
      } else {
        // Rigettata
        final bool doSanzione = sanzionaFalsaTestimonianza && richiesta.tipo == 'malus';
        isSanzionato = doSanzione;

        if (doSanzione) {
          final penalty = (richiesta.penalitaPunti != 0 ? richiesta.penalitaPunti.abs() : 10) * -1;
          penaltyApplied = penalty;
          final cleanEvId = richiesta.eventoId.trim();

          for (var uDoc in uDocs) {
            if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['nome'] ?? '', cleanRichiedente, uDocs)) {
              final curPts = (uDoc['puntiTotali'] as num?)?.toInt() ?? 0;
              final curStorico = List<String>.from(uDoc['storicoVoti'] ?? []);
              curStorico.insert(0, '🚨 Sanzione VAR: Falsa Testimonianza ($penalty PT) per l\'evento "${richiesta.eventoTitolo}" ($timeStr)');

              await DbService.instance.utentiCollection.update(
                where.id(uDoc['_id'] as ObjectId),
                modify.set('puntiTotali', curPts + penalty).set('storicoVoti', curStorico),
              );
              break;
            }
          }

          // Inserisce o aggiorna Malus formale unico in BonusMalus per la classifica live
          final evTitle = richiesta.eventoTitolo.trim();
          var existingBmDoc = await DbService.instance.bonusMalusCollection.findOne(
            where.eq('eventoId', cleanEvId).and(
              where.eq('nome', '🚨 Falsa Testimonianza VAR').or(where.eq('titolo', '🚨 Falsa Testimonianza VAR')),
            ),
          );
          if (existingBmDoc == null && evTitle.isNotEmpty) {
            existingBmDoc = await DbService.instance.bonusMalusCollection.findOne(
              where.eq('eventoId', evTitle).and(
                where.eq('nome', '🚨 Falsa Testimonianza VAR').or(where.eq('titolo', '🚨 Falsa Testimonianza VAR')),
              ),
            );
          }

          if (existingBmDoc != null) {
            final curAss = List<dynamic>.from(existingBmDoc['assegnatoA'] ?? []);
            curAss.add(cleanRichiedente);
            await DbService.instance.bonusMalusCollection.update(
              where.id(existingBmDoc['_id'] as ObjectId),
              modify.set('assegnatoA', curAss).set('punti', penalty).set('riassegnabileMoltepliciVolte', true),
            );
          } else {
            await DbService.instance.bonusMalusCollection.insertOne({
              'eventoId': cleanEvId,
              'nome': '🚨 Falsa Testimonianza VAR',
              'descrizione': 'Penalità inflitta dal Giudice per denuncia infondata o falsa testimonianza.',
              'punti': penalty,
              'assegnatoA': [cleanRichiedente],
              'riassegnabileMoltepliciVolte': true,
              'propostoDa': cleanGiudice,
              'approvato': true,
              'createdAt': now.toIso8601String(),
            });
          }
        }

        // Aggiorna stato RichiestaVar ed ELIMINA foto
        await DbService.instance.richiesteVarCollection.update(
          selector,
          modify
              .set('stato', 'rifiutata')
              .set('dataDecisione', now.toIso8601String())
              .set('sanzioneApplicata', doSanzione)
              .set('giudiceEffettivo', cleanGiudice)
              .unset('fotoBase64'),
        );

        // Notifica al richiedente
        final sanzioneNotice = doSanzione ? ' Ti sono stati decurtati ${richiesta.penalitaPunti} PT per segnalazione infondata.' : '';
        await DbService.instance.notificheCollection.insertOne({
          'notificaId': 'var_res_${ts}_${cleanRichiedente.toLowerCase()}',
          'mittente': cleanGiudice,
          'destinatario': cleanRichiedente,
          'titolo': doSanzione ? '🚨 VAR: Denuncia Respinta e Sanzionata! ❌' : '📺 VAR: Segnalazione Respinta ❌',
          'messaggio': 'Il Giudice ha esaminato e respinto la tua segnalazione per "${richiesta.bonusMalusTitolo}".$sanzioneNotice',
          'eventoId': richiesta.eventoId,
          'varId': varId,
          'tipo': 'var_esito',
          'stato': doSanzione ? 'sanzionato' : 'rifiutata',
          'letto': false,
          'data': now.toIso8601String(),
        });

        // Se il bersaglio è diverso dal richiedente, notifica al bersaglio che è stato scagionato
        if (!NicknameHelper.isSame(cleanBersaglio, cleanRichiedente, uDocs)) {
          await DbService.instance.notificheCollection.insertOne({
            'notificaId': 'var_target_${ts}_${cleanBersaglio.toLowerCase()}',
            'mittente': cleanGiudice,
            'destinatario': cleanBersaglio,
            'titolo': '📺 VAR: Segnalazione Respinta',
            'messaggio': 'La segnalazione contro di te per "${richiesta.bonusMalusTitolo}" è stata esaminata e respinta dal Giudice.',
            'eventoId': richiesta.eventoId,
            'varId': varId,
            'tipo': 'var_esito',
            'stato': 'rifiutata',
            'letto': false,
            'data': now.toIso8601String(),
          });
        }
      }

      // Aggiorna notifica per il giudice e testimoni in modo sicuro tramite _id
      final notDocs = await DbService.instance.notificheCollection.find(
        where.eq('varId', varId),
      ).toList();
      for (var nDoc in notDocs) {
        if (nDoc['_id'] is ObjectId) {
          final dDest = (nDoc['destinatario'] ?? '').toString().trim();
          final dTipo = (nDoc['tipo'] ?? '').toString();
          if (NicknameHelper.isSame(dDest, cleanGiudice, uDocs) || dTipo == 'var_richiesta_giudice') {
            await DbService.instance.notificheCollection.update(
              where.id(nDoc['_id'] as ObjectId),
              modify.set('stato', approva ? 'approvata' : 'rifiutata').set('letto', true),
            );
          } else if (dTipo == 'var_testimone' && nDoc['stato'] == 'in_attesa') {
            await DbService.instance.notificheCollection.update(
              where.id(nDoc['_id'] as ObjectId),
              modify.set('stato', 'concluso').set('letto', true),
            );
          }
        }
      }

      print('📺 [VAR] Decisione registrata per VAR $varId da $cleanGiudice: approvato=$approva');
      return _jsonResponse({
        'success': true,
        'varId': varId,
        'approvato': approva,
        'richiedente': cleanRichiedente,
        'bersaglio': cleanBersaglio,
        'giudice': cleanGiudice,
        'eventoId': richiesta.eventoId,
        'eventoTitolo': richiesta.eventoTitolo,
        'bonusMalusTitolo': richiesta.bonusMalusTitolo,
        'punti': richiesta.punti,
        'tipo': richiesta.tipo,
        'destinatari': eventParticipants.toList(),
        'sanzionato': isSanzionato,
        'penalita': penaltyApplied,
      });
    } catch (e) {
      print('❌ [VAR] Errore decisione: $e');
      return _errorResponse(e.toString(), statusCode: 500);
    }
  }
}
