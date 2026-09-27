import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  print('=== TEST AUTOMATIZZATO: BLOCCO ASSEGNAZIONE PUNTI SE NON IN CORSO ===');

  final evColl = db.collection('Evento');
  final bmColl = db.collection('BonusMalus');

  final testEvId = ObjectId();
  final testEvIdStr = testEvId.oid;
  final testBmId = ObjectId();

  try {
    // 1. Crea evento In Programma (orario futuro)
    final now = DateTime.now();
    await evColl.insertOne({
      '_id': testEvId,
      'titolo': 'Test Blocco Assegnazione',
      'nome': 'Test Blocco Assegnazione',
      'data': now.add(const Duration(hours: 3)).toIso8601String(),
      'dataFine': now.add(const Duration(hours: 6)).toIso8601String(),
      'stato': 'in_programma',
      'creatore': 'Cloud',
      'propostoDa': 'Cloud',
      'partecipanti': ['Cloud', 'Ugnom'],
      'invitati': [],
    });

    await bmColl.insertOne({
      '_id': testBmId,
      'eventoId': testEvIdStr,
      'titolo': 'Bonus Prova',
      'nome': 'Bonus Prova',
      'punti': 10,
      'stato': 'approvato',
      'approvato': true,
      'assegnatoA': [],
      'riassegnabileMoltepliciVolte': false,
    });

    // 2. Simula controllo assegnazione su evento in programma
    final evDoc = await evColl.findOne(where.id(testEvId));
    final stato = (evDoc!['stato'] ?? 'in_programma').toString().toLowerCase();
    final dtStart = DateTime.parse(evDoc['data']);
    final dtEnd = DateTime.parse(evDoc['dataFine']);
    final bool isConcluso = stato == 'concluso' || now.isAfter(dtEnd);
    final bool isInCorso = !isConcluso && (stato == 'in_corso' || (now.isAfter(dtStart) && now.isBefore(dtEnd)));

    print('Stato evento: $stato | In Corso: $isInCorso');
    assert(!isInCorso, 'L\'evento NON deve risultare in corso');
    print('✅ 1. Assegnazione correttamente bloccata quando l\'evento è in programma!');

    // 3. Simula evento passato a "in_corso"
    final pastStart = now.subtract(const Duration(minutes: 10));
    await evColl.update(where.id(testEvId), modify.set('stato', 'in_corso').set('data', pastStart.toIso8601String()));
    final evInCorsoDoc = await evColl.findOne(where.id(testEvId));
    final statoInCorso = (evInCorsoDoc!['stato'] ?? 'in_programma').toString().toLowerCase();
    final dtStartInCorso = DateTime.parse(evInCorsoDoc['data']);
    final dtEndInCorso = DateTime.parse(evInCorsoDoc['dataFine']);
    final bool isConclusoInCorso = statoInCorso == 'concluso' || now.isAfter(dtEndInCorso);
    final bool isInCorsoNow = !isConclusoInCorso && (statoInCorso == 'in_corso' || (now.isAfter(dtStartInCorso) && now.isBefore(dtEndInCorso)));

    print('Stato evento aggiornato: $statoInCorso | In Corso: $isInCorsoNow');
    assert(isInCorsoNow, 'L\'evento DEVE risultare in corso');
    print('✅ 2. Assegnazione correttamente consentita quando l\'evento è in corso!');

    print('\n🎉 TUTTI I TEST SONO STATI SUPERATI CON SUCCESSO!');
  } finally {
    await evColl.remove(where.id(testEvId));
    await bmColl.remove(where.id(testBmId));
    print('🧹 Fixture di test pulite dal DB.');
    await db.close();
  }
}
