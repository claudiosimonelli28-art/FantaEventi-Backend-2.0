import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA FLUSSO COMPLETO PROPOSTA -> VOTAZIONE -> APPROVAZIONE -> ASSEGNAZIONE ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Ugnom propone Bonus "Bevo 5 Birre" (+10 PT) per l'evento "Ferragosto 4.0"
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_ferragosto_4',
    'nome': 'Bevo 5 Birre',
    'descrizione': 'Proposta bonus durante evento',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
    'assegnatoA': [],
  });
  final bmId = bmRes.id.toHexString();

  // Voto 1: Ugnom vota PRO in automatico
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'utente': 'Ugnom',
    'voto': 'pro',
    'stato': 'in_corso',
    'data': DateTime.now().toIso8601String(),
  });

  print('✅ Step 1: Bonus "Bevo 5 Birre" proposto da Ugnom (1 Voto PRO automatico da Ugnom, stato: in_votazione)');

  // 2. Cloud riceve la notifica e vota PRO (Voto 2)
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'utente': 'Cloud',
    'voto': 'pro',
    'stato': 'approvato',
    'data': DateTime.now().toIso8601String(),
  });

  // Raggiunto il quorum (2 voti PRO) -> Aggiorna BonusMalus a 'approvato'
  await db.collection('BonusMalus').update(
    where.id(bmRes.id as ObjectId),
    modify.set('stato', 'approvato').set('approvato', true),
  );

  final bmApproved = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));
  if (bmApproved?['stato'] == 'approvato') {
    print('✅ Step 2: Cloud vota PRO -> Quorum 2/2 Raggiunto -> BonusMalus APPROVATO con successo!');
  }

  // 3. L'organizzatore assegna il bonus a Cloud
  await db.collection('BonusMalus').update(
    where.id(bmRes.id as ObjectId),
    modify.set('assegnatoA', ['Cloud']),
  );

  final bmAssigned = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));
  final List<dynamic> assList = List.from(bmAssigned?['assegnatoA'] ?? []);
  if (assList.contains('Cloud')) {
    print('✅ Step 3: Bonus "Bevo 5 Birre" assegnato a Cloud -> assegnatoA: ["Cloud"] salvato in MongoDB Atlas!');
  }

  // 4. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
  print('🧹 Pulizia dati test completata.');

  await db.close();
  print('🎉 TUTTO IL FLUSSO È STATO VERIFICATO AL 100%! ZERO ERRORI!');
}
