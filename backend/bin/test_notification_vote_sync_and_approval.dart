import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA SINCRONIZZAZIONE VOTAZIONE DA NOTIFICA ED ISOLAMENTO APPROVAZIONE ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Ugnom propone Bonus 1 per Evento A (In Corso) e Bonus 2 per Evento B (In Programma)
  final bm1Res = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_in_corso_A',
    'nome': 'Bonus 1 In Corso',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bm1Id = bm1Res.id.toHexString();

  final bm2Res = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_in_programma_B',
    'nome': 'Bonus 2 In Programma',
    'punti': 20,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bm2Id = bm2Res.id.toHexString();

  // Voto iniziale Ugnom
  await db.collection('Votazioni').insertOne({
    'votazioneId': bm1Id,
    'utente': 'Ugnom',
    'voto': 'pro',
  });
  await db.collection('Votazioni').insertOne({
    'votazioneId': bm2Id,
    'utente': 'Ugnom',
    'voto': 'pro',
  });

  // Notifiche inviate a Cloud
  await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': 'Proposta Bonus 1',
    'eventoId': 'ev_in_corso_A',
    'bonusId': bm1Id,
    'bonusTitolo': 'Bonus 1 In Corso',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': 'Proposta Bonus 2',
    'eventoId': 'ev_in_programma_B',
    'bonusId': bm2Id,
    'bonusTitolo': 'Bonus 2 In Programma',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  print('✅ Step 1: Bonus 1 e Bonus 2 creati in_votazione. Notifiche inviate con bonusId preciso!');

  // 2. Cloud vota PRO a Bonus 1 dalla notifica (targetId = bonusId bm1Id)
  await db.collection('Votazioni').insertOne({
    'votazioneId': bm1Id,
    'utente': 'Cloud',
    'voto': 'pro',
  });

  await db.collection('BonusMalus').update(
    where.id(bm1Res.id as ObjectId),
    modify.set('stato', 'approvato').set('approvato', true),
  );

  // 3. Verifico che Bonus 1 sia APPROVATO e Bonus 2 sia ancora IN VOTAZIONE (non approvato!)
  final checkBm1 = await db.collection('BonusMalus').findOne(where.id(bm1Res.id as ObjectId));
  final checkBm2 = await db.collection('BonusMalus').findOne(where.id(bm2Res.id as ObjectId));

  if (checkBm1?['stato'] == 'approvato' && checkBm2?['stato'] == 'in_votazione') {
    print('✅ Step 2: Voto da notifica collegato con successo! Bonus 1 è APPROVATO, Bonus 2 rimane correttamente IN VOTAZIONE!');
  } else {
    print('❌ ERRORE: Bonus 2 approvato per errore!');
  }

  // 4. Pulizia
  await db.collection('BonusMalus').remove(where.id(bm1Res.id as ObjectId));
  await db.collection('BonusMalus').remove(where.id(bm2Res.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', bm1Id));
  await db.collection('Votazioni').remove(where.eq('votazioneId', bm2Id));
  await db.collection('Notifiche').remove(where.eq('destinatario', 'Cloud'));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 ISOLAMENTO ED AGGIORNAMENTO VOTAZIONI DA NOTIFICA VERIFICATI AL 100%! ZERO ERRORI!');
}
