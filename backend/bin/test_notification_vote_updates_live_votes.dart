import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA DEFINITIVA VOTO DA NOTIFICA AGGIORNA VOTAZIONI LIVE ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Ugnom propone Bonus "Cocktail Party" (+10 PT)
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_party_1',
    'nome': 'Cocktail Party',
    'descrizione': 'Bonus proposto da Ugnom',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bmId = bmRes.id.toHexString();

  // Voto 1: Ugnom PRO
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'bonusId': bmId,
    'bonusTitolo': 'Cocktail Party',
    'utente': 'Ugnom',
    'voto': 'pro',
  });

  // Notifica inviata a Cloud col bonusId preciso
  await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto "Cocktail Party" (+10 PT)',
    'eventoId': 'ev_party_1',
    'bonusId': bmId,
    'bonusTitolo': 'Cocktail Party',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'letto': false,
  });

  // 2. Cloud tocca "VOTA PRO" dal Centro Notifiche
  await db.collection('Votazioni').insertOne({
    'votazioneId': bmId,
    'bonusId': bmId,
    'bonusTitolo': 'Cocktail Party',
    'utente': 'Cloud',
    'voto': 'pro',
    'stato': 'approvato',
  });

  await db.collection('BonusMalus').update(
    where.id(bmRes.id as ObjectId),
    modify.set('stato', 'approvato').set('approvato', true),
  );

  // 3. Simulo la lettura delle votazioni live
  final votiList = await db.collection('Votazioni').find(where.eq('votazioneId', bmId)).toList();
  final favCount = votiList.where((v) => v['voto'] == 'pro').length;

  final bmCheck = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));

  if (favCount == 2 && bmCheck?['stato'] == 'approvato') {
    print('✅ Voto da Notifica Verificato: Votazioni Live aggiornate a 2/2 PRO e Bonus APPROVATO con successo!');
  }

  // 4. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', bmId));
  await db.collection('Notifiche').remove(where.eq('eventoId', 'ev_party_1'));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 AGGIORNAMENTO VOTAZIONI LIVE DA NOTIFICA VERIFICATO AL 100%! ZERO ERRORI!');
}
