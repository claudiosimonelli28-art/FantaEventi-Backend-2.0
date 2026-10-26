import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/bonus_malus.dart';
import '../models/utente.dart';
import '../utils/nickname_helper.dart';

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

      List<Map<String, dynamic>> allUtenti = [];
      try {
        allUtenti = await DbService.instance.utentiCollection.find().toList();
      } catch (_) {}

      final rawProposto = data['utente']?.toString() ?? data['propostoDa']?.toString() ?? 'Cloud';
      final String propostoDaUtente = NicknameHelper.resolve(rawProposto, allUtenti);

      final eventoId = data['eventoId']?.toString() ?? '';
      final eventoTitolo = data['eventoTitolo']?.toString() ?? data['titoloEvento']?.toString() ?? '';
      final nome = data['nome']?.toString() ?? data['titolo']?.toString() ?? '';

      // Clamping rigoroso sui punti [-100, 100]
      final rawPunti = (data['punti'] as num?)?.toInt() ?? 0;
      final safePunti = rawPunti > 100 ? 100 : (rawPunti < -100 ? -100 : rawPunti);

      // Controllo anti-duplicato
      final existing = await DbService.instance.bonusMalusCollection.findOne(
        where.eq('eventoId', eventoId).and(where.eq('nome', nome)),
      );

      String bmHexId;
      if (existing != null) {
        bmHexId = existing['_id'] is ObjectId
            ? (existing['_id'] as ObjectId).oid
            : (existing['_id']?.toString() ?? '');

        await DbService.instance.bonusMalusCollection.update(
          where.id(existing['_id'] as ObjectId),
          modify
            .set('propostoDa', propostoDaUtente)
            .set('punti', safePunti)
            .set('stato', 'in_votazione')
            .set('categoria', data['categoria'] ?? 'Goliardia')
            .set('riassegnabileMoltepliciVolte', data['riassegnabileMoltepliciVolte'] == true),
        );
      } else {
        final bmMap = {
          'eventoId': eventoId,
          'nome': nome,
          'titolo': nome,
          'descrizione': data['descrizione'] ?? '',
          'punti': safePunti,
          'categoria': data['categoria'] ?? 'Goliardia',
          'tipo': safePunti >= 0 ? 'bonus' : 'malus',
          'propostoDa': propostoDaUtente,
          'stato': data['stato'] ?? 'in_votazione',
          'approvato': false,
          'assegnatoA': <String>[],
          'riassegnabileMoltepliciVolte': data['riassegnabileMoltepliciVolte'] == true,
        };

        final res = await DbService.instance.bonusMalusCollection.insertOne(bmMap);
        bmHexId = res.id?.oid ?? '';
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

        // Esclude categoricamente il proponente da ricezione notifiche
        destinatariSet.removeWhere((d) {
          final cleanD = d.trim();
          if (cleanD.isEmpty) return true;
          return NicknameHelper.isSame(cleanD, propostoDaUtente, allUtenti);
        });

        final now = DateTime.now();
        for (var rawDest in destinatariSet) {
          final destUser = NicknameHelper.resolve(rawDest, allUtenti);
          final existingNot = await DbService.instance.notificheCollection.findOne(
            where.eq('destinatario', destUser).and(where.eq('bonusId', bmHexId)),
          );

          if (existingNot == null) {
            final notifica = {
              'mittente': propostoDaUtente,
              'destinatario': destUser,
              'titolo': '⭐ Nuova Proposta: $nome',
              'messaggio': '$propostoDaUtente ha proposto il ${safePunti >= 0 ? "bonus" : "malus"} "$nome" (${safePunti >= 0 ? "+$safePunti" : "$safePunti"} PT) per l\'evento "$eventoNome"!',
              'eventoId': eventoId,
              'bonusId': bmHexId,
              'bonusTitolo': nome,
              'tipo': 'bonus_malus',
              'stato': 'in_attesa',
              'letto': false,
              'data': now.toIso8601String(),
            };
            await DbService.instance.notificheCollection.insertOne(notifica);
          }
        }
      } catch (_) {}

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

  // POST /api/bonusmalus/assegna
  Future<Response> assegnaBonusMalus(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final eventoId = data['eventoId']?.toString() ?? '';
      final bonusId = data['bonusId']?.toString() ?? data['bonusMalusId']?.toString() ?? '';
      final utenteDestinatario = data['utenteDestinatario']?.toString() ?? data['partecipante']?.toString() ?? '';
      final eventoTitolo = data['eventoTitolo']?.toString() ?? 'Evento';
      final bonusTitolo = data['bonusTitolo']?.toString() ?? 'Bonus';
      final mittente = (data['mittente']?.toString() ?? 'Sistema').trim();
      final rawPunti = (data['punti'] as num?)?.toInt() ?? 0;
      final safePunti = rawPunti > 100 ? 100 : (rawPunti < -100 ? -100 : rawPunti);

      if (eventoId.isEmpty || bonusId.isEmpty || utenteDestinatario.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'eventoId, bonusId e utenteDestinatario sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final ptStr = safePunti >= 0 ? '+$safePunti' : '$safePunti';
      final logText = '[${now.toIso8601String().substring(0, 10)} $timeStr] 🏆 Ricevuto ${safePunti >= 0 ? "Bonus" : "Malus"} "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoTitolo" ($timeStr)';

      // 1. Controllo che l'evento sia in corso
      ObjectId? evObjId;
      try { evObjId = ObjectId.fromHexString(eventoId); } catch (_) {}
      final evSelector = evObjId != null ? where.id(evObjId) : where.eq('_id', eventoId);
      final evDoc = await DbService.instance.eventiCollection.findOne(evSelector);

      if (evDoc != null) {
        final stato = (evDoc['stato'] ?? 'in_programma').toString().toLowerCase();
        final dtEnd = evDoc['dataFine'] != null ? DateTime.tryParse(evDoc['dataFine'].toString()) : null;
        final bool isConcluso = stato == 'concluso' || (dtEnd != null && now.isAfter(dtEnd));
        if (isConcluso) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Questo evento è concluso: le assegnazioni dei punti sono chiuse!'}),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // 2. Aggiorna documento BonusMalus (aggiungi in assegnatoA)
      ObjectId? bmObjId;
      try { bmObjId = ObjectId.fromHexString(bonusId); } catch (_) {}
      final bmSelector = bmObjId != null ? where.id(bmObjId) : where.eq('_id', bonusId);
      var bmDoc = await DbService.instance.bonusMalusCollection.findOne(bmSelector);
      bmDoc ??= await DbService.instance.bonusMalusCollection.findOne(where.eq('nome', bonusTitolo));

      if (bmDoc != null) {
        final List<dynamic> assList = List.from(bmDoc['assegnatoA'] ?? []);
        final bool isMulti = bmDoc['riassegnabileMoltepliciVolte'] == true;
        final cleanDest = utenteDestinatario.trim().toLowerCase();
        if (isMulti || !assList.any((u) => u.toString().trim().toLowerCase() == cleanDest)) {
          assList.add(utenteDestinatario);
        }
        await DbService.instance.bonusMalusCollection.update(
          where.id(bmDoc['_id'] as ObjectId),
          modify.set('assegnatoA', assList),
        );
      }

      // 3. Aggiorna punti e storico utente con carry-over XP
      final uDocs = await DbService.instance.utentiCollection.find().toList();
      for (var uDoc in uDocs) {
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? '').toString().trim().toLowerCase();
        final uName = (uDoc['nome'] ?? '').toString().trim().toLowerCase();
        final target = utenteDestinatario.trim().toLowerCase();

        if (uNick == target || uName == target) {
          final oldPunti = (uDoc['puntiTotali'] ?? 0) as int;
          final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
          final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
          final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);

          // Formula punti * 10 XP con tetto massimo di sicurezza a 100 punti (+1000 XP max)
          final deltaXp = safePunti > 0 ? (safePunti * 10) : 0;
          final prog = XpProgression.aggiungiXp(
            livelloAttuale: curLiv,
            xpLivelloAttuale: curXp,
            deltaXp: deltaXp,
            xpTotaliAttuali: curTot,
          );

          final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
          oldStorico.insert(0, logText);

          await DbService.instance.utentiCollection.update(
            where.id(uDoc['_id'] as ObjectId),
            modify
              .set('puntiTotali', oldPunti + safePunti)
              .set('xp', prog.xp)
              .set('livello', prog.livello)
              .set('xpProssimoLivello', prog.xpProssimoLivello)
              .set('xpTotali', prog.xpTotali)
              .set('storicoVoti', oldStorico),
          );
          break;
        }
      }

      // 4. Inserimento notifiche in-app per TUTTI i partecipanti dell'evento
      try {
        final allEventi = await DbService.instance.eventiCollection.find().toList();
        Map<String, dynamic>? targetEv;
        if (evObjId != null) {
          targetEv = allEventi.firstWhere((e) => e['_id'] == evObjId, orElse: () => {});
        }
        if (targetEv == null || targetEv.isEmpty) {
          targetEv = allEventi.firstWhere(
            (e) => (e['id']?.toString() == eventoId ||
                    e['nome']?.toString().toLowerCase() == eventoTitolo.toLowerCase() ||
                    e['titolo']?.toString().toLowerCase() == eventoTitolo.toLowerCase()),
            orElse: () => {},
          );
        }

        final eventoNome = (targetEv['nome'] ?? targetEv['titolo'] ?? (eventoTitolo.isNotEmpty ? eventoTitolo : 'Evento')).toString();
        final Set<String> destList = {};
        if (targetEv.isNotEmpty) {
          final List<dynamic> pList = List.from(targetEv['partecipanti'] ?? []);
          final List<dynamic> iList = List.from(targetEv['invitati'] ?? []);
          for (var item in [...pList, ...iList]) {
            final s = item.toString().trim();
            if (s.isNotEmpty) destList.add(NicknameHelper.resolve(s, uDocs));
          }
        }
        if (destList.isEmpty) {
          destList.add(utenteDestinatario);
        }

        final bool isBonus = safePunti >= 0;
        final String notificaTipo = isBonus ? 'assegnazione_bonus' : 'assegnazione_malus';
        final String notificaTitolo = isBonus ? '🏆 Bonus Assegnato!' : '💀 Malus Assegnato!';
        final int ts = now.millisecondsSinceEpoch;

        for (var d in destList) {
          await DbService.instance.notificheCollection.insertOne({
            'notificaId': 'bm_ass_${ts}_${d.toLowerCase()}',
            'mittente': mittente.isNotEmpty ? mittente : 'Sistema',
            'destinatario': d,
            'titolo': notificaTitolo,
            'messaggio': '$utenteDestinatario ha ricevuto "$bonusTitolo" ($ptStr PT) per l\'evento "$eventoNome"!',
            'eventoId': eventoId,
            'tipo': notificaTipo,
            'stato': 'consegnato',
            'letto': false,
            'votoEspresso': 'pro',
            'data': now.toIso8601String(),
          });
        }
      } catch (errNot) {
        print('Notice inserimento notifica assegnazione: $errNot');
      }

      return Response.ok(
        jsonEncode({'message': 'Bonus assegnato con successo', 'punti': safePunti}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/bonusmalus/annulla-assegnazione
  Future<Response> annullaAssegnazioneBonus(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final eventoId = data['eventoId']?.toString() ?? '';
      final bonusId = data['bonusId']?.toString() ?? data['bonusMalusId']?.toString() ?? '';
      final utenteDestinatario = data['utenteDestinatario']?.toString() ?? data['partecipante']?.toString() ?? '';
      final rawPunti = (data['punti'] as num?)?.toInt() ?? 0;
      final safePunti = rawPunti > 100 ? 100 : (rawPunti < -100 ? -100 : rawPunti);
      final cleanDest = utenteDestinatario.trim().toLowerCase();

      // 1. Blocco assoluto se originato da sentenza VAR
      ObjectId? bmObjId;
      try { bmObjId = ObjectId.fromHexString(bonusId); } catch (_) {}
      final bmSelector = bmObjId != null ? where.id(bmObjId) : where.eq('_id', bonusId);
      var bmDoc = await DbService.instance.bonusMalusCollection.findOne(bmSelector);
      if (bmDoc != null) {
        final bmCat = (bmDoc['categoria'] ?? '').toString().toUpperCase();
        final bmTit = (bmDoc['titolo'] ?? bmDoc['nome'] ?? '').toString();
        if (bmCat == 'VAR' || bmTit.contains('VAR') || bmTit.contains('Falsa Testimonianza')) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Non è possibile stornare un bonus/malus o sanzione assegnata tramite sentenza VAR.'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final realBmId = bmDoc['_id'] is ObjectId ? (bmDoc['_id'] as ObjectId).oid : bmDoc['_id']?.toString() ?? bonusId;
        final approvedVar = await DbService.instance.richiesteVarCollection.findOne(
          where.eq('eventoId', eventoId)
              .and(where.eq('stato', 'approvata'))
              .and(where.eq('bonusMalusId', realBmId)),
        );
        if (approvedVar != null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Non è possibile stornare un bonus/malus convalidato tramite VAR.'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final List<dynamic> assList = List.from(bmDoc['assegnatoA'] ?? []);
        final idx = assList.indexWhere((u) => u.toString().trim().toLowerCase() == cleanDest);
        if (idx != -1) {
          assList.removeAt(idx);
        }
        await DbService.instance.bonusMalusCollection.update(
          where.id(bmDoc['_id'] as ObjectId),
          modify.set('assegnatoA', assList),
        );
      }

      // 2. Storna i punti dall'utente (XP PERMANENTI: NON vengono sottratti)
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] ⚠️ Annullata assegnazione bonus (-$safePunti PT) (ore $timeStr)';

      final uDocs = await DbService.instance.utentiCollection.find().toList();
      for (var uDoc in uDocs) {
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? '').toString().trim().toLowerCase();
        final uName = (uDoc['nome'] ?? '').toString().trim().toLowerCase();
        if (uNick == cleanDest || uName == cleanDest) {
          final oldPunti = (uDoc['puntiTotali'] ?? 0) as int;
          final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
          oldStorico.insert(0, logVoce);

          final newPunti = (oldPunti - safePunti).clamp(0, 999999);

          // Nota di Game Design: L'XP guadagnato dal giocatore è esperienza permanente e non viene de-livellato
          await DbService.instance.utentiCollection.update(
            where.id(uDoc['_id'] as ObjectId),
            modify
              .set('puntiTotali', newPunti)
              .set('storicoVoti', oldStorico),
          );
          break;
        }
      }

      return Response.ok(
        jsonEncode({'message': 'Assegnazione bonus annullata con successo'}),
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

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(bmId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('nome', bmId);

      await DbService.instance.bonusMalusCollection.remove(selector);

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
