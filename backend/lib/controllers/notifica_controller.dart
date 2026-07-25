import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';

class NotificaController {
  // GET /api/notifiche?utente=NICKNAME
  Future<Response> getNotificheUtente(Request request) async {
    try {
      final dest = request.url.queryParameters['utente'] ?? '';
      print('📥 [HTTP GET /api/notifiche] Recupero notifiche per "$dest"...');

      final docs = await DbService.instance.db.collection('Notifiche').find(
        where.eq('destinatario', dest).or(where.eq('destinatario', dest.toLowerCase())),
      ).toList();

      final list = docs.map((d) => {
        'id': d['_id']?.toHexString() ?? d['_id']?.toString() ?? '',
        'mittente': d['mittente'] ?? 'FantaEventi',
        'destinatario': d['destinatario'] ?? '',
        'titolo': d['titolo'] ?? 'Nuova Notifica',
        'messaggio': d['messaggio'] ?? '',
        'eventoId': d['eventoId'] ?? '',
        'tipo': d['tipo'] ?? 'invito', // 'invito', 'info'
        'stato': d['stato'] ?? 'in_attesa', // 'in_attesa', 'accettato', 'rifiutato'
        'data': d['data']?.toString() ?? DateTime.now().toIso8601String(),
      }).toList();

      return Response.ok(
        jsonEncode(list),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore recupero notifiche: $e');
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
      final azione = data['azione']?.toString() ?? ''; // 'accetta' o 'rifiuta'
      final utente = data['utente']?.toString() ?? '';

      print('📥 [HTTP POST /api/notifiche/rispondi] Notifica ID "$notificaId" -> Azione: $azione di $utente');

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(notificaId);
      } catch (_) {}

      final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);
      final doc = await DbService.instance.db.collection('Notifiche').findOne(selector);

      if (doc != null) {
        final eventoId = doc['eventoId']?.toString() ?? '';
        final nuovoStato = azione == 'accetta' ? 'accettato' : 'rifiutato';

        // Aggiorna la notifica su MongoDB
        await DbService.instance.db.collection('Notifiche').update(
          selector,
          modify.set('stato', nuovoStato),
        );

        // Se accetta, aggiungi l'utente ai partecipanti dell'evento!
        if (azione == 'accetta' && eventoId.isNotEmpty) {
          ObjectId? evObjId;
          try {
            evObjId = ObjectId.fromHexString(eventoId);
          } catch (_) {}

          final evSelector = evObjId != null ? where.id(evObjId) : where.eq('nome', eventoId);
          final evDoc = await DbService.instance.eventiCollection.findOne(evSelector);

          if (evDoc != null) {
            final List<dynamic> part = List.from(evDoc['partecipanti'] ?? []);
            if (!part.contains(utente)) {
              part.add(utente);
              await DbService.instance.eventiCollection.update(
                evSelector,
                modify.set('partecipanti', part),
              );
              print('✅ Utente "$utente" iscritto all\'evento su MongoDB a seguito dell\'accettazione!');
            }
          }
        }
      }

      return Response.ok(
        jsonEncode({'message': 'Risposta inviata con successo!'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore risposta notifica: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
