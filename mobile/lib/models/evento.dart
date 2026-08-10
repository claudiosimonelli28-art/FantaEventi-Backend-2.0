import 'bonus_malus.dart';
import 'votazione.dart';

class Evento {
  final String id;
  final String titolo;
  final String descrizione;
  final DateTime data;
  final DateTime dataFine;
  final String luogo;
  final String stato; // 'in_programma', 'in_corso', 'concluso'
  final String propostoDa;
  final List<String> partecipanti;
  final List<String> invitati;
  final List<BonusMalus> bonusMalusApplicati;
  final List<Votazione> votazioniAttive;
  final String? copertinaUrl;

  String get creatore => propostoDa;
  String get categoria => stato;
  bool get isConcluso => DateTime.now().isAfter(dataFine) || stato == 'concluso';

  Evento({
    required this.id,
    required this.titolo,
    required this.descrizione,
    required this.data,
    DateTime? dataFine,
    required this.luogo,
    required this.stato,
    this.propostoDa = '',
    required this.partecipanti,
    List<String>? invitati,
    required this.bonusMalusApplicati,
    required this.votazioniAttive,
    this.copertinaUrl,
  })  : dataFine = dataFine ?? data.add(const Duration(hours: 4)),
        invitati = invitati ?? [];

  factory Evento.fromJson(Map<String, dynamic> json) {
    final dtInizio = json['data'] != null
        ? DateTime.tryParse(json['data'] as String) ?? DateTime.now()
        : DateTime.now();

    final dtFine = json['dataFine'] != null
        ? DateTime.tryParse(json['dataFine'] as String) ?? dtInizio.add(const Duration(hours: 4))
        : dtInizio.add(const Duration(hours: 4));

    final now = DateTime.now();
    String calculatedStato = 'in_programma';
    if (now.isAfter(dtFine)) {
      calculatedStato = 'concluso';
    } else if (now.isAfter(dtInizio) && now.isBefore(dtFine)) {
      calculatedStato = 'in_corso';
    } else {
      calculatedStato = json['stato'] as String? ?? 'in_programma';
    }

    return Evento(
      id: json['id'] as String? ?? '',
      titolo: json['titolo'] as String? ?? (json['nome'] as String? ?? ''),
      descrizione: json['descrizione'] as String? ?? '',
      data: dtInizio,
      dataFine: dtFine,
      luogo: json['luogo'] as String? ?? '',
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
      'stato': isConcluso ? 'concluso' : stato,
      'propostoDa': propostoDa,
      'creatore': propostoDa,
      'partecipanti': partecipanti,
      'invitati': invitati,
      'bonusMalusApplicati':
          bonusMalusApplicati.map((b) => b.toJson()).toList(),
      'votazioniAttive': votazioniAttive.map((v) => v.toJson()).toList(),
      'copertinaUrl': copertinaUrl,
    };
  }

  Evento copyWith({
    String? id,
    String? titolo,
    String? descrizione,
    DateTime? data,
    DateTime? dataFine,
    String? luogo,
    String? stato,
    String? propostoDa,
    List<String>? partecipanti,
    List<String>? invitati,
    List<BonusMalus>? bonusMalusApplicati,
    List<Votazione>? votazioniAttive,
    String? copertinaUrl,
  }) {
    return Evento(
      id: id ?? this.id,
      titolo: titolo ?? this.titolo,
      descrizione: descrizione ?? this.descrizione,
      data: data ?? this.data,
      dataFine: dataFine ?? this.dataFine,
      luogo: luogo ?? this.luogo,
      stato: stato ?? this.stato,
      propostoDa: propostoDa ?? this.propostoDa,
      partecipanti: partecipanti ?? this.partecipanti,
      invitati: invitati ?? this.invitati,
      bonusMalusApplicati: bonusMalusApplicati ?? this.bonusMalusApplicati,
      votazioniAttive: votazioniAttive ?? this.votazioniAttive,
      copertinaUrl: copertinaUrl ?? this.copertinaUrl,
    );
  }
}
