import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final evColl = db.collection('Evento');
  final events = await evColl.find(where.eq('stato', 'concluso')).toList();
  print('=== CONCLUDED EVENTS ===');
  for (var ev in events) {
    print('ID: ${ev['_id']} | Titolo: ${ev['titolo'] ?? ev['nome']} | Partecipanti: ${ev['partecipanti']}');
    print('  titoliAssegnati: ${ev['titoliAssegnati']}');
    print('  titoliVincitori: ${ev['titoliVincitori']}');
  }

  print('\n=== ALL USERS TITLE COUNTERS ===');
  final users = await db.collection('Utenti').find().toList();
  for (var u in users) {
    print('${u['nickname'] ?? u['nome']}: Avvocato=${u['countAvvocato']}, Giudice=${u['countGiudice']}, ReMalus=${u['countReMalus']}, Fantasma=${u['countFantasma']}, Sbirro=${u['countSbirro']}, Giustiziere=${u['countGiustiziere']}');
  }

  await db.close();
}
