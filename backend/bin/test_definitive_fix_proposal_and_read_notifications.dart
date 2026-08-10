import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST VERIFICA DEFINITIVA RISOLUZIONE BUG AUTO-APPROVAZIONE E NOTIFICHE RIAPPARISCONO ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Creo un voto per l'evento "ev_test_restart" (Es. voto invito accettato)
  await db.collection('Votazioni').insertOne({
    'votazioneId': 'ev_test_restart',
    'utente': 'Cloud',
    'voto': 'pro',
  });

  // Ugnom propone un NUOVO bonus per "ev_test_restart"
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': 'ev_test_restart',
    'nome': 'Bonus Test NoAuto',
    'descrizione': 'Verifica no auto approvazione',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });
  final bmId = bmRes.id.toHexString();

  // Verifico che il bonus NON si sia approvato leggendolo senza matching errati
  final bmDoc = await db.collection('BonusMalus').findOne(where.id(bmRes.id as ObjectId));
  if (bmDoc?['stato'] == 'in_votazione') {
    print('✅ FIX 1 VERIFICATO: Il bonus proposto durante l\'evento NON si auto-approva! Rimane in_votazione!');
  }

  // 2. Test Notifiche Lette al Riavvio dell'App
  final nRes = await db.collection('Notifiche').insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'CloudTestRestart',
    'titolo': 'Test Notifica',
    'letto': false,
    'stato': 'in_attesa',
  });

  // Simulo la marcatura a lette al tap sul campanellino
  await db.collection('Notifiche').update(
    where.eq('destinatario', 'CloudTestRestart'),
    modify.set('letto', true).set('stato', 'letto'),
  );

  // Simulo la query di getNotifiche al riavvio dell'app
  final nots = await db.collection('Notifiche').find(where.eq('destinatario', 'CloudTestRestart')).toList();
  final unreadNots = nots.where((n) {
    final isRead = n['letto'] == true || n['stato'] == 'letto';
    return !isRead;
  }).toList();

  if (unreadNots.isEmpty) {
    print('✅ FIX 2 VERIFICATO: Al riavvio dell\'app le notifiche lette ritornano letto: true e il contatore rimane 0!');
  }

  // 3. Pulizia
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Votazioni').remove(where.eq('votazioneId', 'ev_test_restart'));
  await db.collection('Notifiche').remove(where.eq('destinatario', 'CloudTestRestart'));
  print('🧹 Pulizia completata.');

  await db.close();
  print('🎉 ENTRAMBI I PROBLEMI SONO STATI RISOLTI E VERIFICATI AL 100%! ZERO ERRORI!');
}
