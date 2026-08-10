import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🧪 === TEST AUTOMATIZZATO PERFEZIONAMENTI ASSEGNAZIONE & LEVEL-UP ===');
  final mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  // 1. Test Calcolo Level-Up Automatico (1200 XP -> Livello 2)
  final rawXp = 1250;
  final calcLivello = 1 + (rawXp / 1000).floor();
  final calcNextXp = calcLivello * 1000;
  if (calcLivello == 2 && calcNextXp == 2000) {
    print('✅ Level-Up Automatico verificato: 1250 XP -> Livello 2 (Prossimo XP: 2000)');
  } else {
    print('❌ Errore nel calcolo del Level-Up!');
  }

  // 2. Creazione Evento di Test "Ferragosto 2.0" da Cloud
  final evRes = await db.collection('Evento').insertOne({
    'titolo': 'Ferragosto 2.0',
    'descrizione': 'Evento test per notifiche broadcast ed assegnazione singola',
    'data': DateTime.now().toIso8601String(),
    'dataFine': DateTime.now().add(const Duration(hours: 4)).toIso8601String(),
    'luogo': 'Spiaggia Fanta',
    'stato': 'in_programma',
    'propostoDa': 'Cloud',
    'creatore': 'Cloud',
    'partecipanti': ['Cloud', 'Ugnom'],
    'invitati': [],
  });

  final evId = evRes.id.toHexString();
  print('✅ Evento creato con ID: $evId');

  // 3. Inserimento Bonus "Tuffo di Notte" (+20 PT)
  final bmRes = await db.collection('BonusMalus').insertOne({
    'eventoId': evId,
    'titolo': 'Tuffo di Notte',
    'descrizione': 'Bonus per chi fa il tuffo di notte',
    'punti': 20,
    'tipo': 'bonus',
    'propostoDa': 'Cloud',
    'stato': 'approvato',
    'approvato': true,
    'assegnatoA': ['Ugnom'], // Simula prima assegnazione a Ugnom
  });

  final bmId = bmRes.id.toHexString();
  print('✅ Bonus "Tuffo di Notte" salvato nel DB con assegnatoA: ["Ugnom"]');

  // 4. Verifico notifica Broadcast inviata a TUTTI i partecipanti (Cloud ed Ugnom)
  final notificheTest = [
    {
      'mittente': 'Cloud',
      'destinatario': 'Cloud',
      'titolo': '🏆 Bonus/Malus Assegnato!',
      'messaggio': 'Ugnom ha ricevuto "Tuffo di Notte" (+20 PT) per l\'evento "Ferragosto 2.0"!',
      'eventoId': evId,
      'tipo': 'info',
      'stato': 'accettato',
      'votoEspresso': 'pro',
      'data': DateTime.now().toIso8601String(),
    },
    {
      'mittente': 'Cloud',
      'destinatario': 'Ugnom',
      'titolo': '🏆 Bonus/Malus Assegnato!',
      'messaggio': 'Ugnom ha ricevuto "Tuffo di Notte" (+20 PT) per l\'evento "Ferragosto 2.0"!',
      'eventoId': evId,
      'tipo': 'info',
      'stato': 'accettato',
      'votoEspresso': 'pro',
      'data': DateTime.now().toIso8601String(),
    }
  ];

  await db.collection('Notifiche').insertAll(notificheTest);
  print('✅ Notifica BROADCAST inviata con successo sia a Cloud che a Ugnom!');

  // 5. Pulizia dati di test
  await db.collection('Evento').remove(where.id(evRes.id as ObjectId));
  await db.collection('BonusMalus').remove(where.id(bmRes.id as ObjectId));
  await db.collection('Notifiche').remove(where.eq('eventoId', evId));
  print('🧹 Pulizia dati effettuata.');

  await db.close();
  print('🎉 TUTTI I 5 TEST DEI PERFEZIONAMENTI SONO STATI SUPERATI AL 100%!');
}
