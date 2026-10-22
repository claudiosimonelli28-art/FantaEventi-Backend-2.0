import 'dart:async';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../models/evento.dart';
import '../models/utente.dart';
import '../models/votazione.dart';
import '../models/bonus_malus.dart';
import '../models/richiesta_var.dart';
import '../services/api_service.dart';
import 'base_view_model.dart';

class EventTitles {
  final String? campioneNick;
  final int campionePts;
  final String? reMalusNick;
  final int maxMalusVal;
  final String? giudiceNick; // L'Avvocato
  final int maxAttivita;
  final String? fantasmaNick;
  final int minAzioni;
  final String? sbirroNick;
  final int maxSbirroVal;
  final String? giustiziereNick;
  final int maxGiustiziereVal;

  const EventTitles({
    this.campioneNick,
    this.campionePts = 0,
    this.reMalusNick,
    this.maxMalusVal = 0,
    this.giudiceNick,
    this.maxAttivita = 0,
    this.fantasmaNick,
    this.minAzioni = 0,
    this.sbirroNick,
    this.maxSbirroVal = 0,
    this.giustiziereNick,
    this.maxGiustiziereVal = 0,
  });
}

class EventDetailViewModel extends BaseViewModel {
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();

  Evento _evento;
  final List<Votazione> _votazioniEvento = [];
  List<BonusMalus> _allBonusMalus = [];
  List<RichiestaVar> _richiesteVarEvento = [];
  Set<String> _invitatiInSospeso = {};
  List<String> _partecipantiConfermati = [];
  Timer? _liveLeaderboardTimer;
  bool _isSyncing = false;

  EventDetailViewModel(this._evento);

  // Getters
  Evento get evento => _evento;
  List<Votazione> get votazioniEvento => List.unmodifiable(_votazioniEvento);
  List<BonusMalus> get allBonusMalus => List.unmodifiable(_allBonusMalus);
  List<RichiestaVar> get richiesteVarEvento => List.unmodifiable(_richiesteVarEvento);
  Set<String> get invitatiInSospeso => Set.unmodifiable(_invitatiInSospeso);
  List<String> get partecipantiConfermati => List.unmodifiable(_partecipantiConfermati);

  Utente? get currentUser => _apiService.currentUser;
  String get currentUserNick {
    final u = _apiService.currentUser;
    if (u == null) return 'Cloud';
    if (u.nickname.isNotEmpty) return u.nickname;
    if (u.nome.isNotEmpty) return u.nome;
    return 'Cloud';
  }
  String get creatore => _evento.propostoDa.isNotEmpty ? _evento.propostoDa : 'Cloud';
  bool get isCreatore {
    final cNick = currentUserNick.trim().toLowerCase();
    final cReal = (_apiService.currentUser?.nome ?? '').trim().toLowerCase();
    final evCreatore = creatore.trim().toLowerCase();
    return evCreatore == cNick ||
        evCreatore == cReal ||
        (cNick == 'cloud' && evCreatore == 'claudio') ||
        (cReal == 'claudio' && evCreatore == 'cloud');
  }
  bool get isConcluso => _evento.isConcluso;
  bool get giaPartecipa {
    final cNick = currentUserNick.trim().toLowerCase();
    final cReal = (_apiService.currentUser?.nome ?? '').trim().toLowerCase();
    final curId = _apiService.currentUser?.id.trim().toLowerCase() ?? '';

    return _partecipantiConfermati.any((p) {
      final pClean = p.trim().toLowerCase();
      return pClean == cNick ||
          pClean == cReal ||
          (cNick == 'cloud' && pClean == 'claudio') ||
          (cReal == 'claudio' && pClean == 'cloud') ||
          (curId.isNotEmpty && pClean == curId);
    });
  }

  int get totalePartecipanti => _partecipantiConfermati.length;
  // Formula maggioranza assoluta: (N / 2).floor() + 1
  int get quorumCalcolato => totalePartecipanti <= 0 ? 1 : (totalePartecipanti / 2).floor() + 1;

