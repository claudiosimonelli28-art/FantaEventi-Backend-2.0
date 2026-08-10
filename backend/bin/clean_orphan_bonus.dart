import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🔎 === ISPEZIONE E PULIZIA BONUS ORFANI IN MONGODB ATLAS ===');
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final bmColl = db.collection('BonusMalus');
  final evColl = db.collection('Evento');
  final votColl = db.collection('Votazioni');
  final notColl = db.collection('Notifiche');

  // Trova tutti i BonusMalus
  final allBm = await bmColl.find().toList();
  print('Trovati ${allBm.length} bonus/malus nel database.');

  final allEvs = await evColl.find().toList();
  final Set<String> validEvIds = allEvs.map((e) => e['_id']?.toHexString() ?? e['_id']?.toString() ?? '').cast<String>().toSet();

  int removedCount = 0;
  for (var bm in allBm) {
    final bmId = bm['_id']?.toHexString() ?? bm['_id']?.toString() ?? '';
    final bmNome = bm['nome']?.toString() ?? bm['titolo']?.toString() ?? '';
    final evId = bm['eventoId']?.toString() ?? '';

    final isGeheh = bmNome.toLowerCase().contains('geheh');
    final isOrphan = evId.isNotEmpty && !validEvIds.contains(evId) && !validEvIds.contains('e_$evId');

    if (isGeheh || isOrphan) {
      print('🗑️ Rimuovo bonus orfano: "$bmNome" (ID: $bmId, EventoId: $evId)');
      await bmColl.remove(where.id(bm['_id'] as ObjectId));
      await votColl.remove(where.eq('votazioneId', bmId));
      await notColl.remove(where.eq('eventoId', evId));
      removedCount++;
    }
  }

  await db.close();
  print('✨ Pulizia completata: $removedCount bonus orfani/GEHEH rimossi dal database.');
}
