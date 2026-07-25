import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/votazione.dart';

class VotazioneController {
  // GET /api/votazioni
  Future<Response> getVotazioni(Request request) async {
    try {
      final docs = await DbService.instance.votazioniCollection.find().toList();
      final lista = docs.map((d) => Votazione.fromMap(d).toJson()).toList();
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

  // POST /api/votazioni/vota
  Future<Response> vota(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final votazione = Votazione(
        eventoId: data['eventoId'] ?? '',
        utenteId: data['utenteId'] ?? '',
        destinatarioId: data['destinatarioId'] ?? '',
        bonusMalusId: data['bonusMalusId'] ?? '',
        punti: (data['punti'] as num?)?.toInt() ?? 0,
        note: data['note'],
      );

      final res = await DbService.instance.votazioniCollection.insertOne(votazione.toMap());
      
      // Aggiorna anche i punti totali del destinatario in utenti
      if (votazione.destinatarioId.isNotEmpty) {
        await DbService.instance.utentiCollection.update(
          where.id(ObjectId.fromHexString(votazione.destinatarioId)),
          modify.inc('puntiTotali', votazione.punti),
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Votazione registrata con successo', 'id': res.id?.toHexString()}),
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
