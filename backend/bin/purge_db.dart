import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧹 === INIZIO PURGE TOTALE DATABASE MONGODB ATLAS ===');
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();
  print('✅ Connesso a MongoDB Atlas (FantaEventi)');

  // 1. Collezione Utenti - PRESERVATA AL 100%
  final utentiColl = db.collection('Utenti');
  final nUtenti = await utentiColl.count();
  print('👤 Collezione "Utenti" PRESERVATA: $nUtenti utenti salvaguardati.');

  // 2. Cancellazione Eventi
  final evColl = db.collection('Evento');
  final nEv = await evColl.count();
  await evColl.remove(where.exists('_id'));
  print('🗑️ Rimossi $nEv documenti dalla collezione "Evento".');

  // 3. Cancellazione Notifiche
  final notColl = db.collection('Notifiche');
  final nNot = await notColl.count();
  await notColl.remove(where.exists('_id'));
  print('🗑️ Rimossi $nNot documenti dalla collezione "Notifiche".');

  // 4. Cancellazione BonusMalus
  final bmColl = db.collection('BonusMalus');
  final nBm = await bmColl.count();
  await bmColl.remove(where.exists('_id'));
  print('🗑️ Rimossi $nBm documenti dalla collezione "BonusMalus".');

  // 5. Cancellazione Votazioni
  final votColl = db.collection('Votazioni');
  final nVot = await votColl.count();
  await votColl.remove(where.exists('_id'));
  print('🗑️ Rimossi $nVot documenti dalla collezione "Votazioni".');

  await db.close();
  print('✨ === BONIFICA E PURGE COMPLETATI CON SUCCESSO! ===');
}
