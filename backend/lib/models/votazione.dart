import 'package:mongo_dart/mongo_dart.dart';
import 'bonus_malus.dart';

class Votazione {
  final ObjectId? mongoId;
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
    this.mongoId,
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
  int get maxVotiConcordi => votiFavorevoli >= votiContrari ? votiFavorevoli : votiContrari;
  bool get quorumRaggiunto => votiFavorevoli >= quorum || votiContrari >= quorum;
  bool get isApprovata => stato == 'approvato' || votiFavorevoli >= quorum;
  bool get isRespinta => stato == 'respinto' || votiContrari >= quorum;

  factory Votazione.fromMap(Map<String, dynamic> map) {
    ObjectId? mId = map['_id'] is ObjectId
        ? map['_id'] as ObjectId
        : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null);

    final rawId = mId?.oid ?? (map['id'] ?? map['_id'] ?? '');

    return Votazione(
      mongoId: mId,
      id: rawId.toString(),
      titolo: map['titolo'] as String? ?? (map['bonusTitolo'] as String? ?? ''),
      descrizione: map['descrizione'] as String? ?? '',
      bonusMalus: map['bonusMalus'] != null
          ? BonusMalus.fromMap(map['bonusMalus'] as Map<String, dynamic>)
          : null,
      votiFavorevoli: (map['votiFavorevoli'] as num?)?.toInt() ?? 0,
      votiContrari: (map['votiContrari'] as num?)?.toInt() ?? 0,
      quorum: (map['quorum'] as num?)?.toInt() ?? 5,
      stato: map['stato'] as String? ?? 'in_corso',
      scadenza: map['scadenza'] != null
          ? (map['scadenza'] is DateTime ? map['scadenza'] as DateTime : DateTime.tryParse(map['scadenza'].toString()) ?? DateTime.now().add(const Duration(hours: 24)))
          : DateTime.now().add(const Duration(hours: 24)),
      votiUtenti: map['votiUtenti'] != null
          ? Map<String, String>.from(map['votiUtenti'] as Map)
          : {},
      paritaDecisaDaOrganizzatore: map['paritaDecisaDaOrganizzatore'] as bool? ?? false,
      nomeOrganizzatore: map['nomeOrganizzatore'] as String?,
    );
  }

  factory Votazione.fromJson(Map<String, dynamic> json) => Votazione.fromMap(json);

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'titolo': titolo,
      'bonusTitolo': titolo,
      'descrizione': descrizione,
      'bonusMalus': bonusMalus?.toMap(),
      'votiFavorevoli': votiFavorevoli,
      'votiContrari': votiContrari,
      'quorum': quorum,
      'stato': stato,
      'scadenza': scadenza.toIso8601String(),
      'votiUtenti': votiUtenti,
      'paritaDecisaDaOrganizzatore': paritaDecisaDaOrganizzatore,
      'nomeOrganizzatore': nomeOrganizzatore,
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
      'bonusTitolo': titolo,
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
}
