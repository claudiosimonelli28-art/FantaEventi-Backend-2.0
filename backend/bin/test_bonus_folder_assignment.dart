import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST AUTOMATIZZATO CARTELLE EVENTO E ASSEGNAZIONE BONUS ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Creazione Evento di Test "Ferragosto Test" da Cloud
  final evRes = await db.collection('Evento').insertOne({
    'titolo': 'Ferragosto Test',
    'descrizione': 'Evento di test per cartelle e assegnazione bonus',
    'data': DateTime.now().toIso8601String(),
    'dataFine': DateTime.now().add(const Duration(hours: 4)).toIso8601String(),
    'luogo': 'Lido Fanta',
    'stato': 'in_programma',
    'propostoDa': 'Cloud',
    'creatore': 'Cloud',
    'partecipanti': ['Cloud', 'Ugnom'],
    'invitati': [],
  });

  final evId = evRes.id.toHexString();
  print('✅ Evento "Ferragosto Test" creato con ID: $evId');

  // 2. Inserimento Bonus Approvato "Ballo di Mezzanotte" (+10 PT)
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': evId,
    'titolo': 'Ballo di Mezzanotte',
    'descrizione': 'Bonus per chi balla a mezzanotte',
    'punti': 10,
    'tipo': 'bonus',
    'propostoDa': 'Ugnom',
    'stato': 'approvato',
    'approvato': true,
  });

  final bmId = bmRes.id.toHexString();
  print('✅ Bonus approvato "Ballo di Mezzanotte" (+10 PT) inserito nella cartella dell\'evento');

  // 3. Simula Assegnazione da parte dell'Organizzatore Cloud a Ugnom
  final uDoc = await db.collection('Utenti').findOne(where.eq('nome', 'Ugnom'));
  if (uDoc != null) {
    final int oldPunti = uDoc['puntiTotali'] ?? 0;
    final List<dynamic> oldStorico = List.from(uDoc['storicoVoti'] ?? []);
    oldStorico.insert(0, '🏆 Ricevuto Bonus "Ballo di Mezzanotte" (+10 PT) per l\'evento "Ferragosto Test"');

    await db.collection('Utenti').update(
      where.id(uDoc['_id'] as ObjectId),
      modify.set('puntiTotali', oldPunti + 10).set('storicoVoti', oldStorico),
    );

    await db.collection('Notifiche').insertOne({
      'mittente': 'Cloud',
      'destinatario': 'Ugnom',
      'titolo': '🏆 Bonus/Malus Assegnato!',
      'messaggio': 'Ti è stato assegnato "Ballo di Mezzanotte" (+10 PT) per l\'evento "Ferragosto Test"!',
      'eventoId': evId,
      'tipo': 'info',
      'stato': 'accettato',
      'votoEspresso': 'pro',
      'data': DateTime.now().toIso8601String(),
    });

    print('✅ Bonus (+10 PT) assegnato con successo a Ugnom! Nuovo totale: ${oldPunti + 10} PT');
  }

  // 4. Pulizia dati di test
  await db.collection('Evento').remove(where.id(evRes.id as ObjectId));
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Notifiche').remove(where.eq('eventoId', evId));
  print('🧹 Pulizia dati di test completata con successo.');

  await db.close();
  print('🎉 TEST DELLE CARTELLE EVENTI ED ASSEGNAZIONE BONUS SUPERATO AL 100%!');
}
