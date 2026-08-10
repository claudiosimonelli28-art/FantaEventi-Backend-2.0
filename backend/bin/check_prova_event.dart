import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🔎 === ISPEZIONE EVENTO "Prova" IN MONGODB ATLAS ===');
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final evColl = db.collection('Evento');
  final docs = await evColl.find(where.eq('titolo', 'Prova')).toList();
  if (docs.isEmpty) {
    final all = await evColl.find().toList();
    print('Nessun evento intitolato "Prova". Eventi presenti nel DB: ${all.length}');
    for (var a in all) {
      print('EV: "${a['titolo']}" - data: ${a['data']} | dataFine: ${a['dataFine']}');
    }
  } else {
    for (var d in docs) {
      print('DOCUMENTO TROVATO:');
      print('  ID: ${d['_id']}');
      print('  Titolo: ${d['titolo']}');
      print('  Data Inizio (raw): ${d['data']} (Tipo: ${d['data'].runtimeType})');
      print('  Data Fine (raw): ${d['dataFine']} (Tipo: ${d['dataFine'].runtimeType})');
      print('  Partecipanti: ${d['partecipanti']}');
    }
  }
  await db.close();
}
