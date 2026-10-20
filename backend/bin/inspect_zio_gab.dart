import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = Platform.environment["MONGODB_URI"] ?? (File(".env").existsSync() ? File(".env").readAsLinesSync().firstWhere((l) => l.startsWith("MONGODB_URI=")).split("=")[1] : "");
  final db = await Db.create(mongoUri);
  await db.open();

  print('=== RECENT PASSWORD RESET TOKENS ===');
  final tokens = await db.collection('PasswordResetTokens').find().toList();
  for (var t in tokens) {
    print('Token doc: $t');
  }

  print('\n=== UTENTI (NOMI ED EMAIL) ===');
  final utenti = await db.collection('Utenti').find().toList();
  for (var u in utenti) {
    print('User: id=${u['_id']}, nome=${u['nome']}, username=${u['username']}, nickname=${u['nickname']}, email=${u['email']}');
  }

  await db.close();
}
