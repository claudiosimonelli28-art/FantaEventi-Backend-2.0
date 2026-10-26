import 'dart:io';
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

void main() async {
  await DbService.instance.connect();

  final app = Router();
  final utenteCtrl = UtenteController();
  final eventoCtrl = EventoController();
  final bonusMalusCtrl = BonusMalusController();
  final votazioneCtrl = VotazioneController();
  final notificaCtrl = NotificaController();
  final varCtrl = VarController();

  // Rotte Utenti
  app.post('/api/login', utenteCtrl.login);
  app.post('/api/registrazione', utenteCtrl.creaUtente);
  app.get('/api/utenti/check-nickname', utenteCtrl.checkNickname);
  app.post('/api/utenti/imposta-password', utenteCtrl.impostaPassword);
  app.post('/api/utenti/richiedi-reset-password', utenteCtrl.richiediResetPassword);
  app.post('/api/utenti/conferma-reset-password', utenteCtrl.confermaResetPassword);
  app.post('/api/utenti/avatar', utenteCtrl.aggiornaAvatar);
  app.post('/api/utenti/elimina-account', utenteCtrl.eliminaAccount);
  app.get('/api/utenti', utenteCtrl.getUtenti);

  // Rotte Eventi
  app.get('/api/eventi', eventoCtrl.getEventi);
  app.post('/api/eventi/crea', eventoCtrl.creaEvento);
  app.post('/api/eventi/partecipa', eventoCtrl.partecipaEvento);
  app.post('/api/eventi/elimina', eventoCtrl.eliminaEvento);

  // Rotte Notifiche & Inviti
  app.get('/api/notifiche', notificaCtrl.getNotificheUtente);
  app.post('/api/notifiche/rispondi', notificaCtrl.rispondiNotifica);
  app.post('/api/notifiche/segna-letta', notificaCtrl.segnaLetta);

  // Rotte Bonus / Malus
  app.get('/api/bonusmalus', bonusMalusCtrl.getBonusMalus);
  app.post('/api/bonusmalus/crea', bonusMalusCtrl.creaBonusMalus);
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

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(app.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8088');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server avviato in ascolto su http://${server.address.host}:${server.port}');
}
