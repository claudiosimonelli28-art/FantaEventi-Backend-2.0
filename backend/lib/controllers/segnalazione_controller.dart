import 'dart:async';
import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../services/fcm_service.dart';
import '../utils/auth_token_helper.dart';
import '../utils/italian_time.dart';
import '../utils/nickname_helper.dart';
import 'utente_controller.dart';

class SegnalazioneController {
  /// Registra una nuova segnalazione inviata da un utente
  Future<Response> creaSegnalazione(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final verifiedCaller = AuthTokenHelper.getVerifiedNickname(request);
      final rawSegnalatore = (data['segnalatore'] ?? '').toString().trim();
      final segnalatore = (verifiedCaller != null && verifiedCaller.isNotEmpty) ? verifiedCaller : rawSegnalatore;
      final segnalato = (data['segnalato'] ?? '').toString().trim();
      final motivo = (data['motivo'] ?? '').toString().trim();
      final dettagli = (data['dettagli'] ?? '').toString().trim();

      if (segnalatore.isEmpty || segnalato.isEmpty || motivo.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Parametri segnalatore, segnalato e motivo obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final uDocs = await UtenteController.getCachedUtentiDocs();
      final cleanSegnalatore = NicknameHelper.resolve(segnalatore, uDocs);
      final cleanSegnalato = NicknameHelper.resolve(segnalato, uDocs);

      final nowIso = ItalianTime.now().toIso8601String();
      final Map<String, dynamic> doc = <String, dynamic>{
        'segnalatore': cleanSegnalatore,
        'segnalato': cleanSegnalato,
        'motivo': motivo,
        'dettagli': dettagli,
        'timestamp': nowIso,
        'stato': 'in_attesa', // in_attesa | ammonito | bannato | riabilitato | archiviata
      };

      await DbService.instance.segnalazioniCollection.insertOne(doc);

      // Notifica in-app per Cloud (Amministratore)
      await DbService.instance.notificheCollection.insertOne(<String, dynamic>{
        'mittente': cleanSegnalatore,
        'destinatario': 'Cloud',
        'tipo': 'segnalazione_utente',
        'titolo': '🛡️ Nuova Segnalazione Community',
        'messaggio': '@$cleanSegnalatore ha segnalato @$cleanSegnalato per "$motivo"${dettagli.isNotEmpty ? ' ("$dettagli")' : ''}. Apri il Centro Moderazione nel tuo Profilo per gestirla.',
        'stato': 'in_attesa',
        'letto': false,
        'data': nowIso,
        'timestamp': nowIso,
      });

      unawaited(
        FcmService.instance.inviaPushAUtenti(
          ['Cloud'],
          titolo: '🛡️ Nuova Segnalazione Community',
          messaggio: '@$cleanSegnalatore ha segnalato @$cleanSegnalato per "$motivo". Apri il Centro Moderazione nel tuo Profilo.',
          data: {'tipo': 'segnalazione_utente'},
        ),
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'notificaCreata': true,
          'message': 'Segnalazione registrata con successo',
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// Recupera tutte le segnalazioni (riservato esclusivamente all'amministratore Cloud verificato via JWT)
  Future<Response> getSegnalazioni(Request request) async {
    try {
      if (!AuthTokenHelper.isAdminRequest(request)) {
        return Response.forbidden(
          jsonEncode({'error': 'Accesso riservato esclusivamente all\'amministratore'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final docs = await DbService.instance.segnalazioniCollection
          .find(where.sortBy('timestamp', descending: true))
          .toList();
      final uDocs = await UtenteController.getCachedUtentiDocs();
      final Set<String> utentiGiaAmmoniti = {};

      for (var u in uDocs) {
        final nick = NicknameHelper.resolve((u['nickname'] ?? u['username'] ?? u['nome'] ?? '').toString(), uDocs).toLowerCase();
        final int amm = (u['ammonizioni'] is num) ? (u['ammonizioni'] as num).toInt() : 0;
        if (amm >= 1 && u['isBanned'] != true) {
          utentiGiaAmmoniti.add(nick);
        }
      }

      final list = docs.map((d) {
        final idStr = d['_id'] is ObjectId ? (d['_id'] as ObjectId).oid : d['_id']?.toString() ?? '';
        return <String, dynamic>{
          'id': idStr,
          'segnalatore': d['segnalatore'] ?? '',
          'segnalato': d['segnalato'] ?? '',
          'motivo': d['motivo'] ?? '',
          'dettagli': d['dettagli'] ?? '',
          'timestamp': d['timestamp'] ?? '',
          'stato': d['stato'] ?? 'in_attesa',
          'ammonizioneScontata': d['ammonizioneScontata'] == true,
        };
      }).toList();

      final Set<String> utentiValutatiDaStorico = {};
      for (var s in list) {
        final st = (s['stato'] ?? '').toString().toLowerCase();
        final nick = NicknameHelper.resolve((s['segnalato'] ?? '').toString(), uDocs).toLowerCase();
        if (nick.isEmpty || utentiValutatiDaStorico.contains(nick)) continue;

        if (st == 'bannato' || st == 'riabilitato') {
          utentiGiaAmmoniti.remove(nick);
          utentiValutatiDaStorico.add(nick);
        } else if (st == 'ammonito') {
          if (s['ammonizioneScontata'] == true) {
            utentiGiaAmmoniti.remove(nick);
          } else {
            utentiGiaAmmoniti.add(nick);
          }
          utentiValutatiDaStorico.add(nick);
        }
      }

      for (var s in list) {
        final nick = NicknameHelper.resolve((s['segnalato'] ?? '').toString(), uDocs).toLowerCase();
        s['giaAmmonito'] = utentiGiaAmmoniti.contains(nick);
      }

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

  /// Gestisce una segnalazione: Ammonisci, Banna o Archivia (riservato esclusivamente a Cloud verificato via JWT)
  Future<Response> gestisciSegnalazione(Request request) async {
    try {
      if (!AuthTokenHelper.isAdminRequest(request)) {
        return Response.forbidden(
          jsonEncode({'error': 'Azioni di moderazione riservate esclusivamente all\'amministratore'}),
          headers: {'content-type': 'application/json'},
        );
      }

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

      final uDocs = await UtenteController.getCachedUtentiDocs();
      final cleanSegnalato = NicknameHelper.resolve(segnalato, uDocs);
      final bool isSecondaAmmonizione = data['secondaAmmonizione'] == true;
      final nowIso = ItalianTime.now().toIso8601String();

      if (azione == 'ammonisci') {
        await DbService.instance.segnalazioniCollection.update(
          sSelector,
          modify.set('stato', 'ammonito'),
        );

        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (NicknameHelper.isSame(uNick, cleanSegnalato, uDocs)) {
            final uId = uDoc['_id'] as ObjectId;
            await DbService.instance.utentiCollection.update(
              where.id(uId),
              modify.set('ammonizioni', 1),
            );
            break;
          }
        }
        UtenteController.invalidateCache();

        // Notifica ufficiale di ammonimento al segnalato
        await DbService.instance.notificheCollection.insertOne(<String, dynamic>{
          'mittente': 'Amministrazione',
          'destinatario': cleanSegnalato,
          'tipo': 'ammonizione_utente',
          'titolo': '⚠️ Richiamo Ufficiale di Moderazione (1/2)',
          'messaggio': 'Sei stato ammonito dall\'Amministrazione per comportamenti non conformi al regolamento di FantaEventi. Attenzione: alla prossima ammonizione il tuo account verrà automaticamente sospeso.',
          'stato': 'in_attesa',
          'letto': false,
          'data': nowIso,
          'timestamp': nowIso,
        });

        unawaited(
          FcmService.instance.inviaPushAUtenti(
            [cleanSegnalato],
            titolo: '⚠️ Richiamo Ufficiale di Moderazione (1/2)',
            messaggio:
                'Sei stato ammonito dall\'Amministrazione per comportamenti non conformi al regolamento di FantaEventi. Attenzione: alla prossima ammonizione il tuo account verrà automaticamente sospeso.',
            data: {'tipo': 'ammonizione_utente'},
          ),
        );

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'ammonito', 'notificaCreata': true}),
          headers: {'content-type': 'application/json'},
        );
      } else if (azione == 'banna') {
        await DbService.instance.segnalazioniCollection.update(
          sSelector,
          modify.set('stato', 'bannato'),
        );
        await DbService.instance.segnalazioniCollection.update(
          where.eq('segnalato', cleanSegnalato).and(where.eq('stato', 'ammonito')),
          modify.set('ammonizioneScontata', true),
          multiUpdate: true,
        );

        // Disabilita account su Utenti e azzera contatore ammonizioni
        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (NicknameHelper.isSame(uNick, cleanSegnalato, uDocs)) {
            final uId = uDoc['_id'] as ObjectId;
            await DbService.instance.utentiCollection.update(
              where.id(uId),
              modify.set('isBanned', true).set('ammonizioni', 0),
            );
            break;
          }
        }
        UtenteController.invalidateCache();

        final banTitle = isSecondaAmmonizione ? '⛔ Account Sospeso (2ª Ammonizione)' : '⛔ Account Sospeso';
        final banMsg = isSecondaAmmonizione
            ? 'Hai ricevuto una seconda ammonizione ufficiale dall\'Amministrazione. Per somma di ammonizioni il tuo account su FantaEventi è stato sospeso.'
            : 'Il tuo account è stato sospeso dall\'Amministrazione per violazione del regolamento della community di FantaEventi.';

        await DbService.instance.notificheCollection.insertOne(<String, dynamic>{
          'mittente': 'Amministrazione',
          'destinatario': cleanSegnalato,
          'tipo': 'ban_utente',
          'titolo': banTitle,
          'messaggio': banMsg,
          'stato': 'in_attesa',
          'letto': false,
          'data': nowIso,
          'timestamp': nowIso,
        });

        unawaited(
          FcmService.instance.inviaPushAUtenti(
            [cleanSegnalato],
            titolo: banTitle,
            messaggio: banMsg,
            data: {'tipo': 'ban_utente'},
          ),
        );

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'bannato', 'notificaCreata': true}),
          headers: {'content-type': 'application/json'},
        );
      } else if (azione == 'sbanna' || azione == 'riabilita') {
        await DbService.instance.segnalazioniCollection.update(
          sSelector,
          modify.set('stato', 'riabilitato'),
        );
        await DbService.instance.segnalazioniCollection.update(
          where.eq('segnalato', cleanSegnalato).and(where.eq('stato', 'ammonito')),
          modify.set('ammonizioneScontata', true),
          multiUpdate: true,
        );

        // Riabilita account su Utenti e azzera contatore ammonizioni
        for (var uDoc in uDocs) {
          final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
          if (NicknameHelper.isSame(uNick, cleanSegnalato, uDocs)) {
            final uId = uDoc['_id'] as ObjectId;
            await DbService.instance.utentiCollection.update(
              where.id(uId),
              modify.set('isBanned', false).set('ammonizioni', 0),
            );
            break;
          }
        }
        UtenteController.invalidateCache();

        await DbService.instance.notificheCollection.insertOne(<String, dynamic>{
          'mittente': 'Amministrazione',
          'destinatario': cleanSegnalato,
          'tipo': 'riabilita_utente',
          'titolo': '✅ Account Riabilitato',
          'messaggio': 'La sospensione del tuo account è stata revocata dall\'Amministrazione. Puoi tornare a utilizzare FantaEventi!',
          'stato': 'in_attesa',
          'letto': false,
          'data': nowIso,
          'timestamp': nowIso,
        });

        unawaited(
          FcmService.instance.inviaPushAUtenti(
            [cleanSegnalato],
            titolo: '✅ Account Riabilitato',
            messaggio:
                'La sospensione del tuo account è stata revocata dall\'Amministrazione. Puoi tornare a utilizzare FantaEventi!',
            data: {'tipo': 'riabilita_utente'},
          ),
        );

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'riabilitato', 'notificaCreata': true}),
          headers: {'content-type': 'application/json'},
        );
      } else if (azione == 'archivia') {
        await DbService.instance.segnalazioniCollection.update(
          sSelector,
          modify.set('stato', 'archiviata'),
        );

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'archiviata', 'notificaCreata': true}),
          headers: {'content-type': 'application/json'},
        );
      } else if (azione == 'elimina') {
        await DbService.instance.segnalazioniCollection.remove(sSelector);

        return Response.ok(
          jsonEncode({'success': true, 'azione': 'eliminata', 'notificaCreata': true}),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.badRequest(
        body: jsonEncode({'error': 'Azione non riconosciuta (ammonisci, banna, sbanna, archivia, elimina)'}),
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
