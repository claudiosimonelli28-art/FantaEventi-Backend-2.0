import 'package:mongo_dart/mongo_dart.dart';

class Evento {
  final ObjectId? id;
  final String titolo;
  final String descrizione;
  final DateTime data;
  final DateTime dataFine;
  final String luogo;
  final String stato;
  final String propostoDa;
  final List<String> partecipanti;
  final List<String> invitati;

  Evento({
    this.id,
    required this.titolo,
    required this.descrizione,
    required this.data,
    DateTime? dataFine,
    this.luogo = '',
    this.stato = 'in_programma',
    required this.propostoDa,
    List<String>? partecipanti,
    List<String>? invitati,
  })  : dataFine = dataFine ?? data.add(const Duration(hours: 4)),
        partecipanti = partecipanti ?? [],
        invitati = invitati ?? [];

  factory Evento.fromMap(Map<String, dynamic> map) {
    final dtInizio = map['data'] is DateTime
        ? map['data'] as DateTime
        : (map['data'] != null ? DateTime.tryParse(map['data'].toString()) ?? DateTime.now() : DateTime.now());

    final dtFine = map['dataFine'] is DateTime
        ? map['dataFine'] as DateTime
        : (map['dataFine'] != null
            ? DateTime.tryParse(map['dataFine'].toString()) ?? dtInizio.add(const Duration(hours: 4))
            : dtInizio.add(const Duration(hours: 4)));

    final now = DateTime.now();
    final isExpired = now.isAfter(dtFine);

    return Evento(
      id: map['_id'] is ObjectId
          ? map['_id'] as ObjectId
          : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null),
      titolo: map['nome'] as String? ?? (map['titolo'] as String? ?? 'Evento senza nome'),
      descrizione: map['descrizione'] as String? ?? '',
      data: dtInizio,
      dataFine: dtFine,
      luogo: map['luogo'] as String? ?? 'Luogo non specificato',
      stato: isExpired ? 'concluso' : (map['stato'] as String? ?? 'in_programma'),
      propostoDa: map['propostoDa']?.toString() ?? (map['creatore']?.toString() ?? ''),
      partecipanti: (map['partecipanti'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      invitati: (map['invitati'] as List<dynamic>?)
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
      'dataFine': dataFine.toIso8601String(),
      'luogo': luogo,
      'stato': stato,
      'propostoDa': propostoDa,
      'creatore': propostoDa,
      'partecipanti': partecipanti,
      'invitati': invitati,
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
      'dataFine': dataFine.toIso8601String(),
      'luogo': luogo,
      'stato': stato,
      'propostoDa': propostoDa,
      'creatore': propostoDa,
      'partecipanti': partecipanti,
      'invitati': invitati,
    };
  }
}
