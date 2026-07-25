import 'package:mongo_dart/mongo_dart.dart';

class Evento {
  final ObjectId? id;
  final String titolo;
  final String descrizione;
  final DateTime data;
  final String luogo;
  final String stato;
  final String propostoDa;
  final List<String> partecipanti;

  Evento({
    this.id,
    required this.titolo,
    required this.descrizione,
    required this.data,
    this.luogo = '',
    this.stato = 'in_corso',
    required this.propostoDa,
    List<String>? partecipanti,
  }) : partecipanti = partecipanti ?? [];

  factory Evento.fromMap(Map<String, dynamic> map) {
    return Evento(
      id: map['_id'] is ObjectId
          ? map['_id'] as ObjectId
          : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null),
      titolo: map['nome'] as String? ?? (map['titolo'] as String? ?? 'Evento senza nome'),
      descrizione: map['descrizione'] as String? ?? '',
      data: map['data'] is DateTime
          ? map['data'] as DateTime
          : (map['data'] != null ? DateTime.parse(map['data'].toString()) : DateTime.now()),
      luogo: map['luogo'] as String? ?? 'Luogo non specificato',
      stato: map['stato'] as String? ?? 'in_corso',
      propostoDa: map['propostoDa']?.toString() ?? '',
      partecipanti: (map['partecipanti'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nome': titolo,
      'titolo': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'luogo': luogo,
      'stato': stato,
      'propostoDa': propostoDa,
      'partecipanti': partecipanti,
    };
    if (id != null) {
      map['_id'] = id;
    }
    return map;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id?.oid ?? id?.toHexString(),
      'titolo': titolo,
      'nome': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'luogo': luogo,
      'stato': stato,
      'propostoDa': propostoDa,
      'partecipanti': partecipanti,
    };
  }
}
