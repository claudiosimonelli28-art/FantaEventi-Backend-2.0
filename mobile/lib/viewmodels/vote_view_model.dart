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
  String get currentUserNick => _apiService.currentUser?.nome.isNotEmpty == true
      ? _apiService.currentUser!.nome
      : 'Cloud';

  bool get isPartecipante {
    final curUser = _apiService.currentUser;
    final curUserNick = curUser?.nome.isNotEmpty == true ? curUser!.nome : 'Cloud';
    final cleanUser = curUserNick.trim().toLowerCase();
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanId = (curUser?.id ?? '').trim().toLowerCase();

    final evId = _votazione.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
    final evMatch = _apiService.eventi.firstWhere(
      (e) => (evId.isNotEmpty && (e.id.trim().toLowerCase() == evId || e.titolo.trim().toLowerCase() == evId)) ||
             (e.titolo.isNotEmpty && _votazione.titolo.toLowerCase().contains(e.titolo.toLowerCase())) ||
             (e.titolo.isNotEmpty && _votazione.descrizione.toLowerCase().contains(e.titolo.toLowerCase())),
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
      final cleanCreatore = (evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa).trim().toLowerCase();
      final pList = evMatch.partecipanti.map((p) => p.trim().toLowerCase()).toList();
      final iList = evMatch.invitati.map((p) => p.trim().toLowerCase()).toList();

      return cleanCreatore == cleanUser || cleanCreatore == cleanNick || cleanCreatore == cleanId ||
             pList.contains(cleanUser) || pList.contains(cleanNick) || pList.contains(cleanId) ||
             iList.contains(cleanUser) || iList.contains(cleanNick) || iList.contains(cleanId);
    }
    return true;
  }

  bool get isProponente {
    final curUser = _apiService.currentUser;
    final curUserNick = curUser?.nome.isNotEmpty == true ? curUser!.nome : 'Cloud';
    final cleanUser = curUserNick.trim().toLowerCase();
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanId = (curUser?.id ?? '').trim().toLowerCase();

    final propostoDa = (_votazione.bonusMalus?.propostoDa ?? '').trim().toLowerCase();
    return (propostoDa.isNotEmpty && (propostoDa == cleanUser || (cleanNick.isNotEmpty && propostoDa == cleanNick) || (cleanId.isNotEmpty && propostoDa == cleanId))) ||
        _votazione.descrizione.toLowerCase().contains('proposto da $cleanUser') ||
        (cleanNick.isNotEmpty && _votazione.descrizione.toLowerCase().contains('proposto da $cleanNick'));
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
