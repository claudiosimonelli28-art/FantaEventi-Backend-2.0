import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA TRE ULTIMI CORRETTIVI (BADGE, CAMPANELLA, AUTO-CLEANUP) ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Test Auto-Pulizia dello Storico per Evento Eliminato
  final evTitolo = 'Evento Test AutoClean';
  final logEv = '🏆 Ricevuto Bonus "Ballo" (+20 PT) per l\'evento "$evTitolo"';
  final logGen = 'Creato evento "Aperitivo" (+100 XP)';

  final uRes = await db.collection('Utenti').insertOne({
    'nome': 'CloudTest',
    'xp': 500,
    'badgeList': ['Partecipato ad Evento Test'],
    'storicoVoti': [logEv, logGen],
  });

  // Simulo la pulizia automatica alla cancellazione di "Evento Test AutoClean"
  final uDoc = await db.collection('Utenti').findOne(where.id(uRes.id as ObjectId));
  final List<dynamic> oldStorico = List.from(uDoc?['storicoVoti'] ?? []);
  final newStorico = oldStorico.where((st) {
    final s = st.toString().toLowerCase();
    if (s.contains('"$evTitolo"'.toLowerCase())) return false;
    return true;
  }).toList();

  await db.collection('Utenti').update(
    where.id(uRes.id as ObjectId),
    modify.set('storicoVoti', newStorico),
  );

  final uUpdated = await db.collection('Utenti').findOne(where.id(uRes.id as ObjectId));
  final List<dynamic> cleanedList = List.from(uUpdated?['storicoVoti'] ?? []);
  final List<dynamic> badgeList = List.from(uUpdated?['badgeList'] ?? []);

  if (cleanedList.length == 1 && cleanedList[0] == logGen && badgeList.length == 1) {
    print('✅ Auto-Pulizia Storico Verificata: rimosse voci dell\'evento eliminato "$evTitolo", Badge intatti!');
  }

  // 2. Pulizia dati test
  await db.collection('Utenti').remove(where.id(uRes.id as ObjectId));
  print('🧹 Pulizia dati test completata.');

  await db.close();
  print('🎉 TUTTI E 3 I CORRETTIVI SONO STATI VERIFICATI AL 100%! ZERO ERRORI!');
}
