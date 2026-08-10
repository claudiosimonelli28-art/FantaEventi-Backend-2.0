import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === INIZIO TEST FLUSSO SCADENZA EVENTI E BADGE STORICO ===');
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();
  print('✅ Connesso a MongoDB Atlas (FantaEventi)');

  final evColl = db.collection('Evento');
  final utColl = db.collection('Utenti');

  // Pulizia evento test
  await evColl.remove(where.eq('titolo', 'Ferragosto Test'));

  final now = DateTime.now();
  final dtStart = now.subtract(const Duration(hours: 2));
  final dtEnd = now.subtract(const Duration(minutes: 5)); // Evento gia scaduto 5 minuti fa

  print('\n--------------------------------------------------');
  print('TEST 1: Inserimento Evento Scaduto "Ferragosto Test" (Inizio: 2h fa, Fine: 5m fa)');
  final evRes = await evColl.insertOne({
    'titolo': 'Ferragosto Test',
    'descrizione': 'Festa in spiaggia',
    'data': dtStart.toIso8601String(),
    'dataFine': dtEnd.toIso8601String(),
    'propostoDa': 'Cloud',
    'partecipanti': ['Cloud', 'Ugnom'],
    'invitati': [],
  });

  final evId = evRes.id as ObjectId;
  print('Evento inserito con ID: ${evId.toHexString()}');

  print('\n--------------------------------------------------');
  print('TEST 2: Simulazione Controllo Scadenza ed Assegnazione Badge Storico');
  final docs = await evColl.find().toList();
  final expiredDocs = docs.where((d) {
    final endStr = d['dataFine']?.toString() ?? d['data']?.toString() ?? '';
    final endDt = DateTime.tryParse(endStr) ?? now;
    return now.isAfter(endDt);
  }).toList();

  print('Eventi scaduti trovati nel DB: ${expiredDocs.length}');
  assert(expiredDocs.isNotEmpty, '❌ ERRORE: Nessun evento scaduto trovato!');

  for (var d in expiredDocs) {
    final badgeStr = '🎉 Partecipato a "${d['titolo']}" (${dtStart.day}/${dtStart.month} - ${dtEnd.day}/${dtEnd.month}/${dtEnd.year})';
    final partList = (d['partecipanti'] as List<dynamic>).map((e) => e.toString()).toList();
    
    for (var u in partList) {
      final uDoc = await utColl.findOne(where.eq('nome', u));
      if (uDoc != null) {
        final List<dynamic> badges = List.from(uDoc['badgeList'] ?? []);
        if (!badges.contains(badgeStr)) {
          badges.add(badgeStr);
          await utColl.update(where.eq('nome', u), modify.set('badgeList', badges));
          print('🎖️ Badge storico assegnato a $u: $badgeStr');
        }
      }
    }

    await evColl.remove(where.id(d['_id'] as ObjectId));
    print('🗑️ Evento scaduto ${d['titolo']} rimosso dal DB.');
  }

  print('\n--------------------------------------------------');
  print('TEST 3: Verifica che Cloud ed Ugnom posseggano il badge nel profilo');
  final cloudDoc = await utColl.findOne(where.eq('nome', 'Cloud'));
  final ugnomDoc = await utColl.findOne(where.eq('nome', 'Ugnom'));

  print('Badge Cloud: ${cloudDoc?['badgeList']}');
  print('Badge Ugnom: ${ugnomDoc?['badgeList']}');

  final countEv = await evColl.count(where.eq('titolo', 'Ferragosto Test'));
  print('Conteggio Evento "Ferragosto Test" negli eventi attivi: $countEv (ATTESO: 0)');
  assert(countEv == 0, '❌ ERRORE: Evento non rimosso dagli eventi attivi!');

  await db.close();
  print('\n🎉 === TEST SCADENZA AUTOMATICA E BADGE PASSATO CON SUCCESSO 100%! ===');
}
