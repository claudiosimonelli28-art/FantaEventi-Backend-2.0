import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/richiesta_var.dart';
import '../services/api_service.dart';

class VarDecisionModal extends StatefulWidget {
  final String varId;
  final VoidCallback onResolved;

  const VarDecisionModal({
    super.key,
    required this.varId,
    required this.onResolved,
  });

  @override
  State<VarDecisionModal> createState() => _VarDecisionModalState();
}

class _VarDecisionModalState extends State<VarDecisionModal> {
  final ApiService _apiService = ApiService();
  RichiestaVar? _richiesta;
  Uint8List? _cachedPhotoBytes;
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _sanzionaFalsaTestimonianza = true;

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
    Uint8List? bytes;
    if (req?.fotoBase64 != null && req!.fotoBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(req.fotoBase64!.split(',').last);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _richiesta = req;
        _cachedPhotoBytes = bytes;
        _isLoading = false;
      });
    }
  }

  void _apriFotoFullScreen(Uint8List imageBytes) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      barrierDismissible: true,
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: GestureDetector(
                  onTap: () {}, // Evita chiusura se si tocca la foto
                  child: InteractiveViewer(
                    panEnabled: true,
                    boundaryMargin: const EdgeInsets.all(20),
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: SafeArea(
                  child: IconButton(
                    icon: const CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _prendiDecisione(bool approva) async {
    final curUser = _apiService.currentUser;
    if (curUser == null || _richiesta == null) return;

    setState(() {
      _isProcessing = true;
    });

    final success = await _apiService.decidiRichiestaVar(
      varId: widget.varId,
      giudiceNick: curUser.nickname,
      approva: approva,
      sanzionaFalsaTestimonianza: !approva && _sanzionaFalsaTestimonianza,
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: approva ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            content: Text(
              approva
                  ? '✅ Richiesta VAR approvata! Punti assegnati.'
                  : (_sanzionaFalsaTestimonianza && _richiesta!.isMalus
                      ? '❌ Denuncia respinta! Applicata sanzione per falsa testimonianza.'
                      : '❌ Richiesta VAR respinta.'),
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        widget.onResolved();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Errore durante la registrazione della decisione.'),
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
              'Richiesta VAR non trovata o rimossa.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
          ],
        ),
      );
    }

    final req = _richiesta!;
    final isBonus = req.isBonus;
    final colorAccent = isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444);

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
            // HEADER TRIBUNALE VAR
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
                  child: const Text('⚖️', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tribunale del VAR',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Evento: ${req.eventoTitolo}',
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

            // SCHEDA BONUS O MALUS
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorAccent.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorAccent),
                        ),
                        child: Text(
                          isBonus ? 'BONUS' : 'MALUS (DENUNCIA)',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colorAccent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${isBonus ? "+" : ""}${req.punti} PT',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    req.bonusMalusTitolo,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFF334155), height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Richiesto da: ', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                      Text(
                        req.richiedente,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (!isBonus) ...[
                        const SizedBox(width: 14),
                        Text('Denunciato: ', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                        Text(
                          req.bersaglio,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // DESCRIZIONE
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
                    'Dichiarazione dell\'accaduto:',
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

            // ANTEPRIMA PROVA FOTOGRAFICA
            if (_cachedPhotoBytes != null) ...[
              Text(
                '📸 Prova Fotografica (Tocca per ingrandire):',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _apriFotoFullScreen(_cachedPhotoBytes!),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                    image: DecorationImage(
                      image: MemoryImage(_cachedPhotoBytes!),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.zoom_in, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Ingrandisci', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // RIEPILOGO TESTIMONI E VOTI
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
                  Row(
                    children: [
                      const Text('👥', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        'Testimonianze (${req.testimoni.length})',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const Spacer(),
                      // CHIP RIEPILOGO
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${req.numeroConferme} ✅',
                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${req.numeroDinieghi} ❌',
                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (req.testimoni.isEmpty)
                    Text(
                      'Nessun testimone indicato dal richiedente.',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                    )
                  else
                    ...req.testimoni.map((t) {
                      final hasVoted = req.votiTestimoni.containsKey(t.toLowerCase());
                      final vote = req.votiTestimoni[t.toLowerCase()];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(
                              '• $t: ',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                            ),
                            if (!hasVoted)
                              Text(
                                '⏳ In attesa di risposta',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFFACC15), fontWeight: FontWeight.w600),
                              )
                            else if (vote == true)
                              Text(
                                '✅ Ha confermato l\'accaduto',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF10B981), fontWeight: FontWeight.bold),
                              )
                            else
                              Text(
                                '❌ Ha negato l\'accaduto',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444), fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // STATO O PULSANTI DECISIONE
            if (!req.isPending) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: req.isApprovata
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFFEF4444).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: req.isApprovata ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      req.isApprovata ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: req.isApprovata ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      req.isApprovata ? 'RICHIESTA CONVALIDATA' : 'RICHIESTA RESPINTA',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: req.isApprovata ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // SEZIONE MALUS: TOGGLE SANZIONE FALSA TESTIMONIANZA
              if (req.isMalus) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _sanzionaFalsaTestimonianza,
                        activeColor: const Color(0xFFEF4444),
                        onChanged: (val) {
                          setState(() {
                            _sanzionaFalsaTestimonianza = val ?? true;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          'Se respinta: sanziona il denunciante con ${req.penalitaPunti} PT per Falsa Testimonianza',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // PULSANTI DI GIUDIZIO
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _prendiDecisione(true),
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: Text(
                        'CONVALIDA',
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
                      onPressed: _isProcessing ? null : () => _prendiDecisione(false),
                      icon: const Icon(Icons.cancel_rounded, color: Colors.white, size: 18),
                      label: Text(
                        'RESPINGI',
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
