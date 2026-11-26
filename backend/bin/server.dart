import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:backend/db/db_service.dart';
import 'package:backend/controllers/utente_controller.dart';
import 'package:backend/controllers/evento_controller.dart';
import 'package:backend/controllers/bonus_malus_controller.dart';
import 'package:backend/controllers/votazione_controller.dart';
import 'package:backend/controllers/notifica_controller.dart';
import 'package:backend/controllers/var_controller.dart';
import 'package:backend/controllers/privacy_controller.dart';
import 'package:backend/controllers/segnalazione_controller.dart';
import 'package:backend/utils/auth_token_helper.dart';
import 'package:backend/utils/nickname_helper.dart';

Middleware _corsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
        });
      }
      final response = await innerHandler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
      });
    };
  };
}

Future<void> _dbRequestQueue = Future.value();

const Set<String> _sessionExemptPaths = {
  'api/health',
  'api/login',
  'api/registrazione',
  'api/utenti/check-nickname',
  'api/utenti/imposta-password',
  'api/utenti/richiedi-reset-password',
  'api/utenti/conferma-reset-password',
  'api/utenti/fcm-token/rimuovi',
};

/// Verifica che il dispositivo richiedente sia ancora l'unica sessione attiva del profilo ("1 Profilo = 1 Dispositivo").
/// Se l'utente ha effettuato un nuovo login su un altro dispositivo (activeSessionId diverso da sid),
/// restituisce 401 sessionDisplaced: true così il vecchio dispositivo effettua subito il logout pulito.
Future<Response?> _checkSingleDeviceSession(Request request) async {
  final cleanPath = request.url.path.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
  if (_sessionExemptPaths.contains(cleanPath) || cleanPath.startsWith('privacy') || cleanPath == 'termini') {
    return null;
  }

  final authHeader = (request.headers['authorization'] ?? request.headers['Authorization'] ?? '').trim();
  if (authHeader.toLowerCase().startsWith('bearer ')) {
    final rawToken = authHeader.substring(7).trim();
    if (rawToken.isNotEmpty) {
      final payload = AuthTokenHelper.verifyToken(rawToken);
      if (payload == null) {
        return Response(
          401,
          body: jsonEncode({
            'sessionDisplaced': true,
            'error': 'La tua sessione è scaduta. Effettua nuovamente l\'accesso.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final tokenSub = (payload['sub'] ?? '').toString().trim();
      final tokenNick = (payload['nickname'] ?? '').toString().trim();
      final tokenSid = (payload['sid'] ?? '').toString().trim();

      final uDocs = await UtenteController.getCachedUtentiDocs();
      Map<String, dynamic>? matchedUser;
      for (final u in uDocs) {
        final uId = u['_id'] is ObjectId ? (u['_id'] as ObjectId).oid : (u['_id']?.toString() ?? '');
        final uNick = (u['nickname'] ?? u['username'] ?? u['nome'] ?? '').toString().trim();
        if ((tokenSub.isNotEmpty && uId == tokenSub) ||
            (tokenNick.isNotEmpty && NicknameHelper.isSame(uNick, tokenNick, uDocs))) {
          matchedUser = u;
          break;
        }
      }

      if (matchedUser != null) {
        if (matchedUser['isBanned'] == true) {
          return Response.forbidden(
            jsonEncode({
              'isBanned': true,
              'error': 'Account sospeso dall\'Amministrazione.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        final dbActiveSid = (matchedUser['activeSessionId'] ?? '').toString().trim();
        if (dbActiveSid.isNotEmpty && tokenSid != dbActiveSid) {
          return Response(
            401,
            body: jsonEncode({
              'sessionDisplaced': true,
              'error':
                  'Hai effettuato l\'accesso a questo profilo su un altro dispositivo. Per sicurezza puoi restare collegato su un solo dispositivo alla volta.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }
      return null;
    }
  }

  // Fallback per vecchie sessioni salvate prive di header Bearer sulle rotte strettamente personali
  if (cleanPath == 'api/eventi' || cleanPath == 'api/notifiche' || cleanPath == 'api/utenti') {
    final queryUser = (request.url.queryParameters['utente'] ?? '').trim();
    if (queryUser.isNotEmpty) {
      final uDocs = await UtenteController.getCachedUtentiDocs();
      for (final u in uDocs) {
        final uNick = (u['nickname'] ?? u['username'] ?? u['nome'] ?? '').toString().trim();
        if (NicknameHelper.isSame(uNick, queryUser, uDocs)) {
          final dbActiveSid = (u['activeSessionId'] ?? '').toString().trim();
          if (dbActiveSid.isNotEmpty) {
            return Response(
              401,
              body: jsonEncode({
                'sessionDisplaced': true,
                'error':
                    'Hai effettuato l\'accesso a questo profilo su un altro dispositivo. Per sicurezza puoi restare collegato su un solo dispositivo alla volta.',
              }),
              headers: {'content-type': 'application/json'},
            );
          }
          break;
        }
      }
    }
  }

  return null;
}

Middleware _mongoDbMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.url.path == 'api/health' || request.url.path.startsWith('privacy')) {
        return await innerHandler(request);
      }

      final completer = Completer<void>();
      final previous = _dbRequestQueue;
      _dbRequestQueue = completer.future;
      try {
        await previous;
      } catch (_) {}

      try {
        String? cachedBody;
        Request effectiveReq = request;
        if (request.method != 'GET' && request.method != 'HEAD' && request.method != 'OPTIONS') {
          cachedBody = await request.readAsString();
          effectiveReq = request.change(body: cachedBody);
        }

        try {
          await DbService.instance.ensureConnected();
        } catch (e) {
          print('⚠️ Errore ensureConnected, tento reconnect: $e');
          try {
            await DbService.instance.reconnect();
          } catch (_) {}
        }

        final sessionErrorRes = await _checkSingleDeviceSession(effectiveReq);
        if (sessionErrorRes != null) {
          DbService.instance.markActive();
          return sessionErrorRes;
        }

        var response = await innerHandler(effectiveReq);
        if (response.statusCode == 500) {
          final errBody = await response.readAsString();
          final isSocketDrop = errBody.contains('ConnectionException') ||
              errBody.contains('connection closed') ||
              errBody.contains('Database non connesso') ||
              errBody.contains('SocketException') ||
              errBody.contains('No master connection');

          if (isSocketDrop) {
            print('🔄 [MongoDB] Socket chiusa rilevata su ${request.method} /${request.url.path}, riconnessione e retry immediato...');
            try {
              await DbService.instance.reconnect();
              final retryReq = cachedBody != null ? request.change(body: cachedBody) : request;
              final retryRes = await innerHandler(retryReq);
              if (retryRes.statusCode < 500) {
                DbService.instance.markActive();
              }
              return retryRes;
            } catch (_) {
              return Response.internalServerError(
                body: errBody,
                headers: {'content-type': 'application/json'},
              );
            }
          }
          return Response.internalServerError(
            body: errBody,
            headers: {'content-type': 'application/json'},
          );
        }

        DbService.instance.markActive();
        return response;
      } finally {
        completer.complete();
      }
    };
  };
}

void main() async {
  await DbService.instance.connect();
  try {
    await UtenteController.getCachedUtentiDocs();
  } catch (e) {
    print('⚠️ Pre-caching utenti fallito: $e');
  }

  final app = Router();
  final utenteCtrl = UtenteController();
  final eventoCtrl = EventoController();
  final bonusMalusCtrl = BonusMalusController();
  final votazioneCtrl = VotazioneController();
  final notificaCtrl = NotificaController();
  final varCtrl = VarController();
  final segnalazioneCtrl = SegnalazioneController();

  // Health Check
  app.get('/api/health', (Request req) => Response.ok('OK v2.5-secure'));

  // Rotte Utenti
  app.post('/api/login', utenteCtrl.login);
  app.post('/api/registrazione', utenteCtrl.creaUtente);
  app.get('/api/utenti/check-nickname', utenteCtrl.checkNickname);
  app.post('/api/utenti/imposta-password', utenteCtrl.impostaPassword);
  app.post('/api/utenti/richiedi-reset-password', utenteCtrl.richiediResetPassword);
  app.post('/api/utenti/conferma-reset-password', utenteCtrl.confermaResetPassword);
  app.post('/api/utenti/avatar', utenteCtrl.aggiornaAvatar);
  app.get('/api/utenti/avatar', utenteCtrl.getAvatar);
  app.post('/api/utenti/fcm-token', utenteCtrl.registraFcmToken);
  app.post('/api/utenti/fcm-token/rimuovi', utenteCtrl.rimuoviFcmToken);
  app.post('/api/utenti/elimina-account', utenteCtrl.eliminaAccount);
  app.get('/api/utenti', utenteCtrl.getUtenti);
  app.post('/api/utenti/blocca', utenteCtrl.bloccaUtente);
  app.post('/api/utenti/sblocca', utenteCtrl.sbloccaUtente);
  app.get('/api/utenti/bloccati', utenteCtrl.getUtentiBloccati);
  app.post('/api/utenti/completa-guida', utenteCtrl.completaGuida);
  app.post('/api/utenti/amicizia/richiedi', utenteCtrl.inviaRichiestaAmicizia);
  app.post('/api/utenti/amicizia/rispondi', utenteCtrl.rispondiRichiestaAmicizia);

  // Rotte Segnalazioni & Moderazione (Apple UGC 1.2)
  app.post('/api/segnalazioni/crea', segnalazioneCtrl.creaSegnalazione);
  app.get('/api/segnalazioni', segnalazioneCtrl.getSegnalazioni);
  app.post('/api/segnalazioni/gestisci', segnalazioneCtrl.gestisciSegnalazione);

  // Rotte Eventi
  app.get('/api/eventi', eventoCtrl.getEventi);
  app.post('/api/eventi/crea', eventoCtrl.creaEvento);
  app.post('/api/eventi/partecipa', eventoCtrl.partecipaEvento);
  app.post('/api/eventi/elimina', eventoCtrl.eliminaEvento);
  app.post('/api/eventi/invita', eventoCtrl.invitaAmici);
  app.post('/api/eventi/copertina', eventoCtrl.aggiornaCopertina);
  app.post('/api/eventi/riconcilia', eventoCtrl.riconciliaEventiETitoli);

  // Rotte Notifiche & Inviti
  app.get('/api/notifiche', notificaCtrl.getNotificheUtente);
  app.post('/api/notifiche/push', notificaCtrl.inviaPush);
  app.post('/api/notifiche/rispondi', notificaCtrl.rispondiNotifica);
  app.post('/api/notifiche/segna-letta', notificaCtrl.segnaLetta);
  app.post('/api/notifiche/segna-tutte-lette', notificaCtrl.segnaTutteLette);
  app.post('/api/notifiche/elimina', notificaCtrl.eliminaNotifica);
  app.post('/api/notifiche/elimina-multiple', notificaCtrl.eliminaNotificheMultiple);
  app.post('/api/notifiche/elimina-multiplo', notificaCtrl.eliminaNotificheMultiple);
  app.post('/api/notifiche/elimina-tutte', notificaCtrl.eliminaTutteNotifiche);
  app.post('/api/notifiche/benvenuto', notificaCtrl.assicuraNotificaBenvenuto);

  // Rotte Bonus / Malus
  app.get('/api/bonusmalus', bonusMalusCtrl.getBonusMalus);
  app.post('/api/bonusmalus/crea', bonusMalusCtrl.creaBonusMalus);
  app.post('/api/bonus-malus/proponi', bonusMalusCtrl.creaBonusMalus);
  app.post('/api/bonusmalus/assegna', bonusMalusCtrl.assegnaBonusMalus);
  app.post('/api/bonusmalus/annulla-assegnazione', bonusMalusCtrl.annullaAssegnazioneBonus);
  app.post('/api/bonusmalus/elimina', bonusMalusCtrl.eliminaBonusMalus);

  // Rotte Votazioni
  app.get('/api/votazioni', votazioneCtrl.getVotazioni);
  app.post('/api/votazioni/vota', votazioneCtrl.vota);

  // Rotte VAR (Verifica Assistita da Regia)
  app.post('/api/var/crea', varCtrl.creaRichiestaVar);
  app.get('/api/var/dettaglio', varCtrl.getRichiestaVar);
  app.get('/api/var/evento', varCtrl.getRichiesteVarEvento);
  app.get('/api/var/giudice', varCtrl.getRichiesteVarGiudice);
  app.post('/api/var/vota-testimone', varCtrl.votaTestimonianza);
  app.post('/api/var/decidi', varCtrl.decidiRichiesta);

  // Informativa sulla Privacy & Termini di Servizio (Web endpoint pubblico per Google Play & Apple Store)
  app.get('/privacy', PrivacyController.getPrivacyPolicy);
  app.get('/privacy-policy', PrivacyController.getPrivacyPolicy);
  app.get('/termini', PrivacyController.getPrivacyPolicy);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addMiddleware(_mongoDbMiddleware())
      .addHandler(app.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8088');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server avviato in ascolto su http://${server.address.host}:${server.port}');
}
