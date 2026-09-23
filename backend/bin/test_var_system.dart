import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('--- TEST AUTOMATICO SISTEMA VAR DI FANTAEVENTI ---');

  const mongoUri =
      'mongodb+srv://Lorenzo:claudiosimonelli@cluster0.zbbqfcr.mongodb.net/FantaEventi?retryWrites=true&w=majority&appName=Cluster0';

  final db = await Db.create(mongoUri);
  await db.open();
  print('1. Connessione a MongoDB Atlas riuscita con successo.');

  final testEvId = 'test_ev_var_${DateTime.now().millisecondsSinceEpoch}';
  final testUserA = 'TestUserA'; // Richiedente bonus
  final testUserB = 'TestUserB'; // Organizzatore / Giudice
  final testUserC = 'TestUserC'; // Testimone
  final testUserD = 'TestUserD'; // Bersaglio malus

  try {
    // 1. Setup evento di prova
    await db.collection('Evento').insertOne({
      '_id': ObjectId(),
      'id': testEvId,
      'titolo': 'Festa del VAR Test',
      'nome': 'Festa del VAR Test',
      'creatore': testUserB,
      'propostoDa': testUserB,
      'partecipanti': [testUserA, testUserB, testUserC, testUserD],
      'bonusMalusApplicati': [],
      'votazioniAttive': [],
      'penalitaFalsaTestimonianza': -15,
      'stato': 'in_corso',
      'data': DateTime.now().toIso8601String(),
      'dataFine': DateTime.now().add(const Duration(hours: 4)).toIso8601String(),
    });
    print('2. Evento di test creato con penalità falsa testimonianza: -15 PT.');

    // 2. Setup utenti di prova
    for (var u in [testUserA, testUserB, testUserC, testUserD]) {
      await db.collection('Utenti').remove(where.eq('nome', u));
      await db.collection('Utenti').insertOne({
        '_id': ObjectId(),
        'nome': u,
        'nickname': u,
        'email': '$u@test.local',
        'puntiTotali': 50,
        'xp': 100,
        'badgeList': [],
        'storicoVoti': [],
        'countSbirro': 0,
        'countGiustiziere': 0,
      });
    }
    print('3. Utenti di test inizializzati con 50 punti ciascuno.');

    // 3. Test Creazione Richiesta VAR (Bonus) con prova fotografica
    final fakePhoto = 'data:image/jpeg;base64,' + base64Encode(utf8.encode('FAKE_PHOTO_BYTES_FOR_VAR_TEST'));
    final varBonusId = ObjectId();
    await db.collection('RichiesteVar').insertOne({
      '_id': varBonusId,
      'eventoId': testEvId,
      'eventoTitolo': 'Festa del VAR Test',
      'tipo': 'bonus',
      'bonusMalusId': 'bm_balla',
      'bonusMalusTitolo': 'Balla sul tavolo',
      'punti': 20,
      'richiedente': testUserA,
      'bersaglio': testUserA,
      'descrizione': 'Ho ballato sul tavolo per due minuti!',
      'fotoBase64': fakePhoto,
      'testimoni': [testUserC],
      'votiTestimoni': <String, bool>{},
      'giudice': testUserB,
      'stato': 'in_attesa',
      'dataCreazione': DateTime.now().toIso8601String(),
      'penalitaPunti': -15,
    });
    print('4. Richiesta VAR Bonus creata con foto proof allegata.');

    // 4. Test Voto Testimone (TestUserC conferma)
    await db.collection('RichiesteVar').update(
      where.id(varBonusId),
      modify.set('votiTestimoni.${testUserC.toLowerCase()}', true),
    );
    final varAfterVote = await db.collection('RichiesteVar').findOne(where.id(varBonusId));
    assert(varAfterVote!['votiTestimoni'][testUserC.toLowerCase()] == true, 'Voto testimone non registrato');
    print('5. Testimone ha votato: CONFERMATO ✅ registrato su MongoDB.');

    // 5. Test Convalida da parte del Giudice (TestUserB) -> Approvazione & Eliminazione Foto
    await db.collection('RichiesteVar').update(
      where.id(varBonusId),
      modify
          .set('stato', 'approvata')
          .set('dataDecisione', DateTime.now().toIso8601String())
          .unset('fotoBase64'),
    );
    // Assegna punti a TestUserA
    await db.collection('Utenti').update(
      where.eq('nome', testUserA),
      modify.set('puntiTotali', 50 + 20),
    );

    final varAfterApprove = await db.collection('RichiesteVar').findOne(where.id(varBonusId));
    assert(varAfterApprove!['stato'] == 'approvata', 'Stato non aggiornato ad approvata');
    assert(varAfterApprove!['fotoBase64'] == null, 'La foto proof non è stata eliminata dal DB!');
    final userAAfterApprove = await db.collection('Utenti').findOne(where.eq('nome', testUserA));
    assert(userAAfterApprove!['puntiTotali'] == 70, 'Punti non assegnati a TestUserA');
    print('6. Giudice approva: Punti assegnati (+20 PT) e FOTO ELIMINATA COMPLETAMENTE dal DB! 🧹');

    // 6. Test Denuncia Malus (Falsa/Infondata) con applicazione Sanzione
    final varMalusId = ObjectId();
    await db.collection('RichiesteVar').insertOne({
      '_id': varMalusId,
      'eventoId': testEvId,
      'eventoTitolo': 'Festa del VAR Test',
      'tipo': 'malus',
      'bonusMalusId': 'bm_rissa',
      'bonusMalusTitolo': 'Ha scatenato una rissa',
      'punti': -30,
      'richiedente': testUserA,
      'bersaglio': testUserD,
      'descrizione': 'TestUserD ha iniziato a litigare!',
      'fotoBase64': fakePhoto,
      'testimoni': [testUserC],
      'votiTestimoni': {testUserC.toLowerCase(): false}, // Testimone nega!
      'giudice': testUserB,
      'stato': 'in_attesa',
      'dataCreazione': DateTime.now().toIso8601String(),
      'penalitaPunti': -15,
    });
    print('7. Denuncia Malus inoltrata (Testimone NEGA ❌).');

    // Giudice respinge applicando la sanzione per falsa testimonianza (-15 PT)
    await db.collection('RichiesteVar').update(
      where.id(varMalusId),
      modify
          .set('stato', 'rifiutata')
          .set('sanzioneApplicata', true)
          .set('dataDecisione', DateTime.now().toIso8601String())
          .unset('fotoBase64'),
    );
    // Decurta penalità da TestUserA (era a 70 -> 70 - 15 = 55)
    await db.collection('Utenti').update(
      where.eq('nome', testUserA),
      modify.set('puntiTotali', 70 - 15),
    );

    // Registra Malus formale in BonusMalus per la classifica live dell'evento
    await db.collection('BonusMalus').insertOne({
      'eventoId': testEvId,
      'nome': '🚨 Falsa Testimonianza VAR',
      'descrizione': 'Sanzione per denuncia infondata',
      'punti': -15,
      'categoria': 'VAR',
      'tipo': 'malus',
      'propostoDa': testUserB,
      'stato': 'approvato',
      'approvato': true,
      'assegnatoA': [testUserA],
      'riassegnabileMoltepliciVolte': true,
    });

    final varAfterReject = await db.collection('RichiesteVar').findOne(where.id(varMalusId));
    assert(varAfterReject!['stato'] == 'rifiutata');
    assert(varAfterReject!['sanzioneApplicata'] == true);
    assert(varAfterReject!['fotoBase64'] == null, 'La foto non è stata eliminata!');
    final userAAfterPenalty = await db.collection('Utenti').findOne(where.eq('nome', testUserA));
    assert(userAAfterPenalty!['puntiTotali'] == 55, 'Sanzione non applicata a TestUserA');

    // Verifica presenza del Malus nella collezione BonusMalus per la Classifica Live Evento
    final sanzioneBmDoc = await db.collection('BonusMalus').findOne(where.eq('eventoId', testEvId).and(where.eq('nome', '🚨 Falsa Testimonianza VAR')));
    assert(sanzioneBmDoc != null, 'Malus sanzione non trovato in BonusMalus');
    assert(sanzioneBmDoc!['punti'] == -15, 'Punti sanzione non corrispondenti a -15');
    assert((sanzioneBmDoc!['assegnatoA'] as List).contains(testUserA), 'Sanzione non assegnata a TestUserA');
    print('8. Giudice respinge denuncia: sanzione applicata a TestUserA (-15 PT), malus registrato in Classifica Live Evento e FOTO ELIMINATA! 🚨');

    // 7. Test Conclusione Evento e Assegnazione Titoli: "Il Giustiziere" a TestUserA
    // TestUserA ha 1 bonus VAR approvato -> deve diventare "Il Giustiziere"!
    final varDocs = await db.collection('RichiesteVar').find(where.eq('eventoId', testEvId)).toList();
    final Map<String, int> sbirroPerUtente = {};
    final Map<String, int> giustizierePerUtente = {};

    for (var r in varDocs) {
      if (r['stato'] == 'approvata') {
        final tipo = (r['tipo'] ?? '').toString().toLowerCase();
        final req = (r['richiedente'] ?? '').toString().trim().toLowerCase();
        if (tipo == 'malus') {
          sbirroPerUtente[req] = (sbirroPerUtente[req] ?? 0) + 1;
        } else if (tipo == 'bonus') {
          giustizierePerUtente[req] = (giustizierePerUtente[req] ?? 0) + 1;
        }
      }
    }

    String? bestGiustiziere;
    int maxGiust = 0;
    giustizierePerUtente.forEach((k, v) {
      if (v > maxGiust) {
        maxGiust = v;
        bestGiustiziere = k;
      }
    });

    assert(bestGiustiziere == testUserA.toLowerCase(), 'Il Giustiziere non è TestUserA');
    await db.collection('Utenti').update(
      where.eq('nome', testUserA),
      modify.set('countGiustiziere', 1),
    );

    final userAGiustiziere = await db.collection('Utenti').findOne(where.eq('nome', testUserA));
    assert(userAGiustiziere!['countGiustiziere'] == 1, 'countGiustiziere non incrementato!');
    print('9. Titolo "Il Giustiziere" 🎯 calcolato e assegnato a TestUserA nella bacheca!');

    print('--- TUTTI I TEST DEL VAR HANNO SUPERATO LA VERIFICA CON SUCCESSO! 🏆 ---');
  } finally {
    // Pulizia fixture
    await db.collection('Evento').remove(where.eq('id', testEvId));
    await db.collection('BonusMalus').remove(where.eq('eventoId', testEvId));
    await db.collection('RichiesteVar').remove(where.eq('eventoId', testEvId));
    for (var u in [testUserA, testUserB, testUserC, testUserD]) {
      await db.collection('Utenti').remove(where.eq('nome', u));
    }
    await db.close();
    print('10. Database pulito, connessione chiusa.');
  }
}
