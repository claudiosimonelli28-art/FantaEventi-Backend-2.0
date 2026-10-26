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
  final String id;
  final String nome;
  final String cognome;
  final String nickname;
  final String email;
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

  Utente({
    required this.id,
    required this.nome,
    this.cognome = '',
    String? nickname,
    required this.email,
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
  }) : nickname = (nickname != null && nickname.isNotEmpty) ? nickname : (nome.isNotEmpty ? nome : 'Utente');

  String get username => nickname;
  int get countAvvocato => countGiudice;
  int get countCampione => badgeVincitore.length;

  factory Utente.fromJson(Map<String, dynamic> json) {
    final rawName = (json['nome'] ?? '').toString().trim();
    final rawNick = (json['nickname'] ?? json['username'] ?? '').toString().trim();
    final parsedNome = rawName.isNotEmpty ? rawName : (rawNick.isNotEmpty ? rawNick : 'Utente');
    final parsedNick = rawNick.isNotEmpty ? rawNick : parsedNome;

    int parsedLivello = (json['livello'] as num?)?.toInt() ?? 1;
    int parsedXp = (json['xp'] as num?)?.toInt() ?? ((json['puntiEsperienza'] as num?)?.toInt() ?? 100);
    int parsedXpProssimo = (json['xpProssimoLivello'] as num?)?.toInt() ?? 2000;
    int parsedXpTotali = (json['xpTotali'] as num?)?.toInt() ?? 0;

    if (parsedXpTotali > 0) {
      final prog = XpProgression.calcolaProgressione(xpTotali: parsedXpTotali);
      parsedLivello = prog.livello;
      parsedXp = prog.xp;
      parsedXpProssimo = prog.xpProssimoLivello;
    } else if (parsedXp >= parsedXpProssimo || parsedXpProssimo <= 1000) {
      // Dati legacy: converti partendo dagli XP cumulativi
      final prog = XpProgression.calcolaProgressione(xpTotali: parsedXp);
      parsedLivello = prog.livello;
      parsedXp = prog.xp;
      parsedXpProssimo = prog.xpProssimoLivello;
      parsedXpTotali = prog.xpTotali;
    } else {
      parsedXpProssimo = XpProgression.xpNecessariPerLivello(parsedLivello);
      parsedXpTotali = XpProgression.calcolaXpTotaliDaLivello(parsedLivello, parsedXp);
    }

    // Genera o recupera Codice Amico (es. FE-1234)
    String friendCode = json['codiceAmico'] as String? ?? '';
    if (friendCode.isEmpty) {
      final String idPart = parsedNick.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      final String codeSeed = idPart.length >= 3 ? idPart.substring(0, 3) : 'FE';
      final int numSeed = (parsedNick.hashCode.abs() % 8999) + 1000;
      friendCode = 'FE-$codeSeed$numSeed';
    }

    final String rawAvatar = (json['avatarUrl'] ?? '').toString().trim();
    final String parsedAvatar = rawAvatar.isNotEmpty
        ? rawAvatar
        : 'https://i.pravatar.cc/150?u=${Uri.encodeComponent(parsedNick)}';

    final String parsedId = json['id'] as String? ?? json['_id']?.toString() ?? '';
    String parsedCognome = (json['cognome'] ?? '').toString().trim();
    if (parsedCognome.toLowerCase() == 'null') {
      parsedCognome = '';
    }

    String parsedDataReg = (json['dataRegistrazione'] ?? json['dataCreazione'] ?? json['creatoIl'] ?? json['data'] ?? '').toString();
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
      id: parsedId,
      nome: parsedNome,
      cognome: parsedCognome,
      nickname: parsedNick,
      email: json['email'] as String? ?? '',
      avatarUrl: parsedAvatar,
      livello: parsedLivello,
      xp: parsedXp,
      xpProssimoLivello: parsedXpProssimo,
      xpTotali: parsedXpTotali,
      puntiTotali: (json['puntiTotali'] as num?)?.toInt() ?? 0,
      badgeList: (json['badgeList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['🎉 Partecipante FantaEventi'],
      storicoVoti: (json['storicoVoti'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      codiceAmico: friendCode,
      amici: (json['amici'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      richiesteAmicizia: (json['richiesteAmicizia'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      badgeVincitore: (json['badgeVincitore'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      countGiudice: (json['countGiudice'] as num?)?.toInt() ?? (json['countAvvocato'] as num?)?.toInt() ?? 0,
      countReMalus: (json['countReMalus'] as num?)?.toInt() ?? 0,
      countFantasma: (json['countFantasma'] as num?)?.toInt() ?? 0,
      countSbirro: (json['countSbirro'] as num?)?.toInt() ?? 0,
      countGiustiziere: (json['countGiustiziere'] as num?)?.toInt() ?? 0,
      haVistoGuida: json['haVistoGuida'] == true,
      fcmTokens: (json['fcmTokens'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      dataRegistrazione: parsedDataReg,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'cognome': cognome,
      'nickname': nickname,
      'email': email,
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

  Utente copyWith({
    String? id,
    String? nome,
    String? cognome,
    String? nickname,
    String? email,
    String? avatarUrl,
    int? livello,
    int? xp,
    int? xpProssimoLivello,
    int? xpTotali,
    int? puntiTotali,
    List<String>? badgeList,
    List<String>? storicoVoti,
    String? codiceAmico,
    List<String>? amici,
    List<Map<String, dynamic>>? richiesteAmicizia,
    List<Map<String, dynamic>>? badgeVincitore,
    int? countGiudice,
    int? countReMalus,
    int? countFantasma,
    int? countSbirro,
    int? countGiustiziere,
    bool? haVistoGuida,
    List<String>? fcmTokens,
    String? dataRegistrazione,
  }) {
    return Utente(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      cognome: cognome ?? this.cognome,
      nickname: nickname ?? this.nickname,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      livello: livello ?? this.livello,
      xp: xp ?? this.xp,
      xpProssimoLivello: xpProssimoLivello ?? this.xpProssimoLivello,
      xpTotali: xpTotali ?? this.xpTotali,
      puntiTotali: puntiTotali ?? this.puntiTotali,
      badgeList: badgeList ?? this.badgeList,
      storicoVoti: storicoVoti ?? this.storicoVoti,
      codiceAmico: codiceAmico ?? this.codiceAmico,
      amici: amici ?? this.amici,
      richiesteAmicizia: richiesteAmicizia ?? this.richiesteAmicizia,
      badgeVincitore: badgeVincitore ?? this.badgeVincitore,
      countGiudice: countGiudice ?? this.countGiudice,
      countReMalus: countReMalus ?? this.countReMalus,
      countFantasma: countFantasma ?? this.countFantasma,
      countSbirro: countSbirro ?? this.countSbirro,
      countGiustiziere: countGiustiziere ?? this.countGiustiziere,
      haVistoGuida: haVistoGuida ?? this.haVistoGuida,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      dataRegistrazione: dataRegistrazione ?? this.dataRegistrazione,
    );
  }
}
