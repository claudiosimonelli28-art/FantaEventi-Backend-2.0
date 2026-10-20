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
    try {
      final envFile = File('.env');
      if (envFile.existsSync()) {
        final lines = envFile.readAsLinesSync();
        for (var line in lines) {
          if (line.startsWith('BREVO_API_KEY=')) {
            return line.substring('BREVO_API_KEY='.length).trim();
          }
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> connect() async {
    String? mongoUri = Platform.environment['MONGODB_URI'];

    if (mongoUri == null || mongoUri.trim().isEmpty) {
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
    }

    if (mongoUri == null || mongoUri.trim().isEmpty) {
      throw StateError('MONGODB_URI non configurato nell\'ambiente o nel file .env');
    }

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
