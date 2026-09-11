class BonusMalus {
  final String id;
  final String titolo;
  final String descrizione;
  final int punti;
  final String categoria;
  final String propostoDa;
  final bool approvato;
  final String stato;
  final String eventoId;
  final List<String> assegnatoA;
  final bool riassegnabileMoltepliciVolte;

  BonusMalus({
    required this.id,
    required this.titolo,
    required this.descrizione,
    required this.punti,
    required this.categoria,
    required this.propostoDa,
    this.approvato = false,
    this.stato = 'in_votazione',
    this.eventoId = '',
    this.assegnatoA = const [],
    this.riassegnabileMoltepliciVolte = false,
  });

  bool get isBonus => punti >= 0;

  factory BonusMalus.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['_id'] ?? '';
    final rawEvId = json['eventoId'] ?? '';

    return BonusMalus(
      id: rawId.toString(),
      titolo: json['titolo'] as String? ?? json['nome'] as String? ?? 'Bonus',
      descrizione: json['descrizione'] as String? ?? '',
      punti: (json['punti'] as num?)?.toInt() ?? 0,
      categoria: json['categoria'] as String? ?? 'Generale',
      propostoDa: json['propostoDa'] as String? ?? json['utente'] as String? ?? 'Anonimo',
      approvato: json['approvato'] as bool? ?? (json['stato'] == 'approvato'),
      stato: json['stato'] as String? ?? 'in_votazione',
      eventoId: rawEvId.toString(),
      assegnatoA: (json['assegnatoA'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      riassegnabileMoltepliciVolte: json['riassegnabileMoltepliciVolte'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titolo': titolo,
      'descrizione': descrizione,
      'punti': punti,
      'categoria': categoria,
      'propostoDa': propostoDa,
      'approvato': approvato,
      'stato': stato,
      'eventoId': eventoId,
      'assegnatoA': assegnatoA,
      'riassegnabileMoltepliciVolte': riassegnabileMoltepliciVolte,
    };
  }

  BonusMalus copyWith({
    String? id,
    String? titolo,
    String? descrizione,
    int? punti,
    String? categoria,
    String? propostoDa,
    bool? approvato,
    String? stato,
    String? eventoId,
    List<String>? assegnatoA,
    bool? riassegnabileMoltepliciVolte,
  }) {
    return BonusMalus(
      id: id ?? this.id,
      titolo: titolo ?? this.titolo,
      descrizione: descrizione ?? this.descrizione,
      punti: punti ?? this.punti,
      categoria: categoria ?? this.categoria,
      propostoDa: propostoDa ?? this.propostoDa,
      approvato: approvato ?? this.approvato,
      stato: stato ?? this.stato,
      eventoId: eventoId ?? this.eventoId,
      assegnatoA: assegnatoA ?? this.assegnatoA,
      riassegnabileMoltepliciVolte: riassegnabileMoltepliciVolte ?? this.riassegnabileMoltepliciVolte,
    );
  }
}
