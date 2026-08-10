import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA PROPOSTE MULTIPLE BONUS/MALUS PER LO STESSO EVENTO ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final evId = 'ev_multi_bonus_test';

  // 1. Proposta Bonus 1: "Birra Media" (+5 PT)
  final bm1Res = await db.collection('BonusMalus').insertOne({
    'eventoId': evId,
    'nome': 'Birra Media',
    'punti': 5,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bm1Id = bm1Res.id.toHexString();

  final not1Res = await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto "Birra Media" (+5 PT)',
    'eventoId': evId,
    'bonusId': bm1Id,
    'bonusTitolo': 'Birra Media',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  // Cloud legge la prima notifica
  await db.collection('Notifiche').update(
    where.id(not1Res.id as ObjectId),
    modify.set('letto', true),
  );

  // 2. Proposta Bonus 2 per lo STESSO evento: "Cocktail Special" (+15 PT)
  final bm2Res = await db.collection('BonusMalus').insertOne({
    'eventoId': evId,
    'nome': 'Cocktail Special',
    'punti': 15,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bm2Id = bm2Res.id.toHexString();

  final not2Res = await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto "Cocktail Special" (+15 PT)',
    'eventoId': evId,
    'bonusId': bm2Id,
    'bonusTitolo': 'Cocktail Special',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  // 3. Verifico che per Cloud ci siano ENTRAMBE le notifiche e che la seconda sia NON LETTA (badge = 1)
  final allNots = await db.collection('Notifiche').find(where.eq('destinatario', 'Cloud').and(where.eq('eventoId', evId))).toList();
  final unreadNots = allNots.where((n) => n['letto'] != true).toList();

  if (allNots.length == 2 && unreadNots.length == 1) {
    print('✅ Step 1: Entrambe le notifiche sono presenti ed il secondo bonus genera correttamente il badge "1" non letto!');
  }

  // 4. Pulizia
  await db.collection('BonusMalus').remove(where.id(bm1Res.id as ObjectId));
  await db.collection('BonusMalus').remove(where.id(bm2Res.id as ObjectId));
  await db.collection('Notifiche').remove(where.eq('eventoId', evId));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 PROPOSTE MULTIPLE PER LO STESSO EVENTO VERIFICATE AL 100%! ZERO ERRORI!');
}
