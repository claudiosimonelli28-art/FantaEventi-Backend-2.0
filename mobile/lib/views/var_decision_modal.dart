import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../viewmodels/var_view_model.dart';
import '../widgets/app_toast.dart';

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
  late final VarDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = VarDetailViewModel(widget.varId);
    _viewModel.caricaRichiesta();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
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
    if (_viewModel.isProcessing) return;
    try {
      final success = await _viewModel.decidiRichiesta(approva);
      if (mounted) {
        if (success) {
          Navigator.pop(context);
          if (approva) {
            AppToast.showSuccess(
              context,
              'Denuncia Convalidata ✅',
              'La segnalazione è stata convalidata! I punti sono stati aggiornati.',
            );
          } else {
            AppToast.showWarning(
              context,
              'Denuncia Respinta ❌',
              (_viewModel.sanzionaFalsaTestimonianza && (_viewModel.richiesta?.isMalus ?? false))
                  ? 'Denuncia respinta! Applicata sanzione per falsa testimonianza.'
                  : 'Richiesta VAR respinta dal Giudice.',
            );
          }
          widget.onResolved();
        } else {
          Navigator.pop(context);
          AppToast.showError(
            context,
            'Decisione Già Registrata',
            'Questa richiesta VAR è già stata elaborata o non è più in attesa.',
          );
          widget.onResolved();
        }
      }
    } catch (_) {
      if (mounted) {
        AppToast.showError(
          context,
          'Errore Decisione VAR',
          'Si è verificato un errore imprevisto durante la decisione.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final isLoading = _viewModel.isLoading;
        final richiesta = _viewModel.richiesta;
        final cachedPhotoBytes = _viewModel.cachedPhotoBytes;
        final isProcessing = _viewModel.isProcessing;
        final decisioneScelta = _viewModel.decisioneScelta;
        final sanzionaFalsaTestimonianza = _viewModel.sanzionaFalsaTestimonianza;

        if (isLoading) {
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

    if (richiesta == null) {
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

    final req = richiesta;
    final isBonus = req.isBonus;
    final colorAccent = isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return PopScope(
      canPop: !isProcessing,
      child: Stack(
        children: [
          Container(
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
            if (cachedPhotoBytes != null) ...[
              Text(
                '📸 Prova Fotografica (Tocca per ingrandire):',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _apriFotoFullScreen(cachedPhotoBytes),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                    image: DecorationImage(
                      image: MemoryImage(cachedPhotoBytes),
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
                        value: sanzionaFalsaTestimonianza,
                        activeColor: const Color(0xFFEF4444),
                        onChanged: (val) {
                          _viewModel.setSanzionaFalsaTestimonianza(val ?? true);
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
                      onPressed: isProcessing ? null : () => _prendiDecisione(true),
                      icon: (isProcessing && decisioneScelta == 'convalida')
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: Text(
                        (isProcessing && decisioneScelta == 'convalida')
                            ? 'Convalida in corso...'
                            : 'CONVALIDA',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF059669),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isProcessing ? null : () => _prendiDecisione(false),
                      icon: (isProcessing && decisioneScelta == 'respingi')
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cancel_rounded, color: Colors.white, size: 18),
                      label: Text(
                        (isProcessing && decisioneScelta == 'respingi')
                            ? 'Rifiuto in corso...'
                            : 'RESPINGI',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFDC2626),
                        disabledForegroundColor: Colors.white,
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
    ),

    // OVERLAY DI CARICAMENTO BLOCCANTE CON FEEDBACK
    if (isProcessing)
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFFFACC15),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    decisioneScelta == 'convalida'
                        ? '⚖️ Convalida VAR in corso...'
                        : '⚖️ Registrazione rifiuto VAR...',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aggiornamento punteggi e notifiche in corso. Attendere...',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
      },
    );
  }
}
