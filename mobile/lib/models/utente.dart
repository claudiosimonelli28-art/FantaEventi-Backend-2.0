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
  });

  String get nickname => nome;
  String get username => nome;

  factory Utente.fromJson(Map<String, dynamic> json) {
    final nameValue = json['nickname'] ?? json['nome'] ?? json['username'] ?? 'Utente';
    final int rawXp = (json['xp'] as num?)?.toInt() ?? ((json['puntiEsperienza'] as num?)?.toInt() ?? 100);
    final int calcLivello = 1 + (rawXp / 1000).floor();
    final int calcNextXp = calcLivello * 1000;

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
    );
  }
}
