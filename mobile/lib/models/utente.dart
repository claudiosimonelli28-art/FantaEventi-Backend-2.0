class Utente {
  final String id;
  final String nome;
  final String email;
  final String avatarUrl;
  final int livello;
  final int xp;
  final int xpProssimoLivello;
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

  Utente({
    required this.id,
    required this.nome,
    required this.email,
    required this.avatarUrl,
    required this.livello,
    required this.xp,
    required this.xpProssimoLivello,
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
  });

  String get nickname => nome;
  String get username => nome;
  int get countCampione => badgeVincitore.length;


  factory Utente.fromJson(Map<String, dynamic> json) {
    final nameValue = json['nickname'] ?? json['nome'] ?? json['username'] ?? 'Utente';
    final int rawXp = (json['xp'] as num?)?.toInt() ?? ((json['puntiEsperienza'] as num?)?.toInt() ?? 100);
    final int calcLivello = 1 + (rawXp / 1000).floor();
    final int calcNextXp = calcLivello * 1000;

    // Genera o recupera Codice Amico (es. FE-1234)
    String friendCode = json['codiceAmico'] as String? ?? '';
    if (friendCode.isEmpty) {
      final String idPart = nameValue.toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      final String codeSeed = idPart.length >= 3 ? idPart.substring(0, 3) : 'FE';
      final int numSeed = (nameValue.toString().hashCode.abs() % 8999) + 1000;
      friendCode = 'FE-$codeSeed$numSeed';
    }

    final String rawAvatar = (json['avatarUrl'] ?? '').toString().trim();
    final String parsedAvatar = rawAvatar.isNotEmpty
        ? rawAvatar
        : 'https://i.pravatar.cc/150?u=${Uri.encodeComponent(nameValue.toString())}';

    return Utente(
      id: json['id'] as String? ?? json['_id']?.toString() ?? '',
      nome: nameValue.toString(),
      email: json['email'] as String? ?? '',
      avatarUrl: parsedAvatar,
      livello: calcLivello,
      xp: rawXp,
      xpProssimoLivello: calcNextXp,
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
      countGiudice: (json['countGiudice'] as num?)?.toInt() ?? 0,
      countReMalus: (json['countReMalus'] as num?)?.toInt() ?? 0,
      countFantasma: (json['countFantasma'] as num?)?.toInt() ?? 0,
      countSbirro: (json['countSbirro'] as num?)?.toInt() ?? 0,
      countGiustiziere: (json['countGiustiziere'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'email': email,
      'avatarUrl': avatarUrl,
      'livello': livello,
      'xp': xp,
      'xpProssimoLivello': xpProssimoLivello,
      'puntiTotali': puntiTotali,
      'badgeList': badgeList,
      'storicoVoti': storicoVoti,
      'codiceAmico': codiceAmico,
      'amici': amici,
      'richiesteAmicizia': richiesteAmicizia,
      'badgeVincitore': badgeVincitore,
      'countGiudice': countGiudice,
      'countReMalus': countReMalus,
      'countFantasma': countFantasma,
      'countSbirro': countSbirro,
      'countGiustiziere': countGiustiziere,
    };
  }

  Utente copyWith({
    String? id,
    String? nome,
    String? email,
    String? avatarUrl,
    int? livello,
    int? xp,
    int? xpProssimoLivello,
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
  }) {
    return Utente(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      livello: livello ?? this.livello,
      xp: xp ?? this.xp,
      xpProssimoLivello: xpProssimoLivello ?? this.xpProssimoLivello,
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
    );
  }
}

