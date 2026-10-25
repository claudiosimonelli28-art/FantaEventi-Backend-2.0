import 'bonus_malus.dart';
import 'votazione.dart';

class Evento {
  final String id;
  final String titolo;
  final String descrizione;
  final DateTime data;
  final DateTime dataFine;
  final String luogo;
  final double? latitudine;
  final double? longitudine;
  final String stato; // 'in_programma', 'in_corso', 'concluso'
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
    required this.bonusMalusApplicati,
    required this.votazioniAttive,
    this.copertinaUrl,
    this.penalitaFalsaTestimonianza = -10,
    this.titoliVincitori,
  })  : dataFine = dataFine ?? data.add(const Duration(hours: 4)),
        invitati = invitati ?? [];

  factory Evento.fromJson(Map<String, dynamic> json) {
    final dtInizio = json['data'] != null
        ? DateTime.tryParse(json['data'] as String) ?? DateTime.now()
        : DateTime.now();

    final dtFine = json['dataFine'] != null
        ? DateTime.tryParse(json['dataFine'] as String) ?? dtInizio.add(const Duration(hours: 4))
        : dtInizio.add(const Duration(hours: 4));

    final rawCreatore = (json['propostoDa'] as String? ?? (json['creatore'] as String? ?? '')).trim();
    final pList = (json['partecipanti'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .toList() ??
        [];
    final bool haAltri = pList.any((p) => p.isNotEmpty && p.toLowerCase() != rawCreatore.toLowerCase());

    final now = DateTime.now();
    String calculatedStato = 'in_programma';
    final rawStato = (json['stato'] as String? ?? 'in_programma').toLowerCase();

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

    return Evento(
      id: json['id'] as String? ?? '',
      titolo: json['titolo'] as String? ?? (json['nome'] as String? ?? ''),
      descrizione: json['descrizione'] as String? ?? '',
      data: dtInizio,
      dataFine: dtFine,
      luogo: json['luogo'] as String? ?? '',
      latitudine: (json['latitudine'] as num?)?.toDouble(),
      longitudine: (json['longitudine'] as num?)?.toDouble(),
      stato: calculatedStato,
      propostoDa: json['propostoDa'] as String? ?? (json['creatore'] as String? ?? ''),
      partecipanti: (json['partecipanti'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      invitati: (json['invitati'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      bonusMalusApplicati: (json['bonusMalusApplicati'] as List<dynamic>?)
              ?.map((e) => BonusMalus.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      votazioniAttive: (json['votazioniAttive'] as List<dynamic>?)
              ?.map((e) => Votazione.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      copertinaUrl: json['copertinaUrl'] as String?,
      penalitaFalsaTestimonianza: (json['penalitaFalsaTestimonianza'] as num?)?.toInt() ?? -10,
      titoliVincitori: json['titoliVincitori'] != null
          ? Map<String, dynamic>.from(json['titoliVincitori'] as Map)
          : null,
    );
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
      if (latitudine != null) 'latitudine': latitudine,
      if (longitudine != null) 'longitudine': longitudine,
      'stato': isAnnullato ? 'annullato' : (isConcluso ? 'concluso' : (isInCorso ? 'in_corso' : stato)),
      'propostoDa': propostoDa,
      'creatore': propostoDa,
      'partecipanti': partecipanti,
      'invitati': invitati,
      'bonusMalusApplicati':
          bonusMalusApplicati.map((b) => b.toJson()).toList(),
      'votazioniAttive': votazioniAttive.map((v) => v.toJson()).toList(),
      'copertinaUrl': copertinaUrl,
      'penalitaFalsaTestimonianza': penalitaFalsaTestimonianza,
      if (titoliVincitori != null) 'titoliVincitori': titoliVincitori,
    };
  }

  Evento copyWith({
    String? id,
    String? titolo,
    String? descrizione,
    DateTime? data,
    DateTime? dataFine,
    String? luogo,
    double? latitudine,
    double? longitudine,
    String? stato,
    String? propostoDa,
    List<String>? partecipanti,
    List<String>? invitati,
    List<BonusMalus>? bonusMalusApplicati,
    List<Votazione>? votazioniAttive,
    String? copertinaUrl,
    int? penalitaFalsaTestimonianza,
    Map<String, dynamic>? titoliVincitori,
  }) {
    return Evento(
      id: id ?? this.id,
      titolo: titolo ?? this.titolo,
      descrizione: descrizione ?? this.descrizione,
      data: data ?? this.data,
      dataFine: dataFine ?? this.dataFine,
      luogo: luogo ?? this.luogo,
      latitudine: latitudine ?? this.latitudine,
      longitudine: longitudine ?? this.longitudine,
      stato: stato ?? this.stato,
      propostoDa: propostoDa ?? this.propostoDa,
      partecipanti: partecipanti ?? this.partecipanti,
      invitati: invitati ?? this.invitati,
      bonusMalusApplicati: bonusMalusApplicati ?? this.bonusMalusApplicati,
      votazioniAttive: votazioniAttive ?? this.votazioniAttive,
      copertinaUrl: copertinaUrl ?? this.copertinaUrl,
      penalitaFalsaTestimonianza: penalitaFalsaTestimonianza ?? this.penalitaFalsaTestimonianza,
      titoliVincitori: titoliVincitori ?? this.titoliVincitori,
    );
  }
}