  void inizializza() {
    calcolaCoerenzaInvitiEVotazioni();
    _liveLeaderboardTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      calcolaCoerenzaInvitiEVotazioni();
    });
  }

  Future<void> calcolaCoerenzaInvitiEVotazioni() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final creatoreNick = creatore;
      final List<String> confermati = [creatoreNick];
      final Set<String> inSospeso = {};

      for (var p in _evento.partecipanti) {
        if (!confermati.any((c) => c.trim().toLowerCase() == p.trim().toLowerCase())) {
          confermati.add(p);
        }
      }

      for (var inv in _evento.invitati) {
        if (!confermati.any((c) => c.trim().toLowerCase() == inv.trim().toLowerCase())) {
          inSospeso.add(inv);
        }
      }

      List<BonusMalus> bmList = [];
      try {
        bmList = await _apiService.getBonusMalusList().catchError((_) => <BonusMalus>[]);
        await _apiService.getUtenti().catchError((_) => <Utente>[]);
        final varReqs = await _apiService.getRichiesteVarEvento(_evento.id).catchError((_) => <RichiestaVar>[]);

        for (var bm in bmList) {
          final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
              bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
          if (isSameEv) {
            for (var u in bm.assegnatoA) {
              if (u.trim().isNotEmpty && !confermati.any((c) => c.trim().toLowerCase() == u.trim().toLowerCase())) {
                confermati.add(u.trim());
              }
            }
          }
        }

        _richiesteVarEvento = varReqs;
      } catch (_) {}

      _partecipantiConfermati = confermati;
      _invitatiInSospeso = inSospeso;
      _allBonusMalus = bmList;
      notifyListeners();
    } finally {
      _isSyncing = false;
    }
  }

  List<MapEntry<String, int>> getSortedLeaderboardEntries() {
    final Map<String, int> puntiPerPartecipante = {};
    for (var p in _partecipantiConfermati) {
      puntiPerPartecipante[p] = 0;
    }

    for (var bm in _allBonusMalus) {
      final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
          bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
      if (isSameEv || _allBonusMalus.length == 1) {
        for (var p in _partecipantiConfermati) {
          final count = bm.assegnatoA.where((u) => u.trim().toLowerCase() == p.trim().toLowerCase()).length;
          if (count > 0) {
            puntiPerPartecipante[p] = (puntiPerPartecipante[p] ?? 0) + (bm.punti * count);
          }
        }
      }
    }

    return puntiPerPartecipante.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  EventTitles calcolaTitoli(List<MapEntry<String, int>> sortedEntries) {
    if (sortedEntries.isEmpty) return const EventTitles();

    final savedTitoli = _evento.titoliVincitori;

    String? campioneNick = sortedEntries.isNotEmpty ? sortedEntries.first.key : null;
    int campionePts = sortedEntries.isNotEmpty ? sortedEntries.first.value : 0;
    String? reMalusNick;
    int maxMalusVal = 0;
    String? giudiceNick;
    int maxAttivita = 0;
    String? fantasmaNick;
    int minAzioni = 0;
    String? sbirroNick;
    int maxSbirroVal = 0;
    String? giustiziereNick;
    int maxGiustiziereVal = 0;

    if (savedTitoli != null && savedTitoli.isNotEmpty) {
      if (savedTitoli['campione'] != null) {
        campioneNick = savedTitoli['campione'].toString();
        campionePts = (savedTitoli['campionePunti'] as num?)?.toInt() ?? campionePts;
      }
      reMalusNick = savedTitoli['reMalus']?.toString();
      maxMalusVal = (savedTitoli['reMalusPunti'] as num?)?.toInt() ?? 0;
      giudiceNick = savedTitoli['avvocato']?.toString();
      maxAttivita = (savedTitoli['avvocatoAzioni'] as num?)?.toInt() ?? 0;
      fantasmaNick = savedTitoli['fantasma']?.toString();
      minAzioni = (savedTitoli['fantasmaAzioni'] as num?)?.toInt() ?? 0;
      sbirroNick = savedTitoli['sbirro']?.toString();
      maxSbirroVal = (savedTitoli['sbirroDenunce'] as num?)?.toInt() ?? 0;
      giustiziereNick = savedTitoli['giustiziere']?.toString();
      maxGiustiziereVal = (savedTitoli['giustiziereApprovate'] as num?)?.toInt() ?? 0;
    } else {
      // 1. Campione: primo con punteggio maggiore (se >= 0)
      final campioneEntry = sortedEntries.first;
      campioneNick = campioneEntry.key;
      campionePts = campioneEntry.value;

      // 2. Re dei Malus: chi ha accumulato il maggior totale di punti malus negativi
      final Map<String, int> malusPunti = {};
      // 3. L'Avvocato: chi ha proposto o votato più volte
      final Map<String, int> attivitaUtenti = {};
      // 4. Per il Fantasma: totale azioni (ricevute + proposte + voti)
      final Map<String, int> azioniTotali = {};

      for (var p in _evento.partecipanti) {
        final pNorm = p.trim().toLowerCase();
        malusPunti[pNorm] = 0;
        attivitaUtenti[pNorm] = 0;
        azioniTotali[pNorm] = 0;
      }

      for (var bm in _allBonusMalus) {
        final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
            bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
        if (!isSameEv && _allBonusMalus.length > 1) continue;

        // Escludi sanzioni d'ufficio del VAR dalle proposte community
        final bool isVarSanzione = bm.categoria.toUpperCase() == 'VAR' ||
            bm.titolo.contains('Falsa Testimonianza') ||
            bm.descrizione.toLowerCase().contains('sanzione per denuncia');

        // Proposte da
        final prop = bm.propostoDa.trim().toLowerCase();
        if (!isVarSanzione && prop.isNotEmpty && attivitaUtenti.containsKey(prop)) {
          attivitaUtenti[prop] = (attivitaUtenti[prop] ?? 0) + 1;
          azioniTotali[prop] = (azioniTotali[prop] ?? 0) + 1;
        }

        // Assegnato a
        for (var u in bm.assegnatoA) {
          final uNorm = u.trim().toLowerCase();
          azioniTotali[uNorm] = (azioniTotali[uNorm] ?? 0) + 1;
          if (bm.punti < 0) {
            malusPunti[uNorm] = (malusPunti[uNorm] ?? 0) + bm.punti.abs();
          }
        }
      }

      for (var v in _votazioniEvento) {
        for (var u in v.votiUtenti.keys) {
          final uNorm = u.trim().toLowerCase();
          if (attivitaUtenti.containsKey(uNorm)) {
            attivitaUtenti[uNorm] = (attivitaUtenti[uNorm] ?? 0) + 1;
            azioniTotali[uNorm] = (azioniTotali[uNorm] ?? 0) + 1;
          }
        }
      }

      // Re dei Malus
      malusPunti.forEach((nickLower, tot) {
        if (tot > maxMalusVal) {
          maxMalusVal = tot;
          reMalusNick = _evento.partecipanti.firstWhere(
            (p) => p.trim().toLowerCase() == nickLower,
            orElse: () => nickLower,
          );
        }
      });

      // L'Avvocato
      attivitaUtenti.forEach((nickLower, count) {
        if (count > maxAttivita) {
          maxAttivita = count;
          giudiceNick = _evento.partecipanti.firstWhere(
            (p) => p.trim().toLowerCase() == nickLower,
            orElse: () => nickLower,
          );
        }
      });

      // Fantasma: chi ha fatto meno azioni in assoluto (escluso chi ha vinto come campione)
      minAzioni = 999999;
      if (_evento.partecipanti.length > 1) {
        for (var p in _evento.partecipanti) {
          final pLower = p.trim().toLowerCase();
          if (pLower == campioneNick.trim().toLowerCase()) continue;
          final azioni = azioniTotali[pLower] ?? 0;
          if (azioni < minAzioni) {
            minAzioni = azioni;
            fantasmaNick = p;
          }
        }
      }

      // 5. Lo Sbirro: chi ha effettuato più denunce malus al VAR
      final Map<String, int> sbirroCounts = {};
      // 6. Il Giustiziere: chi ha aperto più chiamate VAR convalidate e approvate
      final Map<String, int> giustiziereCounts = {};

      for (var r in _richiesteVarEvento) {
        final req = r.richiedente.trim().toLowerCase();
        if (r.isApprovata) {
          giustiziereCounts[req] = (giustiziereCounts[req] ?? 0) + 1;
        }
        if (r.isMalus) {
          sbirroCounts[req] = (sbirroCounts[req] ?? 0) + 1;
        }
      }

      sbirroCounts.forEach((nickLower, count) {
        if (count > maxSbirroVal) {
          maxSbirroVal = count;
          sbirroNick = _evento.partecipanti.firstWhere(
            (p) => p.trim().toLowerCase() == nickLower,
            orElse: () => nickLower,
          );
        }
      });

      giustiziereCounts.forEach((nickLower, count) {
        if (count > maxGiustiziereVal) {
          maxGiustiziereVal = count;
          giustiziereNick = _evento.partecipanti.firstWhere(
            (p) => p.trim().toLowerCase() == nickLower,
            orElse: () => nickLower,
          );
        }
      });
    }

    return EventTitles(
      campioneNick: campioneNick,
      campionePts: campionePts,
      reMalusNick: reMalusNick,
      maxMalusVal: maxMalusVal,
      giudiceNick: giudiceNick,
      maxAttivita: maxAttivita,
      fantasmaNick: fantasmaNick,
      minAzioni: minAzioni == 999999 ? 0 : minAzioni,
      sbirroNick: sbirroNick,
      maxSbirroVal: maxSbirroVal,
      giustiziereNick: giustiziereNick,
      maxGiustiziereVal: maxGiustiziereVal,
    );
  }

  List<Map<String, dynamic>> getIstanzeAssegnazioniGiocatore(String targetNick) {
    final List<Map<String, dynamic>> istanzeAssegnazioni = [];
    for (var bm in _allBonusMalus) {
      final isSameEv = bm.eventoId.trim().toLowerCase() == _evento.id.trim().toLowerCase() ||
          bm.eventoId.trim().toLowerCase() == _evento.titolo.trim().toLowerCase();
      if (isSameEv || _allBonusMalus.length == 1) {
        final count = bm.assegnatoA.where((u) => u.trim().toLowerCase() == targetNick.trim().toLowerCase()).length;
        for (int i = 0; i < count; i++) {
          istanzeAssegnazioni.add({
            'bonus': bm,
            'numIstanza': i + 1,
            'totaleIstanze': count,
          });
        }
      }
    }
    return istanzeAssegnazioni;
  }

  Future<void> partecipaAdEvento() async {
    final nick = currentUserNick;
    await _apiService.partecipaAdEvento(_evento.id, nick);
    if (!_partecipantiConfermati.contains(nick)) {
      _partecipantiConfermati.add(nick);
    }
    _invitatiInSospeso.remove(nick);
    notifyListeners();
  }

  Future<String?> scattaFotoCopertina() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final b64 = 'data:image/png;base64,${base64Encode(bytes)}';
        await aggiornaCopertina(b64);
        return b64;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> selezionaFotoCopertinaDaGalleria() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final b64 = 'data:image/png;base64,${base64Encode(bytes)}';
        await aggiornaCopertina(b64);
        return b64;
      }
    } catch (_) {}
    return null;
  }

  Future<void> aggiornaCopertina(String nuovaCopertina) async {
    _evento = _evento.copyWith(copertinaUrl: nuovaCopertina);
    notifyListeners();
    await _apiService.aggiornaCopertinaEvento(_evento.id, nuovaCopertina);
  }

  Future<void> annullaAssegnazioneBonus({
    required String bonusId,
    required String utenteDestinatario,
    required int punti,
  }) async {
    await _apiService.annullaAssegnazioneBonus(
      eventoId: _evento.id,
      bonusId: bonusId,
      utenteDestinatario: utenteDestinatario,
      punti: punti,
    );
    await calcolaCoerenzaInvitiEVotazioni();
  }

  Future<List<Utente>> getGiocatoriInvitabili() async {
    return await _apiService.getGiocatoriInvitabili();
  }

  Future<void> invitaAmiciAdEvento(List<String> daInvitare) async {
    await _apiService.invitaAmiciAdEvento(_evento.id, daInvitare);
    _invitatiInSospeso.addAll(daInvitare);
    notifyListeners();
  }

  String getAvatarPerUtente(String nick) {
    return _apiService.getAvatarPerUtente(nick);
  }

  Utente? getUtenteInMemoria(String nick) {
    return _apiService.getUtenteInMemoria(nick);
  }

  Future<List<Utente>> fetchUtenti() async {
    return await _apiService.getUtenti();
  }

  @override
  void dispose() {
    _liveLeaderboardTimer?.cancel();
    super.dispose();
  }
}
