import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../utils/nickname_helper.dart';

class SegnalazioneController {
  /// Registra una nuova segnalazione inviata da un utente
  Future<Response> creaSegnalazione(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final segnalatore = (data['segnalatore'] ?? '').toString().trim();
      final segnalato = (data['segnalato'] ?? '').toString().trim();
      final motivo = (data['motivo'] ?? '').toString().trim();
      final dettagli = (data['dettagli'] ?? '').toString().trim();

      if (segnalatore.isEmpty || segnalato.isEmpty || motivo.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Parametri segnalatore, segnalato e motivo obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final doc = {
        'segnalatore': segnalatore,
        'segnalato': segnalato,
        'motivo': motivo,
        'dettagli': dettagli,
        'timestamp': DateTime.now().toIso8601String(),
        'stato': 'in_attesa', // in_attesa | ammonito | bannato | archiviata
      };

      await DbService.instance.segnalazioniCollection.insertOne(doc);

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Segnalazione registrata con successo'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// Recupera tutte le segnalazioni (riservato all'amministratore / Cloud)
  Future<Response> getSegnalazioni(Request request) async {
    try {
      final utenteRichiedente = (request.url.queryParameters['utente'] ?? '').toString().trim().toLowerCase();
      // Riservato a Cloud / Admin
      if (utenteRichiedente.isNotEmpty && utenteRichiedente != 'cloud' && utenteRichiedente != 'claudio') {
        return Response.forbidden(
          jsonEncode({'error': 'Accesso riservato all\'amministratore'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final docs = await DbService.instance.segnalazioniCollection
          .find(where.sortBy('timestamp', descending: true))
          .toList();

      final list = docs.map((d) {
        final idStr = d['_id'] is ObjectId ? (d['_id'] as ObjectId).oid : d['_id']?.toString() ?? '';
        return {
          'id': idStr,
          'segnalatore': d['segnalatore'] ?? '',
          'segnalato': d['segnalato'] ?? '',
          'motivo': d['motivo'] ?? '',
          'dettagli': d['dettagli'] ?? '',
          'timestamp': d['timestamp'] ?? '',
          'stato': d['stato'] ?? 'in_attesa',
        };
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

  /// Gestisce una segnalazione: Ammonisci, Banna o Archivia (riservato a Cloud)
  Future<Response> gestisciSegnalazione(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final segnalazioneId = (data['segnalazioneId'] ?? '').toString().trim();
      final azione = (data['azione'] ?? '').toString().trim().toLowerCase(); // ammonisci | banna | archivia
      final segnalato = (data['segnalato'] ?? '').toString().trim();

      if (segnalazioneId.isEmpty || azione.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'segnalazioneId e azione obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? sObjId;
      try {
        sObjId = ObjectId.fromHexString(segnalazioneId);
      } catch (_) {}

      final sSelector = sObjId != null ? where.id(sObjId) : where.eq('_id', segnalazioneId);

      final uDocs = await DbService.instance.utentiCollection.find().toList();
      final cleanSegnalato = NicknameHelper.resolve(segnalato, uDocs);

      if (azione == 'ammonisci') {
        await DbService.instance.segnalazioniCollection.update(
          sSelector,
          modify.set('stato', 'ammonito'),
        );

        // Notifica ufficiale di ammonimento al segnalato
        await DbService.instance.notificheCollection.insertOne({
          'tipo': 'ammonizione_utente',
          'titolo': '⚠️ Richiamo di Moderazione',
          'messaggio': 'Sei stato segnalato per comportamenti non conformi al regolamento di FantaEventi. Ti invitiamo al rispetto delle regole della community.',
          'destinatario': cleanSegnalato,
          'timestamp': DateTime.now().toIso8601String(),
          'letto': false,
        });

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'ammonito'}),
          headers: {'content-type': 'application/json'},
        );
      } else if (azione == 'banna') {
        await DbService.instance.segnalazioniCollection.update(
          sSelector,
          modify.set('stato', 'bannato'),
        );

        // Disabilita account su Utenti
        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (NicknameHelper.isSame(uNick, cleanSegnalato, uDocs)) {
            final uId = uDoc['_id'] as ObjectId;
            await DbService.instance.utentiCollection.update(
              where.id(uId),
              modify.set('isBanned', true),
            );
            break;
          }
        }

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'bannato'}),
          headers: {'content-type': 'application/json'},
        );
      } else if (azione == 'archivia') {
        await DbService.instance.segnalazioniCollection.update(
          sSelector,
          modify.set('stato', 'archiviata'),
        );

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'archiviata'}),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.badRequest(
        body: jsonEncode({'error': 'Azione non riconosciuta (ammonisci, banna, archivia)'}),
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
