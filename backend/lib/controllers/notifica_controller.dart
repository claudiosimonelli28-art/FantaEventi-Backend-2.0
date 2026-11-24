import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../services/fcm_service.dart';
import '../utils/italian_time.dart';
import '../utils/nickname_helper.dart';
import 'utente_controller.dart';

class NotificaController {
  static bool _isVeteranoUser(Map<String, dynamic>? uDoc) {
    if (uDoc == null) return false;
    if (uDoc['haVistoGuida'] == true ||
        uDoc['tutorialV3Completato'] == true ||
        uDoc['tutorialPremioRiscattato'] == true) {
      return true;
    }
    final liv = (uDoc['livello'] as num?)?.toInt() ?? 1;
    final xpTot = (uDoc['xpTotali'] as num?)?.toInt() ?? 100;
    final storico = uDoc['storicoVoti'];
    if (liv > 1 || xpTot > 100 || (storico is List && storico.isNotEmpty)) {
      return true;
    }
    return false;
  }

  // GET /api/notifiche?utente=NICKNAME
  Future<Response> getNotificheUtente(Request request) async {
    try {
      final dest = (request.url.queryParameters['utente'] ?? '').trim();
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final allNotifiche = await DbService.instance.notificheCollection.find().toList();
      final eventiDocs = await DbService.instance.eventiCollection.find().toList();
      final bmDocs = await DbService.instance.bonusMalusCollection.find().toList();
      final votazioniDocs = await DbService.instance.votazioniCollection.find().toList();
      final varDocs = await DbService.instance.richiesteVarCollection.find(where.excludeFields(['fotoBase64'])).toList();

      final cleanNick = dest.isNotEmpty ? NicknameHelper.resolve(dest, uDocs).trim() : '';

      Map<String, dynamic>? targetUserDoc;
      if (cleanNick.isNotEmpty) {
        for (var u in uDocs) {
          final uNick = (u['nickname'] ?? u['username'] ?? u['nome'] ?? '').toString().trim();
          if (NicknameHelper.isSame(uNick, cleanNick, uDocs)) {
            targetUserDoc = u;
            break;
          }
        }
      }
      final bool isTargetVeterano = _isVeteranoUser(targetUserDoc);

      // Mappa delle RichiesteVar per ID hex / String
      final Map<String, Map<String, dynamic>> varMap = {};
      for (var v in varDocs) {
        final vIdHex = v['_id'] is ObjectId ? (v['_id'] as ObjectId).oid.toLowerCase() : '';
        final vIdStr = (v['_id']?.toString() ?? v['id']?.toString() ?? '').toLowerCase();
        final vClean = vIdStr.replaceAll(RegExp(r'[^a-f0-9]'), '');
        if (vIdHex.isNotEmpty) varMap[vIdHex] = v;
        if (vIdStr.isNotEmpty) varMap[vIdStr] = v;
        if (vClean.isNotEmpty) varMap[vClean] = v;
      }

      // Mappa degli eventi validi: Hex / String / Titolo -> Doc
      final Map<String, Map<String, dynamic>> validEvents = {};
      for (var ev in eventiDocs) {
        final eIdHex = ev['_id'] is ObjectId ? (ev['_id'] as ObjectId).oid.toLowerCase() : '';
        final eIdStr = (ev['_id']?.toString() ?? ev['id']?.toString() ?? '').toLowerCase();
        final eClean = eIdStr.replaceAll(RegExp(r'[^a-f0-9]'), '');
        if (eIdHex.isNotEmpty) validEvents[eIdHex] = ev;
        if (eIdStr.isNotEmpty) validEvents[eIdStr] = ev;
        if (eClean.isNotEmpty) validEvents[eClean] = ev;
        final eNome = (ev['nome'] ?? ev['titolo'] ?? '').toString().trim().toLowerCase();
        if (eNome.isNotEmpty) validEvents[eNome] = ev;
      }

      // Mappa dei BonusMalus per ID hex / Titolo
      final Map<String, Map<String, dynamic>> bonusMalusMap = {};
      for (var bm in bmDocs) {
        final bmIdHex = bm['_id'] is ObjectId
            ? (bm['_id'] as ObjectId).oid.toLowerCase()
            : (bm['_id']?.toString() ?? '').toLowerCase();
        if (bmIdHex.isNotEmpty) bonusMalusMap[bmIdHex] = bm;
        final bmNome = (bm['nome'] ?? bm['titolo'] ?? '').toString().trim().toLowerCase();
        if (bmNome.isNotEmpty) bonusMalusMap[bmNome] = bm;
        final bmTit = (bm['titolo'] ?? '').toString().trim().toLowerCase();
        if (bmTit.isNotEmpty) bonusMalusMap[bmTit] = bm;
      }

      // Mappa delle votazioni per bonusId / votazioneId / titolo
      final Map<String, Map<String, dynamic>> votazioniMap = {};
      for (var vot in votazioniDocs) {
        final vId = vot['_id'] is ObjectId
            ? (vot['_id'] as ObjectId).oid
            : (vot['_id']?.toString() ?? vot['id']?.toString() ?? vot['votazioneId']?.toString() ?? '');
        if (vId.isNotEmpty) votazioniMap[vId.toLowerCase()] = vot;
        final bmId = vot['bonusMalus']?['id']?.toString() ?? vot['bonusId']?.toString() ?? '';
        if (bmId.isNotEmpty) votazioniMap[bmId.toLowerCase()] = vot;
        final vTitolo = (vot['titolo'] ?? vot['bonusMalus']?['titolo'] ?? '').toString().trim().toLowerCase();
        if (vTitolo.isNotEmpty) votazioniMap[vTitolo] = vot;
      }

      final matchDocs = allNotifiche.where((d) {
        final dDest = (d['destinatario'] ?? '').toString().trim();
        if (cleanNick.isEmpty) return true;
        return NicknameHelper.isSame(dDest, cleanNick, uDocs);
      }).toList();

      final Set<String> seenKeys = {};
      final List<Map<String, dynamic>> notificheList = [];

      for (var d in matchDocs) {
        final idStr = d['_id'] is ObjectId
            ? (d['_id'] as ObjectId).oid
            : (d['_id']?.toString() ?? d['notificaId']?.toString() ?? '');
        if (idStr.isEmpty || seenKeys.contains(idStr)) continue;

        final tipo = (d['tipo'] ?? '').toString().toLowerCase();

        // Se l'utente è già veterano e c'è una notifica di benvenuto non letta rigenerata per errore, rimuovila
        if (tipo == 'benvenuto' && isTargetVeterano && d['letto'] != true) {
          if (d['_id'] is ObjectId) {
            try {
              await DbService.instance.notificheCollection.remove(where.id(d['_id'] as ObjectId));
            } catch (_) {}
          }
          continue;
        }

        final evId = (d['eventoId'] ?? '').toString().trim();
        final evIdLower = evId.toLowerCase();
        final evClean = evIdLower.replaceAll(RegExp(r'[^a-f0-9]'), '');

        // Auto-eliminazione notifiche se l'evento collegato è stato cancellato o è già terminato
        if (evId.isNotEmpty) {
          final evDoc = validEvents[evIdLower] ?? (evClean.isNotEmpty ? validEvents[evClean] : null);
          if (evDoc == null) {
            if (d['_id'] is ObjectId) {
              try {
                await DbService.instance.notificheCollection.remove(where.id(d['_id'] as ObjectId));
              } catch (_) {}
            }
            continue;
          } else {
            final statoEv = (evDoc['stato'] ?? '').toString().toLowerCase();
            final dtFineStr = evDoc['dataFine']?.toString();
            final DateTime? dtFine = dtFineStr != null ? DateTime.tryParse(dtFineStr) : null;
            final bool isEvConcluso = statoEv == 'concluso' ||
                (statoEv != 'in_corso' && statoEv != 'in_programma' && dtFine != null && ItalianTime.now().isAfter(dtFine));

            final bool isOperativa =
                tipo == 'invito' || tipo.contains('proposta') || tipo == 'bonus_malus' || tipo.contains('var_');
            if (isEvConcluso && isOperativa) {
              if (d['_id'] is ObjectId) {
                try {
                  await DbService.instance.notificheCollection.remove(where.id(d['_id'] as ObjectId));
                } catch (_) {}
              }
              continue;
            }
          }
        }

        // Controllo dello stato di voto per proposte / votazioni live
        bool haGiaVotato = false;
        String votoEspresso = (d['votoEspresso'] ?? '').toString();
        bool votazioneChiusa = false;
        String esitoVotazione = '';

        final bonusId = (d['bonusId'] ?? '').toString().trim().toLowerCase();
        final bonusTitolo = (d['bonusTitolo'] ?? '').toString().trim().toLowerCase();

        final matchedBm = (bonusId.isNotEmpty ? bonusMalusMap[bonusId] : null) ??
            (bonusTitolo.isNotEmpty ? bonusMalusMap[bonusTitolo] : null);

        if (matchedBm != null) {
          final propDa = (matchedBm['propostoDa'] ?? '').toString().trim();
          if (propDa.isNotEmpty && cleanNick.isNotEmpty && NicknameHelper.isSame(propDa, cleanNick, uDocs)) {
            haGiaVotato = true;
            votoEspresso = 'pro';
          }
          final bmStato = (matchedBm['stato'] ?? '').toString().toLowerCase();
          if (bmStato == 'approvato' || bmStato == 'respinto') {
            votazioneChiusa = true;
            esitoVotazione = bmStato;
          }
        }

        if (!haGiaVotato && cleanNick.isNotEmpty) {
          for (var vDoc in votazioniDocs) {
            final vUser = (vDoc['utente'] ?? '').toString().trim();
            if (!NicknameHelper.isSame(vUser, cleanNick, uDocs)) continue;

            final vId = (vDoc['votazioneId'] ?? vDoc['bonusId'] ?? '').toString().trim().toLowerCase();
            final vTit = (vDoc['bonusTitolo'] ?? '').toString().trim().toLowerCase();
            final vEvId = (vDoc['eventoId'] ?? '').toString().trim().toLowerCase();

            final bool idMatch = bonusId.isNotEmpty && (vId == bonusId);
            final bool titleMatch = bonusTitolo.isNotEmpty &&
                vTit == bonusTitolo &&
                evIdLower.isNotEmpty &&
                vEvId.isNotEmpty &&
                vEvId == evIdLower;

            if (idMatch || titleMatch) {
              haGiaVotato = true;
              votoEspresso = (vDoc['voto']?.toString() ?? 'pro').toLowerCase();
              final vStato = (vDoc['stato'] ?? '').toString().toLowerCase();
              if (vStato == 'approvato' || vStato == 'respinto') {
                votazioneChiusa = true;
                esitoVotazione = vStato;
              }
              break;
            }
          }
        }

        if ((!haGiaVotato || !votazioneChiusa) && cleanNick.isNotEmpty) {
          Map<String, dynamic>? matchVotazione;
          if (bonusId.isNotEmpty && votazioniMap.containsKey(bonusId)) {
            matchVotazione = votazioniMap[bonusId];
          } else if (bonusTitolo.isNotEmpty && votazioniMap.containsKey(bonusTitolo)) {
            matchVotazione = votazioniMap[bonusTitolo];
          }

          if (matchVotazione != null) {
            final votiMap = matchVotazione['votiUtenti'] as Map? ?? {};
            for (var k in votiMap.keys) {
              if (NicknameHelper.isSame(k.toString().trim(), cleanNick, uDocs)) {
                haGiaVotato = true;
                votoEspresso = votiMap[k]?.toString() ?? 'votato';
                break;
              }
            }
            final statoVot = (matchVotazione['stato'] ?? '').toString().toLowerCase();
            if (statoVot == 'approvato' || statoVot == 'respinto' || statoVot == 'scaduto' || statoVot == 'concluso') {
              votazioneChiusa = true;
              esitoVotazione = statoVot;
            }
          }
        }

        final evDoc = evId.isNotEmpty ? (validEvents[evIdLower] ?? (evClean.isNotEmpty ? validEvents[evClean] : null)) : null;
        final String evStato = evDoc != null ? (evDoc['stato'] ?? '').toString().toLowerCase() : '';
        final String evDataInizio = evDoc != null ? (evDoc['data'] ?? '').toString() : '';

        seenKeys.add(idStr);
        final rawMittente = (d['mittente'] ?? 'FantaEventi').toString();
        final resolvedMittente = NicknameHelper.resolve(rawMittente, uDocs);

        String rawMessaggio = (d['messaggio'] ?? '').toString();
        rawMessaggio = rawMessaggio
            .replaceAll('Filippo ha proposto', '$resolvedMittente ha proposto')
            .replaceAll('Claudio ha proposto', 'Cloud ha proposto')
            .replaceAll('Claude ha proposto', 'Cloud ha proposto')
            .replaceAll('Antonio ha proposto', 'Ugnom ha proposto')
            .replaceAll('Claudio ti ha invitato', 'Cloud ti ha invitato')
            .replaceAll('Claude ti ha invitato', 'Cloud ti ha invitato')
            .replaceAll('Filippo ti ha invitato', 'Pippoforte ti ha invitato')
            .replaceAll('Antonio ti ha invitato', 'Ugnom ti ha invitato')
            .replaceAll('Claudio ha ricevuto', 'Cloud ha ricevuto')
            .replaceAll('Claude ha ricevuto', 'Cloud ha ricevuto')
            .replaceAll(' a Claudio ', ' a Cloud ')
            .replaceAll(' a Claude ', ' a Cloud ');

        final notVarId = (d['varId'] ?? '').toString().trim().toLowerCase();
        final notVarClean = notVarId.replaceAll(RegExp(r'[^a-f0-9]'), '');
        String finalStato = (d['stato'] ?? 'in_attesa').toString();
        bool finalLetto = d['letto'] == true;

        if (notVarId.isNotEmpty && tipo != 'var_esito') {
          final matchedVar = varMap[notVarId] ?? (notVarClean.isNotEmpty ? varMap[notVarClean] : null);
          if (matchedVar != null) {
            final vStato = (matchedVar['stato'] ?? '').toString().toLowerCase();
            if (vStato == 'approvata' || vStato == 'approvato') {
              finalStato = 'approvata';
              finalLetto = true;
            } else if (vStato == 'rifiutata' || vStato == 'rifiutato') {
              finalStato = 'rifiutata';
              finalLetto = true;
            }
            if (d['_id'] is ObjectId &&
                (d['stato'] == 'in_attesa' || d['stato'] == 'in_votazione') &&
                (finalStato == 'approvata' || finalStato == 'rifiutata')) {
              try {
                DbService.instance.notificheCollection.update(
                  where.id(d['_id'] as ObjectId),
                  modify.set('stato', finalStato).set('letto', true),
                );
              } catch (_) {}
            }
          }
        }

        notificheList.add({
          'id': idStr,
          'mittente': resolvedMittente,
          'destinatario': NicknameHelper.resolve((d['destinatario'] ?? '').toString(), uDocs),
          'titolo': d['titolo'] ?? 'Nuova Notifica',
          'messaggio': rawMessaggio,
          'eventoId': d['eventoId'] ?? '',
          'eventoStato': evStato,
          'eventoDataInizio': evDataInizio,
          'bonusId': d['bonusId'] ?? '',
          'bonusTitolo': d['bonusTitolo'] ?? '',
          'tipo': d['tipo'] ?? 'invito',
          'varId': d['varId'] ?? '',
          'stato': finalStato,
          'letto': finalLetto,
          'votoEspresso': votoEspresso,
          'haGiaVotato': haGiaVotato,
          'votazioneChiusa': votazioneChiusa,
          'esitoVotazione': esitoVotazione,
          'codiceAmico': d['codiceAmico'] ?? '',
          'segnalazioneId': d['segnalazioneId'] ?? '',
          'data': d['data']?.toString() ?? d['timestamp']?.toString() ?? ItalianTime.now().toIso8601String(),
        });
      }

      return Response.ok(
        jsonEncode(notificheList),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/push
  Future<Response> inviaPush(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawDest = (data['destinatari'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final titolo = (data['titolo'] ?? 'FantaEventi').toString();
      final messaggio = (data['messaggio'] ?? '').toString();
      final payloadData = (data['data'] is Map)
          ? Map<String, dynamic>.from(data['data'] as Map)
          : <String, dynamic>{};

      final sent = await FcmService.instance.inviaPushAUtenti(
        rawDest,
        titolo: titolo,
        messaggio: messaggio,
        data: payloadData,
      );

      return Response.ok(
        jsonEncode({'success': true, 'sent': sent}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/segna-letta
  Future<Response> segnaLetta(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final notificaId = data['notificaId']?.toString() ?? data['id']?.toString() ?? '';

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null
          ? where.id(objId)
          : where.eq('notificaId', notificaId).or(where.eq('_id', notificaId));

      await DbService.instance.notificheCollection.update(
        selector,
        modify.set('letto', true),
      );

      return Response.ok(
        jsonEncode({'message': 'Notifica segnata come letta'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/segna-tutte-lette
  Future<Response> segnaTutteLette(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawNick = (data['destinatario'] ?? data['utente'] ?? data['nickname'] ?? '').toString().trim();
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final cleanNick = NicknameHelper.resolve(rawNick, uDocs).trim().toLowerCase();

      final docs = await DbService.instance.notificheCollection.find().toList();
      for (var d in docs) {
        final dest = NicknameHelper.resolve((d['destinatario'] ?? '').toString(), uDocs).trim().toLowerCase();
        if ((dest == cleanNick || cleanNick.isEmpty) && d['letto'] != true && d['_id'] is ObjectId) {
          await DbService.instance.notificheCollection.update(
            where.id(d['_id'] as ObjectId),
            modify.set('letto', true),
          );
        }
      }

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Tutte le notifiche segnate come lette'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/elimina
  Future<Response> eliminaNotifica(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final notificaId = (data['notificaId'] ?? data['id'] ?? '').toString().trim();
      if (notificaId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'notificaId obbligatorio'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null
          ? where.id(objId)
          : where.eq('notificaId', notificaId).or(where.eq('_id', notificaId));

      await DbService.instance.notificheCollection.remove(selector);
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Notifica eliminata'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/elimina-multiple
  Future<Response> eliminaNotificheMultiple(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawIds = (data['notificaIds'] ?? data['ids']) as List<dynamic>? ?? [];
      for (var rawId in rawIds) {
        final id = rawId.toString().trim();
        if (id.isEmpty) continue;
        ObjectId? objId;
        try { objId = ObjectId.fromHexString(id); } catch (_) {}
        final selector = objId != null
            ? where.id(objId)
            : where.eq('notificaId', id).or(where.eq('_id', id));
        await DbService.instance.notificheCollection.remove(selector);
      }
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Notifiche eliminate'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/elimina-tutte
  Future<Response> eliminaTutteNotifiche(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawDest = (data['destinatario'] ?? data['utente'] ?? '').toString().trim();
      final soloLette = data['soloLette'] == true;
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final cleanNick = NicknameHelper.resolve(rawDest, uDocs).trim().toLowerCase();

      final docs = await DbService.instance.notificheCollection.find().toList();
      for (var d in docs) {
        final dest = NicknameHelper.resolve((d['destinatario'] ?? '').toString(), uDocs).trim().toLowerCase();
        final isLetto = d['letto'] == true;
        if (dest == cleanNick || cleanNick.isEmpty) {
          if (!soloLette || isLetto) {
            if (d['_id'] is ObjectId) {
              await DbService.instance.notificheCollection.remove(where.id(d['_id'] as ObjectId));
            }
          }
        }
      }
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Notifiche eliminate con successo'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/notifiche/benvenuto
  Future<Response> assicuraNotificaBenvenuto(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final rawNick = (data['nickname'] ?? data['utente'] ?? '').toString().trim();
      if (rawNick.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'nickname obbligatorio'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final uDocs = await UtenteController.getCachedUtentiDocs();
      final nickname = NicknameHelper.resolve(rawNick, uDocs);

      Map<String, dynamic>? targetUser;
      for (var u in uDocs) {
        final uNick = (u['nickname'] ?? u['username'] ?? u['nome'] ?? '').toString().trim();
        if (NicknameHelper.isSame(uNick, nickname, uDocs)) {
          targetUser = u;
          break;
        }
      }

      // La notifica di benvenuto deve arrivare SOLO ED UNICAMENTE quando l'utente si è appena iscritto.
      if (_isVeteranoUser(targetUser)) {
        return Response.ok(
          jsonEncode({'success': true, 'skippedVeterano': true}),
          headers: {'content-type': 'application/json'},
        );
      }

      final allDocs = await DbService.instance.notificheCollection.find(
        where.eq('destinatario', nickname),
      ).toList();

      final hasWelcome = allDocs.any((n) =>
          (n['tipo'] ?? '').toString().toLowerCase() == 'benvenuto' ||
          (n['titolo'] ?? '').toString().contains('Benvenuto') ||
          (n['mittente'] ?? '').toString().contains('Redazione'));

      if (!hasWelcome) {
        await DbService.instance.notificheCollection.insertOne({
          'mittente': 'Redazione FantaEventi 👑',
          'destinatario': nickname,
          'titolo': 'Benvenuto in FantaEventi! 🎉',
          'messaggio':
              'Ciao $nickname! Benvenuto nella community ufficiale di FantaEventi. Da qui riceverai tutti gli inviti ad eventi dei tuoi amici, le notifiche del VAR e gli aggiornamenti di classifica. Puoi eliminare qualsiasi notifica toccando la \'X\' in alto a destra nella card!',
          'tipo': 'benvenuto',
          'stato': 'in_attesa',
          'letto': false,
          'data': ItalianTime.now().toIso8601String(),
        });
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
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
      final azione = (data['azione']?.toString() ?? '').toLowerCase();
      final utente = data['utente']?.toString() ?? '';

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(notificaId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('_id', notificaId);
      final doc = await DbService.instance.notificheCollection.findOne(selector);

      if (doc != null) {
        final eventoId = doc['eventoId']?.toString() ?? '';
        final isPro = azione == 'accetta' || azione == 'pro' || azione == 'favorevole';
        final nuovoStato = isPro ? 'accettato' : 'rifiutato';

        await DbService.instance.notificheCollection.update(
          selector,
          modify.set('stato', nuovoStato).set('votoEspresso', isPro ? 'pro' : 'contro').set('letto', true),
        );

        if (azione == 'accetta' && eventoId.isNotEmpty) {
          ObjectId? evObjId;
          try { evObjId = ObjectId.fromHexString(eventoId); } catch (_) {}
          final evSelector = evObjId != null ? where.id(evObjId) : where.eq('nome', eventoId);
          final evDoc = await DbService.instance.eventiCollection.findOne(evSelector);

          if (evDoc != null) {
            final pullList = {
              utente,
              utente.toLowerCase(),
              utente.toUpperCase(),
              utente.trim(),
              utente.trim().toLowerCase(),
            }.toList();

            await DbService.instance.eventiCollection.update(
              evSelector,
              modify
                .addToSet('partecipanti', utente)
                .pullAll('invitati', pullList),
            );
          }
        }

        // Accettazione richiesta di amicizia
        if (azione == 'accetta' && doc['tipo'] == 'richiesta_amicizia') {
          final mittente = (doc['mittente'] ?? '').toString().trim();
          final destinatario = (doc['destinatario'] ?? utente).toString().trim();
          if (mittente.isNotEmpty && destinatario.isNotEmpty) {
            await DbService.instance.utentiCollection.update(
              where.eq('nickname', mittente).or(where.eq('nome', mittente)),
              modify.addToSet('amici', destinatario),
            );
            await DbService.instance.utentiCollection.update(
              where.eq('nickname', destinatario).or(where.eq('nome', destinatario)),
              modify.addToSet('amici', mittente),
            );
            UtenteController.invalidateCache();
          }
        }
      }

      return Response.ok(
        jsonEncode({'message': 'Risposta inviata con successo!'}),
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
