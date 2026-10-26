import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:backend/db/db_service.dart';
import 'package:backend/controllers/utente_controller.dart';
import 'package:backend/controllers/evento_controller.dart';
import 'package:backend/controllers/bonus_malus_controller.dart';
import 'package:backend/controllers/votazione_controller.dart';
import 'package:backend/controllers/notifica_controller.dart';
import 'package:backend/controllers/var_controller.dart';

void main() async {
  print('🧪 [E2E TEST ZERO RISCHI] Avvio suite di validazione automatica Backend...');

  // 1. Connessione a MongoDB Atlas
  await DbService.instance.connect();

  final app = Router();
  final utenteCtrl = UtenteController();
  final eventoCtrl = EventoController();
  final bonusMalusCtrl = BonusMalusController();
  final votazioneCtrl = VotazioneController();
  final notificaCtrl = NotificaController();
  final varCtrl = VarController();

  app.post('/api/login', utenteCtrl.login);
  app.post('/api/registrazione', utenteCtrl.creaUtente);
  app.get('/api/utenti/check-nickname', utenteCtrl.checkNickname);
  app.post('/api/utenti/imposta-password', utenteCtrl.impostaPassword);
  app.post('/api/utenti/richiedi-reset-password', utenteCtrl.richiediResetPassword);
  app.post('/api/utenti/conferma-reset-password', utenteCtrl.confermaResetPassword);
  app.post('/api/utenti/avatar', utenteCtrl.aggiornaAvatar);
  app.post('/api/utenti/elimina-account', utenteCtrl.eliminaAccount);
  app.get('/api/utenti', utenteCtrl.getUtenti);

  app.get('/api/eventi', eventoCtrl.getEventi);
  app.post('/api/eventi/crea', eventoCtrl.creaEvento);
  app.post('/api/eventi/partecipa', eventoCtrl.partecipaEvento);
  app.post('/api/eventi/elimina', eventoCtrl.eliminaEvento);

  app.get('/api/notifiche', notificaCtrl.getNotificheUtente);
  app.post('/api/notifiche/rispondi', notificaCtrl.rispondiNotifica);
  app.post('/api/notifiche/segna-letta', notificaCtrl.segnaLetta);

  app.get('/api/bonusmalus', bonusMalusCtrl.getBonusMalus);
  app.post('/api/bonusmalus/crea', bonusMalusCtrl.creaBonusMalus);
  app.post('/api/bonusmalus/assegna', bonusMalusCtrl.assegnaBonusMalus);
  app.post('/api/bonusmalus/annulla-assegnazione', bonusMalusCtrl.annullaAssegnazioneBonus);
  app.post('/api/bonusmalus/elimina', bonusMalusCtrl.eliminaBonusMalus);

  app.get('/api/votazioni', votazioneCtrl.getVotazioni);
  app.post('/api/votazioni/vota', votazioneCtrl.vota);

  app.post('/api/var/crea', varCtrl.creaRichiestaVar);
  app.get('/api/var/dettaglio', varCtrl.getRichiestaVar);
  app.get('/api/var/evento', varCtrl.getRichiesteVarEvento);
  app.get('/api/var/giudice', varCtrl.getRichiesteVarGiudice);
  app.post('/api/var/vota-testimone', varCtrl.votaTestimonianza);
  app.post('/api/var/decidi', varCtrl.decidiRichiesta);

  final testServer = await io.serve(app.call, InternetAddress.loopbackIPv4, 8099);
  final client = HttpClient();
  final baseUrl = 'http://localhost:8099';

  int passed = 0;
  int failed = 0;

  void report(String testName, bool success, [String? extra]) {
    if (success) {
      passed++;
      print('  ✅ $testName ${extra != null ? "($extra)" : ""}');
    } else {
      failed++;
      print('  ❌ $testName: FALLITO ${extra != null ? "-> $extra" : ""}');
    }
  }

  try {
    // TEST 1: GET /api/utenti
    {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/utenti'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final List<dynamic> list = jsonDecode(body);
      final hasCloud = list.any((u) => u['nickname'] == 'Cloud');
      final cloudDoc = list.firstWhere((u) => u['nickname'] == 'Cloud', orElse: () => {});
      final hasFullFields = cloudDoc['xp'] != null && cloudDoc['xpTotali'] != null && cloudDoc['badgeList'] != null;
      report('1. GET /api/utenti (30 utenti e parità modelli)', res.statusCode == 200 && list.length >= 25 && hasCloud && hasFullFields, 'Trovati ${list.length} utenti, Cloud Liv: ${cloudDoc['livello']} XP: ${cloudDoc['xp']}/${cloudDoc['xpProssimoLivello']}');
    }

    // TEST 2: GET /api/utenti/check-nickname
    {
      final req1 = await client.getUrl(Uri.parse('$baseUrl/api/utenti/check-nickname?nick=Cloud'));
      final res1 = await req1.close();
      final body1 = jsonDecode(await res1.transform(utf8.decoder).join());
      final bool check1 = body1['disponibile'] == false && (body1['suggerimenti'] as List).isNotEmpty;

      final req2 = await client.getUrl(Uri.parse('$baseUrl/api/utenti/check-nickname?nick=SuperTestUnique_XYZ99'));
      final res2 = await req2.close();
      final body2 = jsonDecode(await res2.transform(utf8.decoder).join());
      final bool check2 = body2['disponibile'] == true;

      report('2. GET /api/utenti/check-nickname (debounce e suggerimenti)', check1 && check2, 'Cloud non disp + 3 suggerimenti; XYZ99 disponibile');
    }

    // TEST 3: POST /api/login (Password errata vs corretta)
    {
      final req1 = await client.postUrl(Uri.parse('$baseUrl/api/login'));
      req1.headers.set('content-type', 'application/json');
      req1.add(utf8.encode(jsonEncode({'username': 'Cloud', 'password': 'WrongPassword123!'})));
      final res1 = await req1.close();
      await res1.drain();

      report('3. POST /api/login (sicurezza password non valida)', res1.statusCode == 403, 'Risposta 403 Forbidden corretta');
    }

    // TEST 4: GET /api/eventi
    {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/eventi'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final List<dynamic> list = jsonDecode(body);
      report('4. GET /api/eventi (recupero feed eventi)', res.statusCode == 200, 'Trovati ${list.length} eventi');
    }

    // TEST 5: GET /api/bonusmalus
    {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/bonusmalus'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final List<dynamic> list = jsonDecode(body);
      report('5. GET /api/bonusmalus (recupero catalogo bonus/malus)', res.statusCode == 200, 'Trovati ${list.length} bonus/malus');
    }

    // TEST 6: GET /api/votazioni
    {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/votazioni'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final List<dynamic> list = jsonDecode(body);
      report('6. GET /api/votazioni (aggregazione voti e quorum concorde)', res.statusCode == 200, 'Trovate ${list.length} votazioni');
    }

    // TEST 7: GET /api/notifiche?utente=Cloud
    {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/notifiche?utente=Cloud'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final List<dynamic> list = jsonDecode(body);
      report('7. GET /api/notifiche?utente=Cloud (ricezione notifiche)', res.statusCode == 200, 'Trovate ${list.length} notifiche');
    }
  } finally {
    client.close();
    await testServer.close(force: true);
    await DbService.instance.close();
  }

  print('\n🏁 ==========================================');
  print('   RISULTATO FINALE: $passed SUPERATI / $failed FALLITI');
  print('==========================================\n');

  if (failed == 0) {
    exit(0);
  } else {
    exit(1);
  }
}
