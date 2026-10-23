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
  bool get isBonus => bonusMalus.punti > 0;

  void _initDefaults() {
    if (isOrganizer) {
      final eligibleJudges = evento.partecipanti
          .where((p) => !isMe(p))
          .toList();
      if (eligibleJudges.isNotEmpty) {
        _selectedJudge = eligibleJudges.first;
      }
    }

    if (bonusMalus.punti < 0) {
      final eligibleCulprits = evento.partecipanti
          .where((p) => !isMe(p))
          .toList();
      if (eligibleCulprits.isNotEmpty) {
        _selectedCulprit = eligibleCulprits.first;
      }
    }
  }

  void selectCulprit(String? culprit) {
    _selectedCulprit = culprit;
    notifyListeners();
  }

  void selectJudge(String? judge) {
    _selectedJudge = judge;
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

    final String judge = isOrganizer ? (_selectedJudge ?? '') : evento.creatore;
    if (judge.isEmpty) {
      throw Exception('Seleziona un Co-Organizzatore che farà da Giudice!');
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
