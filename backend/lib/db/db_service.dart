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

  DbCollection get utentiCollection => db.collection('Utenti');
  DbCollection get eventiCollection => db.collection('Evento');
  DbCollection get bonusMalusCollection => db.collection('BonusMalus');
  DbCollection get votazioniCollection => db.collection('Votazioni');
  DbCollection get passwordResetCollection => db.collection('PasswordResetTokens');
  DbCollection get richiesteVarCollection => db.collection('RichiesteVar');
  DbCollection get notificheCollection => db.collection('Notifiche');

  static String get brevoApiKey {
    final key = Platform.environment['BREVO_API_KEY'];
    if (key != null && key.trim().isNotEmpty) return key.trim();
    final candidates = [
      File('.env'),
      File('../.env'),
      File('C:\\Users\\Claudio\\Desktop\\Antigravity\\Fanta_eventi2.0\\Ai\\backend\\.env'),
    ];
    for (var envFile in candidates) {
      try {
        if (envFile.existsSync()) {
          final lines = envFile.readAsLinesSync();
          for (var line in lines) {
            if (line.startsWith('BREVO_API_KEY=')) {
              return line.substring('BREVO_API_KEY='.length).trim();
            }
          }
        }
      } catch (_) {}
    }
    return '';
  }

  Future<void> connect() async {
    String? mongoUri = Platform.environment['MONGODB_URI'];

    if (mongoUri == null || mongoUri.trim().isEmpty) {
      final candidates = [
        File('.env'),
        File('../.env'),
        File('C:\\Users\\Claudio\\Desktop\\Antigravity\\Fanta_eventi2.0\\Ai\\backend\\.env'),
      ];
      for (var envFile in candidates) {
        try {
          if (envFile.existsSync()) {
            final lines = envFile.readAsLinesSync();
            for (var line in lines) {
              if (line.startsWith('MONGODB_URI=')) {
                mongoUri = line.substring('MONGODB_URI='.length).trim();
                break;
              }
            }
            if (mongoUri != null && mongoUri.isNotEmpty) break;
          }
        } catch (_) {}
      }
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
