import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();
  final utColl = db.collection('Utenti');
  
  final docs = await utColl.find().toList();
  for (var u in docs) {
    final List<dynamic> badges = List.from(u['badgeList'] ?? []);
    badges.removeWhere((b) => b.toString().contains('Ferragosto Test'));
    await utColl.update(where.eq('_id', u['_id']), modify.set('badgeList', badges));
  }
  await db.close();
  print('🧹 Cleaned test badges.');
}
