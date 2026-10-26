import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';

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

      final list = docs.map((d) => {
        'id': d['_id'] is ObjectId ? (d['_id'] as ObjectId).oid : (d['_id']?.toString() ?? ''),
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
        'data': d['data']?.toString() ?? DateTime.now().toIso8601String(),
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
