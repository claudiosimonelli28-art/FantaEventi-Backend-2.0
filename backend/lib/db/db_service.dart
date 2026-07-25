import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:mongo_dart/mongo_dart.dart';

class DbService {
  static DbService? _instance;
  Db? _db;

  DbService._();

  static DbService get instance {
    _instance ??= DbService._();
    return _instance!;
  }

  Db get db {
    if (_db == null || !_db!.isConnected) {
      throw StateError('Database non connesso. Chiamare connect() prima.');
    }
    return _db!;
  }

  // Nomi ESATTI delle collezioni presenti nel tuo MongoDB Atlas (Singolari/Plurali esatti!)
  DbCollection get utentiCollection => db.collection('Utenti');
  DbCollection get eventiCollection => db.collection('Evento'); // <--- Collezione 'Evento' singolare!
  DbCollection get bonusMalusCollection => db.collection('BonusMalus');
  DbCollection get votazioniCollection => db.collection('Votazioni');

  Future<void> connect() async {
    String mongoUri = 'mongodb+srv://Lorenzo:[REDACTED]@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';

    try {
      final envFile = File('.env');
      if (envFile.existsSync()) {
        final lines = envFile.readAsLinesSync();
        for (var line in lines) {
          if (line.startsWith('MONGODB_URI=')) {
            mongoUri = line.substring('MONGODB_URI='.length).trim();
            break;
          }
        }
      }
    } catch (_) {}

    print('🔌 Connessione al tuo database MongoDB Atlas in corso...');
    _db = await Db.create(mongoUri);
    await _db!.open();
    print('✅ Connessione a MongoDB Atlas effettuata con successo! (Database: FantaEventi)');
  }

  Future<void> close() async {
    await _db?.close();
    print('Connessione a MongoDB chiusa.');
  }
}
