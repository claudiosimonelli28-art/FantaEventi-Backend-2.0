import 'package:mongo_dart/mongo_dart.dart';
import 'bonus_malus.dart';
import 'votazione.dart';

class Evento {
  final ObjectId? mongoId;
  final String id;
  final String titolo;
  final String descrizione;
  final DateTime data;
  final DateTime dataFine;
  final String luogo;
  final double? latitudine;
  final double? longitudine;
  final String stato; // 'in_programma', 'in_corso', 'concluso', 'annullato'
  final String propostoDa;
  final List<String> partecipanti;
  final List<String> invitati;
  final List<BonusMalus> bonusMalusApplicati;
  final List<Votazione> votazioniAttive;
  final String? copertinaUrl;
  final int penalitaFalsaTestimonianza;
  final Map<String, dynamic>? titoliVincitori;

  String get creatore => propostoDa;
  String get categoria => stato;
  bool get haAltriPartecipanti => partecipanti.any((p) => p.trim().isNotEmpty && p.trim().toLowerCase() != creatore.trim().toLowerCase());
  bool get isAnnullato => stato == 'annullato';
  bool get isConcluso => !isAnnullato && (DateTime.now().isAfter(dataFine) || stato == 'concluso');
  bool get isInCorso {
    final now = DateTime.now();
    return !isConcluso && !isAnnullato && (stato == 'in_corso' || (now.isAfter(data) && now.isBefore(dataFine) && haAltriPartecipanti));
  }
  bool get isInProgramma => !isConcluso && !isAnnullato && !isInCorso;

  Evento({
    this.mongoId,
    required this.id,
    required this.titolo,
    required this.descrizione,
    required this.data,
    DateTime? dataFine,
    required this.luogo,
    this.latitudine,
    this.longitudine,
    required this.stato,
    this.propostoDa = '',
    required this.partecipanti,
    List<String>? invitati,
    this.bonusMalusApplicati = const [],
    this.votazioniAttive = const [],
    this.copertinaUrl,
    this.penalitaFalsaTestimonianza = -10,
    this.titoliVincitori,
  })  : dataFine = dataFine ?? data.add(const Duration(hours: 4)),
        invitati = invitati ?? [];

  factory Evento.fromMap(Map<String, dynamic> map) {
    final dtInizio = map['data'] != null
        ? (map['data'] is DateTime ? map['data'] as DateTime : DateTime.tryParse(map['data'].toString()) ?? DateTime.now())
        : DateTime.now();

    final dtFine = map['dataFine'] != null
        ? (map['dataFine'] is DateTime ? map['dataFine'] as DateTime : DateTime.tryParse(map['dataFine'].toString()) ?? dtInizio.add(const Duration(hours: 4)))
        : dtInizio.add(const Duration(hours: 4));

    final rawCreatore = (map['propostoDa'] as String? ?? (map['creatore'] as String? ?? '')).trim();
    final pList = (map['partecipanti'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .toList() ??
        [];
    final bool haAltri = pList.any((p) => p.isNotEmpty && p.toLowerCase() != rawCreatore.toLowerCase());

    final now = DateTime.now();
    String calculatedStato = 'in_programma';
    final rawStato = (map['stato'] as String? ?? 'in_programma').toLowerCase();

    if (rawStato == 'annullato') {
      calculatedStato = 'annullato';
    } else if (now.isAfter(dtFine)) {
      calculatedStato = 'concluso';
    } else if (now.isAfter(dtInizio)) {
      if (!haAltri) {
        calculatedStato = 'annullato'; // Orario scattato ma nessun partecipante confermato oltre l'organizzatore!
      } else {
        calculatedStato = 'in_corso';
      }
    } else {
      calculatedStato = rawStato;
    }

    ObjectId? mId = map['_id'] is ObjectId
        ? map['_id'] as ObjectId
        : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null);

    final parsedId = mId?.oid ?? (map['id'] as String? ?? map['_id']?.toString() ?? '');

    return Evento(
      mongoId: mId,
      id: parsedId,
      titolo: map['titolo'] as String? ?? (map['nome'] as String? ?? ''),
      descrizione: map['descrizione'] as String? ?? '',
      data: dtInizio,
      dataFine: dtFine,
      luogo: map['luogo'] as String? ?? '',
      latitudine: (map['latitudine'] as num?)?.toDouble(),
      longitudine: (map['longitudine'] as num?)?.toDouble(),
      stato: calculatedStato,
      propostoDa: rawCreatore,
      partecipanti: pList,
      invitati: (map['invitati'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .toList() ??
          [],
      bonusMalusApplicati: (map['bonusMalusApplicati'] as List<dynamic>?)
              ?.map((e) => BonusMalus.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      votazioniAttive: (map['votazioniAttive'] as List<dynamic>?)
              ?.map((e) => Votazione.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      copertinaUrl: map['copertinaUrl'] as String?,
      penalitaFalsaTestimonianza: (map['penalitaFalsaTestimonianza'] as num?)?.toInt() ?? -10,
      titoliVincitori: map['titoliVincitori'] != null
          ? Map<String, dynamic>.from(map['titoliVincitori'] as Map)
          : null,
    );
  }

  factory Evento.fromJson(Map<String, dynamic> json) => Evento.fromMap(json);

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nome': titolo,
      'titolo': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'dataFine': dataFine.toIso8601String(),
      'luogo': luogo,
      'latitudine': latitudine,
      'longitudine': longitudine,
      'stato': stato,
      'propostoDa': propostoDa,
      'creatore': propostoDa,
      'partecipanti': partecipanti,
      'invitati': invitati,
      'bonusMalusApplicati': bonusMalusApplicati.map((b) => b.toMap()).toList(),
      'votazioniAttive': votazioniAttive.map((v) => v.toMap()).toList(),
      'copertinaUrl': copertinaUrl,
      'penalitaFalsaTestimonianza': penalitaFalsaTestimonianza,
      'titoliVincitori': titoliVincitori,
    };
    if (mongoId != null) {
      map['_id'] = mongoId;
    }
    return map;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titolo': titolo,
      'nome': titolo,
      'descrizione': descrizione,
      'data': data.toIso8601String(),
      'dataFine': dataFine.toIso8601String(),
      'luogo': luogo,
      'latitudine': latitudine,
      'longitudine': longitudine,
      'stato': stato,
      'propostoDa': propostoDa,
      'creatore': propostoDa,
      'partecipanti': partecipanti,
      'invitati': invitati,
      'bonusMalusApplicati': bonusMalusApplicati.map((b) => b.toJson()).toList(),
      'votazioniAttive': votazioniAttive.map((v) => v.toJson()).toList(),
      'copertinaUrl': copertinaUrl,
      'penalitaFalsaTestimonianza': penalitaFalsaTestimonianza,
      'titoliVincitori': titoliVincitori,
    };
  }
}
