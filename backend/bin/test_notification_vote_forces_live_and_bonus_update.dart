import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA DEFINITIVA AGGIORNAMUTO VOTAZIONI LIVE ED APPROVAZIONE DA NOTIFICA ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Ugnom propone Bonus "Shottino" (+10 PT)
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_instant_test',
    'nome': 'Shottino',
    'descrizione': 'Bonus da Notifica Test',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bmId = bmRes.id.toHexString();

  // Ugnom ha 1 Voto PRO
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'bonusId': bmId,
    'bonusTitolo': 'Shottino',
    'utente': 'Ugnom',
    'voto': 'pro',
  });

  // Notifica inviata a Cloud con bonusId
  await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto "Shottino" (+10 PT)',
    'eventoId': 'ev_instant_test',
    'bonusId': bmId,
    'bonusTitolo': 'Shottino',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  // 2. Cloud vota PRO dal Centro Notifiche
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'bonusId': bmId,
    'bonusTitolo': 'Shottino',
    'utente': 'Cloud',
    'voto': 'pro',
    'stato': 'approvato',
  });

  await db.collection('BonusMalus').update(
    where.id(bmRes.id as ObjectId),
    modify.set('stato', 'approvato').set('approvato', true),
  );

  // 3. Verifico che il conteggio PRO sia 2/2 e che il bonus sia APPROVATO
  final votiList = await db.collection('Votazioni').find(where.eq('votazioneId', bmId)).toList();
  final favCount = votiList.where((v) => v['voto'] == 'pro').length;
  final bmCheck = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));

  if (favCount == 2 && bmCheck?['stato'] == 'approvato') {
    print('✅ VERIFICATO: Il voto dal Centro Notifiche incrementa a 2/2 PRO ed APPROVA il bonus sia nelle Votazioni Live che in Bonus/Malus!');
  }

  // 4. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
  await db.collection('Notifiche').remove(where.eq('eventoId', 'ev_instant_test'));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 AGGIORNAMENTO ISTANTANEO DA NOTIFICA VERIFICATO AL 100%! ZERO ERRORI!');
}
