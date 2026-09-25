import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('🔎 === ISPEZIONE DOCUMENTI UTENTI IN MONGODB ATLAS ===');
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  final utColl = db.collection('Utenti');
  final docs = await utColl.find().toList();
  print('Trovati ${docs.length} utenti nel database:');
  for (var d in docs) {
    print('--------------------------------------------------');
    print('  Nickname: "${d['nickname'] ?? d['nome'] ?? d['username']}"');
    print('  Nome Completo: "${d['nome'] ?? ''}"');
    final nameValue = d['nickname'] ?? d['nome'] ?? d['username'] ?? 'Utente';
    String friendCode = (d['codiceAmico'] as String? ?? '').trim();
    bool isInDb = friendCode.isNotEmpty;
    if (friendCode.isEmpty) {
      final String idPart = nameValue.toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      final String codeSeed = idPart.length >= 3 ? idPart.substring(0, 3) : 'FE';
      final int numSeed = (nameValue.toString().hashCode.abs() % 8999) + 1000;
      friendCode = 'FE-$codeSeed$numSeed';
    }
    print('  Codice Amico: "$friendCode"${isInDb ? ' (salvato nel DB)' : ' (generato dall\'app)'}');
    print('  Livello: ${d['livello'] ?? 1}');
    print('  Punti Totali: ${d['puntiTotali'] ?? 0} PT');
    print('  Amici Collegati: ${(d['amici'] as List?)?.length ?? 0}');
    print('  Bacheca Titoli:');
    print('    👑 Campione: ${(d['badgeVincitore'] as List?)?.length ?? 0}');
    print('    🤡 Re dei Malus: ${d['countReMalus'] ?? 0}');
    print('    ⚖️ Avvocato: ${d['countAvvocato'] ?? d['countGiudice'] ?? 0}');
    print('    👻 Fantasma: ${d['countFantasma'] ?? 0}');
    print('    🕵️ Sbirro: ${d['countSbirro'] ?? 0}');
    print('    ⚡ Giustiziere: ${d['countGiustiziere'] ?? 0}');
  }

  await db.close();
}
