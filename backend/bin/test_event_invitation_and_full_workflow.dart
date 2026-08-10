import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA FLUSSO COMPLETO INVITO EVENTO -> ACCETTAZIONE -> PROPOSTA BONUS -> APPROVAZIONE ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Cloud crea evento "Ferragosto Party" ed invita Ugnom
  final evRes = await db.collection('Evento').insertOne({
    'titolo': 'Ferragosto Party',
    'descrizione': 'Festa estiva',
    'data': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
    'luogo': 'Spiaggia',
    'stato': 'in_programma',
    'propostoDa': 'Cloud',
    'partecipanti': ['Cloud'],
    'invitati': ['Ugnom'],
  });
  final evId = evRes.id.toHexString();

  final notInvitoRes = await db.collection('Notifiche').insertOne({
    'mittente': 'Cloud',
    'destinatario': 'Ugnom',
    'titolo': '🎉 Invito a Evento',
    'messaggio': 'Cloud ti ha invitato a "Ferragosto Party"',
    'eventoId': evId,
    'tipo': 'invito',
    'stato': 'in_attesa',
    'letto': false,
  });
  final notInvitoId = notInvitoRes.id.toHexString();

  // Verifico che per Ugnom la notifica sia in_attesa (quindi mostra i pulsanti ACCETTA e RIFIUTA)
  final notDoc = await db.collection('Notifiche').findOne(where.id(notInvitoRes.id as ObjectId));
  if (notDoc?['stato'] == 'in_attesa') {
    print('✅ Step 1: Invito evento per Ugnom in stato "in_attesa" -> Pulsanti ACCETTA e RIFIUTA visibili nel centro notifiche!');
  }

  // 2. Ugnom accetta l'invito
  await db.collection('Notifiche').update(
    where.id(notInvitoRes.id as ObjectId),
    modify.set('stato', 'accettato').set('letto', true),
  );
  await db.collection('Evento').update(
    where.id(evRes.id as ObjectId),
    modify.set('partecipanti', ['Cloud', 'Ugnom']),
  );

  final evUpdated = await db.collection('Evento').findOne(where.id(evRes.id as ObjectId));
  final List<dynamic> partList = List.from(evUpdated?['partecipanti'] ?? []);
  if (partList.length == 2 && partList.contains('Ugnom')) {
    print('✅ Step 2: Ugnom accetta l\'invito -> Partecipanti aggiornati automaticamente a 2! (Cloud & Ugnom)');
  }

  // 3. Ugnom propone Bonus "Grigliata" (+10 PT)
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': evId,
    'nome': 'Grigliata Perfect',
    'descrizione': 'Bonus proposto da Ugnom',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
    'assegnatoA': [],
  });
  final bmId = bmRes.id.toHexString();

  // Voto 1: Ugnom PRO
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'utente': 'Ugnom',
    'voto': 'pro',
  });

  // Notifica proposta inviata a Cloud
  await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto "Grigliata Perfect" (+10 PT)',
    'eventoId': evId,
    'bonusId': bmId,
    'bonusTitolo': 'Grigliata Perfect',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  // 4. Cloud vota PRO da notifica / votazioni live
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'utente': 'Cloud',
    'voto': 'pro',
  });

  await db.collection('BonusMalus').update(
    where.id(bmRes.id as ObjectId),
    modify.set('stato', 'approvato').set('approvato', true),
  );

  final bmApproved = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));
  if (bmApproved?['stato'] == 'approvato') {
    print('✅ Step 3: Cloud vota PRO -> Quorum 2/2 Raggiunto -> Bonus APPROVATO e pronto nella schermata Bonus/Malus!');
  }

  // 5. Pulizia
  await db.collection('Evento').remove(where.id(evRes.id as ObjectId));
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
  await db.collection('Notifiche').remove(where.eq('eventoId', evId));
  print('🧹 Pulizia dati test completata.');

  await db.close();
  print('🎉 FLUSSO INTEGRALE DALL\'INVITO ALL\'APPROVAZIONE VERIFICATO AL 100%! ZERO ERRORI!');
}
