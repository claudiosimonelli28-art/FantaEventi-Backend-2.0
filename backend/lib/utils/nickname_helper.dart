class NicknameHelper {
  /// Risolve rigorosamente qualsiasi nome o alias nel NICKNAME ufficiale di gioco.
  /// Il Nome e Cognome NON devono MAI apparire nelle notifiche, feed o votazioni.
  static String resolve(String? candidate, [List<Map<String, dynamic>>? utentiDocs]) {
    if (candidate == null) return 'Cloud';
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return 'Cloud';
    final lower = trimmed.toLowerCase();

    // Mappatura statica di sicurezza per gli account principali
    if (lower == 'claudio' || lower == 'cloud') return 'Cloud';
    if (lower == 'filippo' || lower == 'pippoforte' || lower == 'pippo forte') return 'Pippoforte';
    if (lower == 'antonio' || lower == 'ugnom' || lower == 'ugnome') return 'Ugnom';

    if (utentiDocs != null) {
      for (var u in utentiDocs) {
        final nick = (u['nickname'] ?? u['username'] ?? '').toString().trim();
        final nome = (u['nome'] ?? '').toString().trim();
        final cognome = (u['cognome'] ?? '').toString().trim();
        if (nick.isNotEmpty) {
          if (nick.toLowerCase() == lower) return nick;
          if (nome.isNotEmpty && nome.toLowerCase() == lower) return nick;
          if (cognome.isNotEmpty && '$nome $cognome'.toLowerCase() == lower) return nick;
          final user = (u['username'] ?? '').toString().trim();
          if (user.isNotEmpty && user.toLowerCase() == lower) return nick;
        }
      }
    }
    return trimmed;
  }

  /// Verifica se due stringhe (nome, nickname o alias) appartengono alla stessa persona
  static bool isSame(String? a, String? b, [List<Map<String, dynamic>>? utentiDocs]) {
    if (a == null || b == null) return false;
    final nickA = resolve(a, utentiDocs).toLowerCase();
    final nickB = resolve(b, utentiDocs).toLowerCase();
    if (nickA.isNotEmpty && nickA == nickB) return true;
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }
}
