import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'home_view.dart';
import '../widgets/app_toast.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  final _identifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Campi per la Registrazione
  final _nomeController = TextEditingController();
  final _cognomeController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();

  bool _obscureLoginPassword = true;
  bool _obscureRegPassword = true;
  bool _obscureRegConfirmPassword = true;
  bool _rememberMe = false;

  // Controllo disponibilità Nickname con debounce
  Timer? _nicknameDebounceTimer;
  bool _isCheckingNickname = false;
  bool? _isNicknameAvailable;
  List<String> _suggestedNicknames = [];
  String? _nicknameStatusMessage;

  bool _isRegisterMode = false;
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  void _showError(String message) {
    if (!mounted) return;
    AppToast.showError(
      context,
      'Attenzione',
      message.replaceAll('Exception: ', ''),
    );
  }

  void _onNicknameChanged(String value) {
    _nicknameDebounceTimer?.cancel();
    final trimmed = value.trim();

    if (trimmed.length < 3) {
      setState(() {
        _isCheckingNickname = false;
        _isNicknameAvailable = null;
        _suggestedNicknames = [];
        _nicknameStatusMessage = trimmed.isNotEmpty ? 'Almeno 3 caratteri richiesti' : null;
      });
      return;
    }

    setState(() {
      _isCheckingNickname = true;
      _nicknameStatusMessage = 'Controllo disponibilità...';
    });

    _nicknameDebounceTimer = Timer(const Duration(milliseconds: 1800), () async {
      final currentNick = _nicknameController.text.trim();
      if (currentNick.length < 3) return;

      final res = await _apiService.verificaDisponibilitaNickname(currentNick);

      if (!mounted) return;
      if (_nicknameController.text.trim() == currentNick) {
        setState(() {
          _isCheckingNickname = false;
          _isNicknameAvailable = res.disponibile;
          _nicknameStatusMessage = res.messaggio;
          _suggestedNicknames = res.suggerimenti;
        });
      }
    });
  }

  void _applyNicknameSuggestion(String suggested) {
    _nicknameDebounceTimer?.cancel();
    setState(() {
      _nicknameController.text = suggested;
      _nicknameController.selection = TextSelection.fromPosition(
        TextPosition(offset: suggested.length),
      );
      _isCheckingNickname = false;
      _isNicknameAvailable = true;
      _nicknameStatusMessage = 'Nome utente disponibile! ✨';
      _suggestedNicknames = [];
    });
  }

  Widget? _buildNicknameSuffix() {
    if (_isCheckingNickname) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9333EA)),
          ),
        ),
      );
    }
    if (_isNicknameAvailable == true) {
      return const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 22);
    }
    if (_isNicknameAvailable == false) {
      return const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 22);
    }
    return null;
  }

  // Handle Login Rigoroso con Password
  Future<void> _handleLogin() async {
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.login(
        _identifierController.text.trim(),
        _loginPasswordController.text,
        rememberMe: _rememberMe,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeView()),
      );
    } on NeedsPasswordSetupException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showPasswordSetupModal(e.username, e.email);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showError(e.toString());
    }
  }

  // Handle Registrazione Nuovo Utente in MongoDB Atlas con Password
  Future<void> _handleRegister() async {
    if (!(_registerFormKey.currentState?.validate() ?? false)) return;

    final nick = _nicknameController.text.trim();
    if (nick.length < 3) {
      _showError('Il nickname deve contenere almeno 3 caratteri.');
      return;
    }

    if (_isNicknameAvailable == false) {
      _showError('Il nickname "$nick" non è disponibile. Scegline un altro o usa uno dei suggerimenti proposti!');
      return;
    }

    final pass = _regPasswordController.text.trim();
    final confirmPass = _regConfirmPasswordController.text.trim();

    if (pass.length < 6) {
      _showError('La password deve contenere almeno 6 caratteri.');
      return;
    }

    if (pass != confirmPass) {
      _showError('Le password non coincidono! Controlla e riprova.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.registrazione(
        nome: _nomeController.text.trim(),
        cognome: _cognomeController.text.trim(),
        nickname: nick,
        email: _emailController.text.trim(),
        password: pass,
        rememberMe: _rememberMe,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeView()),
      );
    } on NicknameAlreadyTakenException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isNicknameAvailable = false;
        _nicknameStatusMessage = 'Nome utente già in uso! Prova uno di questi:';
        _suggestedNicknames = e.suggerimenti;
      });
      _showError('Il nickname "${e.nickname}" è già occupato! Scegli uno dei suggerimenti proposti.');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showError(e.toString());
    }
  }

  // Modale per il Primo Accesso degli utenti storici senza password
  void _showPasswordSetupModal(String username, String email) {
    final setupPassController = TextEditingController();
    final setupConfirmPassController = TextEditingController();
    bool obscureSetup1 = true;
    bool obscureSetup2 = true;
    bool setupRememberMe = _rememberMe;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF475569),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.shield_outlined, color: Color(0xFFFACC15), size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Benvenuto, $username! 👋',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Imposta la tua Password',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        'Abbiamo aggiornato la sicurezza di FantaEventi! Per proteggere il tuo profilo, i tuoi badge e tutti i tuoi punti, inserisci una password personale.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFFCBD5E1), height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: setupPassController,
                      obscureText: obscureSetup1,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nuova Password (minimo 6 caratteri)',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFACC15)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureSetup1 ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF64748B),
                          ),
                          onPressed: () => setModalState(() => obscureSetup1 = !obscureSetup1),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: setupConfirmPassController,
                      obscureText: obscureSetup2,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Conferma Nuova Password',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        prefixIcon: const Icon(Icons.lock_reset_outlined, color: Color(0xFFFACC15)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureSetup2 ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF64748B),
                          ),
                          onPressed: () => setModalState(() => obscureSetup2 = !obscureSetup2),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => setModalState(() => setupRememberMe = !setupRememberMe),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: setupRememberMe,
                                onChanged: (val) => setModalState(() => setupRememberMe = val ?? false),
                                activeColor: const Color(0xFFFACC15),
                                checkColor: const Color(0xFF0F172A),
                                side: const BorderSide(color: Color(0xFF64748B)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Mantieni l\'accesso su questo dispositivo',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: isSaving ? null : () async {
                        final p1 = setupPassController.text.trim();
                        final p2 = setupConfirmPassController.text.trim();

                        if (p1.length < 6) {
                          AppToast.showWarning(
                            context,
                            'Password troppo corta',
                            'La password deve contenere almeno 6 caratteri.',
                          );
                          return;
                        }

                        if (p1 != p2) {
                          AppToast.showWarning(
                            context,
                            'Password non coincidenti',
                            'Le password non coincidono! Controlla e riprova.',
                          );
                          return;
                        }

                        final nav = Navigator.of(context);
                        setModalState(() => isSaving = true);

                        try {
                          await _apiService.impostaPasswordPrimoAccesso(
                            username: username,
                            nuovaPassword: p1,
                            rememberMe: setupRememberMe,
                          );

                          if (!mounted) return;
                          Navigator.of(modalCtx).pop(); // Chiudi bottom sheet
                          nav.pushReplacement(
                            MaterialPageRoute(builder: (_) => const HomeView()),
                          );
                        } catch (err) {
                          setModalState(() => isSaving = false);
                          AppToast.showError(
                            context,
                            'Errore salvataggio',
                            err.toString().replaceAll('Exception: ', ''),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFFACC15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 2.5),
                            )
                          : Text(
                              'SALVA PASSWORD ED ENTRA',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                                letterSpacing: 0.8,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Modale di Recupero Password via Codice Email (OTP 6 cifre)
  void _showForgotPasswordModal() {
    final resetIdentController = TextEditingController(text: _identifierController.text.trim());
    final otpCodeController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmNewPassController = TextEditingController();

    int step = 1; // 1 = inserisci email/nickname, 2 = inserisci codice + nuova password
    bool isProcessing = false;
    bool obscureNew1 = true;
    bool obscureNew2 = true;
    String targetEmail = '';
    String maskedEmail = '';
    String detectedUsername = '';
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF475569),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            step == 1 ? Icons.mark_email_read_outlined : Icons.lock_reset,
                            color: const Color(0xFFFACC15),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step == 1 ? 'Password Dimenticata?' : 'Verifica e Nuova Password',
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                step == 1 ? 'Recupero account FantaEventi' : 'Inserisci il codice a 6 cifre',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (modalError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          modalError!,
                          style: GoogleFonts.inter(color: const Color(0xFFFCA5A5), fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (step == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          'Inserisci il tuo Nickname o l\'Email con cui ti sei registrato. Ti invieremo un codice di verifica a 6 cifre per reimpostare la tua password in totale sicurezza.',
                          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFFCBD5E1), height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: resetIdentController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Nickname o Email',
                          hintText: 'Es. Cloud oppure claudio.simonelli28@...',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.person_search_outlined, color: Color(0xFFFACC15)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isProcessing ? null : () async {
                          final ident = resetIdentController.text.trim();
                          if (ident.isEmpty) {
                            setModalState(() => modalError = 'Inserisci il tuo Nickname o la tua Email.');
                            return;
                          }

                          setModalState(() {
                            isProcessing = true;
                            modalError = null;
                          });

                          try {
                            final res = await _apiService.richiediCodiceReset(ident);
                            setModalState(() {
                              isProcessing = false;
                              step = 2;
                              targetEmail = res['email'] ?? '';
                              maskedEmail = res['maskedEmail'] ?? res['email'] ?? '';
                              detectedUsername = res['username'] ?? '';
                            });
                          } catch (e) {
                            setModalState(() {
                              isProcessing = false;
                              modalError = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFFACC15), Color(0xFFEAB308)]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(minHeight: 50),
                            child: isProcessing
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0F172A)),
                                  )
                                : Text(
                                    'Invia Codice di Verifica 📩',
                                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                  ),
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFFCBD5E1), height: 1.4),
                            children: [
                              const TextSpan(text: 'Abbiamo inviato un codice di sicurezza a 6 cifre a: '),
                              TextSpan(
                                text: maskedEmail,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFACC15)),
                              ),
                              const TextSpan(text: '.\nInseriscilo qui sotto assieme alla tua nuova password (scade tra 15 minuti).'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: otpCodeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: GoogleFonts.poppins(
                          color: const Color(0xFFFACC15),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: 'Codice OTP (6 cifre)',
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, letterSpacing: 0),
                          prefixIcon: const Icon(Icons.pin_outlined, color: Color(0xFFFACC15)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newPassController,
                        obscureText: obscureNew1,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Nuova Password (minimo 6 caratteri)',
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFACC15)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureNew1 ? Icons.visibility_off : Icons.visibility,
                              color: const Color(0xFF64748B),
                            ),
                            onPressed: () => setModalState(() => obscureNew1 = !obscureNew1),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmNewPassController,
                        obscureText: obscureNew2,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Conferma Nuova Password',
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: const Icon(Icons.lock_reset_outlined, color: Color(0xFFFACC15)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureNew2 ? Icons.visibility_off : Icons.visibility,
                              color: const Color(0xFF64748B),
                            ),
                            onPressed: () => setModalState(() => obscureNew2 = !obscureNew2),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isProcessing ? null : () async {
                          final code = otpCodeController.text.trim();
                          final p1 = newPassController.text.trim();
                          final p2 = confirmNewPassController.text.trim();

                          if (code.length != 6) {
                            setModalState(() => modalError = 'Il codice di verifica deve essere di 6 cifre.');
                            return;
                          }

                          if (p1.length < 6) {
                            setModalState(() => modalError = 'La password deve contenere almeno 6 caratteri.');
                            return;
                          }

                          if (p1 != p2) {
                            setModalState(() => modalError = 'Le due password non coincidono! Controlla e riprova.');
                            return;
                          }

                          setModalState(() {
                            isProcessing = true;
                            modalError = null;
                          });

                          try {
                            await _apiService.confermaCodiceEReset(
                              email: targetEmail,
                              codice: code,
                              nuovaPassword: p1,
                            );

                            if (!mounted) return;
                            if (modalCtx.mounted) {
                              Navigator.of(modalCtx).pop();
                            }


                            if (detectedUsername.isNotEmpty) {
                              _identifierController.text = detectedUsername;
                            }
                            _loginPasswordController.text = p1;

                            AppToast.showSuccess(
                              context,
                              'Password Aggiornata 🎉',
                              'Password aggiornata con successo! Ora puoi accedere.',
                            );
                          } catch (e) {
                            setModalState(() {
                              isProcessing = false;
                              modalError = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFFACC15), Color(0xFFEAB308)]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(minHeight: 50),
                            child: isProcessing
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0F172A)),
                                  )
                                : Text(
                                    'Reimposta Password 🔒',
                                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: isProcessing ? null : () => setModalState(() {
                            step = 1;
                            modalError = null;
                          }),
                          child: Text(
                            'Non hai ricevuto l\'email? Riprova',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  @override
  void dispose() {
    _nicknameDebounceTimer?.cancel();
    _identifierController.dispose();
    _loginPasswordController.dispose();
    _nomeController.dispose();
    _cognomeController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Logo con Icona Ufficiale FantaEventi
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFACC15), Color(0xFF9333EA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF9333EA).withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icon/app_icon.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'FantaEventi',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.4), width: 1),
                  ),
                  child: Text(
                    '🏆 Trasforma ogni serata con i tuoi amici in una sfida epica! ✨',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFACC15),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isRegisterMode
                      ? 'Crea il tuo profilo e inizia a scalare la classifica!'
                      : 'Inserisci il tuo Nickname o Email per entrare in gioco',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),

                // Form Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF334155),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    crossFadeState: _isRegisterMode ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: Form(
                      key: _loginFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Accedi con il tuo Account',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),

                          TextFormField(
                            controller: _identifierController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Nickname o Email',
                              hintText: 'Es. mario_rossi oppure utente@email.it',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFFACC15)),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Inserisci il tuo Nickname o Email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _loginPasswordController,
                            obscureText: _obscureLoginPassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Inserisci la tua password',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFACC15)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureLoginPassword ? Icons.visibility_off : Icons.visibility,
                                  color: const Color(0xFF64748B),
                                ),
                                onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              InkWell(
                                onTap: () => setState(() => _rememberMe = !_rememberMe),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          onChanged: (val) => setState(() => _rememberMe = val ?? false),

                                          activeColor: const Color(0xFFFACC15),
                                          checkColor: const Color(0xFF0F172A),
                                          side: const BorderSide(color: Color(0xFF64748B)),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Ricordami',
                                        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFFCBD5E1)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _showForgotPasswordModal,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Password dimenticata?',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFFACC15),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),


                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ).copyWith(
                              elevation: WidgetStateProperty.all(0),
                            ),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFACC15), Color(0xFFEAB308)],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Container(
                                alignment: Alignment.center,
                                constraints: const BoxConstraints(minHeight: 52),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Color(0xFF0F172A))
                                    : Text(
                                        'ENTRA IN GIOCO',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F172A),
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    secondChild: Form(
                      key: _registerFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Registrazione Nuovo Utente',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _nomeController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Nome',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFFFACC15)),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Inserisci il nome' : null,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _cognomeController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Cognome',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFFFACC15)),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _nicknameController,
                            onChanged: _onNicknameChanged,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Nickname di Gioco (min. 3 caratteri)',
                              hintText: 'Es. MarioRossi, Bomber99, SuperFanta...',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.stars_rounded, color: Color(0xFF9333EA)),
                              suffixIcon: _buildNicknameSuffix(),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _isNicknameAvailable == true
                                      ? const Color(0xFF22C55E).withValues(alpha: 0.7)
                                      : (_isNicknameAvailable == false
                                          ? const Color(0xFFEF4444).withValues(alpha: 0.7)
                                          : Colors.transparent),
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _isNicknameAvailable == true
                                      ? const Color(0xFF22C55E)
                                      : (_isNicknameAvailable == false
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF9333EA)),
                                  width: 1.8,
                                ),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Inserisci il nickname';
                              if (val.trim().length < 3) return 'Il nickname deve contenere almeno 3 caratteri';
                              if (_isNicknameAvailable == false) return 'Nome utente già in uso';
                              return null;
                            },
                          ),
                          if (_nicknameStatusMessage != null) ...[
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    _isNicknameAvailable == true
                                        ? Icons.check_circle_outline
                                        : (_isNicknameAvailable == false ? Icons.warning_amber_rounded : Icons.info_outline),
                                    size: 15,
                                    color: _isNicknameAvailable == true
                                        ? const Color(0xFF22C55E)
                                        : (_isNicknameAvailable == false ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _nicknameStatusMessage!,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: _isNicknameAvailable == true
                                            ? const Color(0xFF22C55E)
                                            : (_isNicknameAvailable == false ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_suggestedNicknames.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.auto_awesome, color: Color(0xFFFACC15), size: 15),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Suggeriti per te (tocca per scegliere):',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFFACC15),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _suggestedNicknames.map((suggerito) {
                                      return ActionChip(
                                        backgroundColor: const Color(0xFF9333EA).withValues(alpha: 0.25),
                                        side: const BorderSide(color: Color(0xFF9333EA)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        avatar: const Icon(Icons.touch_app_outlined, size: 15, color: Color(0xFFD8B4FE)),
                                        label: Text(
                                          suggerito,
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        onPressed: () => _applyNicknameSuggestion(suggerito),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Indirizzo Email',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFFFACC15)),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty || !val.contains('@') ? 'Email non valida' : null,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _regPasswordController,
                            obscureText: _obscureRegPassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Password (minimo 6 caratteri)',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFACC15)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureRegPassword ? Icons.visibility_off : Icons.visibility,
                                  color: const Color(0xFF64748B),
                                ),
                                onPressed: () => setState(() => _obscureRegPassword = !_obscureRegPassword),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Inserisci una password';
                              if (val.trim().length < 6) return 'Almeno 6 caratteri';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _regConfirmPasswordController,
                            obscureText: _obscureRegConfirmPassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Conferma Password',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.lock_reset_outlined, color: Color(0xFFFACC15)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureRegConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                  color: const Color(0xFF64748B),
                                ),
                                onPressed: () => setState(() => _obscureRegConfirmPassword = !_obscureRegConfirmPassword),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Conferma la password';
                              if (val.trim() != _regPasswordController.text.trim()) return 'Le password non coincidono';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          InkWell(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      onChanged: (val) => setState(() => _rememberMe = val ?? false),
                                      activeColor: const Color(0xFF9333EA),
                                      checkColor: Colors.white,
                                      side: const BorderSide(color: Color(0xFF64748B)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Mantieni l\'accesso',
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ).copyWith(
                              elevation: WidgetStateProperty.all(0),
                            ),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF9333EA), Color(0xFF7E22CE)],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Container(
                                alignment: Alignment.center,
                                constraints: const BoxConstraints(minHeight: 52),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                        'REGISTRATI A FANTAEVENTI',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Switcher per Registrazione
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isRegisterMode = !_isRegisterMode;
                      _nicknameDebounceTimer?.cancel();
                      _isCheckingNickname = false;
                      _isNicknameAvailable = null;
                      _suggestedNicknames = [];
                      _nicknameStatusMessage = null;
                    });
                  },
                  child: Text(
                    _isRegisterMode
                        ? 'Hai già un account? Accedi col tuo Nickname'
                        : 'Non sei ancora registrato? Registrati qui!',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFACC15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
