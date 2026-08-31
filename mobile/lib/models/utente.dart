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
  });

  String get nickname => nome;
  String get username => nome;

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

    return Utente(
      id: json['id'] as String? ?? json['_id']?.toString() ?? '',
      nome: nameValue.toString(),
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? 'https://i.pravatar.cc/150?u=${Uri.encodeComponent(nameValue.toString())}',
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
    );
  }
}
