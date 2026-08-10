import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();
  print('✅ Connected to MongoDB Atlas for Cleanup!');

  final coll = db.collection('Notifiche');
  final docs = await coll.find().toList();

  final Set<String> seenKeys = {};
  int removedCount = 0;

  for (var d in docs) {
    final mitt = (d['mittente'] ?? '').toString().trim().toLowerCase();
    final dest = (d['destinatario'] ?? '').toString().trim().toLowerCase();
    final tit = (d['titolo'] ?? '').toString().trim().toLowerCase();
    final evId = (d['eventoId'] ?? '').toString().trim().toLowerCase();
    final msg = (d['messaggio'] ?? '').toString().trim().toLowerCase();

    final key = '$mitt|$dest|$tit|$evId|$msg';
    if (seenKeys.contains(key)) {
      await coll.remove(where.id(d['_id'] as ObjectId));
      removedCount++;
      print('🗑️ Rimosso duplicato: ID ${d['_id']} ($tit -> $dest)');
    } else {
      seenKeys.add(key);
    }
  }

  print('✨ Pulizia completata! Rimossi $removedCount notifiche duplicate dal database.');
  await db.close();
}
