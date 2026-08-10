import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/bonus_malus.dart';

class BonusMalusController {
  // GET /api/bonusmalus
  Future<Response> getBonusMalus(Request request) async {
    try {
      final docs = await DbService.instance.bonusMalusCollection.find().toList();
      final lista = docs.map((d) => BonusMalus.fromMap(d).toJson()).toList();
      return Response.ok(
        jsonEncode(lista),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/bonusmalus/crea
  Future<Response> creaBonusMalus(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final propostoDaUtente = data['utente']?.toString() ?? data['propostoDa']?.toString() ?? 'Un utente';

      final bmMap = {
        'eventoId': data['eventoId'] ?? '',
        'nome': data['nome'] ?? '',
        'descrizione': data['descrizione'] ?? '',
        'punti': (data['punti'] as num?)?.toInt() ?? 0,
        'tipo': data['tipo'] ?? 'bonus',
        'propostoDa': propostoDaUtente,
        'stato': data['stato'] ?? 'in_votazione',
      };

      final res = await DbService.instance.bonusMalusCollection.insertOne(bmMap);

      // Invia notifica al creatore dell'evento
      final eventoId = data['eventoId']?.toString() ?? '';
      final eventoTitolo = data['eventoTitolo']?.toString() ?? data['titoloEvento']?.toString() ?? '';

      try {
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
        
        final allEventi = await DbService.instance.eventiCollection.find().toList();
        Map<String, dynamic>? evDoc;
        if (objId != null) {
          evDoc = allEventi.firstWhere((e) => e['_id'] == objId, orElse: () => {});
        }
        if (evDoc == null || evDoc.isEmpty) {
          evDoc = allEventi.firstWhere(
            (e) => (e['id']?.toString() == eventoId ||
                    e['nome']?.toString().toLowerCase() == eventoTitolo.toLowerCase() ||
                    e['titolo']?.toString().toLowerCase() == eventoTitolo.toLowerCase() ||
                    e['nome']?.toString().toLowerCase().contains('9 maggio') == true),
            orElse: () => {},
          );
        }

        final eventoNome = (evDoc?['nome'] ?? evDoc?['titolo'] ?? eventoTitolo.isNotEmpty ? eventoTitolo : 'Evento').toString();

        final Set<String> destinatariSet = {'Cloud', 'cloud'};
        final creatore = (evDoc?['propostoDa'] ?? evDoc?['creatore'] ?? '').toString().trim();
        if (creatore.isNotEmpty) destinatariSet.add(creatore);

        final rawPart = (evDoc?['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        destinatariSet.addAll(rawPart);

        final rawInv = (evDoc?['invitati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        destinatariSet.addAll(rawInv);

        destinatariSet.removeWhere((d) => d.trim().toLowerCase() == propostoDaUtente.trim().toLowerCase() || d.trim().isEmpty);

        for (var destUser in destinatariSet) {
          final notifica = {
            'mittente': propostoDaUtente,
            'destinatario': destUser,
            'titolo': '⭐ Nuova Proposta Bonus/Malus',
            'messaggio': '$propostoDaUtente ha proposto il bonus "${data['nome']}" (${((data['punti'] as num?)?.toInt() ?? 0) >= 0 ? "+${data['punti']}" : data['punti']} PT) per l\'evento "$eventoNome"!',
            'eventoId': eventoId,
            'tipo': 'info',
            'stato': 'in_attesa',
            'data': DateTime.now().toIso8601String(),
          };
          await DbService.instance.db.collection('Notifiche').insertOne(notifica);
          print('🔔 [Notifiche] Inviata notifica a "$destUser" per la proposta del bonus "${data['nome']}"!');
        }
      } catch (err) {
        print('⚠️ Errore invio notifica bonus: $err');
      }

      return Response.ok(
        jsonEncode({'message': 'Bonus/Malus creato con successo', 'id': res.id?.toHexString()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/bonusmalus/elimina
  Future<Response> eliminaBonusMalus(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final bmId = data['id']?.toString() ?? data['bonusMalusId']?.toString() ?? '';
      final utente = data['utente']?.toString() ?? '';

      print('📥 [HTTP POST /api/bonusmalus/elimina] ID "$bmId" da "$utente"');

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(bmId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('nome', bmId);

      await DbService.instance.bonusMalusCollection.remove(selector);
      print('🗑️ Bonus/Malus "$bmId" eliminato con successo dal database!');

      return Response.ok(
        jsonEncode({'message': 'Bonus/Malus eliminato con successo'}),
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
