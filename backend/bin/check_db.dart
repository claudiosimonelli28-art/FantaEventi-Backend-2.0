import 'package:backend/db/db_service.dart';

void main() async {
  print('Connessione a MongoDB Atlas per ispezione collezioni...');
  await DbService.instance.connect();
  final db = DbService.instance.db;

  final collections = await db.getCollectionNames();
  print('📊 Collezioni trovate nel DB FantaEventi: $collections');

  for (var colName in collections) {
    if (colName != null) {
      final count = await db.collection(colName).count();
      print('  - Collezione "$colName": $count documenti');
    }
  }

  await DbService.instance.close();
}
