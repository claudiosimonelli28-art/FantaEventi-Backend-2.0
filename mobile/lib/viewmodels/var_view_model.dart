import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../models/richiesta_var.dart';
import '../services/api_service.dart';
import 'base_view_model.dart';

class VarSubmissionViewModel extends BaseViewModel {
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();

  final Evento evento;
  final BonusMalus bonusMalus;

  String? _fotoBase64;
  String? _selectedCulprit;
  String? _selectedJudge;
  final Set<String> _selectedWitnesses = {};
  bool _isSubmitting = false;

  VarSubmissionViewModel({required this.evento, required this.bonusMalus}) {
    _initDefaults();
  }

  String? get fotoBase64 => _fotoBase64;
  String? get selectedCulprit => _selectedCulprit;
  String? get selectedJudge => _selectedJudge;
  Set<String> get selectedWitnesses => Set.unmodifiable(_selectedWitnesses);
  bool get isSubmitting => _isSubmitting;
  String get myNick => (_apiService.currentUser?.nickname.isNotEmpty == true
      ? _apiService.currentUser!.nickname
      : (_apiService.currentUser?.nome ?? '')).trim();
  String get myRealName => (_apiService.currentUser?.nome ?? '').trim();

  bool isMe(String p) {
    return _apiService.isSamePerson(p, myNick) || _apiService.isSamePerson(p, myRealName);
  }

  bool get isOrganizer {
    return _apiService.isSamePerson(evento.creatore, myNick) || _apiService.isSamePerson(evento.creatore, myRealName);
  }

  bool get isOrganizerCulprit {
    if (isBonus || _selectedCulprit == null) return false;
    return _apiService.isSamePerson(evento.creatore, _selectedCulprit!);
  }

  bool get isOrganizerDisqualified => isOrganizer || isOrganizerCulprit;

  bool get isBonus => bonusMalus.punti > 0;

  List<String> get eligibleJudges {
    return evento.partecipanti.where((p) {
      if (isMe(p)) return false;
      if (!isBonus && _selectedCulprit != null && _apiService.isSamePerson(p, _selectedCulprit!)) return false;
      if (isOrganizerDisqualified && _apiService.isSamePerson(p, evento.creatore)) return false;
      return true;
    }).toList();
  }

  String get effectiveJudge {
    if (isOrganizerDisqualified) {
      if (_selectedJudge != null && eligibleJudges.any((j) => _apiService.isSamePerson(j, _selectedJudge!))) {
        return _selectedJudge!;
      }
      return eligibleJudges.isNotEmpty ? eligibleJudges.first : '';
    }
    return evento.creatore;
  }

  List<String> get eligibleWitnesses {
    final curJudge = effectiveJudge;
    return evento.partecipanti.where((p) {
      if (isMe(p)) return false;
      if (!isBonus && _selectedCulprit != null && _apiService.isSamePerson(p, _selectedCulprit!)) return false;
      if (curJudge.isNotEmpty && _apiService.isSamePerson(p, curJudge)) return false;
      return true;
    }).toList();
  }

  void _initDefaults() {
    if (bonusMalus.punti < 0) {
      final eligibleCulprits = evento.partecipanti
          .where((p) => !isMe(p))
          .toList();
      if (eligibleCulprits.isNotEmpty) {
        _selectedCulprit = eligibleCulprits.first;
      }
    }

    if (isOrganizerDisqualified) {
      final validJudges = eligibleJudges;
      if (validJudges.isNotEmpty) {
        _selectedJudge = validJudges.first;
      }
    }
  }

  void selectCulprit(String? culprit) {
    _selectedCulprit = culprit;
    // Pulisci i testimoni dal colpevole
    if (culprit != null) {
      _selectedWitnesses.removeWhere((w) => _apiService.isSamePerson(w, culprit));
      if (_selectedJudge != null && _apiService.isSamePerson(_selectedJudge!, culprit)) {
        _selectedJudge = null;
      }
    }
    // Se l'organizzatore e' squalificato (es. scelto come colpevole), assegna un giudice neutrale valido
    if (isOrganizerDisqualified) {
      final validJudges = eligibleJudges;
      if (_selectedJudge == null || !validJudges.any((j) => _apiService.isSamePerson(j, _selectedJudge!))) {
        _selectedJudge = validJudges.isNotEmpty ? validJudges.first : null;
      }
      if (_selectedJudge != null) {
        _selectedWitnesses.removeWhere((w) => _apiService.isSamePerson(w, _selectedJudge!));
      }
    }
    notifyListeners();
  }

