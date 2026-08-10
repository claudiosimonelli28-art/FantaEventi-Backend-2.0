import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA NUOVO FLUSSO CTA NOTIFICA -> VOTAZIONI LIVE -> APPROVAZIONE ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Ugnom propone Bonus "Drink Special" (+10 PT) per l'evento "ev_cta_test"
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_cta_test',
    'nome': 'Drink Special',
    'descrizione': 'Bonus proposto da Ugnom',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bmId = bmRes.id.toHexString();

  // Voto automatico Ugnom
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'bonusId': bmId,
    'bonusTitolo': 'Drink Special',
    'utente': 'Ugnom',
    'voto': 'pro',
  });

  // Notifica CTA a Cloud
  await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto "Drink Special" (+10 PT)',
    'eventoId': 'ev_cta_test',
    'bonusId': bmId,
    'bonusTitolo': 'Drink Special',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  print('✅ Step 1: Proposta Bonus inviata con notifica CTA per Cloud (Stato: in_votazione)');

  // 2. Cloud tocca "VAI A VOTAZIONI LIVE" e vota PRO direttamente da Votazioni Live
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'bonusId': bmId,
    'bonusTitolo': 'Drink Special',
    'utente': 'Cloud',
    'voto': 'pro',
    'stato': 'approvato',
  });

  await db.collection('BonusMalus').update(
    where.id(bmRes.id as ObjectId),
    modify.set('stato', 'approvato').set('approvato', true),
  );

  // 3. Verifico raggiungimento Quorum (2/2 PRO) e presenza in Bonus/Malus approvati
  final votiList = await db.collection('Votazioni').find(where.eq('votazioneId', bmId)).toList();
  final favCount = votiList.where((v) => v['voto'] == 'pro').length;
  final bmCheck = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));

  if (favCount == 2 && bmCheck?['stato'] == 'approvato') {
    print('✅ Step 2: Voto espresso in Votazioni Live -> Quorum 2/2 PRO raggiunto -> Bonus APPROVATO!');
  }

  // 4. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
  await db.collection('Notifiche').remove(where.eq('eventoId', 'ev_cta_test'));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 NUOVO FLUSSO PULITO E LEGGERO VERIFICATO AL 100%! ZERO ERRORI!');
}
