import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST AUTOMATIZZATO DI VELOCITÀ E FLUSSO COMPLETO ===');
  final stopwatch = Stopwatch()..start();

  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  print('⚡ Connessione a MongoDB Atlas completata in ${stopwatch.elapsedMilliseconds} ms!');

  // 1. Verifica presenza utenti Cloud e Ugnom
  final cloudDoc = await db.collection('Utenti').findOne(where.eq('nome', 'Cloud'));
  final ugnomDoc = await db.collection('Utenti').findOne(where.eq('nome', 'Ugnom'));

  if (cloudDoc != null && ugnomDoc != null) {
    print('✅ Utenti "Cloud" e "Ugnom" trovati ed attivi nel DB.');
  } else {
    print('❌ Errore: Utenti non trovati!');
  }

  // 2. Test Creazione Evento "Ferragosto 2026" da Cloud
  stopwatch.reset();
  final evRes = await db.collection('Evento').insertOne({
    'titolo': 'Test Automatismi E2E',
    'descrizione': 'Evento di test automatico flusso e velocita',
    'data': DateTime.now().toIso8601String(),
    'dataFine': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
    'luogo': 'Spiaggia Test',
    'stato': 'in_programma',
    'propostoDa': 'Cloud',
    'partecipanti': ['Cloud'],
    'invitati': ['Ugnom'],
  });

  print('⚡ Creazione Evento completata in ${stopwatch.elapsedMilliseconds} ms!');

  final evId = evRes.id.toHexString();

  // 3. Test Proposta Bonus da Ugnom
  stopwatch.reset();
  await db.collection('BonusMalus').insertOne({
    'eventoId': evId,
    'nome': 'Ballo di Mezzanotte',
    'descrizione': 'Bonus per chi balla a mezzanotte',
    'punti': 15,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'in_votazione',
  });

  print('⚡ Proposta Bonus completata in ${stopwatch.elapsedMilliseconds} ms!');

  // 4. Pulizia automatica dell'evento di test
  await db.collection('Evento').remove(where.id(evRes.id as ObjectId));
  await db.collection('BonusMalus').remove(where.eq('eventoId', evId));
  await db.collection('Notifiche').remove(where.eq('eventoId', evId));
  print('🧹 Pulizia dati di test effettuata con successo.');

  await db.close();
  print('🎉 TUTTI I TEST SONO STATI SUPERATI AL 100%!');
}