  void selectJudge(String? judge) {
    _selectedJudge = judge;
    if (judge != null) {
      _selectedWitnesses.removeWhere((w) => _apiService.isSamePerson(w, judge));
    }
    notifyListeners();
  }

  void toggleWitness(String witness) {
    if (_selectedWitnesses.contains(witness)) {
      _selectedWitnesses.remove(witness);
    } else {
      _selectedWitnesses.add(witness);
    }
    notifyListeners();
  }

  Future<bool> pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        _fotoBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  void removePhoto() {
    _fotoBase64 = null;
    notifyListeners();
  }

  Future<String?> inviaRichiesta(String descrizione) async {
    final curUser = _apiService.currentUser;
    if (curUser == null) return null;

    final String bersaglio = isBonus ? myNick : (_selectedCulprit ?? '');
    if (bersaglio.isEmpty) {
      throw Exception('Seleziona il giocatore a cui si riferisce l\'infrazione!');
    }

    final String judge = effectiveJudge;
    if (judge.isEmpty) {
      throw Exception('Nessun Giudice neutrale disponibile tra i partecipanti per esaminare questa richiesta!');
    }

    final cleanDesc = descrizione.trim();
    if (cleanDesc.isEmpty) {
      throw Exception('Inserisci una breve descrizione dell\'accaduto!');
    }

    _isSubmitting = true;
    notifyListeners();

    try {
      final resId = await _apiService.inviaRichiestaVar(
        eventoId: evento.id,
        eventoTitolo: evento.titolo,
        tipo: isBonus ? 'bonus' : 'malus',
        bonusMalusId: bonusMalus.id,
        bonusMalusTitolo: bonusMalus.titolo,
        punti: bonusMalus.punti,
        richiedente: myNick,
        bersaglio: bersaglio,
        descrizione: cleanDesc,
        fotoBase64: _fotoBase64,
        testimoni: _selectedWitnesses.toList(),
        giudice: judge,
        penalitaPunti: evento.penalitaFalsaTestimonianza,
      );
      return resId;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}

class VarDetailViewModel extends BaseViewModel {
  final ApiService _apiService = ApiService();
  final String varId;

  RichiestaVar? _richiesta;
  Uint8List? _cachedPhotoBytes;
  bool _isProcessing = false;
  String? _decisioneScelta;
  bool _sanzionaFalsaTestimonianza = true;

  VarDetailViewModel(this.varId);

  RichiestaVar? get richiesta => _richiesta;
  Uint8List? get cachedPhotoBytes => _cachedPhotoBytes;
  bool get isProcessing => _isProcessing;
  String? get decisioneScelta => _decisioneScelta;
  bool get sanzionaFalsaTestimonianza => _sanzionaFalsaTestimonianza;
  String get currentUserNick => _apiService.currentUser?.nickname ?? '';

  void setSanzionaFalsaTestimonianza(bool value) {
    _sanzionaFalsaTestimonianza = value;
    notifyListeners();
  }

  Future<void> caricaRichiesta() async {
    setLoading(true);

    final req = await _apiService.getRichiestaVar(varId);
    Uint8List? bytes;
    if (req?.fotoBase64 != null && req!.fotoBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(req.fotoBase64!.split(',').last);
      } catch (_) {}
    }

    _richiesta = req;
    _cachedPhotoBytes = bytes;
    setLoading(false);
  }

  Future<bool> votaTestimonianza(bool conferma) async {
    final curUser = _apiService.currentUser;
    if (curUser == null || _richiesta == null) return false;

    _isProcessing = true;
    notifyListeners();

    try {
      final success = await _apiService.votaTestimonianzaVar(
        varId: varId,
        testimoneNick: curUser.nickname,
        conferma: conferma,
      );
      return success;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<bool> decidiRichiesta(bool approva) async {
    if (_isProcessing) return false;
    final curUser = _apiService.currentUser;
    if (curUser == null || _richiesta == null) return false;

    _isProcessing = true;
    _decisioneScelta = approva ? 'convalida' : 'respingi';
    notifyListeners();

    try {
      final success = await _apiService.decidiRichiestaVar(
        varId: varId,
        giudiceNick: curUser.nickname,
        approva: approva,
        sanzionaFalsaTestimonianza: !approva && _sanzionaFalsaTestimonianza,
      );
      return success;
    } finally {
      _isProcessing = false;
      _decisioneScelta = null;
      notifyListeners();
    }
  }
}
