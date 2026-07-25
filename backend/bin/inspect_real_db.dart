import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';

  print('🔍 --- ISPEZIONE EMPIRICA REALE MONGO DB ATLAS ---');
  try {
    final db = await Db.create(mongoUri);
    await db.open();
    print('✅ Connessione riuscita a MongoDB Atlas!');

    final collections = await db.getCollectionNames();
    print('\n📊 COLLEZIONI PRESENTI NEL DATABASE "FantaEventi": $collections');

    for (var colName in collections) {
      if (colName != null && !colName.startsWith('system.')) {
        final count = await db.collection(colName).count();
        print('\n📁 Collezione: "$colName" (Totale Documenti: $count)');
        final docs = await db.collection(colName).find().toList();
        if (docs.isEmpty) {
          print('   ⚠️ Nessun documento trovato in "$colName"!');
        } else {
          for (var i = 0; i < docs.length; i++) {
            print('   [$i] Documento: ${docs[i]}');
          }
        }
      }
    }

    await db.close();
  } catch (e, stack) {
    print('❌ ERRORE CONNESSIONE DB: $e');
    print(stack);
  }
}
