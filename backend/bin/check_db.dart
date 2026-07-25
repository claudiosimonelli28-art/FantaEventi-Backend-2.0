import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb://Lorenzo:[REDACTED]@cluster0-shard-00-00.zbbqfcr.mongodb.net:27017,cluster0-shard-00-01.zbbqfcr.mongodb.net:27017,cluster0-shard-00-02.zbbqfcr.mongodb.net:27017/FantaEventi?ssl=true&replicaSet=atlas-shard-0&authSource=admin&retryWrites=true&w=majority';
  
  print('Connessione a MongoDB Atlas per ispezione collezioni...');
  final db = await Db.create(mongoUri);
  await db.open();
  
  final collections = await db.getCollectionNames();
  print('📊 Collezioni trovate nel DB FantaEventi: $collections');

  for (var colName in collections) {
    if (colName != null) {
      final count = await db.collection(colName).count();
      print('  - Collezione "$colName": $count documenti');
      final docs = await db.collection(colName).find().take(5).toList();
      for (var d in docs) {
        print('    Doc: $d');
      }
    }
  }

  await db.close();
}
