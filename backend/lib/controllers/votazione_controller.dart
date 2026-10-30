import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/bonus_malus.dart';
import '../models/votazione.dart';
import '../models/utente.dart';
import '../utils/nickname_helper.dart';
import 'utente_controller.dart';

class VotazioneController {
  // GET /api/votazioni
  Future<Response> getVotazioni(Request request) async {
    try {
      final bmDocs = await DbService.instance.bonusMalusCollection.find().toList();
      final votiDocs = await DbService.instance.votazioniCollection.find().toList();
      final evDocs = await DbService.instance.eventiCollection.find().toList();
      final uDocs = await UtenteController.getCachedUtentiDocs();

      final List<Map<String, dynamic>> resultList = [];

      for (var bm in bmDocs) {
        final bmId = bm['_id'] is ObjectId ? (bm['_id'] as ObjectId).oid : (bm['_id']?.toString() ?? bm['id']?.toString() ?? '');
        final evId = bm['eventoId']?.toString() ?? '';
        final nomeBM = bm['nome']?.toString() ?? bm['titolo']?.toString() ?? 'Bonus';
        final descBM = bm['descrizione']?.toString() ?? '';
        final puntiBM = (bm['punti'] as num?)?.toInt() ?? 0;
        final rawPropDa = (bm['propostoDa'] ?? '').toString().trim();
        final effectivePropDa = NicknameHelper.resolve(rawPropDa, uDocs);

        final Map<String, String> votiUtenti = {
          if (effectivePropDa.isNotEmpty) effectivePropDa: 'pro',
          if (effectivePropDa.isNotEmpty) effectivePropDa.toLowerCase(): 'pro',
        };

        final cleanEvId = evId.trim().toLowerCase();
        for (var vDoc in votiDocs) {
          final vEvId = (vDoc['eventoId'] ?? '').toString().trim().toLowerCase();
          // Rigoroso match dell'evento: un voto espresso per un altro evento non può mai contare qui!
          if (vEvId.isNotEmpty && cleanEvId.isNotEmpty && vEvId != cleanEvId) {
            continue;
          }

          final vId = (vDoc['votazioneId'] ?? vDoc['bonusId'] ?? '').toString().trim().toLowerCase();
          final bTit = (vDoc['bonusTitolo'] ?? '').toString().trim().toLowerCase();
          final rawU = (vDoc['utente'] ?? '').toString().trim();
          final val = (vDoc['voto']?.toString() ?? '').toLowerCase();

          final isMatch = (vId == bmId.toLowerCase()) ||
                          (vId.isNotEmpty && vId == bm['_id']?.toString().toLowerCase()) ||
                          (bTit.isNotEmpty && bTit == nomeBM.toLowerCase() && vEvId.isNotEmpty && vEvId == cleanEvId);

          if (isMatch && rawU.isNotEmpty) {
            final voteStr = (val == 'pro' || val == 'accetta' || val == 'favorevole') ? 'pro' : 'contro';
            final u = NicknameHelper.resolve(rawU, uDocs);
            votiUtenti[u] = voteStr;
            votiUtenti[u.toLowerCase()] = voteStr;
          }
        }

        final evMatch = evDocs.firstWhere(
          (e) => (e['_id']?.toString() == evId ||
                  (e['_id'] is ObjectId && (e['_id'] as ObjectId).oid == evId) ||
                  (e['titolo'] ?? '').toString().toLowerCase() == evId.toLowerCase()),
          orElse: () => <String, dynamic>{},
        );

        final List<dynamic> partList = List.from(evMatch['partecipanti'] ?? []);
        final int numPartecipanti = partList.length >= 2 ? partList.length : 3;
        final int quorumCalcolato = (numPartecipanti / 2).floor() + 1;

        final Set<String> countedUsers = {};
        int fav = 0;
        int cont = 0;
        votiUtenti.forEach((user, vote) {
          String normUser = NicknameHelper.resolve(user, uDocs).trim().toLowerCase();
          if (!countedUsers.contains(normUser)) {
            countedUsers.add(normUser);
            if (vote == 'pro') fav++;
            if (vote == 'contro') cont++;
          }
        });

        final bool isPropostaUtente = effectivePropDa.isNotEmpty;
        final bool giaApprovatoDaDb = !isPropostaUtente && (bm['approvato'] == true || bm['stato'] == 'approvato');
        final bool giaRespintoDaDb = !isPropostaUtente && (bm['stato'] == 'respinto');

        final totalVotiEspressi = fav + cont;
        bool isApprovato = giaApprovatoDaDb || (fav >= quorumCalcolato);
        bool isRespinto = !giaApprovatoDaDb && (giaRespintoDaDb || (cont >= quorumCalcolato));

        bool paritaDecisaDaOrganizzatore = false;
        final rawNomeOrg = (evMatch['creatore'] ?? evMatch['propostoDa'] ?? '').toString();
        final nomeOrganizzatore = NicknameHelper.resolve(rawNomeOrg, uDocs);

        if (!isApprovato && !isRespinto && (numPartecipanti % 2 == 0) && (totalVotiEspressi >= numPartecipanti) && (fav == cont)) {
          final creatoreVoteKey = votiUtenti.keys.firstWhere(
            (k) => NicknameHelper.isSame(k, nomeOrganizzatore, uDocs),
            orElse: () => '',
          );
          if (creatoreVoteKey.isNotEmpty) {
            final creatoreVote = votiUtenti[creatoreVoteKey];
            if (creatoreVote == 'pro') {
              isApprovato = true;
              paritaDecisaDaOrganizzatore = true;
            } else if (creatoreVote == 'contro') {
              isRespinto = true;
              paritaDecisaDaOrganizzatore = true;
            }
          }
        }

        if (isApprovato && !giaApprovatoDaDb && bm['_id'] is ObjectId) {
          try {
            await DbService.instance.bonusMalusCollection.update(
              where.id(bm['_id'] as ObjectId),
              modify.set('stato', 'approvato').set('approvato', true),
            );
          } catch (_) {}
        }
        final statoVot = isApprovato ? 'approvato' : (isRespinto ? 'respinto' : 'in_corso');
        final bmObj = BonusMalus(
          id: bmId,
          eventoId: evId,
          titolo: nomeBM,
          descrizione: descBM,
          punti: puntiBM,
          categoria: bm['categoria']?.toString() ?? 'Goliardia',
          propostoDa: effectivePropDa,
          approvato: isApprovato,
          stato: statoVot,
          assegnatoA: (bm['assegnatoA'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
          riassegnabileMoltepliciVolte: bm['riassegnabileMoltepliciVolte'] == true,
        );

        final votazione = Votazione(
          id: bmId,
          titolo: nomeBM,
          descrizione: descBM.isNotEmpty ? descBM : 'Proposta da $effectivePropDa',
          bonusMalus: bmObj,
          votiFavorevoli: fav,
          votiContrari: cont,
          quorum: quorumCalcolato,
          stato: statoVot,
          scadenza: DateTime.now().add(const Duration(days: 7)),
          votiUtenti: votiUtenti,
          paritaDecisaDaOrganizzatore: paritaDecisaDaOrganizzatore,
          nomeOrganizzatore: nomeOrganizzatore,
        );

        resultList.add(votazione.toJson());
      }

      return Response.ok(
        jsonEncode(resultList),
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

      final idOrEventoId = data['id']?.toString() ?? data['votazioneId']?.toString() ?? data['bonusId']?.toString() ?? '';
      final aFavore = data['aFavore'] == true ||
          data['voto'] == 'pro' ||
          data['voto'] == 'accetta' ||
          data['voto'] == 'favorevole' ||
          data['voto'] == 'si';
      final rawUser = data['utente']?.toString() ?? data['username']?.toString() ?? 'Cloud';

      final uDocs = await UtenteController.getCachedUtentiDocs();
      final userNick = NicknameHelper.resolve(rawUser, uDocs);

      // Risolvi il BonusMalus e il relativo ID reale
      Map<String, dynamic>? bmDoc;
      ObjectId? bmObjId;
      try { bmObjId = ObjectId.fromHexString(idOrEventoId); } catch (_) {}
      if (bmObjId != null) {
        bmDoc = await DbService.instance.bonusMalusCollection.findOne(where.id(bmObjId));
      }
      if (bmDoc == null) {
        bmDoc = await DbService.instance.bonusMalusCollection.findOne(where.eq('nome', idOrEventoId));
      }
      if (bmDoc == null && bmObjId != null) {
        final vDoc = await DbService.instance.votazioniCollection.findOne(where.id(bmObjId));
        if (vDoc != null) {
          final realBmId = (vDoc['bonusId'] ?? vDoc['votazioneId'] ?? '').toString();
          ObjectId? realBmObjId;
          try { realBmObjId = ObjectId.fromHexString(realBmId); } catch (_) {}
          if (realBmObjId != null) {
            bmDoc = await DbService.instance.bonusMalusCollection.findOne(where.id(realBmObjId));
          }
        }
      }

      final realBmHex = bmDoc != null
          ? (bmDoc['_id'] is ObjectId ? (bmDoc['_id'] as ObjectId).oid : bmDoc['_id'].toString())
          : idOrEventoId;

      // 1. Verifica se l'utente ha già votato
      final existingVote = await DbService.instance.votazioniCollection.findOne(
        where.eq('utente', userNick).and(
          where.eq('votazioneId', realBmHex)
               .or(where.eq('bonusId', realBmHex))
               .or(where.eq('votazioneId', idOrEventoId))
               .or(where.eq('bonusId', idOrEventoId)),
        ),
      );
      final bool giaVotato = existingVote != null;

      // 2. Inserisci o aggiorna il voto
      if (existingVote != null) {
        await DbService.instance.votazioniCollection.update(
          where.id(existingVote['_id'] as ObjectId),
          modify.set('voto', aFavore ? 'pro' : 'contro').set('data', DateTime.now().toIso8601String()),
        );
      } else {
        await DbService.instance.votazioniCollection.insertOne({
          'votazioneId': realBmHex,
          'bonusId': realBmHex,
          'utente': userNick,
          'voto': aFavore ? 'pro' : 'contro',
          'data': DateTime.now().toIso8601String(),
        });
      }

      // 2b. Valuta Quorum e aggiorna BonusMalus se target raggiunto
      try {
        final allVotes = await DbService.instance.votazioniCollection.find(
          where.eq('votazioneId', realBmHex)
               .or(where.eq('bonusId', realBmHex))
               .or(where.eq('votazioneId', idOrEventoId))
               .or(where.eq('bonusId', idOrEventoId)),
        ).toList();

        final proCount = allVotes.where((v) => v['voto'] == 'pro' || v['voto'] == 'favorevole' || v['voto'] == 'si' || v['aFavore'] == true).length;
        final controCount = allVotes.where((v) => v['voto'] == 'contro' || v['voto'] == 'no' || v['aFavore'] == false).length;

        if (bmDoc != null) {
          final evId = (bmDoc['eventoId'] ?? '').toString();
          ObjectId? evObjId;
          try { evObjId = ObjectId.fromHexString(evId); } catch (_) {}
          final evDoc = await DbService.instance.eventiCollection.findOne(evObjId != null ? where.id(evObjId) : where.eq('_id', evId));
          final partecipanti = (evDoc?['partecipanti'] as List<dynamic>?) ?? [];
          final numPart = partecipanti.isNotEmpty ? partecipanti.length : 2;
          final quorum = (numPart / 2).ceil();

          if (controCount >= quorum && controCount > proCount) {
            await DbService.instance.bonusMalusCollection.update(
              where.id(bmDoc['_id'] as ObjectId),
              modify.set('stato', 'respinto').set('approvato', false),
            );
          } else if (proCount >= quorum && proCount >= controCount) {
            await DbService.instance.bonusMalusCollection.update(
              where.id(bmDoc['_id'] as ObjectId),
              modify.set('stato', 'approvato').set('approvato', true),
            );
          }
        }
      } catch (_) {}

      // 3. Sincronizza stato notifica dell'utente
      final notDocs = await DbService.instance.notificheCollection.find().toList();
      for (var notDoc in notDocs) {
        final dest = (notDoc['destinatario'] ?? '').toString().trim().toLowerCase();
        final bId = (notDoc['bonusId'] ?? '').toString().trim().toLowerCase();
        final notId = notDoc['_id'] is ObjectId ? (notDoc['_id'] as ObjectId).oid : notDoc['_id']?.toString() ?? '';
        final isMatch = (bId.isNotEmpty && (bId == idOrEventoId.toLowerCase())) || notId == idOrEventoId;
        if (dest == userNick.toLowerCase() && isMatch) {
          await DbService.instance.notificheCollection.update(
            where.id(notDoc['_id'] as ObjectId),
            modify.set('stato', aFavore ? 'accettato' : 'rifiutato').set('votoEspresso', aFavore ? 'pro' : 'contro').set('letto', true),
          );
        }
      }

      // 4. Assegna +25 XP con progressione se primo voto
      if (!giaVotato) {
        for (var uDoc in uDocs) {
          if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['username'] ?? '', userNick, uDocs)) {
            final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
            final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
            final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);
            final prog = XpProgression.aggiungiXp(
              livelloAttuale: curLiv,
              xpLivelloAttuale: curXp,
              deltaXp: 25,
              xpTotaliAttuali: curTot,
            );

            final now = DateTime.now();
            final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
            final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] Votato ${aFavore ? "FAVOREVOLE" : "CONTRARIO"} (+25 XP)';

            final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
            oldStorico.insert(0, logVoce);

            await DbService.instance.utentiCollection.update(
              where.id(uDoc['_id'] as ObjectId),
              modify
                .set('xp', prog.xp)
                .set('livello', prog.livello)
                .set('xpProssimoLivello', prog.xpProssimoLivello)
                .set('xpTotali', prog.xpTotali)
                .set('storicoVoti', oldStorico),
            );
            break;
          }
        }
      }

      return Response.ok(
        jsonEncode({'message': 'Voto registrato con successo', 'nuovoVotante': !giaVotato}),
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
