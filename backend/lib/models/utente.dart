import 'package:mongo_dart/mongo_dart.dart';

class XpProgression {
  /// XP necessari per completare un livello e passare a quello successivo: (livello + 1) * 1000.
  /// Livello 1 -> 2: 2000 XP
  /// Livello 2 -> 3: 3000 XP
  /// Livello 3 -> 4: 4000 XP
  /// Livello 4 -> 5: 5000 XP
  static int xpNecessariPerLivello(int level) => (level < 1 ? 1 : level + 1) * 1000;

  /// Ricalcola livello, XP nel livello corrente e XP necessari partendo dagli XP cumulativi totali
  static ({int livello, int xp, int xpProssimoLivello, int xpTotali}) calcolaProgressione({
    required int xpTotali,
  }) {
    int level = 1;
    int curXp = xpTotali < 0 ? 0 : xpTotali;
    int needed = xpNecessariPerLivello(level);

    while (curXp >= needed) {
      curXp -= needed;
      level++;
      needed = xpNecessariPerLivello(level);
    }

    return (
      livello: level,
      xp: curXp,
      xpProssimoLivello: needed,
      xpTotali: xpTotali < 0 ? 0 : xpTotali,
    );
  }

  /// Calcola gli XP cumulativi totali partendo da livello e XP parziali nel livello
  static int calcolaXpTotaliDaLivello(int level, int xpNelLivello) {
    int sum = 0;
    for (int l = 1; l < level; l++) {
      sum += xpNecessariPerLivello(l);
    }
    return sum + (xpNelLivello < 0 ? 0 : xpNelLivello);
  }

  /// Aggiunge XP garantendo avanzamento di livello progressivo con conservazione dello scarto (carry-over)
  static ({int livello, int xp, int xpProssimoLivello, int xpTotali}) aggiungiXp({
    required int livelloAttuale,
    required int xpLivelloAttuale,
    required int deltaXp,
    int? xpTotaliAttuali,
  }) {
    if (deltaXp <= 0) {
      final needed = xpNecessariPerLivello(livelloAttuale);
      final tot = xpTotaliAttuali ?? calcolaXpTotaliDaLivello(livelloAttuale, xpLivelloAttuale);
      return (
        livello: livelloAttuale < 1 ? 1 : livelloAttuale,
        xp: xpLivelloAttuale,
        xpProssimoLivello: needed,
        xpTotali: tot,
      );
    }

    int level = livelloAttuale < 1 ? 1 : livelloAttuale;
    int curXp = xpLivelloAttuale + deltaXp;
    int needed = xpNecessariPerLivello(level);

    while (curXp >= needed) {
      curXp -= needed;
      level++;
      needed = xpNecessariPerLivello(level);
    }

    final int newTotali = (xpTotaliAttuali != null)
        ? (xpTotaliAttuali + deltaXp)
        : calcolaXpTotaliDaLivello(level, curXp);

    return (
      livello: level,
      xp: curXp,
      xpProssimoLivello: needed,
      xpTotali: newTotali,
    );
  }
}

class Utente {
  final ObjectId? mongoId;
  final String id;
  final String nome;
  final String cognome;
  final String nickname;
  final String email;
  final String password;
  final String ruolo;
  final String avatarUrl;
  final int livello;
  final int xp;
  final int xpProssimoLivello;
  final int xpTotali;
  final int puntiTotali;
  final List<String> badgeList;
  final List<String> storicoVoti;
  final String codiceAmico;
  final List<String> amici;
  final List<Map<String, dynamic>> richiesteAmicizia;
  final List<Map<String, dynamic>> badgeVincitore;
  final int countGiudice;
  final int countReMalus;
  final int countFantasma;
  final int countSbirro;
  final int countGiustiziere;
  final bool haVistoGuida;
  final List<String> fcmTokens;
  final String dataRegistrazione;
  final List<String> utentiBloccati;
  final bool isBanned;

