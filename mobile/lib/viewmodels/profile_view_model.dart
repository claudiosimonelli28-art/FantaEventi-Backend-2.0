import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/utente.dart';
import '../services/api_service.dart';
import '../widgets/avatar_helper.dart';
import 'base_view_model.dart';

/// ViewModel dedicato alla schermata Profilo Utente e Bacheca Badge (MVVM).
///
/// Separa completamente:
/// - Recupero e sincronizzazione dello stato utente e badge
/// - Gestione conteggio titoli in bacheca
/// - Scatto fotocamera e selezione da galleria con conversione base64
/// - Gestione codice amico e invio richieste di amicizia
/// - Stato del completamento del tutorial e premio XP
/// - Filtro temporale dello storico attività
class ProfileViewModel extends BaseViewModel {
  final ApiService _apiService;
  final ImagePicker _picker;

  ProfileViewModel({
    ApiService? apiService,
    ImagePicker? picker,
  })  : _apiService = apiService ?? ApiService(),
        _picker = picker ?? ImagePicker();

  late Utente _utente;
  File? _fotoLocaleFile;
  int _filtroGiorniStorico = 7;
  int _countCampione = 0;
  int _countReMalus = 0;
  int _countAvvocato = 0;
  int _countFantasma = 0;
  int _countSbirro = 0;
  int _countGiustiziere = 0;
  bool _haGiaRiscattatoPremio = false;

  final List<String> _avatarsPredefiniti = const [
    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1580489944761-15a19d654956?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1628157582853-a796fa650a6a?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80',
  ];

  // --- GETTER STATO ---
  Utente get utente => _utente;
  File? get fotoLocaleFile => _fotoLocaleFile;
  int get filtroGiorniStorico => _filtroGiorniStorico;
  int get countCampione => _countCampione;
  int get countReMalus => _countReMalus;
  int get countAvvocato => _countAvvocato;
  int get countFantasma => _countFantasma;
  int get countSbirro => _countSbirro;
  int get countGiustiziere => _countGiustiziere;
  bool get haGiaRiscattatoPremio => _haGiaRiscattatoPremio;
  List<String> get avatarsPredefiniti => _avatarsPredefiniti;

  double get xpPercent =>
      (_utente.xp / (_utente.xpProssimoLivello == 0 ? 1 : _utente.xpProssimoLivello)).clamp(0.0, 1.0);

  List<String> get storicoFiltrato =>
      ApiService.filtraStorico(_utente.storicoVoti, maxGiorni: _filtroGiorniStorico);

  ImageProvider get currentAvatarImage {
    return _fotoLocaleFile != null && _fotoLocaleFile!.existsSync()
        ? FileImage(_fotoLocaleFile!)
        : getAvatarImageProvider(_utente.avatarUrl);
  }

  String get rankTitle {
    final livello = _utente.livello;
    if (livello >= 10) return '👑 Leggenda Suprema degli Eventi';
    if (livello >= 7) return '🔥 Master Gamifier';
    if (livello >= 5) return '⚡ Anima della Festa';
    if (livello >= 3) return '🎲 Giocatore Esperto';
    return '🌱 Recluta Fanta Eventi';
  }

  // --- INIZIALIZZAZIONE ---
  void inizializza() {
    _utente = _apiService.currentUser ?? _apiService.getCurrentUser();
    _haGiaRiscattatoPremio = _apiService.hasRedeemedTutorialLocally;
    _aggiornaConteggiTitoli(_utente);
    caricaProfiloAggiornato();
  }

  void _aggiornaConteggiTitoli(Utente u) {
    _countCampione = u.countCampione;
    _countReMalus = u.countReMalus;
    _countAvvocato = u.countAvvocato;
    _countFantasma = u.countFantasma;
    _countSbirro = u.countSbirro;
    _countGiustiziere = u.countGiustiziere;
  }

