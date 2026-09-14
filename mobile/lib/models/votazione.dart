import 'bonus_malus.dart';

class Votazione {
  final String id;
  final String titolo;
  final String descrizione;
  final BonusMalus? bonusMalus;
  final int votiFavorevoli;
  final int votiContrari;
  final int quorum;
  final String stato; // 'in_corso', 'approvato', 'respinto'
  final DateTime scadenza;
  final Map<String, String> votiUtenti; // userId -> 'pro' | 'contro'
  final bool paritaDecisaDaOrganizzatore;
  final String? nomeOrganizzatore;

  Votazione({
    required this.id,
    required this.titolo,
    required this.descrizione,
    this.bonusMalus,
    required this.votiFavorevoli,
    required this.votiContrari,
    required this.quorum,
    required this.stato,
    required this.scadenza,
    required this.votiUtenti,
    this.paritaDecisaDaOrganizzatore = false,
    this.nomeOrganizzatore,
  });

  int get totaleVoti => votiFavorevoli + votiContrari;
  bool get quorumRaggiunto => totaleVoti >= quorum;

  factory Votazione.fromJson(Map<String, dynamic> json) {
    return Votazione(
      id: json['id'] as String? ?? '',
      titolo: json['titolo'] as String? ?? '',
      descrizione: json['descrizione'] as String? ?? '',
      bonusMalus: json['bonusMalus'] != null
          ? BonusMalus.fromJson(json['bonusMalus'] as Map<String, dynamic>)
          : null,
      votiFavorevoli: json['votiFavorevoli'] as int? ?? 0,
      votiContrari: json['votiContrari'] as int? ?? 0,
      quorum: json['quorum'] as int? ?? 5,
      stato: json['stato'] as String? ?? 'in_corso',
      scadenza: json['scadenza'] != null
          ? DateTime.parse(json['scadenza'] as String)
          : DateTime.now().add(const Duration(hours: 24)),
      votiUtenti: json['votiUtenti'] != null
          ? Map<String, String>.from(json['votiUtenti'] as Map)
          : {},
      paritaDecisaDaOrganizzatore: json['paritaDecisaDaOrganizzatore'] as bool? ?? false,
      nomeOrganizzatore: json['nomeOrganizzatore'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titolo': titolo,
      'descrizione': descrizione,
      'bonusMalus': bonusMalus?.toJson(),
      'votiFavorevoli': votiFavorevoli,
      'votiContrari': votiContrari,
      'quorum': quorum,
      'stato': stato,
      'scadenza': scadenza.toIso8601String(),
      'votiUtenti': votiUtenti,
      'paritaDecisaDaOrganizzatore': paritaDecisaDaOrganizzatore,
      'nomeOrganizzatore': nomeOrganizzatore,
    };
  }

  Votazione copyWith({
    String? id,
    String? titolo,
    String? descrizione,
    BonusMalus? bonusMalus,
    int? votiFavorevoli,
    int? votiContrari,
    int? quorum,
    String? stato,
    DateTime? scadenza,
    Map<String, String>? votiUtenti,
    bool? paritaDecisaDaOrganizzatore,
    String? nomeOrganizzatore,
  }) {
    return Votazione(
      id: id ?? this.id,
      titolo: titolo ?? this.titolo,
      descrizione: descrizione ?? this.descrizione,
      bonusMalus: bonusMalus ?? this.bonusMalus,
      votiFavorevoli: votiFavorevoli ?? this.votiFavorevoli,
      votiContrari: votiContrari ?? this.votiContrari,
      quorum: quorum ?? this.quorum,
      stato: stato ?? this.stato,
      scadenza: scadenza ?? this.scadenza,
      votiUtenti: votiUtenti ?? this.votiUtenti,
      paritaDecisaDaOrganizzatore: paritaDecisaDaOrganizzatore ?? this.paritaDecisaDaOrganizzatore,
      nomeOrganizzatore: nomeOrganizzatore ?? this.nomeOrganizzatore,
    );
  }
}
