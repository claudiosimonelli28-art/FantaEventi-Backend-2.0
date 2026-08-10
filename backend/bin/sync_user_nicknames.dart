import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🔄 === NORMALIZZAZIONE NICKNAME UTENTI IN MONGODB ATLAS ===');
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final utColl = db.collection('Utenti');
  final docs = await utColl.find().toList();

  for (var d in docs) {
    final nick = (d['nickname'] ?? d['nome'] ?? d['username'] ?? '').toString().trim();
    if (nick.isNotEmpty && nick != 'null') {
      await utColl.update(
        where.id(d['_id'] as ObjectId),
        modify.set('nome', nick).set('username', nick).set('nickname', nick),
      );
      print('✅ Normalizzato utente ID ${d['_id']}: "$nick"');
    }
  }

  await db.close();
  print('✨ Normalizzazione completata con successo!');
}
