import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/founder_badge.dart';
import 'login_view.dart';
import '../viewmodels/profile_view_model.dart';
import '../services/tutorial_controller.dart';
import '../widgets/tutorial_spotlight_overlay.dart';
import '../widgets/app_toast.dart';
import '../widgets/context_info_modal.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final ProfileViewModel _viewModel = ProfileViewModel();
  final _codiceAmicoInputController = TextEditingController();
  bool _isLoggingOut = false;

  Future<void> _eseguiLogout([BuildContext? modalContext]) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    if (modalContext != null && modalContext.mounted) {
      Navigator.of(modalContext).pop();
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF6366F1)),
                const SizedBox(height: 18),
                Text(
                  'Disconnessione in corso...',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        ),
      );
    }

    try {
      await _viewModel.logout();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _viewModel.inizializza();
  }

  @override
  void dispose() {
    _codiceAmicoInputController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _inviaRichiestaAmicizia() async {
    final code = _codiceAmicoInputController.text.trim();
    if (code.isEmpty) return;

    try {
      await _viewModel.inviaRichiestaAmicizia(code);
      _codiceAmicoInputController.clear();
      if (!mounted) return;
      AppToast.showSuccess(
        context,
        'Richiesta Inviata 👥',
        'Richiesta di amicizia inviata con successo!',
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.showError(
        context,
        'Errore invio richiesta',
        e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  void _concludiTutorial() async {
    final bool giaRiscattato = _viewModel.haGiaRiscattatoPremio || ApiService().hasRedeemedTutorialLocally;
    final int userLevel = _viewModel.utente.livello;
    final String badgeAwarded = userLevel >= 2 ? '🎓 Pioniero FantaEventi' : '🌱 Recluta FantaEventi';

    // 1. Rimuovi il banner immediatamente: zero attese
    TutorialController.instance.completeTutorial(context);

    // 2. Salva in background senza bloccare la UI tramite ViewModel
    _viewModel.concludiTutorial(giaRiscattato: giaRiscattato);

    // 3. Mostra subito la modale celebrativa
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFFACC15), width: 2),
        ),
        title: Column(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
            Text(
              'TUTORIAL COMPLETATO!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: const Color(0xFFFACC15),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              giaRiscattato
                  ? 'Ottimo ripasso! Conosci tutte le funzionalità principali di FantaEventi:'
                  : 'Fantastico! Ora conosci tutte le meccaniche di FantaEventi:',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF9333EA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Text('Creazione Eventi & Regole', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Text('Votazioni Live & Quorum', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Text('Centro Notifiche & Inviti', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Text('Foto Selfie & Codice Amico', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  const Divider(color: Color(0xFF334155), height: 16),
                  Text(
                    giaRiscattato ? 'BADGE CONFERMATO AL PROFILO:' : 'BADGE SPECIALE SBLOCCATO:',
                    style: GoogleFonts.poppins(fontSize: 10, color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(badgeAwarded, style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    giaRiscattato
                        ? 'ℹ️ Premio di +100 XP già riscosso in precedenza'
                        : '+100 Punti XP Aggiunti al tuo Profilo! 🚀',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: giaRiscattato ? const Color(0xFF94A3B8) : const Color(0xFF38BDF8),
                      fontWeight: giaRiscattato ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                foregroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'INIZIA A GIOCARE! 🚀',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialIncompletoCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFACC15).withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎓', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'TUTORIAL NON COMPLETATO',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFFACC15),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: Text(
                  'IN SOSPESO',
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Non hai ancora terminato il tutorial guidato! Completalo per scoprire tutte le funzionalità di gioco e ritirare subito il tuo premio di +100 XP e il badge Pioniero.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFFCBD5E1),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _riprendiTutorial,
                  icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF0F172A), size: 22),
                  label: Text(
                    'RIPRENDI IL TUTORIAL',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () async {
                TutorialController.instance.skipTutorial();
                await _viewModel.saltaTutorialDefinitivamente();
              },
              child: Text(
                'Salta tutorial definitivamente',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF94A3B8),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _riprendiTutorial() async {
    final savedStage = await TutorialController.instance.getSavedStage();
    if (savedStage == TutorialStage.step10_in_profile) {
      TutorialController.instance.setStage(TutorialStage.step10_in_profile);
      if (mounted) setState(() {});
    } else {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  // MODALE CON LA LISTA COMPLETA DEGLI AMICI
  void _mostraModalAmici() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            final amiciList = _viewModel.utente.amici;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('👥', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Text(
                            'I Tuoi Amici (${amiciList.length})',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                  Text(
                    'Elenco completo dei tuoi compagni e dettagli del loro profilo',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: amiciList.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.people_outline_rounded, size: 48, color: Color(0xFF64748B)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nessun amico ancora aggiunto',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Condividi il tuo Codice Amico per collegarti con i tuoi amici!',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: amiciList.length,
                            itemBuilder: (context, index) {
                              final amicoNick = amiciList[index];
                              final amicoUtente = _viewModel.getUtenteInMemoria(amicoNick);
                              final displayName = (amicoUtente?.nome.isNotEmpty == true)
                                  ? amicoUtente!.nome
                                  : amicoNick;
                              final avatarUrl = (amicoUtente?.avatarUrl.isNotEmpty == true) ? amicoUtente!.avatarUrl : _viewModel.getAvatarPerUtente(amicoNick);
                              final friendCode = amicoUtente?.codiceAmico ?? '';
                              final points = amicoUtente?.puntiTotali ?? 0;
                              final level = amicoUtente?.livello ?? 1;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.6),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 22,
                                        backgroundImage: getAvatarImageProvider(avatarUrl),
                                        backgroundColor: const Color(0xFF334155),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  displayName,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.poppins(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              if (FounderBadge.isFounder(amicoNick) || FounderBadge.isFounder(displayName)) ...[
                                                const SizedBox(width: 8),
                                                FounderBadge(nickname: amicoNick, isLarge: false),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1E293B),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Liv. $level',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(0xFFFACC15),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '$points PT',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFF10B981),
                                                ),
                                              ),
                                              if (friendCode.isNotEmpty) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '• $friendCode',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: const Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // MODALE CON LA BACHECA VITTORIE / SALA TROFEI
  void _mostraModalVittorie() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            final vittorie = _viewModel.utente.badgeVincitore;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('🏆', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Text(
                            'Sala Trofei (${vittorie.length})',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                  Text(
                    'Tutti gli eventi in cui hai conquistato il 1° posto',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: vittorie.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.emoji_events_outlined, size: 48, color: Color(0xFF64748B)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nessun trofeo conquistato al momento',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Conquista il primo posto nei tuoi prossimi eventi per arricchire la tua sala trofei!',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: vittorie.length,
                            itemBuilder: (context, index) {
                              final b = vittorie[index];
                              final evName = b['evento'] ?? 'Evento';
                              final pts = b['punti'] ?? 0;
                              String dataStr = '';
                              if (b['data'] != null) {
                                try {
                                  final dt = DateTime.parse(b['data'].toString());
                                  dataStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                                } catch (_) {}
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFACC15), Color(0xFFB45309)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.emoji_events_rounded, color: Color(0xFF0F172A), size: 28),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '1° POSTO: $evName',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Punti: $pts PT',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                                                ),
                                              ),
                                              if (dataStr.isNotEmpty)
                                                Text(
                                                  dataStr,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: const Color(0xFF0F172A).withValues(alpha: 0.75),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // MODALE CON LA LISTA COMPLETA DEI BADGE SBLOCCATI
  void _mostraModalBadge() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            final badges = _viewModel.utente.badgeList;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('🎖️', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Text(
                            'Badge Sbloccati (${badges.length})',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                  Text(
                    'Tutti i badge e le partecipazioni agli eventi della tua carriera',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: badges.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.military_tech_outlined, size: 48, color: Color(0xFF64748B)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nessun badge sbloccato',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Partecipa ai tuoi primi eventi per sbloccare i tuoi badge ufficiali!',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: badges.length,
                            itemBuilder: (context, index) {
                              final badge = badges[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFFACC15).withValues(alpha: 0.4),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFACC15).withValues(alpha: 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.stars_rounded, color: Color(0xFFFACC15), size: 24),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        badge,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // APRE LA VERA FOTOCAMERA FISICA DEL TELEFONO
  Future<void> _scattaFotoConFotocamera() async {
    try {
      final success = await _viewModel.scattaFotoConFotocamera();
      if (success && mounted) {
        AppToast.showSuccess(
          context,
          'Foto Salvata 📸',
          'Foto avatar salvata con successo nel tuo profilo!',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.showError(
        context,
        'Errore Fotocamera',
        'Impossibile scattare o salvare la foto: $e',
      );
    }
  }

  // APRE LA VERA GALLERIA FOTO DEL TELEFONO
  Future<void> _scegliFotoDaGalleria() async {
    try {
      final success = await _viewModel.scegliFotoDaGalleria();
      if (success && mounted) {
        AppToast.showSuccess(
          context,
          'Foto Salvata 🖼️',
          'Foto dalla galleria salvata nel tuo profilo!',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.showError(
        context,
        'Errore Galleria',
        'Impossibile caricare o salvare la foto: $e',
      );
    }
  }

  void _mostraModalCambioFoto() {
    final customUrlController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24.0,
          right: 24.0,
          top: 24.0,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24.0,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF475569),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Foto Profilo',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // ANTEPRIMA INGRANDITA DELLA FOTO ATTUALE
              Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFACC15), Color(0xFF9333EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFACC15).withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 65,
                    backgroundImage: _viewModel.currentAvatarImage,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _viewModel.utente.nickname.isNotEmpty ? '@${_viewModel.utente.nickname}' : _viewModel.utente.nome,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              Center(
                child: Text(
                  'Foto profilo attuale',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFF334155), thickness: 1),
              const SizedBox(height: 12),

              Text(
                'Vuoi cambiare la tua foto?',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

            // OPZIONE 1: SCATTA UNA FOTO IN QUESTO MOMENTO (Fotocamera Reale)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _scattaFotoConFotocamera();
              },
              icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF0F172A), size: 20),
              label: Text(
                'Scatta una foto adesso',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF0F172A), fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),

            // OPZIONE 2: CARICA DALLA TUA GALLERIA (Galleria Reale)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _scegliFotoDaGalleria();
              },
              icon: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 20),
              label: Text(
                'Carica dalla galleria',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9333EA),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),

            // OPZIONE 3: SCEGLI DA AVATAR
            Text(
              'Oppure scegli un avatar dalla lista:',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _viewModel.avatarsPredefiniti.length,
                itemBuilder: (context, index) {
                  final url = _viewModel.avatarsPredefiniti[index];
                  return GestureDetector(
                    onTap: () {
                      _viewModel.impostaAvatarUrl(url);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFACC15), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundImage: NetworkImage(url),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // OPZIONE 4: CUSTOM URL
            TextField(
              controller: customUrlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Oppure incolla URL foto...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                prefixIcon: const Icon(Icons.link, color: Color(0xFF9333EA)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: () {
                final newUrl = customUrlController.text.trim();
                if (newUrl.isNotEmpty) {
                  _viewModel.impostaAvatarUrl(newUrl);
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'SALVA URL FOTO',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final utente = _viewModel.utente;
        final double xpPercent = _viewModel.xpPercent;
        final ImageProvider avatarImage = _viewModel.currentAvatarImage;
        final bool isTutorialStep10 = TutorialController.instance.stage == TutorialStage.step10_in_profile;

        return PopScope(
          canPop: !isTutorialStep10,
          child: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            appBar: AppBar(
              automaticallyImplyLeading: !isTutorialStep10,
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                'Profilo Giocatore',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline_rounded, color: Color(0xFFFACC15), size: 24),
                  tooltip: 'Guida Profilo',
                  onPressed: () => ContextInfoModal.mostra(context, tipo: ContextInfoType.profilo),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF818CF8), width: 1.2),
                    ),
                    child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFFA5B4FC), size: 20),
                  ),
                  tooltip: 'Area Riservata & Dati Account',
                  onPressed: _mostraModalGestioneAccount,
                ),
              ],
            ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                if (isTutorialStep10) ...[
                  TutorialStepBanner(
                    stepTag: 'Tappa 4 di 4 • Profilo & Codice Amico',
                    title: 'Personalizza il tuo Profilo & Connettiti!',
                    description: '1) FOTO: Tocca la fotocamera qui sotto per scattare un selfie reale con la fotocamera, caricare dalla galleria o scegliere un avatar!\n2) CODICE AMICO: È il tuo codice personale univoco. Copialo per inviarlo agli amici su WhatsApp, e incolla il loro codice per aggiungerli!',
                    onSkip: () {
                      TutorialController.instance.skipTutorial();
                      setState(() {});
                    },
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    child: ElevatedButton.icon(
                      onPressed: _concludiTutorial,
                      icon: Text(_viewModel.haGiaRiscattatoPremio ? '✅' : '🏆', style: const TextStyle(fontSize: 22)),
                      label: Text(
                        _viewModel.haGiaRiscattatoPremio
                            ? 'COMPLETA IL TUTORIAL (PREMIO GIÀ RISCATTATO)'
                            : 'COMPLETA IL TUTORIAL E RITIRA +100 XP',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 12.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _viewModel.haGiaRiscattatoPremio ? const Color(0xFF334155) : const Color(0xFFFACC15),
                        foregroundColor: _viewModel.haGiaRiscattatoPremio ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: _viewModel.haGiaRiscattatoPremio ? const BorderSide(color: Color(0xFF64748B), width: 1.2) : BorderSide.none,
                        ),
                        elevation: 6,
                      ),
                    ),
                  ),
                ] else if (!utente.haVistoGuida) ...[
                  _buildTutorialIncompletoCard(),
                ],
              // Avatar & Basic Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF334155)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.15),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _mostraModalCambioFoto,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFFFACC15), Color(0xFF9333EA)],
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 46,
                              backgroundImage: avatarImage,
                              backgroundColor: const Color(0xFF334155),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFACC15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Scatta una foto o scegli dalla galleria',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFFACC15), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      utente.nickname.isNotEmpty ? utente.nickname : utente.nome,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (FounderBadge.isFounder(utente.nickname)) ...[
                      FounderBadge(nickname: utente.nickname, isLarge: true),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _viewModel.rankTitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFACC15),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      utente.email,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const SizedBox(height: 16),

                    // Codice Amico & Condivisione
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Il tuo Codice Amico:',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                  SelectableText(
                                    utente.codiceAmico,
                                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: utente.codiceAmico));
                                  if (!context.mounted) return;
                                  AppToast.showSuccess(
                                    context,
                                    'Codice Copiato 📲',
                                    'Codice Amico ${utente.codiceAmico} copiato negli appunti!',
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF0F172A)),
                                label: const Text('COPIA'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFACC15),
                                  foregroundColor: const Color(0xFF0F172A),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Level XP Progress Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progresso XP Livello',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                '${utente.xp} / ${utente.xpProssimoLivello} XP',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFFACC15),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: xpPercent,
                              minHeight: 12,
                              backgroundColor: const Color(0xFF1E293B),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF9333EA)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats Quick Row
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${utente.puntiTotali}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFFACC15),
                                  ),
                                ),
                                Text(
                                  'Punti Fanta',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _mostraModalAmici,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${utente.amici.length}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF10B981),
                                    ),
                                  ),
                                  Text(
                                    'Amici 👥',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _mostraModalVittorie,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF9333EA).withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${utente.badgeVincitore.length}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF9333EA),
                                    ),
                                  ),
                                  Text(
                                    'Vittorie 🏆',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // BACHECA TITOLI E RICONOSCIMENTI
              _buildBachecaTitoli(),
              const SizedBox(height: 16),

              // BACHECA VITTORIE (Card Compatta Cliccabile)
              InkWell(
                onTap: _mostraModalVittorie,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Bacheca Vittorie',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${utente.badgeVincitore.length}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFFACC15),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tocca per ammirare la sala trofei nei dettagli',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFACC15), size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // BADGE SBLOCCATI (Card Compatta Cliccabile)
              InkWell(
                onTap: _mostraModalBadge,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9333EA).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Text('🎖️', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Badge Sbloccati',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF9333EA).withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${utente.badgeList.length}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFC084FC),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tocca per visualizzare la lista dei tuoi badge ed eventi',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFC084FC), size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // AGGIUNGI AMICO PER CODICE AMICO
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFFACC15), size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Aggiungi Amico per Codice',
                          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codiceAmicoInputController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Es. FE-7391...',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.paste_rounded, color: Color(0xFFFACC15), size: 20),
                                tooltip: 'Incolla dagli appunti',
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                    setState(() {
                                      _codiceAmicoInputController.text = data.text!.trim();
                                    });
                                    if (!context.mounted) return;
                                    AppToast.showSuccess(
                                      context,
                                      'Codice Incollato 📋',
                                      'Codice incollato dagli appunti!',
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _inviaRichiestaAmicizia,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF9333EA),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          child: Text('INVIA', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Storico Attività con Filtro Temporale (24h, 3gg, 7gg)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Storico Voti & Attività 📜',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      selected: _viewModel.filtroGiorniStorico == 1,
                      label: const Text('Ultimi 24h'),
                      selectedColor: const Color(0xFF9333EA),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: _viewModel.filtroGiorniStorico == 1 ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => _viewModel.setFiltroGiorniStorico(1),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _viewModel.filtroGiorniStorico == 3,
                      label: const Text('Ultimi 3 Giorni'),
                      selectedColor: const Color(0xFF9333EA),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: _viewModel.filtroGiorniStorico == 3 ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => _viewModel.setFiltroGiorniStorico(3),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _viewModel.filtroGiorniStorico == 7,
                      label: const Text('Ultimi 7 Giorni'),
                      selectedColor: const Color(0xFF9333EA),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: _viewModel.filtroGiorniStorico == 7 ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => _viewModel.setFiltroGiorniStorico(7),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final storicoFiltrato = _viewModel.storicoFiltrato;
                  if (storicoFiltrato.isEmpty) {
                    return Text(
                      'Nessuna attività registrata nel periodo selezionato.',
                      style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: storicoFiltrato.length,
                    itemBuilder: (context, index) {
                      final item = storicoFiltrato[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_toggle_off, color: Color(0xFF9333EA), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            ],
          ),
        ),
      ),
    ),
  );
      },
    );
}

  void _mostraModalGestioneAccount() {
    final utente = _viewModel.utente;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF475569),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF818CF8), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Area Riservata',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Informazioni personali e gestione account',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SCHEDA DATI ACCOUNT
                  Text(
                    'INFORMAZIONI PERSONALI',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: const Color(0xFF818CF8),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          icon: Icons.person_rounded,
                          label: 'Nome',
                          value: utente.nome,
                        ),
                        if (utente.cognome.isNotEmpty) ...[
                          const Divider(color: Color(0xFF334155), height: 20),
                          _buildInfoRow(
                            icon: Icons.badge_outlined,
                            label: 'Cognome',
                            value: utente.cognome,
                          ),
                        ],
                        const Divider(color: Color(0xFF334155), height: 20),
                        _buildInfoRow(
                          icon: Icons.sports_esports_rounded,
                          label: 'Nickname in Gioco',
                          value: '@${utente.nickname}',
                          valueColor: const Color(0xFFFACC15),
                        ),
                        const Divider(color: Color(0xFF334155), height: 20),
                        _buildInfoRow(
                          icon: Icons.alternate_email_rounded,
                          label: 'Email',
                          value: utente.email,
                        ),
                        const Divider(color: Color(0xFF334155), height: 20),
                        _buildInfoRow(
                          icon: Icons.key_rounded,
                          label: 'Codice Amico',
                          value: utente.codiceAmico,
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_rounded, color: Color(0xFFFACC15), size: 18),
                            tooltip: 'Copia codice',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: utente.codiceAmico));
                              AppToast.showSuccess(context, 'Codice Amico copiato negli appunti!');
                            },
                          ),
                        ),
                        const Divider(color: Color(0xFF334155), height: 20),
                        _buildInfoRow(
                          icon: Icons.calendar_today_rounded,
                          label: 'Data di Iscrizione',
                          value: utente.dataRegistrazione,
                        ),
                        const Divider(color: Color(0xFF334155), height: 20),
                        _buildInfoRow(
                          icon: Icons.verified_user_outlined,
                          label: 'Stato Profilo',
                          value: 'Attivo & Verificato',
                          valueColor: const Color(0xFF10B981),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // SICUREZZA & PASSWORD
                  Text(
                    'SICUREZZA & SESSIONE',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF60A5FA), size: 20),
                          ),
                          title: Text(
                            'Reimposta Password',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          subtitle: Text(
                            'Invia codice di verifica per cambiare password',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 14),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _mostraDialogReimpostaPassword();
                          },
                        ),
                        const Divider(color: Color(0xFF334155), height: 1),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 20),
                          ),
                          title: Text(
                            'Disconnetti (Logout)',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          subtitle: Text(
                            'Termina la sessione su questo dispositivo',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 14),
                          onTap: () => _eseguiLogout(ctx),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ZONA PERICOLO - ELIMINAZIONE ACCOUNT
                  Text(
                    'ZONA PERICOLO',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Eliminazione Definitiva Account',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFFCA5A5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Questa operazione rimuoverà irreversibilmente il tuo profilo, i punteggi, i badge e la cronologia delle votazioni conforme alle policy di privacy.',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFF94A3B8),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 18),
                            label: Text(
                              'Elimina Definitivamente Account',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _confermaEliminazioneAccount();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF64748B), size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  void _confermaEliminazioneAccount() {
    final utente = _viewModel.utente;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Eliminare l\'account?',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attenzione: questa azione è irreversibile.',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFFCA5A5)),
              ),
              const SizedBox(height: 10),
              Text(
                'Tutti i dati dell\'utente "${utente.nome}", inclusi ${utente.puntiTotali} punti totali, ${utente.badgeList.length} badge e lo storico completo delle votazioni, verranno eliminati per sempre dal database.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'Annulla',
                style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                _eseguiEliminazioneAccount();
              },
              child: Text(
                'Sì, Elimina per sempre',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _eseguiEliminazioneAccount() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFEF4444)),
              const SizedBox(height: 16),
              Text(
                'Eliminazione account in corso...',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, decoration: TextDecoration.none),
              ),
            ],
          ),
        ),
      ),
    );

    final success = await _viewModel.eliminaAccount();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (success) {
      AppToast.showSuccess(context, 'Account eliminato con successo. Arrivederci!');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginView()),
        (route) => false,
      );
    } else {
      AppToast.showError(context, 'Impossibile eliminare l\'account. Riprova più tardi.');
    }
  }

  void _mostraDialogReimpostaPassword() {
    final utente = _viewModel.utente;
    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.lock_reset_rounded, color: Color(0xFF60A5FA), size: 24),
              const SizedBox(width: 10),
              Text(
                'Reimposta Password',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
            ],
          ),
          content: Text(
            'Vuoi richiedere un codice di verifica alla tua email (${utente.email}) per reimpostare la tua password?',
            style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: Text('Chiudi', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.of(dCtx).pop();
                try {
                  await ApiService().richiediCodiceReset(utente.email);
                  if (mounted) {
                    AppToast.showSuccess(context, 'Codice di verifica inviato a ${utente.email}!');
                  }
                } catch (e) {
                  if (mounted) {
                    AppToast.showError(context, 'Errore nell\'invio del codice: $e');
                  }
                }
              },
              child: Text('Invia Codice', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBachecaTitoli() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFACC15).withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎖️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bacheca Titoli & Riconoscimenti',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Titoli conquistati negli eventi conclusi a cui hai partecipato.',
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 14),
          Row(
              children: [
                Expanded(
                  child: _buildBachecaBadge(
                    icon: '👑',
                    label: 'Campione',
                    count: _viewModel.countCampione,
                    color: const Color(0xFFFACC15),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildBachecaBadge(
                    icon: '🤡',
                    label: 'Re Malus',
                    count: _viewModel.countReMalus,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildBachecaBadge(
                    icon: '⚖️',
                    label: 'Avvocato',
                    count: _viewModel.countAvvocato,
                    color: const Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildBachecaBadge(
                    icon: '👻',
                    label: 'Fantasma',
                    count: _viewModel.countFantasma,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildBachecaBadge(
                    icon: '🕵️',
                    label: 'Lo Sbirro',
                    count: _viewModel.countSbirro,
                    color: const Color(0xFFF97316),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildBachecaBadge(
                    icon: '⚡',
                    label: 'Giustiziere',
                    count: _viewModel.countGiustiziere,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }

  Widget _buildBachecaBadge({
    required String icon,
    required String label,
    required int count,
    required Color color,
  }) {
    final bool hasTitle = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasTitle ? color.withValues(alpha: 0.4) : const Color(0xFF334155),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasTitle ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
                Text(
                  hasTitle ? '$count ${count == 1 ? "volta" : "volte"}' : 'Non ancora',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: hasTitle ? FontWeight.w600 : FontWeight.normal,
                    color: hasTitle ? color : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
