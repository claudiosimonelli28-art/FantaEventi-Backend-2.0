import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import 'utente_controller.dart';

class NotificaController {
  // GET /api/notifiche?utente=NICKNAME
  Future<Response> getNotificheUtente(Request request) async {
    try {
      final dest = request.url.queryParameters['utente'] ?? '';
      final cleanDest = dest.trim().toLowerCase();
      final allNotifiche = await DbService.instance.notificheCollection.find().toList();
      final docs = allNotifiche.where((d) {
        final dDest = (d['destinatario'] ?? '').toString().trim().toLowerCase();
        return dDest == cleanDest || cleanDest.isEmpty;
      }).toList();

      final list = docs.map((d) {
        final map = Map<String, dynamic>.from(d);
        map['id'] = d['_id'] is ObjectId ? (d['_id'] as ObjectId).oid : (d['_id']?.toString() ?? '');
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
        map['data'] = map['data']?.toString() ?? DateTime.now().toIso8601String();
        return map;
      }).toList();

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

  // POST /api/notifiche/segna-letta
  Future<Response> segnaLetta(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final notificaId = data['notificaId']?.toString() ?? data['id']?.toString() ?? '';

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);

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
