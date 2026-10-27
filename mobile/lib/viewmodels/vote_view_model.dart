import 'dart:async';
import '../models/evento.dart';
import '../models/votazione.dart';
import '../models/utente.dart';
import '../services/api_service.dart';
import 'base_view_model.dart';

class VoteViewModel extends BaseViewModel {
  final ApiService _apiService = ApiService();
  Votazione _votazione;
  bool _isSubmitting = false;

  VoteViewModel(this._votazione);

  Votazione get votazione => _votazione;
  bool get isSubmitting => _isSubmitting;
  Utente? get currentUser => _apiService.currentUser;

  String get currentUserNick {
    final u = _apiService.currentUser;
    if (u == null) return 'Cloud';
    final nick = u.nickname.isNotEmpty ? u.nickname : (u.nome.isNotEmpty ? u.nome : 'Cloud');
    return _apiService.resolveNickname(nick);
  }

  bool get isPartecipante {
    final cleanNick = currentUserNick;

    final evId = _votazione.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
    final evMatch = _apiService.eventi.firstWhere(
      (e) => evId.isNotEmpty && (e.id.trim().toLowerCase() == evId || e.titolo.trim().toLowerCase() == evId),
      orElse: () => Evento(
        id: '',
        titolo: '',
        descrizione: '',
        data: DateTime.now(),
        luogo: '',
        stato: '',
        propostoDa: '',
        partecipanti: [],
        bonusMalusApplicati: [],
        votazioniAttive: [],
      ),
    );

    if (evMatch.id.isNotEmpty) {
      final cleanCreatore = (evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa).trim();
      return _apiService.isSamePerson(cleanCreatore, cleanNick) ||
             evMatch.partecipanti.any((p) => _apiService.isSamePerson(p, cleanNick)) ||
             evMatch.invitati.any((p) => _apiService.isSamePerson(p, cleanNick));
    }
    return true;
  }

  bool get isProponente {
    final curNick = currentUserNick;
    final propostoDa = (_votazione.bonusMalus?.propostoDa ?? '').trim();

    if (propostoDa.isNotEmpty && _apiService.isSamePerson(propostoDa, curNick)) {
      return true;
    }

    final desc = _votazione.descrizione.toLowerCase();
    if (curNick.isNotEmpty && desc.contains('proposto da ${curNick.toLowerCase()}')) return true;
    if (desc.contains('proposto da ${_apiService.resolveNickname(curNick).toLowerCase()}')) return true;

    return false;
  }

  Future<Votazione> vota(bool aFavore) async {
    if (!isPartecipante) {
      throw Exception('Non puoi votare perché non partecipi a questo evento!');
    }
    _isSubmitting = true;
    notifyListeners();

    try {
      final vAggiornata = await _apiService.vota(_votazione.id, aFavore);
      _votazione = vAggiornata;
      return vAggiornata;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
