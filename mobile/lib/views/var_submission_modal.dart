import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../viewmodels/var_view_model.dart';
import '../widgets/app_toast.dart';
import '../widgets/context_info_modal.dart';

class VarSubmissionModal extends StatefulWidget {
  final Evento evento;
  final BonusMalus bonusMalus;
  final VoidCallback onSubmitted;

  const VarSubmissionModal({
    super.key,
    required this.evento,
    required this.bonusMalus,
    required this.onSubmitted,
  });

  @override
  State<VarSubmissionModal> createState() => _VarSubmissionModalState();
}

class _VarSubmissionModalState extends State<VarSubmissionModal> {
  late final VarSubmissionViewModel _viewModel;
  final TextEditingController _descrizioneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewModel = VarSubmissionViewModel(
      evento: widget.evento,
      bonusMalus: widget.bonusMalus,
    );
  }

  @override
  void dispose() {
    _descrizioneController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final ok = await _viewModel.pickImage(source);
    if (!ok && mounted) {
      AppToast.showError(context, 'Errore Immagine', 'Impossibile caricare l\'immagine.');
    }
  }

  Future<void> _inviaRichiesta() async {
    try {
      final resId = await _viewModel.inviaRichiesta(_descrizioneController.text);
      if (mounted) {
        if (resId != null) {
          Navigator.pop(context);
          final judge = _viewModel.isOrganizer
              ? (_viewModel.selectedJudge ?? '')
              : widget.evento.creatore;
          AppToast.showSuccess(
            context,
            'Richiesta VAR Inoltrata 📺',
            'Richiesta inviata al Giudice $judge! Testimoni allertati.',
          );
          widget.onSubmitted();
        } else {
          AppToast.showError(
            context,
            'Errore VAR',
            'Errore durante l\'invio della richiesta VAR. Riprova.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        if (msg.contains('Mancante') || msg.contains('Seleziona') || msg.contains('Inserisci')) {
          AppToast.showWarning(context, 'Attenzione', msg);
        } else {
          AppToast.showError(context, 'Errore VAR', msg);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final myNick = _viewModel.myNick;
        final isBonus = _viewModel.isBonus;
        final isOrganizer = _viewModel.isOrganizer;
        final effectiveJudge = isOrganizer ? (_viewModel.selectedJudge ?? '') : widget.evento.creatore;

        // Testimoni selezionabili: partecipanti esclusi richiedente, bersaglio e arbitro
        final eligibleWitnesses = widget.evento.partecipanti.where((p) {
          final pLower = p.trim().toLowerCase();
          if (_viewModel.isMe(p)) return false;
          final effJudgeLower = effectiveJudge.trim().toLowerCase();
          if (pLower == effJudgeLower ||
              (effJudgeLower == 'cloud' && (pLower == 'claudio' || pLower.contains('claudio'))) ||
              (effJudgeLower == 'claudio' && pLower == 'cloud')) {
            return false;
          }
          if (!isBonus && _viewModel.selectedCulprit != null && pLower == _viewModel.selectedCulprit!.trim().toLowerCase()) return false;
          return true;
        }).toList();

        final colorAccent = isBonus ? const Color(0xFF10B981) : const Color(0xFFEF4444);

        return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // INTESTAZIONE MODALE
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
                  child: const Text('📺', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isBonus ? 'VAR: Autocertificazione Bonus' : 'VAR: Denuncia Malus',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        widget.evento.titolo,
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline_rounded, color: Color(0xFFFACC15), size: 22),
                  tooltip: 'Guida Richiesta VAR',
                  onPressed: () => ContextInfoModal.mostra(context, tipo: ContextInfoType.varSubmission),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // SCHEDA BONUS/MALUS IN QUESTIONE
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    isBonus ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                    color: colorAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.bonusMalus.titolo,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${isBonus ? "+" : ""}${widget.bonusMalus.punti} PT',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // SEZIONE CASO PARTICOLARE: ORGANIZZATORE RICHIEDE PER SÉ
            if (isOrganizer) ...[
              Text(
                '⚖️ Chi giudicherà questa tua richiesta? (Co-Organizzatore)',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFACC15),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _viewModel.selectedJudge,
                    dropdownColor: const Color(0xFF0F172A),
                    isExpanded: true,
                    hint: const Text('Seleziona un Co-Organizzatore', style: TextStyle(color: Colors.white54)),
                    items: widget.evento.partecipanti
                        .where((p) => p.trim().toLowerCase() != myNick.trim().toLowerCase())
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p, style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      _viewModel.selectJudge(val);
                      if (val != null && _viewModel.selectedWitnesses.contains(val)) {
                        _viewModel.toggleWitness(val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // SEZIONE MALUS: SCELTA DEL COLPEVOLE + AVVISO FALSA TESTIMONIANZA
            if (!isBonus) ...[
              Text(
                '🎯 Chi ha commesso l\'infrazione?',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _viewModel.selectedCulprit,
                    dropdownColor: const Color(0xFF0F172A),
                    isExpanded: true,
                    hint: const Text('Seleziona il giocatore', style: TextStyle(color: Colors.white54)),
                    items: widget.evento.partecipanti
                        .where((p) => p.trim().toLowerCase() != myNick.trim().toLowerCase())
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p, style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      _viewModel.selectCulprit(val);
                      if (val != null && _viewModel.selectedWitnesses.contains(val)) {
                        _viewModel.toggleWitness(val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // BANNER DI SANZIONE FALSA TESTIMONIANZA
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ATTENZIONE: Se l\'organizzatore rigetterà questa denuncia poiché infondata o falsa, riceverai una sanzione di ${widget.evento.penalitaFalsaTestimonianza} PT per Simulazione / Falsa Testimonianza!',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFFFECACA),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // DESCRIZIONE ACCADUTO
            Text(
              '📝 Cosa è successo? Racconta l\'accaduto:',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descrizioneController,
              maxLines: 3,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: isBonus
                    ? 'Es. Ho ballato sul tavolo per 2 minuti durante la canzone!'
                    : 'Es. Marco ha rovesciato il bicchiere di birra sul divano!',
                hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // CARICAMENTO PROVA FOTOGRAFICA
            Text(
              '📸 Prova Fotografica (Consigliata per la convalida):',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (_viewModel.fotoBase64 != null) ...[
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
                      image: DecorationImage(
                        image: MemoryImage(
                          base64Decode(_viewModel.fotoBase64!.split(',').last),
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const CircleAvatar(
                      backgroundColor: Colors.black87,
                      radius: 14,
                      child: Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                    onPressed: _viewModel.removePhoto,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded, size: 18, color: Color(0xFF38BDF8)),
                      label: Text(
                        'SCATTA FOTO',
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF38BDF8)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded, size: 18, color: Color(0xFFFACC15)),
                      label: Text(
                        'GALLERIA',
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFACC15)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // SELEZIONE TESTIMONI
            Text(
              '👀 Invita Testimoni a confermare:',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'I testimoni riceveranno una notifica e potranno votare Confermo ✅ o Nego ❌.',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 8),

            if (eligibleWitnesses.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Nessun altro partecipante disponibile come testimone.',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontStyle: FontStyle.italic),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: eligibleWitnesses.map((w) {
                  final isSelected = _viewModel.selectedWitnesses.contains(w);
                  return FilterChip(
                    label: Text(w),
                    selected: isSelected,
                    selectedColor: const Color(0xFF6366F1),
                    checkmarkColor: Colors.white,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    ),
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF334155),
                      ),
                    ),
                    onSelected: (_) => _viewModel.toggleWitness(w),
                  );
                }).toList(),
              ),
            const SizedBox(height: 24),

            // TASTO DI INVIO AL VAR
            ElevatedButton.icon(
              onPressed: _viewModel.isSubmitting ? null : _inviaRichiesta,
              icon: _viewModel.isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('📺', style: TextStyle(fontSize: 16)),
              label: Text(
                _viewModel.isSubmitting
                    ? 'INVIO IN CORSO...'
                    : (isBonus ? 'INVIA RICHIESTA AL VAR' : 'INVIA DENUNCIA AL VAR'),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}
