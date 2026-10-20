import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/richiesta_var.dart';

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
      final varId = (varDoc['_id'] as ObjectId?)?.toHexString() ??
          (result.id is ObjectId ? (result.id as ObjectId).toHexString() : result.id.toString());

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
        resMap['_id'] = (resMap['_id'] as ObjectId).toHexString();
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
          map['_id'] = (map['_id'] as ObjectId).toHexString();
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

      final cleanGiudice = giudice.trim().toLowerCase();
      final filtered = docs.where((d) {
        final dGiudice = (d['giudice'] ?? '').toString().trim().toLowerCase();
        return dGiudice == cleanGiudice;
      }).map((d) {
        final map = Map<String, dynamic>.from(d);
        if (map['_id'] is ObjectId) {
          map['_id'] = (map['_id'] as ObjectId).toHexString();
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

      final cleanNick = testimone.trim().toLowerCase();
      await DbService.instance.richiesteVarCollection.update(
        selector,
        modify.set('votiTestimoni.$cleanNick', conferma),
      );

      // Aggiorna notifica testimone a stato votato
      await DbService.instance.notificheCollection.update(
        where.eq('varId', varId).and(where.eq('destinatario', testimone)),
        modify.set('stato', conferma ? 'confermato' : 'negato').set('letto', true),
      );

      print('👀 [VAR] Voto testimonianza registrato per $testimone su VAR $varId: $conferma');
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

      if (approva) {
        // 1. Assegna punti al bersaglio
        final cleanDest = richiesta.bersaglio.trim().toLowerCase();
        final ptStr = richiesta.punti >= 0 ? '+${richiesta.punti}' : '${richiesta.punti}';
        final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        final logText = '📺 VAR: Ricevuto ${richiesta.punti >= 0 ? "Bonus" : "Malus"} "${richiesta.bonusMalusTitolo}" ($ptStr PT) per l\'evento "${richiesta.eventoTitolo}" ($timeStr)';

        // Aggiorna Utente destinatario
        final uDocs = await DbService.instance.utentiCollection.find().toList();
        for (var uDoc in uDocs) {
          final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
          if (uName == cleanDest) {
            final curPts = (uDoc['puntiTotali'] as num?)?.toInt() ?? 0;
            final curStorico = List<String>.from(uDoc['storicoVoti'] ?? []);
            curStorico.add(logText);
            await DbService.instance.utentiCollection.update(
              where.id(uDoc['_id'] as ObjectId),
              modify.set('puntiTotali', curPts + richiesta.punti).set('storicoVoti', curStorico),
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
          curAss.add(richiesta.bersaglio.trim());
          await DbService.instance.bonusMalusCollection.update(
            bmSelector,
            modify.set('assegnatoA', curAss),
          );
        }

        // 2. Se era una denuncia Malus, assegna +25 XP al richiedente
        if (richiesta.tipo == 'malus') {
          for (var uDoc in uDocs) {
            final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
            if (uName == richiesta.richiedente.trim().toLowerCase()) {
              final curXp = (uDoc['xp'] as num?)?.toInt() ?? ((uDoc['puntiEsperienza'] as num?)?.toInt() ?? 100);
              await DbService.instance.utentiCollection.update(
                where.id(uDoc['_id'] as ObjectId),
                modify.set('xp', curXp + 25).set('puntiEsperienza', curXp + 25),
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
              .unset('fotoBase64'),
        );

        // 4. Invia notifica al richiedente
        await DbService.instance.notificheCollection.insertOne({
          'notificaId': 'var_res_${ts}_${richiesta.richiedente.toLowerCase()}',
          'mittente': giudice,
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
          final penalty = (richiesta.penalitaPunti != 0 ? richiesta.penalitaPunti.abs() : 10) * -1;
          final cleanRichiedente = richiesta.richiedente.trim();
          final cleanEvId = richiesta.eventoId.trim();

          final uDocs = await DbService.instance.utentiCollection.find().toList();
          for (var uDoc in uDocs) {
            final uName = (uDoc['nome'] ?? uDoc['username'] ?? uDoc['nickname'] ?? '').toString().trim().toLowerCase();
            if (uName == cleanRichiedente.toLowerCase()) {
              final curPts = (uDoc['puntiTotali'] as num?)?.toInt() ?? 0;
              final curStorico = List<String>.from(uDoc['storicoVoti'] ?? []);
              final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              curStorico.add('🚨 Sanzione VAR: Falsa Testimonianza ($penalty PT) per l\'evento "${richiesta.eventoTitolo}" ($timeStr)');

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
              'propostoDa': giudice,
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
              .unset('fotoBase64'),
        );

        // Notifica al richiedente
        final sanzioneNotice = doSanzione ? ' Ti sono stati decurtati ${richiesta.penalitaPunti} PT per segnalazione infondata.' : '';
        await DbService.instance.notificheCollection.insertOne({
          'notificaId': 'var_res_${ts}_${richiesta.richiedente.toLowerCase()}',
          'mittente': giudice,
          'destinatario': richiesta.richiedente,
          'titolo': '📺 VAR: Segnalazione Respinta',
          'messaggio': 'Il Giudice ha esaminato e respinto la tua segnalazione per "${richiesta.bonusMalusTitolo}".$sanzioneNotice',
          'eventoId': richiesta.eventoId,
          'varId': varId,
          'tipo': 'var_esito',
          'stato': 'rifiutato',
          'letto': false,
          'data': now.toIso8601String(),
        });
      }

      // Aggiorna notifica per il giudice
      await DbService.instance.notificheCollection.update(
        where.eq('varId', varId).and(where.eq('destinatario', giudice)),
        modify.set('stato', approva ? 'approvata' : 'rifiutata').set('letto', true),
      );

      print('📺 [VAR] Decisione registrata per VAR $varId da $giudice: approvato=$approva');
      return _jsonResponse({'success': true});
    } catch (e) {
      print('❌ [VAR] Errore decisione: $e');
      return _errorResponse(e.toString(), statusCode: 500);
    }
  }
}
