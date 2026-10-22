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
    if (u.nickname.isNotEmpty) return u.nickname;
    if (u.nome.isNotEmpty) return u.nome;
    return 'Cloud';
  }

  bool get isPartecipante {
    final curUser = _apiService.currentUser;
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanNome = (curUser?.nome ?? '').trim().toLowerCase();
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

      return cleanCreatore == cleanNick || cleanCreatore == cleanNome || cleanCreatore == cleanId ||
             (cleanNick == 'cloud' && cleanCreatore == 'claudio') || (cleanNome == 'claudio' && cleanCreatore == 'cloud') ||
             pList.contains(cleanNick) || pList.contains(cleanNome) || pList.contains(cleanId) ||
             (cleanNick == 'cloud' && pList.contains('claudio')) || (cleanNome == 'claudio' && pList.contains('cloud')) ||
             iList.contains(cleanNick) || iList.contains(cleanNome) || iList.contains(cleanId) ||
             (cleanNick == 'cloud' && iList.contains('claudio')) || (cleanNome == 'claudio' && iList.contains('cloud'));
    }
    return true;
  }

  bool get isProponente {
    final curUser = _apiService.currentUser;
    final curNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final curNome = (curUser?.nome ?? '').trim().toLowerCase();
    final curId = (curUser?.id ?? '').trim().toLowerCase();

    final propostoDa = (_votazione.bonusMalus?.propostoDa ?? '').trim().toLowerCase();
    final isCloud = curNick == 'cloud' || curNome == 'claudio' || curNick == 'claudio' || curNome == 'cloud';
    final isPropostoCloud = propostoDa == 'cloud' || propostoDa == 'claudio';

    if (propostoDa.isNotEmpty) {
      if (propostoDa == curNick || (curNome.isNotEmpty && propostoDa == curNome) || (curId.isNotEmpty && propostoDa == curId)) return true;
      if (isCloud && isPropostoCloud) return true;
    }

    final desc = _votazione.descrizione.toLowerCase();
    if (curNick.isNotEmpty && desc.contains('proposto da $curNick')) return true;
    if (curNome.isNotEmpty && desc.contains('proposto da $curNome')) return true;
    if (isCloud && (desc.contains('proposto da cloud') || desc.contains('proposto da claudio'))) return true;

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
