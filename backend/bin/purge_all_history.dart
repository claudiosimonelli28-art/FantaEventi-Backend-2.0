import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧹 === PULIZIA GLOBALE DATABASE MONGODB ATLAS ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Elimina tutti gli eventi
  final evRes = await db.collection('Evento').remove({});
  print('🗑️ Eliminati tutti gli eventi da "Evento" collection.');

  // 2. Elimina tutte le notifiche
  final notRes = await db.collection('Notifiche').remove({});
  print('🗑️ Eliminate tutte le notifiche da "Notifiche" collection.');

  // 3. Elimina tutti i bonus/malus
  final bmRes = await db.collection('BonusMalus').remove({});
  print('🗑️ Eliminati tutti i bonus/malus da "BonusMalus" collection.');

  // 4. Elimina tutte le votazioni
  final votRes = await db.collection('Votazioni').remove({});
  print('🗑️ Eliminate tutte le votazioni da "Votazioni" collection.');

  // 5. Azzera lo storico attività e badge dagli utenti ma MANTIENE intatti Nomi, Email, AvatarUrl e Profili!
  final utenti = await db.collection('Utenti').find().toList();
  print('🔄 Reset storico per ${utenti.length} utenti...');
  for (var u in utenti) {
    await db.collection('Utenti').update(
      where.id(u['_id'] as ObjectId),
      modify
          .set('xp', 100)
          .set('livello', 1)
          .set('puntiTotali', 0)
          .set('badgeList', ['🎉 Partecipante FantaEventi'])
          .set('storicoVoti', []),
    );
  }

  print('✨ Reset completato! Tutti i profili utente e le foto profilo sono rimasti INTATTI.');
  await db.close();
}