  Utente({
    this.mongoId,
    required this.id,
    required this.nome,
    this.cognome = '',
    String? nickname,
    required this.email,
    this.password = '',
    this.ruolo = 'partecipante',
    required this.avatarUrl,
    required this.livello,
    required this.xp,
    required this.xpProssimoLivello,
    this.xpTotali = 0,
    required this.puntiTotali,
    required this.badgeList,
    required this.storicoVoti,
    required this.codiceAmico,
    required this.amici,
    required this.richiesteAmicizia,
    required this.badgeVincitore,
    this.countGiudice = 0,
    this.countReMalus = 0,
    this.countFantasma = 0,
    this.countSbirro = 0,
    this.countGiustiziere = 0,
    this.haVistoGuida = false,
    this.fcmTokens = const [],
    this.dataRegistrazione = '',
    this.utentiBloccati = const [],
    this.isBanned = false,
  }) : nickname = (nickname != null && nickname.isNotEmpty) ? nickname : (nome.isNotEmpty ? nome : 'Utente');

  String get username => nickname;
  int get countAvvocato => countGiudice;
  int get countCampione => badgeVincitore.length;

  factory Utente.fromMap(Map<String, dynamic> map) {
    final rawName = (map['nome'] ?? '').toString().trim();
    final rawNick = (map['nickname'] ?? map['username'] ?? '').toString().trim();
    final parsedNome = rawName.isNotEmpty ? rawName : (rawNick.isNotEmpty ? rawNick : 'Utente');
    final parsedNick = rawNick.isNotEmpty ? rawNick : parsedNome;

    int parsedLivello = (map['livello'] as num?)?.toInt() ?? 1;
    int parsedXp = (map['xp'] as num?)?.toInt() ?? ((map['puntiEsperienza'] as num?)?.toInt() ?? 100);
    int parsedXpProssimo = (map['xpProssimoLivello'] as num?)?.toInt() ?? 2000;
    int parsedXpTotali = (map['xpTotali'] as num?)?.toInt() ?? 0;

    if (parsedXpTotali > 0) {
      final prog = XpProgression.calcolaProgressione(xpTotali: parsedXpTotali);
      parsedLivello = prog.livello;
      parsedXp = prog.xp;
      parsedXpProssimo = prog.xpProssimoLivello;
    } else if (parsedXp >= parsedXpProssimo || parsedXpProssimo <= 1000) {
      final prog = XpProgression.calcolaProgressione(xpTotali: parsedXp);
      parsedLivello = prog.livello;
      parsedXp = prog.xp;
      parsedXpProssimo = prog.xpProssimoLivello;
      parsedXpTotali = prog.xpTotali;
    } else {
      parsedXpProssimo = XpProgression.xpNecessariPerLivello(parsedLivello);
      parsedXpTotali = XpProgression.calcolaXpTotaliDaLivello(parsedLivello, parsedXp);
    }

    String friendCode = map['codiceAmico'] as String? ?? '';
    if (friendCode.isEmpty) {
      final String idPart = parsedNick.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      final String codeSeed = idPart.length >= 3 ? idPart.substring(0, 3) : 'FE';
      final int numSeed = (parsedNick.hashCode.abs() % 8999) + 1000;
      friendCode = 'FE-$codeSeed$numSeed';
    }

    final String rawAvatar = (map['avatarUrl'] ?? '').toString().trim();
    final String parsedAvatar = rawAvatar.isNotEmpty
        ? rawAvatar
        : 'https://i.pravatar.cc/150?u=${Uri.encodeComponent(parsedNick)}';

    ObjectId? mId = map['_id'] is ObjectId
        ? map['_id'] as ObjectId
        : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null);

    final String parsedId = mId?.oid ?? (map['id'] as String? ?? map['_id']?.toString() ?? '');
    String parsedCognome = (map['cognome'] ?? '').toString().trim();
    if (parsedCognome.toLowerCase() == 'null') {
      parsedCognome = '';
    }

