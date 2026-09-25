import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  print('=== APPLICAZIONE FIX TITOLI E CONTATORI PER "Test Var 2.0" ===');

  // 1. Aggiorna Evento "Test Var 2.0" con titoliVincitori ufficiali
  final evColl = db.collection('Evento');
  final evId = ObjectId.fromHexString('6ab41e33b176a83c5fc0448c');
  final titoliMap = {
    'campione': 'Cloud',
    'campionePunti': 0,
    'reMalus': 'Ugnom',
    'reMalusPunti': 20,
    'avvocato': 'Cloud',
    'avvocatoAzioni': 2,
    'fantasma': 'Ugnom',
    'fantasmaAzioni': 1,
    'sbirro': 'Ugnom',
    'sbirroDenunce': 2,
  };

  final resEv = await evColl.update(
    where.id(evId),
    modify
      .set('badgeVincitoreAssegnato', true)
      .set('titoliAssegnati', true)
      .set('titoliVincitori', titoliMap),
  );
  print('Evento aggiornato: $resEv');

  // 2. Allinea contatori Utente Cloud
  final utColl = db.collection('Utenti');
  final resCloud = await utColl.update(
    where.eq('nickname', 'Cloud'),
    modify
      .set('countAvvocato', 1)
      .set('countGiudice', 1)
      .set('countReMalus', 0)
      .set('countFantasma', 0)
      .set('countSbirro', 0)
      .set('countGiustiziere', 0),
  );
  print('Utente Cloud aggiornato: $resCloud');

  // 3. Allinea contatori Utente Ugnom
  final resUgnom = await utColl.update(
    where.eq('nickname', 'Ugnom'),
    modify
      .set('countAvvocato', 0)
      .set('countGiudice', 0)
      .set('countReMalus', 1)
      .set('countFantasma', 1)
      .set('countSbirro', 1)
      .set('countGiustiziere', 0),
  );
  print('Utente Ugnom aggiornato: $resUgnom');

  print('\n=== VERIFICA POST-UPDATE ===');
  final updatedEv = await evColl.findOne(where.id(evId));
  print('Evento titoliVincitori: ${updatedEv?['titoliVincitori']}');

  final updatedCloud = await utColl.findOne(where.eq('nickname', 'Cloud'));
  print('Cloud: Avvocato=${updatedCloud?['countAvvocato']}, Sbirro=${updatedCloud?['countSbirro']}, Giudice=${updatedCloud?['countGiudice']}');

  final updatedUgnom = await utColl.findOne(where.eq('nickname', 'Ugnom'));
  print('Ugnom: Avvocato=${updatedUgnom?['countAvvocato']}, ReMalus=${updatedUgnom?['countReMalus']}, Fantasma=${updatedUgnom?['countFantasma']}, Sbirro=${updatedUgnom?['countSbirro']}');

  await db.close();
  print('Operazione completata con successo!');
}
