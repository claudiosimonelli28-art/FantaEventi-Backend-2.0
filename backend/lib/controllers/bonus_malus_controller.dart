import 'dart:convert';
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

      final bm = BonusMalus(
        eventoId: data['eventoId'] ?? '',
        nome: data['nome'] ?? '',
        descrizione: data['descrizione'] ?? '',
        punti: (data['punti'] as num?)?.toInt() ?? 0,
        tipo: data['tipo'] ?? 'bonus',
      );

      final res = await DbService.instance.bonusMalusCollection.insertOne(bm.toMap());
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
}
