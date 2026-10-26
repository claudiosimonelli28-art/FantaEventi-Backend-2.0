import 'package:mongo_dart/mongo_dart.dart';

class BonusMalus {
  final ObjectId? mongoId;
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
    this.mongoId,
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

  factory BonusMalus.fromMap(Map<String, dynamic> map) {
    ObjectId? mId = map['_id'] is ObjectId
        ? map['_id'] as ObjectId
        : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null);

    final rawId = mId?.oid ?? (map['id'] ?? map['_id'] ?? '');
    final rawEvId = map['eventoId'] ?? map['eventoTitolo'] ?? '';

    final int rawPunti = (map['punti'] as num?)?.toInt() ?? 0;
    // Clamping di sicurezza su punti [-100, 100]
    final int safePunti = rawPunti > 100 ? 100 : (rawPunti < -100 ? -100 : rawPunti);

    return BonusMalus(
      mongoId: mId,
      id: rawId.toString(),
      titolo: map['titolo'] as String? ?? (map['nome'] as String? ?? 'Bonus'),
      descrizione: map['descrizione'] as String? ?? '',
      punti: safePunti,
      categoria: map['categoria'] as String? ?? 'Generale',
      propostoDa: map['propostoDa'] as String? ?? (map['utente'] as String? ?? 'Anonimo'),
      approvato: map['approvato'] as bool? ?? (map['stato'] == 'approvato' || map['stato'] == 'confermato'),
      stato: map['stato'] as String? ?? 'in_votazione',
      eventoId: rawEvId.toString(),
      assegnatoA: (map['assegnatoA'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      riassegnabileMoltepliciVolte: map['riassegnabileMoltepliciVolte'] as bool? ?? false,
    );
  }

  factory BonusMalus.fromJson(Map<String, dynamic> json) => BonusMalus.fromMap(json);

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nome': titolo,
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
    if (mongoId != null) {
      map['_id'] = mongoId;
    }
    return map;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': titolo,
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
}
