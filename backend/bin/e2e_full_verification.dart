import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';

const String baseUrl = 'http://localhost:8088/api';
const String mongoUri = 'mongodb+srv://Lorenzo:T3RUH4GJDfaXeee@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';

void main() async {
  print('=====================================================');
  print('🚀 INIZIO COLLAUDO COMPLETO END-TO-END FANTAEVENTI 2.0');
  print('=====================================================');

  final Stopwatch totalWatch = Stopwatch()..start();
  int testsPassed = 0;
  int testsTotal = 0;

  void report(String testName, bool success, [String details = '']) {
    testsTotal++;
    if (success) {
      testsPassed++;
      print('  ✅ [PASS] $testName ${details.isNotEmpty ? "($details)" : ""}');
    } else {
      print('  ❌ [FAIL] $testName: $details');
    }
  }

  // 1. Health check
  print('\n--- 1. VERIFICA HEALTH & RENDER DISPONIBILITÀ ---');
  final healthWatch = Stopwatch()..start();
  try {
    final res = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 15));
    healthWatch.stop();
    report('Health Check Endpoint', res.statusCode == 200, '${healthWatch.elapsedMilliseconds}ms, body: ${res.body.trim()}');
  } catch (e) {
    report('Health Check Endpoint', false, e.toString());
  }

  // 2. Feed Eventi retrieval speed (Pull-to-refresh simulation)
  print('\n--- 2. FEED EVENTI & PERFORMANCE PULL-TO-REFRESH ---');
  final feedWatch = Stopwatch()..start();
  try {
    final res = await http.get(Uri.parse('$baseUrl/eventi')).timeout(const Duration(seconds: 8));
    feedWatch.stop();
    final List<dynamic> eventi = jsonDecode(res.body);
    report('Feed Eventi Response Time', feedWatch.elapsedMilliseconds < 1000, '${feedWatch.elapsedMilliseconds}ms (target <1000ms, trovati ${eventi.length} eventi)');
  } catch (e) {
    report('Feed Eventi Response Time', false, e.toString());
  }

  // 3. Verifica Utenti & Autenticazione (Cloud & Ugnom)
  print('\n--- 3. AUTENTICAZIONE & PROFILI (CLOUD & UGNOM) ---');
  Map<String, dynamic>? cloudUser;
  Map<String, dynamic>? ugnomUser;
  try {
    final res = await http.get(Uri.parse('$baseUrl/utenti')).timeout(const Duration(seconds: 8));
    final List<dynamic> users = jsonDecode(res.body);
    for (var u in users) {
      final nick = (u['nickname'] ?? u['nome'] ?? '').toString().toLowerCase();
      if (nick == 'cloud') cloudUser = Map<String, dynamic>.from(u as Map);
      if (nick == 'ugnom') ugnomUser = Map<String, dynamic>.from(u as Map);
    }
    report('Recupero Profilo Cloud', cloudUser != null, 'Cloud amici: ${cloudUser?['amici']}');
    report('Recupero Profilo Ugnom', ugnomUser != null, 'Ugnom amici: ${ugnomUser?['amici']}');
  } catch (e) {
    report('Recupero Profili', false, e.toString());
  }

  // 4. Verifica Amicizia Bidirezionale Iniziale
  print('\n--- 4. AMICIZIE BIDIREZIONALI (CLOUD <-> UGNOM) ---');
  bool cloudHasUgnom = false;
  bool ugnomHasCloud = false;
  if (cloudUser != null && ugnomUser != null) {
    final cloudAmici = (cloudUser['amici'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};
    final ugnomAmici = (ugnomUser['amici'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};
    cloudHasUgnom = cloudAmici.contains('ugnom');
    ugnomHasCloud = ugnomAmici.contains('cloud');
    report('Cloud vede Ugnom negli amici', cloudHasUgnom);
    report('Ugnom vede Cloud negli amici', ugnomHasCloud);
  }

  // 5. Test Blocco Utente (Cloud blocca Ugnom)
  print('\n--- 5. MODERAZIONE: TEST BLOCCO UTENTE ---');
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/utenti/blocca'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'utente': 'Cloud', 'target': 'Ugnom'}),
    ).timeout(const Duration(seconds: 8));
    report('HTTP POST /utenti/blocca', res.statusCode == 200, res.body.trim());

    // Verifica su lista utenti aggiornata
    final uRes = await http.get(Uri.parse('$baseUrl/utenti')).timeout(const Duration(seconds: 8));
    final List<dynamic> freshUsers = jsonDecode(uRes.body);
    final freshCloud = freshUsers.firstWhere((u) => u['nickname'] == 'Cloud');
    final freshUgnom = freshUsers.firstWhere((u) => u['nickname'] == 'Ugnom');

    final bloccatiCloud = (freshCloud['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};
    final amiciCloud = (freshCloud['amici'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};
    final amiciUgnom = (freshUgnom['amici'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};

    report('Ugnom aggiunto a utentiBloccati di Cloud', bloccatiCloud.contains('ugnom'));
    report('Ugnom rimosso da amici di Cloud', !amiciCloud.contains('ugnom'));
    report('Cloud rimosso da amici di Ugnom', !amiciUgnom.contains('cloud'));
  } catch (e) {
    report('Test Blocco Utente', false, e.toString());
  }

  // 6. Test Sblocco Utente & Ripristino Amicizia Bidirezionale (Cloud sblocca Ugnom)
  print('\n--- 6. MODERAZIONE: TEST SBLOCCO UTENTE & RIPRISTINO AMICI ---');
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/utenti/sblocca'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'utente': 'Cloud', 'target': 'Ugnom'}),
    ).timeout(const Duration(seconds: 8));
    report('HTTP POST /utenti/sblocca', res.statusCode == 200, res.body.trim());

    // Verifica su lista utenti aggiornata
    final uRes = await http.get(Uri.parse('$baseUrl/utenti')).timeout(const Duration(seconds: 8));
    final List<dynamic> freshUsers = jsonDecode(uRes.body);
    final freshCloud = freshUsers.firstWhere((u) => u['nickname'] == 'Cloud');
    final freshUgnom = freshUsers.firstWhere((u) => u['nickname'] == 'Ugnom');

    final bloccatiCloud = (freshCloud['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};
    final amiciCloud = (freshCloud['amici'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};
    final amiciUgnom = (freshUgnom['amici'] as List<dynamic>?)?.map((e) => e.toString().toLowerCase()).toSet() ?? {};

    report('Ugnom rimosso da utentiBloccati di Cloud', !bloccatiCloud.contains('ugnom'));
    report('Ugnom RIPRISTINATO negli amici di Cloud', amiciCloud.contains('ugnom'), 'amici: $amiciCloud');
    report('Cloud RIPRISTINATO negli amici di Ugnom', amiciUgnom.contains('cloud'), 'amici: $amiciUgnom');
  } catch (e) {
    report('Test Sblocco Utente', false, e.toString());
  }

  // 7. Notifiche REST endpoint
  print('\n--- 7. NOTIFICHE & INVITI (ENDPOINT RAPIDO) ---');
  try {
    final res = await http.get(Uri.parse('$baseUrl/notifiche?utente=Ugnom')).timeout(const Duration(seconds: 5));
    report('HTTP GET /notifiche?utente=Ugnom', res.statusCode == 200, 'Trovate ${jsonDecode(res.body).length} notifiche');
    final nots = jsonDecode(res.body) as List;
    final sbloccoNot = nots.firstWhere((n) => n['tipo'] == 'sblocco_utente', orElse: () => null);
    report('Notifica di Sblocco presente per Ugnom', sbloccoNot != null, sbloccoNot?['messaggio'] ?? '');
  } catch (e) {
    report('Notifiche Endpoint', false, e.toString());
  }

  // 8. Creazione Evento
  print('\n--- 8. CREAZIONE EVENTO DA CLOUD ---');
  String? createdEventId;
  final testEventTitle = 'Collaudo Zero Rischi Cloud e Ugnom';
  try {
    final res = await http.post(
      Uri.parse('$baseUrl/eventi/crea'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'titolo': testEventTitle,
        'descrizione': 'Evento di verifica funzionale e performance automatica',
        'data': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'dataFine': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        'luogo': 'Arena Test',
        'propostoDa': 'Cloud',
        'partecipanti': ['Cloud'],
        'invitati': ['Ugnom'],
      }),
    ).timeout(const Duration(seconds: 8));
    report('HTTP POST /eventi/crea', res.statusCode == 200, res.body.trim());
    final data = jsonDecode(res.body);
    createdEventId = data['id']?.toString() ?? data['eventoId']?.toString();
    report('ID Evento Creato Assegnato', createdEventId != null && createdEventId!.isNotEmpty, 'ID: $createdEventId');
  } catch (e) {
    report('Creazione Evento', false, e.toString());
  }

  // 9. Partecipazione Evento (Ugnom entra nell'evento)
  print('\n--- 9. PARTECIPAZIONE EVENTO (UGNOM SI UNISCE) ---');
  if (createdEventId != null) {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/eventi/partecipa'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'eventoId': createdEventId,
          'utente': 'Ugnom',
        }),
      ).timeout(const Duration(seconds: 8));
      report('HTTP POST /eventi/partecipa', res.statusCode == 200, res.body.trim());

      // Verifica partecipanti aggiornati
      final evRes = await http.get(Uri.parse('$baseUrl/eventi')).timeout(const Duration(seconds: 8));
      final List<dynamic> freshEventi = jsonDecode(evRes.body);
      final ev = freshEventi.firstWhere((e) => e['id'] == createdEventId, orElse: () => null);
      final parts = (ev?['partecipanti'] as List<dynamic>?)?.map((p) => p.toString().toLowerCase()).toList() ?? [];
      report('Partecipanti aggiornati istantaneamente (2 giocatori)', parts.length == 2 && parts.contains('ugnom') && parts.contains('cloud'), 'partecipanti: $parts');
    } catch (e) {
      report('Partecipazione Evento', false, e.toString());
    }
  }

  // 10. Proposta Bonus/Malus
  print('\n--- 10. PROPOSTA BONUS/MALUS ---');
  String? createdBonusId;
  if (createdEventId != null) {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/bonus-malus/proponi'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'eventoId': createdEventId,
          'eventoTitolo': testEventTitle,
          'titolo': 'Bonus Birra Fredda',
          'descrizione': 'Offre da bere a tutti i presenti',
          'punti': 15,
          'tipo': 'bonus',
          'propostoDa': 'Cloud',
          'destinatario': 'Ugnom',
        }),
      ).timeout(const Duration(seconds: 8));
      report('HTTP POST /bonus-malus/proponi', res.statusCode == 200, res.body.trim());
      final data = jsonDecode(res.body);
      createdBonusId = data['id']?.toString() ?? data['bonusId']?.toString();
      report('ID Bonus Assegnato', createdBonusId != null && createdBonusId!.isNotEmpty, 'BonusId: $createdBonusId');
    } catch (e) {
      report('Proposta Bonus/Malus', false, e.toString());
    }
  }

  // 11. Votazione Bonus/Malus
  print('\n--- 11. VOTAZIONE LIVE SU BONUS ---');
  if (createdBonusId != null) {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/votazioni/vota'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'votazioneId': createdBonusId,
          'utente': 'Ugnom',
          'voto': 'favorevole',
        }),
      ).timeout(const Duration(seconds: 8));
      report('HTTP POST /votazioni/vota', res.statusCode == 200, res.body.trim());
    } catch (e) {
      report('Votazione Live', false, e.toString());
    }
  }

  // 12. Eliminazione Evento (Test Eliminazione Istantanea & Cascata)
  print('\n--- 12. ELIMINAZIONE EVENTO RAPIDA & CASCATA ---');
  if (createdEventId != null) {
    final delWatch = Stopwatch()..start();
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/eventi/elimina'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'eventoId': createdEventId,
          'utente': 'Cloud',
        }),
      ).timeout(const Duration(seconds: 8));
      delWatch.stop();
      report('Eliminazione Evento Backend REST', res.statusCode == 200 && delWatch.elapsedMilliseconds < 800, '${delWatch.elapsedMilliseconds}ms, ${res.body.trim()}');

      // Verifica che non sia più presente nel feed eventi
      final evRes = await http.get(Uri.parse('$baseUrl/eventi')).timeout(const Duration(seconds: 8));
      final List<dynamic> freshEventi = jsonDecode(evRes.body);
      final exists = freshEventi.any((e) => e['id'] == createdEventId);
      report('Evento rimosso con successo dal Feed Eventi', !exists);
    } catch (e) {
      report('Eliminazione Evento', false, e.toString());
    }
  }

  // 13. Verifica Stato Finale Database MongoDB Atlas
  print('\n--- 13. STATO FINALE MONGODB ATLAS ---');
  try {
    final db = await Db.create(mongoUri);
    await db.open(secure: true);
    final usersCol = db.collection('Utenti');
    final finalCloud = await usersCol.findOne(where.eq('nickname', 'Cloud'));
    final finalUgnom = await usersCol.findOne(where.eq('nickname', 'Ugnom'));
    await db.close();

    final cloudAmici = (finalCloud?['amici'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final ugnomAmici = (finalUgnom?['amici'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final cloudBloccati = (finalCloud?['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final ugnomBloccati = (finalUgnom?['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    report('MongoDB: Cloud amici include Ugnom', cloudAmici.contains('Ugnom'), 'amici: $cloudAmici');
    report('MongoDB: Ugnom amici include Cloud', ugnomAmici.contains('Cloud'), 'amici: $ugnomAmici');
    report('MongoDB: Cloud bloccati è vuoto', cloudBloccati.isEmpty, 'bloccati: $cloudBloccati');
    report('MongoDB: Ugnom bloccati è vuoto', ugnomBloccati.isEmpty, 'bloccati: $ugnomBloccati');
  } catch (e) {
    report('Verifica Finale MongoDB Atlas', false, e.toString());
  }

  totalWatch.stop();
  print('\n=====================================================');
  print('🏁 RISULTATO COLLAUDO: $testsPassed / $testsTotal TEST SUPERATI');
  print('⏱️  TEMPO TOTALE ESECUZIONE: ${totalWatch.elapsedMilliseconds}ms');
  print('=====================================================');
}
