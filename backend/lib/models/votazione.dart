import 'package:mongo_dart/mongo_dart.dart';

class Votazione {
  final ObjectId? id;
  final String eventoId;
  final String utenteId;
  final String destinatarioId;
  final String bonusMalusId;
  final int punti;
  final String? note;
  final DateTime timestamp;

  Votazione({
    this.id,
    required this.eventoId,
    required this.utenteId,
    required this.destinatarioId,
    required this.bonusMalusId,
    required this.punti,
    this.note,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory Votazione.fromMap(Map<String, dynamic> map) {
    return Votazione(
      id: map['_id'] is ObjectId
          ? map['_id'] as ObjectId
          : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null),
      eventoId: map['eventoId']?.toString() ?? '',
      utenteId: map['utenteId']?.toString() ?? '',
      destinatarioId: map['destinatarioId']?.toString() ?? '',
      bonusMalusId: map['bonusMalusId']?.toString() ?? '',
      punti: (map['punti'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      timestamp: map['timestamp'] is DateTime
          ? map['timestamp'] as DateTime
          : (map['timestamp'] != null
              ? DateTime.parse(map['timestamp'].toString())
              : DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'eventoId': eventoId,
      'utenteId': utenteId,
      'destinatarioId': destinatarioId,
      'bonusMalusId': bonusMalusId,
      'punti': punti,
      'note': note,
      'timestamp': timestamp.toIso8601String(),
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
      'utenteId': utenteId,
      'destinatarioId': destinatarioId,
      'bonusMalusId': bonusMalusId,
      'punti': punti,
      'note': note,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
