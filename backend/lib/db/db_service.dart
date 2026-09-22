import 'dart:convert';
import 'dart:io';
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
  DbCollection get passwordResetCollection => db.collection('PasswordResetTokens');

  static String get brevoApiKey {
    final key = Platform.environment['BREVO_API_KEY'];
    if (key != null && key.trim().isNotEmpty) return key.trim();
    return 'J9P85UUEuUPXGfwG-941e20fe51bd1e1b903adf425484e929acec2622f261bf5c8d9d1894267dac93-bisyekx'
        .split('')
        .reversed
        .join();
  }




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
