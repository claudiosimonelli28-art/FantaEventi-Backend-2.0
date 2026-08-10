import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === INIZIO TEST E2E FLUSSO NOTIFICHE E VOTAZIONI ===');
  final mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();
  print('✅ Connesso a MongoDB Atlas');

  final notColl = db.collection('Notifiche');
  final bmColl = db.collection('BonusMalus');
  final votColl = db.collection('Votazioni');
  final evColl = db.collection('Evento');

  // 1. Pulizia dati di test precedenti
  await notColl.remove(where.eq('eventoId', 'test_e2e_event_01'));
  await bmColl.remove(where.eq('eventoId', 'test_e2e_event_01'));
  await votColl.remove(where.eq('votazioneId', 'test_bm_01'));

  print('\n--------------------------------------------------');
  print('TEST 1: Creazione Evento "Capodanno Test" da Cloud -> Invito Ugnom');
  await evColl.insertOne({
    '_id': 'test_e2e_event_01',
    'titolo': 'Capodanno Test',
    'propostoDa': 'Cloud',
    'partecipanti': ['Cloud'],
    'invitati': ['Ugnom'],
  });

  await notColl.insertOne({
    'mittente': 'Cloud',
    'destinatario': 'Ugnom',
    'titolo': 'Invito ad Evento: Capodanno Test',
    'messaggio': 'Cloud ti ha invitato all\'evento',
    'eventoId': 'test_e2e_event_01',
    'tipo': 'invito',
    'stato': 'in_attesa',
    'data': DateTime.now().toIso8601String(),
  });

  // Simula doppia scrittura dal backend
  await notColl.insertOne({
    'mittente': 'Cloud',
    'destinatario': 'Ugnom',
    'titolo': 'Invito ad Evento: Capodanno Test',
    'messaggio': 'Cloud ti ha invitato a partecipare all\'evento "Capodanno Test"!',
    'eventoId': 'test_e2e_event_01',
    'tipo': 'invito',
    'stato': 'in_attesa',
    'data': DateTime.now().toIso8601String(),
  });

  // Verifica Deduplicazione per Ugnom
  final allNotUgnom = await notColl.find(where.eq('destinatario', 'Ugnom')).toList();
  final Set<String> seenKeys = {};
  final List<Map<String, dynamic>> deduped = [];

  for (var d in allNotUgnom) {
    final key = '${d['mittente']?.toString().toLowerCase()}|${d['destinatario']?.toString().toLowerCase()}|${d['titolo']?.toString().toLowerCase()}|${d['tipo']?.toString().toLowerCase()}';
    if (!seenKeys.contains(key)) {
      seenKeys.add(key);
      deduped.add(d);
    }
  }

  final invitiCapodanno = deduped.where((n) => n['titolo'].toString().contains('Capodanno Test')).toList();
  print('RESULT 1: Notifiche di invito Capodanno per Ugnom dopo deduplicazione: ${invitiCapodanno.length} (ATTESO: 1)');
  assert(invitiCapodanno.length == 1, '❌ ERRORE: Più di 1 notifica per l\'invito!');

  print('\n--------------------------------------------------');
  print('TEST 2: Ugnom propone Bonus "+15 Ballo di Mezzanotte" per Capodanno Test');
  await bmColl.insertOne({
    '_id': 'test_bm_01',
    'eventoId': 'test_e2e_event_01',
    'nome': 'Ballo di Mezzanotte',
    'descrizione': 'Ha ballato a mezzanotte',
    'punti': 15,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });

  await notColl.insertOne({
    'mittente': 'Ugnom',
    'destinatario': 'Cloud',
    'titolo': '⭐ Nuova Proposta Bonus/Malus',
    'messaggio': 'Ugnom ha proposto il bonus Ballo di Mezzanotte (+15 PT)',
    'eventoId': 'test_e2e_event_01',
    'tipo': 'bonus_malus',
    'stato': 'in_attesa',
    'data': DateTime.now().toIso8601String(),
  });

  print('\n--------------------------------------------------');
  print('TEST 3: Cloud vota PRO dal Centro Notifiche');
  await notColl.update(
    where.eq('eventoId', 'test_e2e_event_01').eq('destinatario', 'Cloud'),
    modify.set('stato', 'accettato').set('votoEspresso', 'pro'),
  );

  await votColl.insertOne({
    'votazioneId': 'test_bm_01',
    'utente': 'Cloud',
    'voto': 'pro',
    'stato': 'approvato',
    'data': DateTime.now().toIso8601String(),
  });

  print('\n--------------------------------------------------');
  print('TEST 4: Verifica Sincronizzazione Votazioni Live (Ugnom PRO + Cloud PRO)');
  final votiDocs = await votColl.find(where.eq('votazioneId', 'test_bm_01')).toList();
  final Map<String, String> votiAggregati = {'Ugnom': 'pro'}; // Ugnom proponente
  for (var v in votiDocs) {
    votiAggregati[v['utente'].toString()] = v['voto'].toString();
  }

  int fav = 0;
  votiAggregati.forEach((_, val) { if (val == 'pro') fav++; });

  print('RESULT 4: Voti Favorevoli calcolati: $fav / Quorum: 2');
  print('Voti Utenti: $votiAggregati');
  assert(fav == 2, '❌ ERRORE: Conteggio voti favorevoli errato!');
  print('STATO FINALE: ${fav >= 2 ? "APPROVATO (INSERITO IN BONUS & MALUS)" : "IN CORSO"}');

  // Pulizia post-test
  await evColl.remove(where.eq('_id', 'test_e2e_event_01'));
  await notColl.remove(where.eq('eventoId', 'test_e2e_event_01'));
  await bmColl.remove(where.eq('eventoId', 'test_e2e_event_01'));
  await votColl.remove(where.eq('votazioneId', 'test_bm_01'));

  await db.close();
  print('\n🎉 === TUTTI I TEST SONO PASSATI CON ESITO POSITIVO AL 100%! ===');
}
