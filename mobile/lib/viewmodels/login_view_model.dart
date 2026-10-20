import 'dart:async';
import 'package:flutter/material.dart';
import '../models/utente.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import 'base_view_model.dart';

/// ViewModel dedicato alla schermata di Login e Registrazione (MVVM).
///
/// Separa completamente:
/// - Logiche di autenticazione e registrazione
/// - Verifica della disponibilità del nickname con debounce
/// - Gestione visibilità password e stato "Ricordami"
/// - Reset password e primo accesso utenti storici
/// - Sincronizzazione dei token push FCM post-login
class LoginViewModel extends BaseViewModel {
  final ApiService _apiService;
  final PushNotificationService _pushService;

  LoginViewModel({
    ApiService? apiService,
    PushNotificationService? pushService,
  })  : _apiService = apiService ?? ApiService(),
        _pushService = pushService ?? PushNotificationService.instance;

  // --- STATO VISTA ---
  bool _isRegisterMode = false;
  bool _rememberMe = true;
  bool _obscureLoginPassword = true;
  bool _obscureRegPassword = true;
  bool _obscureRegConfirmPassword = true;

  // --- CONTROLLO NICKNAME (DEBOUNCE) ---
  Timer? _nicknameDebounceTimer;
  bool _isCheckingNickname = false;
  bool? _isNicknameAvailable;
  List<String> _suggestedNicknames = [];
  String? _nicknameStatusMessage;

  // --- GETTER STATO ---
  bool get isRegisterMode => _isRegisterMode;
  bool get rememberMe => _rememberMe;
  bool get obscureLoginPassword => _obscureLoginPassword;
  bool get obscureRegPassword => _obscureRegPassword;
  bool get obscureRegConfirmPassword => _obscureRegConfirmPassword;

  bool get isCheckingNickname => _isCheckingNickname;
  bool? get isNicknameAvailable => _isNicknameAvailable;
  List<String> get suggestedNicknames => List.unmodifiable(_suggestedNicknames);
  String? get nicknameStatusMessage => _nicknameStatusMessage;

  // --- TOGGLE AZIONI UI ---
  void toggleMode() {
    _isRegisterMode = !_isRegisterMode;
    _resetNicknameStatus();
    notifyListeners();
  }

  void setRememberMe(bool value) {
    if (_rememberMe == value) return;
    _rememberMe = value;
    notifyListeners();
  }

  void toggleObscureLoginPassword() {
    _obscureLoginPassword = !_obscureLoginPassword;
    notifyListeners();
  }

  void toggleObscureRegPassword() {
    _obscureRegPassword = !_obscureRegPassword;
    notifyListeners();
  }

  void toggleObscureRegConfirmPassword() {
    _obscureRegConfirmPassword = !_obscureRegConfirmPassword;
    notifyListeners();
  }

  void _resetNicknameStatus() {
    _nicknameDebounceTimer?.cancel();
    _isCheckingNickname = false;
    _isNicknameAvailable = null;
    _suggestedNicknames = [];
    _nicknameStatusMessage = null;
  }

  // --- LOGICA NICKNAME DEBOUNCE ---
  void onNicknameChanged(String value, TextEditingController controller) {
    _nicknameDebounceTimer?.cancel();
    final trimmed = value.trim();

    if (trimmed.length < 3) {
      _isCheckingNickname = false;
      _isNicknameAvailable = null;
      _suggestedNicknames = [];
      _nicknameStatusMessage = trimmed.isNotEmpty ? 'Almeno 3 caratteri richiesti' : null;
      notifyListeners();
      return;
    }

    _isCheckingNickname = true;
    _nicknameStatusMessage = 'Controllo disponibilità...';
    notifyListeners();

    _nicknameDebounceTimer = Timer(const Duration(milliseconds: 1800), () async {
      final currentNick = controller.text.trim();
      if (currentNick.length < 3) return;

      try {
        final res = await _apiService.verificaDisponibilitaNickname(currentNick);
        if (isDisposed) return;

        if (controller.text.trim() == currentNick) {
          _isCheckingNickname = false;
          _isNicknameAvailable = res.disponibile;
          _nicknameStatusMessage = res.messaggio;
          _suggestedNicknames = res.suggerimenti;
          notifyListeners();
        }
      } catch (_) {
        if (isDisposed) return;
        _isCheckingNickname = false;
        notifyListeners();
      }
    });
  }

