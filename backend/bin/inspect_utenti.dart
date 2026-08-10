import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🔎 === ISPEZIONE DOCUMENTI UTENTI IN MONGODB ATLAS ===');
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final utColl = db.collection('Utenti');
  final docs = await utColl.find().toList();
  print('Trovati ${docs.length} utenti nel database:');
  for (var d in docs) {
    print('--------------------------------------------------');
    print('  ID: ${d['_id']}');
    print('  nome: "${d['nome']}"');
    print('  username: "${d['username']}"');
    print('  nickname: "${d['nickname']}"');
    print('  email: "${d['email']}"');
  }

  await db.close();
}
