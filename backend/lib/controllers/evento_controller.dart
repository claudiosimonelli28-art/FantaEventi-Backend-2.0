import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/evento.dart';
import '../models/utente.dart';
import '../utils/nickname_helper.dart';
import 'utente_controller.dart';

class EventoController {
  // GET /api/eventi
  Future<Response> getEventi(Request request) async {
    try {
      final now = DateTime.now();
      final docs = await DbService.instance.eventiCollection.find().toList();
      final utentiDocs = await UtenteController.getCachedUtentiDocs();

      final List<Map<String, dynamic>> resultList = [];

      for (var d in docs) {
        final evId = d['_id'] is ObjectId ? (d['_id'] as ObjectId) : null;
        final titolo = (d['titolo'] ?? d['nome'] ?? 'Evento').toString().trim();
        final dtStart = d['data'] is DateTime
            ? d['data'] as DateTime
            : (d['data'] != null ? DateTime.tryParse(d['data'].toString()) ?? now : now);
        final dtEnd = d['dataFine'] is DateTime
            ? d['dataFine'] as DateTime
            : (d['dataFine'] != null ? DateTime.tryParse(d['dataFine'].toString()) ?? dtStart.add(const Duration(hours: 4)) : dtStart.add(const Duration(hours: 4)));

        final rawCreator = (d['propostoDa'] ?? d['creatore'] ?? '').toString().trim();
        final creatorNick = NicknameHelper.resolve(rawCreator, utentiDocs);

        final rawPart = (d['partecipanti'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        final cleanPart = rawPart.map((p) => NicknameHelper.resolve(p, utentiDocs)).toList();

        final rawInv = (d['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        final cleanInv = rawInv.map((i) => NicknameHelper.resolve(i, utentiDocs)).toList();

        final bool haAltriPartecipanti = cleanPart.any((p) => p.isNotEmpty && !NicknameHelper.isSame(p, creatorNick, utentiDocs));
        String stato = (d['stato'] ?? 'in_programma').toString().toLowerCase();

        // 1. Logica di Transizione & Anti-farming
        if (stato == 'annullato') {
          // Rimane annullato
        } else if (now.isAfter(dtEnd)) {
          if (stato != 'concluso' && evId != null) {
            stato = 'concluso';
            await DbService.instance.eventiCollection.update(
              where.id(evId),
              modify.set('stato', 'concluso'),
            );
          }
        } else if (now.isAfter(dtStart)) {
          if (!haAltriPartecipanti) {
            // Orario di inizio scattato ma nessun altro partecipante oltre l'organizzatore: l'evento si annulla!
            if (stato != 'annullato' && evId != null) {
              stato = 'annullato';
              await DbService.instance.eventiCollection.update(
                where.id(evId),
                modify.set('stato', 'annullato').set('xpCreatoreAssegnati', false),
              );
            }
          } else {
            stato = 'in_corso';
            // Accredito +100 XP una tantum al creatore solo quando l'evento parte regolarmente con amici
            if (d['xpCreatoreAssegnati'] != true && evId != null) {
              await DbService.instance.eventiCollection.update(
                where.id(evId),
                modify.set('stato', 'in_corso').set('xpCreatoreAssegnati', true),
              );
              d['xpCreatoreAssegnati'] = true;

              final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] 🏆 Evento "$titolo" avviato con successo (+100 XP)';

              for (var uDoc in utentiDocs) {
                if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['username'] ?? '', creatorNick, utentiDocs)) {
                  final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
                  final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
                  final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);
                  final prog = XpProgression.aggiungiXp(
                    livelloAttuale: curLiv,
                    xpLivelloAttuale: curXp,
                    deltaXp: 100,
                    xpTotaliAttuali: curTot,
                  );

                  final List<dynamic> curStorico = List.from(uDoc['storicoVoti'] ?? []);
                  curStorico.insert(0, logVoce);

                  await DbService.instance.utentiCollection.update(
                    where.id(uDoc['_id'] as ObjectId),
                    modify
                      .set('xp', prog.xp)
                      .set('livello', prog.livello)
                      .set('xpProssimoLivello', prog.xpProssimoLivello)
                      .set('xpTotali', prog.xpTotali)
                      .set('storicoVoti', curStorico),
                  );
                  break;
                }
              }
            }
          }
        }

        final evento = Evento.fromMap(d);
        final json = evento.toJson();
        json['stato'] = stato;
        json['propostoDa'] = creatorNick;
        json['creatore'] = creatorNick;
        json['partecipanti'] = cleanPart;
        json['invitati'] = cleanInv;

        resultList.add(json);
      }

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

  // POST /api/eventi/crea
  Future<Response> creaEvento(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final utentiDocs = await UtenteController.getCachedUtentiDocs();

      final titolo = data['titolo'] ?? data['nome'] ?? 'Evento FantaEventi';
      final rawProposto = (data['propostoDa'] ?? data['creatoreId'] ?? 'Cloud').toString().trim();
      final String propostoDa = NicknameHelper.resolve(rawProposto, utentiDocs);

      final rawPartecipanti = (data['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final rawInvitati = (data['invitati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final Set<String> invitatiSet = {...rawPartecipanti, ...rawInvitati};

      // Solamente il Creatore è confermato nei partecipanti all'inizio
      final List<String> partecipantiConfermati = [propostoDa];
      final List<String> invitatiFinali = invitatiSet
          .where((p) => !NicknameHelper.isSame(p, propostoDa, utentiDocs))
          .map((p) => NicknameHelper.resolve(p, utentiDocs))
          .toList();

      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] Creato evento "$titolo" (in attesa di avvio)';

      final dtInizio = data['data'] != null ? DateTime.parse(data['data']) : now;
      final dtFine = data['dataFine'] != null ? DateTime.parse(data['dataFine']) : dtInizio.add(const Duration(hours: 4));

      final eventoMap = {
        'titolo': titolo,
        'nome': titolo,
        'descrizione': data['descrizione'] ?? '',
        'data': dtInizio.toIso8601String(),
        'dataFine': dtFine.toIso8601String(),
        'luogo': data['luogo'] ?? '',
        'latitudine': data['latitudine'],
        'longitudine': data['longitudine'],
        'stato': 'in_programma',
        'propostoDa': propostoDa,
        'creatore': propostoDa,
        'partecipanti': partecipantiConfermati,
        'invitati': invitatiFinali,
        'xpCreatoreAssegnati': false, // Deferito a quando l'evento parte in corso
        'penalitaFalsaTestimonianza': data['penalitaFalsaTestimonianza'] ?? -10,
      };

      // Anti-duplicazione idempotente: se un evento identico è già stato creato dal medesimo creatore, restituiscilo
      final existingRecent = await DbService.instance.eventiCollection.findOne(
        where.eq('titolo', titolo).and(where.eq('propostoDa', propostoDa)),
      );
      if (existingRecent != null) {
        final existingId = existingRecent['_id']?.oid ?? existingRecent['_id']?.toString() ?? '';
        return Response.ok(
          jsonEncode({'message': 'Evento già creato con successo', 'id': existingId}),
          headers: {'content-type': 'application/json'},
        );
      }

      final res = await DbService.instance.eventiCollection.insertOne(eventoMap);
      final insertedId = res.id?.oid ?? '';

      // Aggiungi voce storico al creatore senza accreditare XP (in attesa di avvio effettivo)
      for (var uDoc in utentiDocs) {
        if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['username'] ?? '', propostoDa, utentiDocs)) {
          final List<dynamic> curStorico = List.from(uDoc['storicoVoti'] ?? []);
          curStorico.insert(0, logVoce);
          await DbService.instance.utentiCollection.update(
            where.id(uDoc['_id'] as ObjectId),
            modify.set('storicoVoti', curStorico),
          );
          break;
        }
      }

      // Notifiche di invito ai partecipanti invitati
      for (var inv in invitatiFinali) {
        final existingNotif = await DbService.instance.notificheCollection.findOne(
          where.eq('eventoId', insertedId).and(where.eq('destinatario', inv)).and(where.eq('tipo', 'invito')),
        );
        if (existingNotif == null) {
          try {
            await DbService.instance.notificheCollection.insertOne({
              'mittente': propostoDa,
              'destinatario': inv,
              'titolo': 'Invito ad Evento: $titolo',
              'messaggio': '$propostoDa ti ha invitato a partecipare all\'evento "$titolo"!',
              'eventoId': insertedId,
              'tipo': 'invito',
              'stato': 'in_attesa',
              'letto': false,
              'data': now.toIso8601String(),
            });
          } catch (_) {}
        }
      }

      return Response.ok(
        jsonEncode({'message': 'Evento creato con successo', 'id': insertedId}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
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

      if (eventoId.isEmpty || utenteName.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'ID Evento ed Utente sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('nome', eventoId);
      final doc = await DbService.instance.eventiCollection.findOne(selector);

      if (doc != null) {
        final stato = (doc['stato'] ?? 'in_programma').toString().toLowerCase();
        final dateStr = doc['data']?.toString() ?? '';
        final dtStart = DateTime.tryParse(dateStr);
        final now = DateTime.now();

        if (stato == 'concluso' || stato == 'in_corso' || (dtStart != null && now.isAfter(dtStart))) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Le iscrizioni per questo evento sono chiuse'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final pullList = {
          utenteName,
          utenteName.toLowerCase(),
          utenteName.toUpperCase(),
          utenteName.trim(),
        }.toList();

        await DbService.instance.eventiCollection.update(
          selector,
          modify
            .addToSet('partecipanti', utenteName)
            .pullAll('invitati', pullList),
        );

        // Se c'era una notifica di invito per questo utente, segnalala come accettata e letta
        try {
          await DbService.instance.notificheCollection.update(
            where.eq('eventoId', eventoId).and(where.eq('destinatario', utenteName)).and(where.eq('tipo', 'invito')),
            modify.set('stato', 'accettato').set('letto', true),
            multiUpdate: true,
          );
        } catch (_) {}
      }

      return Response.ok(
        jsonEncode({'message': 'Iscrizione all\'evento effettuata con successo!'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
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

      if (eventoId.isEmpty || utente.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'ID Evento ed Utente sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('nome', eventoId);
      final doc = await DbService.instance.eventiCollection.findOne(selector);

      if (doc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Evento non trovato nel database'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final utentiDocs = await UtenteController.getCachedUtentiDocs();
      final creatoreDoc = (doc['propostoDa'] ?? doc['creatore'] ?? '').toString().trim();
      final isAllowed = creatoreDoc.isEmpty || NicknameHelper.isSame(creatoreDoc, utente, utentiDocs) || utente.trim().toLowerCase() == 'cloud';

      if (!isAllowed) {
        return Response.forbidden(
          jsonEncode({'error': 'Solo il creatore dell\'evento può eliminarlo!'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await DbService.instance.eventiCollection.remove(selector);
      await DbService.instance.notificheCollection.remove(where.eq('eventoId', eventoId));
      await DbService.instance.bonusMalusCollection.remove(where.eq('eventoId', eventoId));

      return Response.ok(
        jsonEncode({'message': 'Evento eliminato con successo dal database'}),
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