    String parsedDataReg = (map['dataRegistrazione'] ?? map['dataCreazione'] ?? map['creatoIl'] ?? map['data'] ?? '').toString();
    if (parsedDataReg.isEmpty && parsedId.length >= 8) {
      try {
        final sec = int.tryParse(parsedId.substring(0, 8), radix: 16);
        if (sec != null && sec > 1600000000) {
          final dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000).toLocal();
          parsedDataReg = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        }
      } catch (_) {}
    }
    if (parsedDataReg.isEmpty) {
      parsedDataReg = 'Attivo dal 2026';
    }

    return Utente(
      mongoId: mId,
      id: parsedId,
      nome: parsedNome,
      cognome: parsedCognome,
      nickname: parsedNick,
      email: map['email'] as String? ?? '',
      password: (map['password'] ?? map['passwordHash'] ?? '').toString(),
      ruolo: map['ruolo'] as String? ?? 'partecipante',
      avatarUrl: parsedAvatar,
      livello: parsedLivello,
      xp: parsedXp,
      xpProssimoLivello: parsedXpProssimo,
      xpTotali: parsedXpTotali,
      puntiTotali: (map['puntiTotali'] as num?)?.toInt() ?? 0,
      badgeList: (map['badgeList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['🎉 Partecipante FantaEventi'],
      storicoVoti: (map['storicoVoti'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      codiceAmico: friendCode,
      amici: (map['amici'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      richiesteAmicizia: (map['richiesteAmicizia'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      badgeVincitore: (map['badgeVincitore'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      countGiudice: (map['countGiudice'] as num?)?.toInt() ?? (map['countAvvocato'] as num?)?.toInt() ?? 0,
      countReMalus: (map['countReMalus'] as num?)?.toInt() ?? 0,
      countFantasma: (map['countFantasma'] as num?)?.toInt() ?? 0,
      countSbirro: (map['countSbirro'] as num?)?.toInt() ?? 0,
      countGiustiziere: (map['countGiustiziere'] as num?)?.toInt() ?? 0,
      haVistoGuida: map['haVistoGuida'] == true,
      fcmTokens: (map['fcmTokens'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      dataRegistrazione: parsedDataReg,
      utentiBloccati: (map['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      isBanned: map['isBanned'] == true,
    );
  }

  factory Utente.fromJson(Map<String, dynamic> json) => Utente.fromMap(json);

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nome': nome,
      'cognome': cognome,
      'nickname': nickname,
      'username': nickname,
      'email': email,
      'password': password,
      'ruolo': ruolo,
      'avatarUrl': avatarUrl,
      'livello': livello,
      'xp': xp,
      'xpProssimoLivello': xpProssimoLivello,
      'xpTotali': xpTotali,
      'puntiTotali': puntiTotali,
      'puntiEsperienza': xpTotali,
      'badgeList': badgeList,
      'storicoVoti': storicoVoti,
      'codiceAmico': codiceAmico,
      'amici': amici,
      'richiesteAmicizia': richiesteAmicizia,
      'badgeVincitore': badgeVincitore,
      'countGiudice': countGiudice,
      'countAvvocato': countGiudice,
      'countReMalus': countReMalus,
      'countFantasma': countFantasma,
      'countSbirro': countSbirro,
      'countGiustiziere': countGiustiziere,
      'haVistoGuida': haVistoGuida,
      'fcmTokens': fcmTokens,
      'dataRegistrazione': dataRegistrazione,
      'utentiBloccati': utentiBloccati,
      'isBanned': isBanned,
    };
    if (mongoId != null) {
      map['_id'] = mongoId;
    }
    return map;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'cognome': cognome,
      'nickname': nickname,
      'username': nickname,
      'email': email,
      'ruolo': ruolo,
      'avatarUrl': avatarUrl,
      'livello': livello,
      'xp': xp,
      'xpProssimoLivello': xpProssimoLivello,
      'xpTotali': xpTotali,
      'puntiTotali': puntiTotali,
      'badgeList': badgeList,
      'storicoVoti': storicoVoti,
      'codiceAmico': codiceAmico,
      'amici': amici,
      'richiesteAmicizia': richiesteAmicizia,
      'badgeVincitore': badgeVincitore,
      'utentiBloccati': utentiBloccati,
      'isBanned': isBanned,
      'countGiudice': countGiudice,
      'countAvvocato': countGiudice,
      'countReMalus': countReMalus,
      'countFantasma': countFantasma,
      'countSbirro': countSbirro,
      'countGiustiziere': countGiustiziere,
      'haVistoGuida': haVistoGuida,
      'fcmTokens': fcmTokens,
      'dataRegistrazione': dataRegistrazione,
    };
  }
}
