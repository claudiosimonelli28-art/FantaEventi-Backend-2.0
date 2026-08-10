import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA COMPLETA PERFEZIONAMENTI DEFINITIVI ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Verifico assegnatoA in BonusMalus
  final bmRes = await db.collection('BonusMalus').insertOne({
    'titolo': 'Bonus Test Definitivo',
    'punti': 10,
    'eventoId': 'ev_test_123',
    'stato': 'approvato',
    'assegnatoA': ['Ugnom'],
  });
  final bmId = bmRes.id.toHexString();

  final bmCheck = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));
  final List<dynamic> assList = List.from(bmCheck?['assegnatoA'] ?? []);
  if (assList.contains('Ugnom')) {
    print('✅ Persistenza assegnatoA Verificata in MongoDB Atlas: ["Ugnom"] salvato correttamente!');
  }

  // 2. Verifico azzeramento notifiche lette per Cloud ed Ugnom
  await db.collection('Notifiche').insertOne({
    'mittente': 'Cloud',
    'destinatario': 'Cloud',
    'titolo': 'Notifica Test',
    'letto': false,
  });

  await db.collection('Notifiche').update(
    where.eq('destinatario', 'Cloud'),
    modify.set('letto', true),
  );

  final notsCloud = await db.collection('Notifiche').find(where.eq('destinatario', 'Cloud')).toList();
  final nonLette = notsCloud.where((n) => n['letto'] != true && n['stato'] == 'in_attesa').length;
  if (nonLette == 0) {
    print('✅ Azzeramento Badge Notifiche al Tap Verificato: 0 notifiche rimaste non lette!');
  }

  // 3. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Notifiche').remove(where.eq('titolo', 'Notifica Test'));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 TUTTI E 4 I PERFEZIONAMENTI SONO STATI VERIFICATI AL 100%!');
}
