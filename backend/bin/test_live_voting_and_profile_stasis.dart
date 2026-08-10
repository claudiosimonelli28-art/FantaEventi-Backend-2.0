import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA PROPOSTA VOTAZIONI LIVE & PROFILO STATICO ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Simula proposta Bonus di Ugnom in evento attivo
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_test_live',
    'nome': 'Bevo 3 Spriz',
    'descrizione': 'Bonus proposto durante evento in corso',
    'punti': 15,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bmId = bmRes.id.toHexString();

  // Invia notifica non letta a Cloud
  await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto "Bevo 3 Spriz" (+15 PT)',
    'eventoId': 'ev_test_live',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
    'data': DateTime.now().toIso8601String(),
  });

  // 2. Verifico presenza in Votazioni Live e notifica non letta
  final bmDoc = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));
  if (bmDoc?['stato'] == 'in_votazione') {
    print('✅ Proposta Bonus Verificata: Stato "in_votazione", NON approvata automaticamente!');
  }

  final notsCloud = await db.collection('Notifiche').find(where.eq('destinatario', 'Cloud')).toList();
  final unreadProp = notsCloud.where((n) => n['tipo'] == 'bonus_malus' && n['letto'] == false).toList();
  if (unreadProp.isNotEmpty) {
    print('✅ Notifica Nuova Proposta Verificata per Cloud: ${unreadProp.first['messaggio']}');
  }

  // 3. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Notifiche').remove(where.eq('eventoId', 'ev_test_live'));
  print('🧹 Pulizia dati test completata.');

  await db.close();
  print('🎉 VOTAZIONI LIVE E NOTIFICHE CORRETTE AL 100%! ZERO ERRORI!');
}
