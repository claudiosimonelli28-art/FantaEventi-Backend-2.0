class RichiestaVar {
  final String id;
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
  final Map<String, bool> votiTestimoni; // { 'nickname': true (conferma) / false (nega) }
  final String giudice;
  final String stato; // 'in_attesa', 'approvata', 'rifiutata', 'scaduta'
  final DateTime dataCreazione;
  final DateTime? dataDecisione;
  final bool sanzioneApplicata;
  final int penalitaPunti;
  final String? motivoRifiuto;

  RichiestaVar({
    required this.id,
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
    required this.dataCreazione,
    this.dataDecisione,
    this.sanzioneApplicata = false,
    this.penalitaPunti = -10,
    this.motivoRifiuto,
  });

  bool get isBonus => tipo.toLowerCase() == 'bonus';
  bool get isMalus => tipo.toLowerCase() == 'malus';
  bool get isPending => stato == 'in_attesa';
  bool get isApprovata => stato == 'approvata';
  bool get isRifiutata => stato == 'rifiutata';
  bool get isScaduta => stato == 'scaduta';

  int get numeroConferme => votiTestimoni.values.where((v) => v == true).length;
  int get numeroDinieghi => votiTestimoni.values.where((v) => v == false).length;
  int get testimoniInAttesa => testimoni.where((t) => !votiTestimoni.containsKey(t.toLowerCase())).length;

  factory RichiestaVar.fromJson(Map<String, dynamic> json) {
    Map<String, bool> parsedVoti = {};
    if (json['votiTestimoni'] != null && json['votiTestimoni'] is Map) {
      (json['votiTestimoni'] as Map).forEach((k, v) {
        if (v is bool) {
          parsedVoti[k.toString().toLowerCase()] = v;
        } else if (v is String) {
          parsedVoti[k.toString().toLowerCase()] = v.toLowerCase() == 'true';
        }
      });
    }

    DateTime parsedCreazione = DateTime.now();
    if (json['dataCreazione'] != null) {
      parsedCreazione = DateTime.tryParse(json['dataCreazione'].toString()) ?? DateTime.now();
    }

    DateTime? parsedDecisione;
    if (json['dataDecisione'] != null) {
      parsedDecisione = DateTime.tryParse(json['dataDecisione'].toString());
    }

    return RichiestaVar(
      id: json['id']?.toString() ?? json['_id']?.toHexString() ?? json['_id']?.toString() ?? '',
      eventoId: json['eventoId']?.toString() ?? '',
      eventoTitolo: json['eventoTitolo']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? 'bonus',
      bonusMalusId: json['bonusMalusId']?.toString() ?? '',
      bonusMalusTitolo: json['bonusMalusTitolo']?.toString() ?? '',
      punti: (json['punti'] as num?)?.toInt() ?? 0,
      richiedente: json['richiedente']?.toString() ?? '',
      bersaglio: json['bersaglio']?.toString() ?? (json['richiedente']?.toString() ?? ''),
      descrizione: json['descrizione']?.toString() ?? '',
      fotoBase64: json['fotoBase64'] as String?,
      testimoni: (json['testimoni'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      votiTestimoni: parsedVoti,
      giudice: json['giudice']?.toString() ?? '',
      stato: json['stato']?.toString() ?? 'in_attesa',
      dataCreazione: parsedCreazione,
      dataDecisione: parsedDecisione,
      sanzioneApplicata: json['sanzioneApplicata'] == true,
      penalitaPunti: (json['penalitaPunti'] as num?)?.toInt() ?? -10,
      motivoRifiuto: json['motivoRifiuto'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
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
  }

  RichiestaVar copyWith({
    String? id,
    String? eventoId,
    String? eventoTitolo,
    String? tipo,
    String? bonusMalusId,
    String? bonusMalusTitolo,
    int? punti,
    String? richiedente,
    String? bersaglio,
    String? descrizione,
    String? fotoBase64,
    List<String>? testimoni,
    Map<String, bool>? votiTestimoni,
    String? giudice,
    String? stato,
    DateTime? dataCreazione,
    DateTime? dataDecisione,
    bool? sanzioneApplicata,
    int? penalitaPunti,
    String? motivoRifiuto,
  }) {
    return RichiestaVar(
      id: id ?? this.id,
      eventoId: eventoId ?? this.eventoId,
      eventoTitolo: eventoTitolo ?? this.eventoTitolo,
      tipo: tipo ?? this.tipo,
      bonusMalusId: bonusMalusId ?? this.bonusMalusId,
      bonusMalusTitolo: bonusMalusTitolo ?? this.bonusMalusTitolo,
      punti: punti ?? this.punti,
      richiedente: richiedente ?? this.richiedente,
      bersaglio: bersaglio ?? this.bersaglio,
      descrizione: descrizione ?? this.descrizione,
      fotoBase64: fotoBase64 ?? this.fotoBase64,
      testimoni: testimoni ?? this.testimoni,
      votiTestimoni: votiTestimoni ?? this.votiTestimoni,
      giudice: giudice ?? this.giudice,
      stato: stato ?? this.stato,
      dataCreazione: dataCreazione ?? this.dataCreazione,
      dataDecisione: dataDecisione ?? this.dataDecisione,
      sanzioneApplicata: sanzioneApplicata ?? this.sanzioneApplicata,
      penalitaPunti: penalitaPunti ?? this.penalitaPunti,
      motivoRifiuto: motivoRifiuto ?? this.motivoRifiuto,
    );
  }
}
