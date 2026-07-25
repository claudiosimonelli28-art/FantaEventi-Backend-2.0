import 'package:mongo_dart/mongo_dart.dart';

class BonusMalus {
  final ObjectId? id;
  final String eventoId;
  final String nome;
  final String descrizione;
  final int punti;
  final String tipo; // 'bonus' o 'malus'

  BonusMalus({
    this.id,
    required this.eventoId,
    required this.nome,
    required this.descrizione,
    required this.punti,
    required this.tipo,
  });

  factory BonusMalus.fromMap(Map<String, dynamic> map) {
    return BonusMalus(
      id: map['_id'] is ObjectId
          ? map['_id'] as ObjectId
          : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null),
      eventoId: map['eventoId']?.toString() ?? '',
      nome: map['nome'] as String? ?? '',
      descrizione: map['descrizione'] as String? ?? '',
      punti: (map['punti'] as num?)?.toInt() ?? 0,
      tipo: map['tipo'] as String? ?? 'bonus',
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'eventoId': eventoId,
      'nome': nome,
      'descrizione': descrizione,
      'punti': punti,
      'tipo': tipo,
    };
    if (id != null) {
      map['_id'] = id;
    }
    return map;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id?.$oid ?? id?.toHexString(),
      'eventoId': eventoId,
      'nome': nome,
      'descrizione': descrizione,
      'punti': punti,
      'tipo': tipo,
    };
  }
}