  Future<void> caricaProfiloAggiornato() async {
    try {
      final updatedUser = await _apiService.syncCurrentUserFromDb();
      final bool giaRiscattato = await _apiService.haGiaRiscattatoPremioTutorial();
      if (isDisposed) return;

      if (updatedUser != null) {
        _utente = updatedUser;
        _aggiornaConteggiTitoli(_utente);
      }
      _haGiaRiscattatoPremio = giaRiscattato || _apiService.hasRedeemedTutorialLocally;
      notifyListeners();

      await _apiService.getUtenti();
      if (isDisposed) return;
      notifyListeners();
    } catch (_) {}
  }

  void setFiltroGiorniStorico(int giorni) {
    if (_filtroGiorniStorico == giorni) return;
    _filtroGiorniStorico = giorni;
    notifyListeners();
  }

  // --- AMICIZIA ---
  Future<void> inviaRichiestaAmicizia(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return;

    clearError();
    try {
      await _apiService.inviaRichiestaAmicizia(cleanCode);
    } catch (e) {
      setError(e.toString().replaceAll('Exception: ', ''));
      rethrow;
    }
  }

  Utente? getUtenteInMemoria(String nickname) => _apiService.getUtenteInMemoria(nickname);

  String getAvatarPerUtente(String nickname) => _apiService.getAvatarPerUtente(nickname);

  // --- GESTIONE FOTO AVATAR ---
  Future<bool> scattaFotoConFotocamera() async {
    clearError();
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final base64String = 'data:image/png;base64,${base64Encode(bytes)}';
        _fotoLocaleFile = File(photo.path);
        _utente = _utente.copyWith(avatarUrl: base64String);
        notifyListeners();

        await _apiService.aggiornaAvatarUtente(_utente.nickname, base64String);
        return true;
      }
      return false;
    } catch (e) {
      setError('Impossibile scattare o salvare la foto: $e');
      rethrow;
    }
  }

  Future<bool> scegliFotoDaGalleria() async {
    clearError();
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64String = 'data:image/png;base64,${base64Encode(bytes)}';
        _fotoLocaleFile = File(image.path);
        _utente = _utente.copyWith(avatarUrl: base64String);
        notifyListeners();

        await _apiService.aggiornaAvatarUtente(_utente.nickname, base64String);
        return true;
      }
      return false;
    } catch (e) {
      setError('Impossibile caricare o salvare la foto: $e');
      rethrow;
    }
  }

  Future<void> impostaAvatarUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    clearError();
    _fotoLocaleFile = null;
    _utente = _utente.copyWith(avatarUrl: cleanUrl);
    notifyListeners();

    try {
      await _apiService.aggiornaAvatarUtente(_utente.nickname, cleanUrl);
    } catch (e) {
      setError('Impossibile aggiornare l\'avatar: $e');
      rethrow;
    }
  }

  // --- TUTORIAL & GUIDA ---
  Future<void> concludiTutorial({required bool giaRiscattato}) async {
    _haGiaRiscattatoPremio = true;
    notifyListeners();

    try {
      await _apiService.segnaGuidaRegoleCompletata(awardXp: !giaRiscattato);
      await caricaProfiloAggiornato();
    } catch (_) {}
  }

  Future<void> saltaTutorialDefinitivamente() async {
    try {
      await _apiService.segnaGuidaRegoleCompletata(awardXp: false);
      _utente = _utente.copyWith(haVistoGuida: true);
      notifyListeners();
    } catch (_) {}
  }

  // --- LOGOUT ---
  Future<void> logout() async {
    await _apiService.logout();
  }

  // --- ELIMINAZIONE ACCOUNT ---
  Future<bool> eliminaAccount() async {
    setLoading(true);
    try {
      final success = await _apiService.eliminaAccount(
        utenteId: _utente.id,
        nickname: _utente.nickname,
        nome: _utente.nome,
      );
      return success;
    } finally {
      setLoading(false);
    }
  }
}
