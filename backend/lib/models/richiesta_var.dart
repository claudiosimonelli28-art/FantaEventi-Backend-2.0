import 'package:mongo_dart/mongo_dart.dart';

class RichiestaVar {
  final ObjectId? id;
  final String eventoId;
  final String eventoTitolo;
  final String tipo; // 'bonus' o 'malus'
  final String bonusMalusId;
  final String bonusMalusTitolo;
  final int punti;
  final String richiedente;
  final String bersaglio;
  final String descrizione;
  final String? fotoBase64;
  final List<String> testimoni;
  final Map<String, bool> votiTestimoni;
  final String giudice;
  final String stato; // 'in_attesa', 'approvata', 'rifiutata', 'scaduta'
  final DateTime dataCreazione;
  final DateTime? dataDecisione;
  final bool sanzioneApplicata;
  final int penalitaPunti;
  final String? motivoRifiuto;

  RichiestaVar({
    this.id,
    required this.eventoId,
    required this.eventoTitolo,
    required this.tipo,
    required this.bonusMalusId,
    required this.bonusMalusTitolo,
    required this.punti,
    required this.richiedente,
    required this.bersaglio,
    required this.descrizione,
    this.fotoBase64,
    required this.testimoni,
    required this.votiTestimoni,
    required this.giudice,
    this.stato = 'in_attesa',
    DateTime? dataCreazione,
    this.dataDecisione,
    this.sanzioneApplicata = false,
    this.penalitaPunti = -10,
    this.motivoRifiuto,
  }) : dataCreazione = dataCreazione ?? DateTime.now();

  factory RichiestaVar.fromMap(Map<String, dynamic> map) {
    Map<String, bool> parsedVoti = {};
    if (map['votiTestimoni'] != null && map['votiTestimoni'] is Map) {
      (map['votiTestimoni'] as Map).forEach((k, v) {
        if (v is bool) {
          parsedVoti[k.toString().toLowerCase()] = v;
        } else if (v is String) {
          parsedVoti[k.toString().toLowerCase()] = v.toLowerCase() == 'true';
        }
      });
    }

    return RichiestaVar(
      id: map['_id'] is ObjectId
          ? map['_id'] as ObjectId
          : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null),
      eventoId: map['eventoId']?.toString() ?? '',
      eventoTitolo: map['eventoTitolo']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? 'bonus',
      bonusMalusId: map['bonusMalusId']?.toString() ?? '',
      bonusMalusTitolo: map['bonusMalusTitolo']?.toString() ?? '',
      punti: (map['punti'] as num?)?.toInt() ?? 0,
      richiedente: map['richiedente']?.toString() ?? '',
      bersaglio: map['bersaglio']?.toString() ?? (map['richiedente']?.toString() ?? ''),
      descrizione: map['descrizione']?.toString() ?? '',
      fotoBase64: map['fotoBase64'] as String?,
      testimoni: (map['testimoni'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      votiTestimoni: parsedVoti,
      giudice: map['giudice']?.toString() ?? '',
      stato: map['stato']?.toString() ?? 'in_attesa',
      dataCreazione: map['dataCreazione'] is DateTime
          ? map['dataCreazione'] as DateTime
          : (map['dataCreazione'] != null ? DateTime.tryParse(map['dataCreazione'].toString()) : null),
      dataDecisione: map['dataDecisione'] is DateTime
          ? map['dataDecisione'] as DateTime
          : (map['dataDecisione'] != null ? DateTime.tryParse(map['dataDecisione'].toString()) : null),
      sanzioneApplicata: map['sanzioneApplicata'] == true,
      penalitaPunti: (map['penalitaPunti'] as num?)?.toInt() ?? -10,
      motivoRifiuto: map['motivoRifiuto'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'eventoId': eventoId,
      'eventoTitolo': eventoTitolo,
      'tipo': tipo,
      'bonusMalusId': bonusMalusId,
      'bonusMalusTitolo': bonusMalusTitolo,
      'punti': punti,
      'richiedente': richiedente,
      'bersaglio': bersaglio,
      'descrizione': descrizione,
      if (fotoBase64 != null) 'fotoBase64': fotoBase64,
      'testimoni': testimoni,
      'votiTestimoni': votiTestimoni,
      'giudice': giudice,
      'stato': stato,
      'dataCreazione': dataCreazione.toIso8601String(),
      if (dataDecisione != null) 'dataDecisione': dataDecisione!.toIso8601String(),
      'sanzioneApplicata': sanzioneApplicata,
      'penalitaPunti': penalitaPunti,
      if (motivoRifiuto != null) 'motivoRifiuto': motivoRifiuto,
    };
    if (id != null) {
      map['_id'] = id;
    }
    return map;
  }
}
