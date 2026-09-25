import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final mongoUri = 'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';
  final db = await Db.create(mongoUri);
  await db.open();

  print('=== 1. EVENTO "Test Var 2.0" ===');
  final evColl = db.collection('Evento');
  final events = await evColl.find().toList();
  for (var ev in events) {
    final title = ev['titolo'] ?? ev['nome'] ?? '';
    if (title.toString().toLowerCase().contains('var')) {
      print('Evento trovato: ID: ${ev['_id']} | Titolo: "$title"');
      print('  Stato: ${ev['stato']}');
      print('  Data inizio: ${ev['data']} | Data fine: ${ev['dataFine']}');
      print('  Proposto da: ${ev['propostoDa'] ?? ev['creatore']}');
      print('  Partecipanti: ${ev['partecipanti']}');
      print('  Invitati: ${ev['invitati']}');
      print('  badgeVincitoreAssegnato: ${ev['badgeVincitoreAssegnato']}');
      print('  titoliAssegnati: ${ev['titoliAssegnati']}');
    }
  }

  print('\n=== 2. RICHIESTE VAR ===');
  final varColl = db.collection('RichiesteVar');
  final varDocs = await varColl.find().toList();
  print('Totale richieste VAR trovate nel DB: ${varDocs.length}');
  for (var v in varDocs) {
    print('-----------------------------------------');
    print('  ID: ${v['_id']}');
    print('  eventoId: ${v['eventoId']}');
    print('  richiedente: ${v['richiedente']}');
    print('  bersaglio: ${v['bersaglio']}');
    print('  tipo: ${v['tipo']}');
    print('  stato: ${v['stato']}');
    print('  motivo: ${v['motivo']}');
    print('  giudice: ${v['giudice']}');
  }

  print('\n=== 3. BONUS / MALUS PER EVENTO VAR ===');
  final bmColl = db.collection('BonusMalus');
  final bms = await bmColl.find(where.eq('eventoId', '6ab41e33b176a83c5fc0448c')).toList();
  for (var bm in bms) {
    print(bm);
  }

  print('\n=== 4. VOTAZIONI (TUTTI I DOCUMENTI) ===');
  final votColl = db.collection('Votazioni');
  final vots = await votColl.find().toList();
  print('Totale votazioni nel DB: ${vots.length}');
  for (var vt in vots) {
    print(vt);
  }

  print('\n=== 5. UTENTI Cloud e Ugnom ===');
  final utColl = db.collection('Utenti');
  final users = await utColl.find().toList();
  for (var u in users) {
    final nick = (u['nickname'] ?? u['nome'] ?? '').toString();
    if (nick.toLowerCase() == 'cloud' || nick.toLowerCase() == 'ugnom') {
      print('-----------------------------------------');
      print('  Utente: $nick (ID: ${u['_id']})');
      print('  countGiudice: ${u['countGiudice']}');
      print('  countAvvocato: ${u['countAvvocato']}');
      print('  countReMalus: ${u['countReMalus']}');
      print('  countFantasma: ${u['countFantasma']}');
      print('  countSbirro: ${u['countSbirro']}');
      print('  countGiustiziere: ${u['countGiustiziere']}');
      print('  badgeVincitore: ${u['badgeVincitore']}');
      print('  badgeList: ${u['badgeList']}');
    }
  }

  await db.close();
}
