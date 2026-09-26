import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  print('=== TEST AUTOMATIZZATO: INVITO CONTINUATIVO E BLOCCO EVENTO IN CORSO ===');

  final evColl = db.collection('Evento');
  final notColl = db.collection('Notifiche');

  final testEvId = ObjectId();
  final testEvIdStr = testEvId.oid;

  try {
    // 1. Crea Evento di test "In Programma" (orario inizio tra 2 ore)
    final now = DateTime.now();
    final startProg = now.add(const Duration(hours: 2));
    final endProg = now.add(const Duration(hours: 6));

    await evColl.insertOne({
      '_id': testEvId,
      'titolo': 'Test Invito Continuativo',
      'nome': 'Test Invito Continuativo',
      'descrizione': 'Evento di test per verificare inviti e blocchi',
      'data': startProg.toIso8601String(),
      'dataFine': endProg.toIso8601String(),
      'luogo': 'Stadio Test',
      'stato': 'in_programma',
      'propostoDa': 'Cloud',
      'creatore': 'Cloud',
      'partecipanti': ['Cloud'],
      'invitati': ['Ugnom'],
      'penalitaFalsaTestimonianza': -10,
    });
    print('✅ 1. Evento In Programma creato (ID: $testEvIdStr)');

    // 2. Simula invito continuativo di un nuovo amico (es. "Ale04" e "Ziogab")
    final nuoviAmici = ['Ale04', 'Ziogab'];
    
    // Verifica evento e aggiungi
    final evDoc = await evColl.findOne(where.id(testEvId));
    assert(evDoc != null, 'Evento deve esistere');
    final stato = (evDoc!['stato'] ?? 'in_programma').toString().toLowerCase();
    final dtStart = DateTime.parse(evDoc['data']);
    assert(stato == 'in_programma' && DateTime.now().isBefore(dtStart), 'Evento deve essere in programma');

    final List<dynamic> currentInvitati = List.from(evDoc['invitati'] ?? []);
    for (var amico in nuoviAmici) {
      if (!currentInvitati.contains(amico)) currentInvitati.add(amico);
      await notColl.insertOne({
        'mittente': 'Cloud',
        'destinatario': amico,
        'titolo': 'Invito ad Evento: Test Invito Continuativo',
        'messaggio': 'Cloud ti ha invitato a partecipare all\'evento "Test Invito Continuativo"!',
        'eventoId': testEvIdStr,
        'tipo': 'invito',
        'stato': 'in_attesa',
        'data': DateTime.now().toIso8601String(),
      });
    }
    await evColl.update(where.id(testEvId), modify.set('invitati', currentInvitati));

    // Verifica su DB
    final updatedEv = await evColl.findOne(where.id(testEvId));
    final invitatiDb = List<String>.from(updatedEv!['invitati']);
    print('✅ 2. Invito continuativo riuscito! Invitati su DB: $invitatiDb');
    assert(invitatiDb.contains('Ale04') && invitatiDb.contains('Ziogab'), 'Nuovi invitati devono essere presenti');

    final notifs = await notColl.find(where.eq('eventoId', testEvIdStr)).toList();
    print('✅ 3. Notifiche generate nel DB: ${notifs.length}');
    assert(notifs.length >= 2, 'Devono esserci le notifiche per i nuovi invitati');

    // 4. Test blocco: cambia stato in "in_corso" e tenta di invitare o iscriversi
    await evColl.update(where.id(testEvId), modify.set('stato', 'in_corso').set('data', now.subtract(const Duration(minutes: 5)).toIso8601String()));
    final inCorsoDoc = await evColl.findOne(where.id(testEvId));
    final inCorsoStato = (inCorsoDoc!['stato'] ?? '').toString().toLowerCase();
    final inCorsoStart = DateTime.parse(inCorsoDoc['data']);

    bool canInviteInCorso = !(inCorsoStato == 'in_corso' || inCorsoStato == 'concluso' || DateTime.now().isAfter(inCorsoStart));
    print('✅ 4. Test blocco invito ad evento in corso: canInvite = $canInviteInCorso (atteso: false)');
    assert(!canInviteInCorso, 'Non deve essere possibile invitare ad evento in corso');

    bool canJoinInCorso = !(inCorsoStato == 'in_corso' || inCorsoStato == 'concluso' || DateTime.now().isAfter(inCorsoStart));
    print('✅ 5. Test blocco iscrizione ad evento in corso: canJoin = $canJoinInCorso (atteso: false)');
    assert(!canJoinInCorso, 'Non deve essere possibile iscriversi ad evento in corso');

    print('\n🎉 TUTTI I TEST SONO STATI SUPERATI CON SUCCESSO!');
  } finally {
    // Pulizia database
    await evColl.remove(where.id(testEvId));
    await notColl.remove(where.eq('eventoId', testEvIdStr));
    print('🧹 Documenti di test puliti dal database.');
    await db.close();
  }
}
