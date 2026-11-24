import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../services/fcm_service.dart';
import '../utils/nickname_helper.dart';
import 'utente_controller.dart';

class NotificaController {
  // GET /api/notifiche?utente=NICKNAME
  Future<Response> getNotificheUtente(Request request) async {
    try {
      final dest = request.url.queryParameters['utente'] ?? '';
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final cleanDest = NicknameHelper.resolve(dest, uDocs).trim().toLowerCase();
      final allNotifiche = await DbService.instance.notificheCollection.find().toList();
      final docs = allNotifiche.where((d) {
        final rawDest = (d['destinatario'] ?? '').toString().trim();
        final resolvedDest = NicknameHelper.resolve(rawDest, uDocs).trim().toLowerCase();
        return resolvedDest == cleanDest || rawDest.toLowerCase() == cleanDest || cleanDest.isEmpty;
      }).toList();

      // Self-healing per notifiche VAR già decise
      final Map<String, String> varStati = {};
      try {
        final hasVarNotifs = docs.any((d) => (d['varId'] ?? '').toString().isNotEmpty);
        if (hasVarNotifs) {
          final varDocs = await DbService.instance.richiesteVarCollection
              .find(where.fields(['stato']))
              .toList();
          for (var vd in varDocs) {
            final vid = vd['_id'] is ObjectId ? (vd['_id'] as ObjectId).oid : (vd['_id']?.toString() ?? '');
            final vst = (vd['stato'] ?? '').toString().toLowerCase();
            if (vid.isNotEmpty && vst.isNotEmpty) {
              varStati[vid] = vst;
            }
          }
        }
      } catch (_) {}

      final list = <Map<String, dynamic>>[];
      for (var d in docs) {
        final map = Map<String, dynamic>.from(d);
        final docId = d['_id'] is ObjectId ? (d['_id'] as ObjectId).oid : (d['_id']?.toString() ?? '');
        map['id'] = docId;
        map.remove('_id');
        map['mittente'] ??= 'FantaEventi';
        map['destinatario'] ??= '';
        map['titolo'] ??= 'Nuova Notifica';
        map['messaggio'] ??= '';
        map['eventoId'] ??= '';
        map['bonusId'] ??= '';
        map['bonusTitolo'] ??= '';
        map['varId'] ??= '';
        map['tipo'] ??= 'invito';
        map['stato'] ??= 'in_attesa';
        map['letto'] = map['letto'] == true;
        map['data'] = map['data']?.toString() ?? map['timestamp']?.toString() ?? DateTime.now().toIso8601String();

        final varId = map['varId'].toString();
        final tipo = map['tipo'].toString().toLowerCase();
        if (varId.isNotEmpty &&
            (tipo.contains('giudice') || tipo == 'richiesta_var') &&
            map['stato'] == 'in_attesa') {
          final realVarStato = varStati[varId];
          if (realVarStato == 'approvata' || realVarStato == 'rifiutata') {
            map['stato'] = realVarStato;
            map['letto'] = true;
            if (d['_id'] is ObjectId) {
              DbService.instance.notificheCollection.update(
                where.id(d['_id'] as ObjectId),
                modify.set('stato', realVarStato).set('letto', true),
              );
            }
          }
        }

        list.add(map);
      }

      return Response.ok(
        jsonEncode(list),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/push
  Future<Response> inviaPush(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawDest = (data['destinatari'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final titolo = (data['titolo'] ?? 'FantaEventi').toString();
      final messaggio = (data['messaggio'] ?? '').toString();
      final payloadData = (data['data'] is Map)
          ? Map<String, dynamic>.from(data['data'] as Map)
          : <String, dynamic>{};

      final sent = await FcmService.instance.inviaPushAUtenti(
        rawDest,
        titolo: titolo,
        messaggio: messaggio,
        data: payloadData,
      );

      return Response.ok(
        jsonEncode({'success': true, 'sent': sent}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/segna-letta
  Future<Response> segnaLetta(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final notificaId = data['notificaId']?.toString() ?? data['id']?.toString() ?? '';

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null
          ? where.id(objId)
          : where.eq('notificaId', notificaId).or(where.eq('_id', notificaId));

      await DbService.instance.notificheCollection.update(
        selector,
        modify.set('letto', true),
      );

      return Response.ok(
        jsonEncode({'message': 'Notifica segnata come letta'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/segna-tutte-lette
  Future<Response> segnaTutteLette(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawNick = (data['destinatario'] ?? data['utente'] ?? data['nickname'] ?? '').toString().trim();
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final cleanNick = NicknameHelper.resolve(rawNick, uDocs).trim().toLowerCase();

      final docs = await DbService.instance.notificheCollection.find().toList();
      for (var d in docs) {
        final dest = NicknameHelper.resolve((d['destinatario'] ?? '').toString(), uDocs).trim().toLowerCase();
        if ((dest == cleanNick || cleanNick.isEmpty) && d['letto'] != true && d['_id'] is ObjectId) {
          await DbService.instance.notificheCollection.update(
            where.id(d['_id'] as ObjectId),
            modify.set('letto', true),
          );
        }
      }

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Tutte le notifiche segnate come lette'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/elimina
  Future<Response> eliminaNotifica(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final notificaId = (data['notificaId'] ?? data['id'] ?? '').toString().trim();
      if (notificaId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'notificaId obbligatorio'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null
          ? where.id(objId)
          : where.eq('notificaId', notificaId).or(where.eq('_id', notificaId));

      await DbService.instance.notificheCollection.remove(selector);
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Notifica eliminata'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/elimina-multiple
  Future<Response> eliminaNotificheMultiple(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawIds = (data['notificaIds'] ?? data['ids']) as List<dynamic>? ?? [];
      for (var rawId in rawIds) {
        final id = rawId.toString().trim();
        if (id.isEmpty) continue;
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(id); } catch (_) {}
        final selector = objId != null
            ? where.id(objId)
            : where.eq('notificaId', id).or(where.eq('_id', id));
        await DbService.instance.notificheCollection.remove(selector);
      }
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Notifiche eliminate'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/elimina-tutte
  Future<Response> eliminaTutteNotifiche(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawDest = (data['destinatario'] ?? data['utente'] ?? '').toString().trim();
      final soloLette = data['soloLette'] == true;
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final cleanNick = NicknameHelper.resolve(rawDest, uDocs).trim().toLowerCase();

      final docs = await DbService.instance.notificheCollection.find().toList();
      for (var d in docs) {
        final dest = NicknameHelper.resolve((d['destinatario'] ?? '').toString(), uDocs).trim().toLowerCase();
        final isLetto = d['letto'] == true;
        if (dest == cleanNick || cleanNick.isEmpty) {
          if (!soloLette || isLetto) {
            if (d['_id'] is ObjectId) {
              await DbService.instance.notificheCollection.remove(where.id(d['_id'] as ObjectId));
            }
          }
        }
      }
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Notifiche eliminate con successo'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/benvenuto
  Future<Response> assicuraNotificaBenvenuto(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawNick = (data['nickname'] ?? data['utente'] ?? '').toString().trim();
      if (rawNick.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'nickname obbligatorio'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final uDocs = await UtenteController.getCachedUtentiDocs();
      final nickname = NicknameHelper.resolve(rawNick, uDocs);
      final allDocs = await DbService.instance.notificheCollection.find(
        where.eq('destinatario', nickname),
      ).toList();

      final hasWelcome = allDocs.any((n) =>
          (n['titolo'] ?? '').toString().contains('Benvenuto') ||
          (n['mittente'] ?? '').toString().contains('Redazione'));

      if (!hasWelcome) {
        await DbService.instance.notificheCollection.insertOne({
          'mittente': 'Redazione FantaEventi 👑',
          'destinatario': nickname,
          'titolo': 'Benvenuto in FantaEventi! 🎉',
          'messaggio':
              'Ciao $nickname! Benvenuto nella community ufficiale di FantaEventi. Da qui riceverai tutti gli inviti ad eventi dei tuoi amici, le notifiche del VAR e gli aggiornamenti di classifica. Puoi eliminare qualsiasi notifica toccando la \'X\' in alto a destra nella card!',
          'tipo': 'benvenuto',
          'stato': 'letto',
          'letto': false,
          'data': DateTime.now().toIso8601String(),
        });
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/rispondi
  Future<Response> rispondiNotifica(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final notificaId = data['notificaId']?.toString() ?? '';
      final azione = (data['azione']?.toString() ?? '').toLowerCase();
      final utente = data['utente']?.toString() ?? '';

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);
      final doc = await DbService.instance.notificheCollection.findOne(selector);

      if (doc != null) {
        final eventoId = doc['eventoId']?.toString() ?? '';
        final isPro = azione == 'accetta' || azione == 'pro' || azione == 'favorevole';
        final nuovoStato = isPro ? 'accettato' : 'rifiutato';

        await DbService.instance.notificheCollection.update(
          selector,
          modify.set('stato', nuovoStato).set('votoEspresso', isPro ? 'pro' : 'contro').set('letto', true),
        );

        if (azione == 'accetta' && eventoId.isNotEmpty) {
          ObjectId? evObjId;
          try { evObjId = ObjectId.fromHexString(eventoId); } catch (_) {}
          final evSelector = evObjId != null ? where.id(evObjId) : where.eq('nome', eventoId);
          final evDoc = await DbService.instance.eventiCollection.findOne(evSelector);

          if (evDoc != null) {
            final pullList = {
              utente,
              utente.toLowerCase(),
              utente.toUpperCase(),
              utente.trim(),
              utente.trim().toLowerCase(),
            }.toList();

            await DbService.instance.eventiCollection.update(
              evSelector,
              modify
                .addToSet('partecipanti', utente)
                .pullAll('invitati', pullList),
            );
          }
        }

        // Accettazione richiesta di amicizia
        if (azione == 'accetta' && doc['tipo'] == 'richiesta_amicizia') {
          final mittente = (doc['mittente'] ?? '').toString().trim();
          final destinatario = (doc['destinatario'] ?? utente).toString().trim();
          if (mittente.isNotEmpty && destinatario.isNotEmpty) {
            await DbService.instance.utentiCollection.update(
              where.eq('nickname', mittente).or(where.eq('nome', mittente)),
              modify.addToSet('amici', destinatario),
            );
            await DbService.instance.utentiCollection.update(
              where.eq('nickname', destinatario).or(where.eq('nome', destinatario)),
              modify.addToSet('amici', mittente),
            );
            UtenteController.invalidateCache();
          }
        }
      }

      return Response.ok(
        jsonEncode({'message': 'Risposta inviata con successo!'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
