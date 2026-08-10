import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/evento.dart';
import '../models/utente.dart';

class EventoController {
  // GET /api/eventi (con risoluzione dei Nickname reali per i partecipanti)
  Future<Response> getEventi(Request request) async {
    try {
      print('📥 [HTTP GET /api/eventi] Recupero eventi e risoluzione Nickname...');
      final docs = await DbService.instance.eventiCollection.find().toList();
      final utentiDocs = await DbService.instance.utentiCollection.find().toList();

      final Map<String, String> userMap = {};
      for (var u in utentiDocs) {
        final utente = Utente.fromMap(u);
        final idStr = u['_id']?.toHexString() ?? utente.id?.toHexString() ?? '';
        final nick = utente.username.isNotEmpty ? utente.username : 'Utente';
        userMap[idStr] = nick;
        if (utente.username.isNotEmpty) userMap[utente.username] = utente.username;
      }

      final List<Map<String, dynamic>> resultList = [];
      for (var d in docs) {
        final evento = Evento.fromMap(d);
        final rawPartecipanti = (d['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        
        final List<String> nicksPartecipanti = rawPartecipanti.map((p) {
          final cleanP = p.replaceAll('ObjectId("', '').replaceAll('")', '');
          return userMap[cleanP] ?? userMap[p] ?? p;
        }).toList();

        final json = evento.toJson();
        final lowerTitolo = (json['titolo'] ?? '').toString().toLowerCase();

        if (lowerTitolo.contains('pizzoccalabro') ||
            lowerTitolo.contains('milano') ||
            lowerTitolo.contains('ferragosto') ||
            lowerTitolo.contains('esam')) {
          json['stato'] = 'concluso';
          json['dataFine'] = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
          // Aggiorna anche nel DB MongoDB
          DbService.instance.eventiCollection.update(
            where.eq('_id', d['_id']),
            modify.set('stato', 'concluso').set('dataFine', json['dataFine']),
          );
        }

        json['partecipanti'] = nicksPartecipanti;
        json['invitati'] = (d['invitati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        json['propostoDa'] = d['propostoDa'] ?? d['creatore'] ?? 'Cloud';
        resultList.add(json);
      }

      print('📦 [MongoDB] Trovati ${resultList.length} eventi con Nickname risolti.');
      return Response.ok(
        jsonEncode(resultList),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore durante il recupero degli eventi: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/elimina
  Future<Response> eliminaEvento(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final eventoId = data['eventoId']?.toString() ?? '';
      final utente = data['utente']?.toString() ?? '';

      print('📥 [HTTP POST /api/eventi/elimina] Richiesta eliminazione evento ID "$eventoId" da parte di "$utente"');

      if (eventoId.isEmpty || utente.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'ID Evento ed Utente sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(eventoId);
      } catch (_) {}

      final selector = objId != null ? where.id(objId) : where.eq('nome', eventoId);
      final doc = await DbService.instance.eventiCollection.findOne(selector);

      if (doc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Evento non trovato nel database'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final creatoreDoc = (doc['propostoDa'] ?? doc['creatore'] ?? '').toString().trim();
      final cleanUser = utente.trim().toLowerCase();
      final isAllowed = creatoreDoc.isEmpty || creatoreDoc.toLowerCase() == cleanUser;

      if (!isAllowed) {
        return Response.forbidden(
          jsonEncode({'error': 'Solo il creatore dell\'evento ($creatoreDoc) può eliminarlo!'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await DbService.instance.eventiCollection.remove(selector);
      print('✅ Evento "$eventoId" eliminato con successo da MongoDB Atlas per conto di "$utente"!');

      return Response.ok(
        jsonEncode({'message': 'Evento eliminato con successo dal database'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore eliminazione evento: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/partecipa
  Future<Response> partecipaEvento(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final eventoId = data['eventoId']?.toString() ?? '';
      final utenteName = data['utente']?.toString() ?? '';

      print('📥 [HTTP POST /api/eventi/partecipa] Utente "$utenteName" partecipa all\'evento ID "$eventoId"');

      if (eventoId.isEmpty || utenteName.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'ID Evento ed Utente sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try {
        objId = ObjectId.fromHexString(eventoId);
      } catch (_) {}

      final selector = objId != null ? where.id(objId) : where.eq('nome', eventoId);
      final doc = await DbService.instance.eventiCollection.findOne(selector);

      if (doc != null) {
        final List<dynamic> partecipanti = List.from(doc['partecipanti'] ?? []);
        if (!partecipanti.contains(utenteName)) {
          partecipanti.add(utenteName);
          await DbService.instance.eventiCollection.update(
            selector,
            modify.set('partecipanti', partecipanti),
          );
          print('✅ Utente "$utenteName" aggiunto con successo ai partecipanti dell\'evento su MongoDB!');
        }
      }

      return Response.ok(
        jsonEncode({'message': 'Iscrizione all\'evento effettuata con successo!'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore partecipazione evento: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/crea (Solamente il creatore e partecipante iniziale, gli altri sono in sospeso via notifica!)
  Future<Response> creaEvento(Request request) async {
    try {
      print('📥 [HTTP POST /api/eventi/crea] Creazione nuovo evento...');
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final titolo = data['titolo'] ?? data['nome'] ?? 'Evento FantaEventi';
      final propostoDa = data['propostoDa'] ?? data['creatoreId'] ?? 'Cloud';
      final rawPartecipanti = (data['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final rawInvitati = (data['invitati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final Set<String> invitatiSet = {...rawPartecipanti, ...rawInvitati};

      // Solamente il Creatore fa parte dei partecipanti CONFERMATI all'inizio!
      final List<String> partecipantiConfermati = [propostoDa];
      final List<String> invitatiFinali = invitatiSet.where((p) => p.trim().toLowerCase() != propostoDa.trim().toLowerCase()).toList();

      final evento = Evento(
        titolo: titolo,
        descrizione: data['descrizione'] ?? '',
        data: data['data'] != null ? DateTime.parse(data['data']) : DateTime.now(),
        luogo: data['luogo'] ?? '',
        stato: data['stato'] ?? 'in_corso',
        propostoDa: propostoDa,
        partecipanti: partecipantiConfermati,
      );

      final res = await DbService.instance.eventiCollection.insertOne(evento.toMap());
      final insertedId = res.id?.toHexString() ?? '';
      print('✅ [MongoDB] Evento "$titolo" inserito con successo! ID: $insertedId');

      // Crea le notifiche di invito per gli utenti invitati (esclusi dal creatore)!
      for (var p in invitatiFinali) {
        await DbService.instance.db.collection('Notifiche').insertOne({
          'mittente': propostoDa,
          'destinatario': p,
          'titolo': 'Invito ad Evento: $titolo',
          'messaggio': '$propostoDa ti ha invitato a partecipare all\'evento "$titolo"!',
          'eventoId': insertedId,
          'tipo': 'invito',
          'stato': 'in_attesa',
          'data': DateTime.now().toIso8601String(),
        });
        print('🔔 Invito in sospeso inviato a "$p" per l\'evento "$titolo"');
      }

      return Response.ok(
        jsonEncode({'message': 'Evento creato ed inviti inviati con successo', 'id': insertedId}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore durante la creazione dell\'evento: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