  void applyNicknameSuggestion(String suggested, TextEditingController controller) {
    _nicknameDebounceTimer?.cancel();
    controller.text = suggested;
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: suggested.length),
    );
    _isCheckingNickname = false;
    _isNicknameAvailable = true;
    _nicknameStatusMessage = 'Nome utente disponibile! ✨';
    _suggestedNicknames = [];
    notifyListeners();
  }

  // --- AZIONE LOGIN ---
  Future<Utente> login({
    required String identifier,
    required String password,
  }) async {
    clearError();
    setLoading(true);

    try {
      final utente = await _apiService.login(
        identifier.trim(),
        password,
        rememberMe: _rememberMe,
      );

      // Sincronizza il token FCM del dispositivo per il nuovo login
      await _pushService.syncCurrentDeviceToken();

      setLoading(false);
      return utente;
    } on NeedsPasswordSetupException {
      setLoading(false);
      rethrow;
    } catch (e) {
      setLoading(false);
      setError(e.toString().replaceAll('Exception: ', ''));
      rethrow;
    }
  }

  // --- AZIONE REGISTRAZIONE ---
  Future<Utente> register({
    required String nome,
    required String cognome,
    required String nickname,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    clearError();

    final cleanNick = nickname.trim();
    if (cleanNick.length < 3) {
      final err = 'Il nickname deve contenere almeno 3 caratteri.';
      setError(err);
      throw Exception(err);
    }

    if (_isNicknameAvailable == false) {
      final err = 'Il nickname "$cleanNick" non è disponibile. Scegline un altro o usa uno dei suggerimenti proposti!';
      setError(err);
      throw Exception(err);
    }

    final cleanPass = password.trim();
    final cleanConfirmPass = confirmPassword.trim();

    if (cleanPass.length < 6) {
      final err = 'La password deve contenere almeno 6 caratteri.';
      setError(err);
      throw Exception(err);
    }

    if (cleanPass != cleanConfirmPass) {
      final err = 'Le password non coincidono! Controlla e riprova.';
      setError(err);
      throw Exception(err);
    }

    setLoading(true);

    try {
      final nuovoUtente = await _apiService.registrazione(
        nome: nome.trim(),
        cognome: cognome.trim(),
        nickname: cleanNick,
        email: email.trim(),
        password: cleanPass,
        rememberMe: _rememberMe,
      );

      // Sincronizza il token FCM per la ricezione notifiche
      await _pushService.syncCurrentDeviceToken();

      setLoading(false);
      return nuovoUtente;
    } on NicknameAlreadyTakenException catch (e) {
      setLoading(false);
      _isNicknameAvailable = false;
      _nicknameStatusMessage = 'Nome utente già in uso! Prova uno di questi:';
      _suggestedNicknames = e.suggerimenti;
      setError('Il nickname "${e.nickname}" è già occupato! Scegli uno dei suggerimenti proposti.');
      notifyListeners();
      rethrow;
    } catch (e) {
      setLoading(false);
      setError(e.toString().replaceAll('Exception: ', ''));
      rethrow;
    }
  }

  // --- IMPOSTAZIONE PASSWORD PRIMO ACCESSO ---
  Future<Utente> impostaPasswordPrimoAccesso({
    required String username,
    required String nuovaPassword,
    required bool rememberMe,
  }) async {
    final cleanPass = nuovaPassword.trim();
    if (cleanPass.length < 6) {
      throw Exception('La password deve contenere almeno 6 caratteri.');
    }

    final utente = await _apiService.impostaPasswordPrimoAccesso(
      username: username,
      nuovaPassword: cleanPass,
      rememberMe: rememberMe,
    );

    await _pushService.syncCurrentDeviceToken();
    return utente;
  }

  // --- RECUPERO PASSWORD (OTP) ---
  Future<Map<String, dynamic>> richiediCodiceReset(String identifier) async {
    final clean = identifier.trim();
    if (clean.isEmpty) {
      throw Exception('Inserisci il tuo Nickname o la tua Email.');
    }
    return await _apiService.richiediCodiceReset(clean);
  }

  Future<void> confermaCodiceEReset({
    required String email,
    required String codice,
    required String nuovaPassword,
  }) async {
    final cleanCode = codice.trim();
    final cleanPass = nuovaPassword.trim();

    if (cleanCode.length != 6) {
      throw Exception('Il codice di verifica deve essere di 6 cifre.');
    }
    if (cleanPass.length < 6) {
      throw Exception('La password deve contenere almeno 6 caratteri.');
    }

    await _apiService.confermaCodiceEReset(
      email: email,
      codice: cleanCode,
      nuovaPassword: cleanPass,
    );
  }

  @override
  void dispose() {
    _nicknameDebounceTimer?.cancel();
    super.dispose();
  }
}
