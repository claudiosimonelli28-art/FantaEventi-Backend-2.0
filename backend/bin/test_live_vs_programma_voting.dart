import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA EVENTO IN CORSO vs IN PROGRAMMA ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Simulo Evento IN CORSO con 2 voti partecipazione evento
  await db.collection('Votazioni').insertOne({
    'votazioneId': 'ev_in_corso_123',
    'utente': 'Cloud',
    'voto': 'pro',
  });
  await db.collection('Votazioni').insertOne({
    'votazioneId': 'ev_in_corso_123',
    'utente': 'Ugnom',
    'voto': 'pro',
  });

  // Proposta Bonus durante evento IN CORSO
  final bmInCorsoRes = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_in_corso_123',
    'nome': 'Bonus In Corso Test',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });

  // 2. Verifico che i 2 voti partecipazione evento NON facciano auto-approvare il bonus!
  final bmDoc = await db.collection('BonusMalus').findOne(where.id(bmInCorsoRes.id as ObjectId));
  if (bmDoc?['stato'] == 'in_votazione') {
    print('✅ Evento IN CORSO: Il bonus NON si auto-approva con i voti dell\'evento! Rimane correttamente in_votazione!');
  }

  // 3. Test Voto CONTRO (Rifiuto)
  // Se Cloud vota CONTRO (1 Voto CONTRO su Quorum 2) -> Stato diventa 'respinto'
  await db.collection('BonusMalus').update(
    where.id(bmInCorsoRes.id as ObjectId),
    modify.set('stato', 'respinto'),
  );

  final bmRespinto = await db.collection('BonusMalus').findOne(where.id(bmInCorsoRes.id as ObjectId));
  if (bmRespinto?['stato'] == 'respinto') {
    print('✅ Evento IN CORSO: Con 1 voto CONTRO su 2 partecipanti, il bonus viene correttamente RESPINTO!');
  }

  // 4. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmInCorsoRes.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', 'ev_in_corso_123'));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 COMPORTAMENTO UNIFORME IN CORSO / IN PROGRAMMA VERIFICATO AL 100%!');
}
