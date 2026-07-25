import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';

  print('🔍 --- ESTRIAMO EVENTI REALI DA MONGO DB ATLAS ---');
  try {
    final db = await Db.create(mongoUri);
    await db.open();

    final docsEventi = await db.collection('eventi').find().toList();
    print('📁 Collezione "eventi" (minuscola): ${docsEventi.length} documenti trovati!');
    for (var i = 0; i < docsEventi.length; i++) {
      print('   [$i] Evento: ${docsEventi[i]}');
    }

    final docsEventiCap = await db.collection('Eventi').find().toList();
    print('📁 Collezione "Eventi" (Maiuscola): ${docsEventiCap.length} documenti trovati!');
    for (var i = 0; i < docsEventiCap.length; i++) {
      print('   [$i] Evento: ${docsEventiCap[i]}');
    }

    await db.close();
  } catch (e, stack) {
    print('❌ ERRORE: $e');
  }
}
