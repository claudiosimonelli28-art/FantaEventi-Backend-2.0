import 'package:mongo_dart/mongo_dart.dart';

class Utente {
  final ObjectId? id;
  final String username;
  final String email;
  final String password;
  final String ruolo;
  final int puntiTotali;
  final int livello;
  final String? squadra;
  final DateTime createdAt;

  Utente({
    this.id,
    required this.username,
    required this.email,
    this.password = '',
    this.ruolo = 'partecipante',
    this.puntiTotali = 0,
    this.livello = 1,
    this.squadra,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Utente.fromMap(Map<String, dynamic> map) {
    final uname = map['nickname'] ?? map['username'] ?? map['nome'] ?? 'Utente';
    return Utente(
      id: map['_id'] is ObjectId
          ? map['_id'] as ObjectId
          : (map['_id'] != null ? ObjectId.fromHexString(map['_id'].toString()) : null),
      username: uname.toString(),
      email: map['email'] as String? ?? '',
      password: map['password'] as String? ?? '',
      ruolo: map['ruolo'] as String? ?? 'partecipante',
      puntiTotali: (map['puntiTotali'] as num?)?.toInt() ?? ((map['puntiEsperienza'] as num?)?.toInt() ?? 0),
      livello: (map['livello'] as num?)?.toInt() ?? 1,
      squadra: map['squadra'] as String?,
      createdAt: map['createdAt'] is DateTime
          ? map['createdAt'] as DateTime
          : (map['createdAt'] != null
              ? DateTime.parse(map['createdAt'].toString())
              : DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nickname': username,
      'username': username,
      'nome': username,
      'email': email,
      'password': password,
      'ruolo': ruolo,
      'puntiTotali': puntiTotali,
      'puntiEsperienza': puntiTotali,
      'livello': livello,
      'squadra': squadra,
      'createdAt': createdAt.toIso8601String(),
    };
    if (id != null) {
      map['_id'] = id;
    }
    return map;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id?.oid ?? id?.toHexString(),
      'username': username,
      'nome': username,
      'nickname': username,
      'email': email,
      'ruolo': ruolo,
      'puntiTotali': puntiTotali,
      'livello': livello,
      'squadra': squadra,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
