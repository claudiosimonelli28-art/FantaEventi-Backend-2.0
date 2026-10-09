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
      final eventoId = data['eventoId']?.toString() ?? '';
      final eventoTitolo = data['eventoTitolo']?.toString() ?? data['titoloEvento']?.toString() ?? '';
      final nome = data['nome']?.toString() ?? '';

      // Controllo anti-duplicato
      final existing = await DbService.instance.bonusMalusCollection.findOne(
        where.eq('eventoId', eventoId).and(where.eq('nome', nome)),
      );

      String bmHexId;
      if (existing != null) {
        bmHexId = existing['_id'] is ObjectId
            ? (existing['_id'] as ObjectId).toHexString()
            : (existing['_id']?.toString() ?? '');
      } else {
        final bmMap = {
          'eventoId': eventoId,
          'nome': nome,
          'descrizione': data['descrizione'] ?? '',
          'punti': (data['punti'] as num?)?.toInt() ?? 0,
          'categoria': data['categoria'] ?? 'Goliardia',
          'tipo': data['tipo'] ?? 'bonus',
          'propostoDa': propostoDaUtente,
          'stato': data['stato'] ?? 'in_votazione',
          'riassegnabileMoltepliciVolte': data['riassegnabileMoltepliciVolte'] == true,
        };

        final res = await DbService.instance.bonusMalusCollection.insertOne(bmMap);
        bmHexId = res.id?.toHexString() ?? '';
      }

      // Registra voto pro del proponente in Votazioni se non presente
      try {
        final existingVote = await DbService.instance.votazioniCollection.findOne(
          where.eq('votazioneId', bmHexId).and(where.eq('utente', propostoDaUtente)),
        );
        if (existingVote == null) {
          await DbService.instance.votazioniCollection.insertOne({
            'votazioneId': bmHexId,
            'bonusId': bmHexId,
            'eventoId': eventoId,
            'bonusTitolo': nome,
            'utente': propostoDaUtente,
            'voto': 'pro',
            'stato': 'in_votazione',
            'data': DateTime.now().toIso8601String(),
          });
        }
      } catch (_) {}

      // Invia notifica ai partecipanti ed invitati dell'evento
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
                    e['titolo']?.toString().toLowerCase() == eventoTitolo.toLowerCase()),
            orElse: () => {},
          );
        }

        final eventoNome = (evDoc['nome'] ?? evDoc['titolo'] ?? (eventoTitolo.isNotEmpty ? eventoTitolo : 'Evento')).toString();

        final Set<String> destinatariSet = {};
        final creatore = (evDoc['propostoDa'] ?? evDoc['creatore'] ?? '').toString().trim();
        if (creatore.isNotEmpty) destinatariSet.add(creatore);

        final rawPart = (evDoc['partecipanti'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        destinatariSet.addAll(rawPart);

        final rawInv = (evDoc['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        destinatariSet.addAll(rawInv);

        destinatariSet.removeWhere((d) => d.trim().toLowerCase() == propostoDaUtente.trim().toLowerCase() || d.trim().isEmpty);

        for (var destUser in destinatariSet) {
          final existingNot = await DbService.instance.db.collection('Notifiche').findOne(
            where.eq('destinatario', destUser).and(where.eq('bonusId', bmHexId)),
          );

          if (existingNot == null) {
            final notifica = {
              'mittente': propostoDaUtente,
              'destinatario': destUser,
              'titolo': '⭐ Nuova Proposta: $nome',
              'messaggio': '$propostoDaUtente ha proposto il ${((data['punti'] as num?)?.toInt() ?? 0) >= 0 ? "bonus" : "malus"} "$nome" (${((data['punti'] as num?)?.toInt() ?? 0) >= 0 ? "+${data['punti']}" : data['punti']} PT) per l\'evento "$eventoNome"!',
              'eventoId': eventoId,
              'bonusId': bmHexId,
              'bonusTitolo': nome,
              'tipo': 'bonus_malus',
              'stato': 'in_attesa',
              'letto': false,
              'data': DateTime.now().toIso8601String(),
            };
            await DbService.instance.db.collection('Notifiche').insertOne(notifica);
            print('🔔 [Notifiche] Inviata notifica a "$destUser" per la proposta del bonus "$nome"!');
          }
        }
      } catch (err) {
        print('⚠️ Errore invio notifica bonus: $err');
      }

      return Response.ok(
        jsonEncode({'message': 'Bonus/Malus creato con successo', 'id': bmHexId}),
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
