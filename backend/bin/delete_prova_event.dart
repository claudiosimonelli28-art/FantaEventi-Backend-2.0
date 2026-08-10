import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🗑️ === ELIMINAZIONE EVENTO "prova" DA MONGODB ATLAS ===');
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final evColl = db.collection('Evento');
  final notColl = db.collection('Notifiche');
  final bmColl = db.collection('BonusMalus');
  final votColl = db.collection('Votazioni');

  final docs = await evColl.find(where.eq('titolo', 'prova')).toList();
  for (var d in docs) {
    final evId = d['_id']?.toHexString() ?? d['_id']?.toString() ?? '';
    await evColl.remove(where.id(d['_id'] as ObjectId));
    await notColl.remove(where.eq('eventoId', evId));
    await bmColl.remove(where.eq('eventoId', evId));
    print('🗑️ Eliminato evento "prova" (ID: $evId)');
  }

  // Pulisci anche per nome
  await evColl.remove(where.eq('nome', 'prova'));

  await db.close();
  print('✨ Eliminazione completata con successo!');
}
