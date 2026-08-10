import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();
  print('✅ Connected to MongoDB Atlas!');

  final coll = db.collection('Notifiche');
  final docs = await coll.find().toList();

  print('📦 Trovate ${docs.length} notifiche in totale:');
  for (var d in docs) {
    print('-----------------------------------------');
    print('ID: ${d['_id']}');
    print('Mittente: ${d['mittente']}');
    print('Destinatario: ${d['destinatario']}');
    print('Titolo: ${d['titolo']}');
    print('Messaggio: ${d['messaggio']}');
    print('Tipo: ${d['tipo']}');
    print('Stato: ${d['stato']}');
  }

  await db.close();
}
