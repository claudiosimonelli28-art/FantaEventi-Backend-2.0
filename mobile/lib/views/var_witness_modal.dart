import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/richiesta_var.dart';
import '../services/api_service.dart';

class VarWitnessModal extends StatefulWidget {
  final String varId;
  final VoidCallback onVoted;

  const VarWitnessModal({
    super.key,
    required this.varId,
    required this.onVoted,
  });

  @override
  State<VarWitnessModal> createState() => _VarWitnessModalState();
}

class _VarWitnessModalState extends State<VarWitnessModal> {
  final ApiService _apiService = ApiService();
  RichiestaVar? _richiesta;
  bool _isLoading = true;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _caricaRichiesta();
  }

  Future<void> _caricaRichiesta() async {
    setState(() {
      _isLoading = true;
    });
    final req = await _apiService.getRichiestaVar(widget.varId);
    if (mounted) {
      setState(() {
        _richiesta = req;
        _isLoading = false;
      });
    }
  }

  void _apriFotoFullScreen(String base64Str) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(base64Str.split(',').last),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black87,
                child: Icon(Icons.close, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _esprimiVoto(bool conferma) async {
    final curUser = _apiService.currentUser;
    if (curUser == null || _richiesta == null) return;

    setState(() {
      _isVoting = true;
    });

    final success = await _apiService.votaTestimonianzaVar(
      varId: widget.varId,
      testimoneNick: curUser.nickname,
      conferma: conferma,
    );

    if (mounted) {
      setState(() {
        _isVoting = false;
      });

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF6366F1),
            content: Text(
              conferma
                  ? '✅ Hai confermato l\'accaduto al VAR. Testimonianza registrata!'
                  : '❌ Hai negato l\'accaduto al VAR. Testimonianza registrata!',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        widget.onVoted();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Impossibile registrare il voto: il caso potrebbe essere già stato chiuso dall\'arbitro.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFACC15)),
        ),
      );
    }

    if (_richiesta == null) {
      return Container(
        padding: const EdgeInsets.all(30),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              'Richiesta VAR non disponibile.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
          ],
        ),
      );
    }

    final req = _richiesta!;
    final curUser = _apiService.currentUser;
    final myNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final bool hasAlreadyVoted = req.votiTestimoni.containsKey(myNick);
    final bool? myVote = req.votiTestimoni[myNick];
    final bool isAlreadyDecided = !req.isPending;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HEADER MODALE
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('👀', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Testimonianza al VAR',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Sei stato indicato come testimone oculare',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // SCHEDA EVENTO E BONUS/MALUS
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Evento: ${req.eventoTitolo}',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                      ),
                      const Spacer(),
                      Text(
                        '${req.isBonus ? "+" : ""}${req.punti} PT',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: req.isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    req.bonusMalusTitolo,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    req.isBonus
                        ? '👤 Richiedente: ${req.richiedente}'
                        : '🚨 Denuncia di ${req.richiedente} contro ${req.bersaglio}',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFFACC15), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // COSA DICHIARA IL RICHIEDENTE
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dichiarazione:',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    req.descrizione,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // FOTO ALLEGATA
            if (req.fotoBase64 != null && req.fotoBase64!.isNotEmpty) ...[
              Text(
                '📸 Prova Fotografica (Tocca per ingrandire):',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _apriFotoFullScreen(req.fotoBase64!),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                    image: DecorationImage(
                      image: MemoryImage(base64Decode(req.fotoBase64!.split(',').last)),
                      fit: BoxFit.cover,
                    ),
                  ),
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Tocca per ingrandire', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // STATO CASO: DECISO O GIÀ VOTATO
            if (isAlreadyDecided) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF64748B)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF94A3B8), size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'Decisione già presa dal Giudice (${req.isApprovata ? "Convalidata ✅" : "Respinta ❌"}).\nIl tuo voto non è più necessario.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ] else if (hasAlreadyVoted) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: myVote == true
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFFEF4444).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: myVote == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      myVote == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: myVote == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      myVote == true ? 'HAI CONFERMATO L\'ACCADUTO' : 'HAI NEGATO L\'ACCADUTO',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: myVote == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // DOMANDA DI TESTIMONIANZA
              Text(
                '❓ Confermi che quanto descritto è realmente accaduto?',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFACC15),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isVoting ? null : () => _esprimiVoto(true),
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: Text(
                        'CONFERMO ✅',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isVoting ? null : () => _esprimiVoto(false),
                      icon: const Icon(Icons.cancel_rounded, color: Colors.white, size: 18),
                      label: Text(
                        'NEGO ❌',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
