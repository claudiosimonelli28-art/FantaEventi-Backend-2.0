import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/utente.dart';
import '../services/api_service.dart';
import '../widgets/avatar_helper.dart';
import 'login_view.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();
  final _codiceAmicoInputController = TextEditingController();
  late Utente _utente;
  File? _fotoLocaleFile;

  final List<String> _avatarsPredefiniti = [
    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1580489944761-15a19d654956?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1628157582853-a796fa650a6a?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80',
  ];

  int _filtroGiorniStorico = 7;
  int _countCampione = 0;
  int _countReMalus = 0;
  int _countGiudiceSupremo = 0;
  int _countFantasma = 0;

  @override
  void initState() {
    super.initState();
    _utente = _apiService.currentUser ?? _apiService.getCurrentUser();
    _caricaProfiloAggiornato();
  }

  @override
  void dispose() {
    _codiceAmicoInputController.dispose();
    super.dispose();
  }

  Future<void> _inviaRichiestaAmicizia() async {
    final code = _codiceAmicoInputController.text.trim();
    if (code.isEmpty) return;

    try {
      await _apiService.inviaRichiestaAmicizia(code);
      _codiceAmicoInputController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Richiesta di amicizia inviata con successo! 👥', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text(e.toString().replaceAll('Exception: ', ''), style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }
  }

  Future<void> _caricaProfiloAggiornato() async {
    try {
      final updatedUser = await _apiService.syncCurrentUserFromDb();
      if (updatedUser != null && mounted) {
        setState(() {
          _utente = updatedUser;
        });
      }
      await _calcolaTitoliSpeciali();
    } catch (_) {}
  }

  Future<void> _calcolaTitoliSpeciali() async {
    try {
      final userNick = _utente.nickname.trim().toLowerCase();
      final eventi = await _apiService.getEventi();
      final allBonus = await _apiService.getBonusMalusList();
      final allVotazioni = await _apiService.getVotazioni();

      int campione = _utente.badgeVincitore.length;
      int reMalus = 0;
      int giudice = 0;
      int fantasma = 0;

      for (var ev in eventi) {
        if (!ev.isConcluso) continue;

        final Map<String, int> malusPerUtente = {};
        final Map<String, int> attivitaPerUtente = {};
        final Map<String, int> azioniTotaliPerUtente = {};

        for (var p in ev.partecipanti) {
          final pNorm = p.trim().toLowerCase();
          malusPerUtente[pNorm] = 0;
          attivitaPerUtente[pNorm] = 0;
          azioniTotaliPerUtente[pNorm] = 0;
        }

        for (var bm in allBonus) {
          final isSameEv = bm.eventoId.trim().toLowerCase() == ev.id.trim().toLowerCase() ||
              bm.eventoId.trim().toLowerCase() == ev.titolo.trim().toLowerCase();
          if (!isSameEv && allBonus.length > 1) continue;

          final prop = bm.propostoDa.trim().toLowerCase();
          if (attivitaPerUtente.containsKey(prop)) {
            attivitaPerUtente[prop] = (attivitaPerUtente[prop] ?? 0) + 1;
            azioniTotaliPerUtente[prop] = (azioniTotaliPerUtente[prop] ?? 0) + 1;
          }

          for (var u in bm.assegnatoA) {
            final uNorm = u.trim().toLowerCase();
            azioniTotaliPerUtente[uNorm] = (azioniTotaliPerUtente[uNorm] ?? 0) + 1;
            if (bm.punti < 0) {
              malusPerUtente[uNorm] = (malusPerUtente[uNorm] ?? 0) + bm.punti.abs();
            }
          }
        }

        for (var v in allVotazioni) {
          final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';
          final isSameEv = evId == ev.id.trim().toLowerCase() ||
              evId == ev.titolo.trim().toLowerCase();
          if (!isSameEv && allVotazioni.length > 1) continue;

          for (var u in v.votiUtenti.keys) {
            final uNorm = u.trim().toLowerCase();
            if (attivitaPerUtente.containsKey(uNorm)) {
              attivitaPerUtente[uNorm] = (attivitaPerUtente[uNorm] ?? 0) + 1;
              azioniTotaliPerUtente[uNorm] = (azioniTotaliPerUtente[uNorm] ?? 0) + 1;
            }
          }
        }

        // 1. Re dei Malus
        int maxMalus = 0;
        String? bestMalus;
        malusPerUtente.forEach((k, v) {
          if (v > maxMalus) {
            maxMalus = v;
            bestMalus = k;
          }
        });
        if (bestMalus == userNick && maxMalus > 0) {
          reMalus++;
        }

        // 2. Giudice Supremo
        int maxAtt = 0;
        String? bestGiudice;
        attivitaPerUtente.forEach((k, v) {
          if (v > maxAtt) {
            maxAtt = v;
            bestGiudice = k;
          }
        });
        if (bestGiudice == userNick && maxAtt > 0) {
          giudice++;
        }

        // 3. Fantasma (partecipante attivo al minimo indispensabile, escludendo il vincitore)
        if (ev.partecipanti.length > 1 && ev.partecipanti.any((p) => p.trim().toLowerCase() == userNick)) {
          String? bestPlayer;
          int maxPts = -99999;
          for (var p in ev.partecipanti) {
            final pNorm = p.trim().toLowerCase();
            final pts = allBonus
                .where((b) {
                  final matchEv = b.eventoId.trim().toLowerCase() == ev.id.trim().toLowerCase() ||
                      b.eventoId.trim().toLowerCase() == ev.titolo.trim().toLowerCase();
                  return (matchEv || allBonus.length == 1) &&
                      b.assegnatoA.any((x) => x.trim().toLowerCase() == pNorm);
                })
                .fold<int>(0, (sum, b) => sum + b.punti);
            if (pts > maxPts) {
              maxPts = pts;
              bestPlayer = pNorm;
            }
          }

          int minAzioni = 999999;
          String? bestFantasma;
          for (var p in ev.partecipanti) {
            final pNorm = p.trim().toLowerCase();
            if (bestPlayer != null && bestPlayer == pNorm) continue;
            final az = azioniTotaliPerUtente[pNorm] ?? 0;
            if (az < minAzioni) {
              minAzioni = az;
              bestFantasma = pNorm;
            }
          }
          if (bestFantasma == userNick) {
            fantasma++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _countCampione = campione;
          _countReMalus = reMalus;
          _countGiudiceSupremo = giudice;
          _countFantasma = fantasma;
        });
      }
    } catch (_) {}
  }

  // APRE LA VERA FOTOCAMERA FISICA DEL TELEFONO
  Future<void> _scattaFotoConFotocamera() async {
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
        setState(() {
          _fotoLocaleFile = File(photo.path);
          _utente = _utente.copyWith(avatarUrl: base64String);
        });
        await _apiService.aggiornaAvatarUtente(_utente.nickname, base64String);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Foto salvata permanentemente nel tuo profilo MongoDB! 📸',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Errore apertura fotocamera: $e', style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  // APRE LA VERA GALLERIA FOTO DEL TELEFONO
  Future<void> _scegliFotoDaGalleria() async {
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
        setState(() {
          _fotoLocaleFile = File(image.path);
          _utente = _utente.copyWith(avatarUrl: base64String);
        });
        await _apiService.aggiornaAvatarUtente(_utente.nickname, base64String);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF9333EA),
            content: Text('Foto della tua Galleria salvata nel profilo MongoDB! 🖼️',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Errore apertura galleria: $e', style: const TextStyle(color: Colors.white)),
        ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Modifica Foto Profilo',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
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
              icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF0F172A)),
              label: Text(
                '📸 SCATTA UNA FOTO IN QUESTO MOMENTO',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF0F172A), fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                padding: const EdgeInsets.symmetric(vertical: 14),
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
              icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
              label: Text(
                '🖼️ CARICA DALLA TUA GALLERIA',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9333EA),
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                itemCount: _avatarsPredefiniti.length,
                itemBuilder: (context, index) {
                  final url = _avatarsPredefiniti[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _fotoLocaleFile = null;
                        _utente = _utente.copyWith(avatarUrl: url);
                      });
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
                  setState(() {
                    _fotoLocaleFile = null;
                    _utente = _utente.copyWith(avatarUrl: newUrl);
                  });
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
    );
  }

  String _getRankTitle(int livello) {
    if (livello >= 10) return '👑 Leggenda Suprema degli Eventi';
    if (livello >= 7) return '🔥 Master Gamifier';
    if (livello >= 5) return '⚡ Anima della Festa';
    if (livello >= 3) return '🎲 Giocatore Esperto';
    return '🌱 Recluta Fanta Eventi';
  }

  @override
  Widget build(BuildContext context) {
    final double xpPercent = (_utente.xp / _utente.xpProssimoLivello).clamp(0.0, 1.0);

    final ImageProvider avatarImage = _fotoLocaleFile != null && _fotoLocaleFile!.existsSync()
        ? FileImage(_fotoLocaleFile!)
        : getAvatarImageProvider(_utente.avatarUrl);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Profilo Giocatore',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: () async {
              await _apiService.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginView()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
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
                      'Tocca per scattare una foto o dalla galleria',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFFACC15), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      _utente.nome,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getRankTitle(_utente.livello),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFACC15),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _utente.email,
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
                                    _utente.codiceAmico,
                                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFFACC15)),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF10B981),
                                      content: Text('Codice Amico ${_utente.codiceAmico} copiato! Condividilo su WhatsApp! 📲', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
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
                                '${_utente.xp} / ${_utente.xpProssimoLivello} XP',
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
                                  '${_utente.puntiTotali}',
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${_utente.amici.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                                Text(
                                  'Amici',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                                  '${_utente.badgeVincitore.length}',
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
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // BACHECA TITOLI E RICONOSCIMENTI
              _buildBachecaTitoli(),
              const SizedBox(height: 24),

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
              // LISTA AMICI CONFERMATI
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'I Tuoi Amici (${_utente.amici.length}) 👥',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(height: 10),
              if (_utente.amici.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    'Non hai ancora aggiunto nessun amico. Condividi il tuo Codice Amico!',
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _utente.amici.map((amico) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: const Color(0xFF10B981),
                            child: Text(
                              amico.isNotEmpty ? amico[0].toUpperCase() : 'A',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            amico,
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 24),

              // BACHECA TROFEI VINCITORE
              if (_utente.badgeVincitore.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bacheca Vittorie 🏆',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _utente.badgeVincitore.length,
                  itemBuilder: (ctx, i) {
                    final b = _utente.badgeVincitore[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFACC15), Color(0xFFB45309)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.emoji_events_rounded, color: Color(0xFF0F172A), size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('1° POSTO: ${b['evento'] ?? "Evento"}', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF0F172A))),
                                Text('Punti totalizzati: ${b['punti'] ?? 0} PT', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Badge Section
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Badge Sbloccati 🏆',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _utente.badgeList.map((badge) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFACC15).withValues(alpha: 0.1),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

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
                      selected: _filtroGiorniStorico == 1,
                      label: const Text('Ultimi 24h'),
                      selectedColor: const Color(0xFF9333EA),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: _filtroGiorniStorico == 1 ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setState(() => _filtroGiorniStorico = 1),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _filtroGiorniStorico == 3,
                      label: const Text('Ultimi 3 Giorni'),
                      selectedColor: const Color(0xFF9333EA),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: _filtroGiorniStorico == 3 ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setState(() => _filtroGiorniStorico = 3),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _filtroGiorniStorico == 7,
                      label: const Text('Ultimi 7 Giorni'),
                      selectedColor: const Color(0xFF9333EA),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: _filtroGiorniStorico == 7 ? Colors.white : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setState(() => _filtroGiorniStorico = 7),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final storicoFiltrato = ApiService.filtraStorico(_utente.storicoVoti, maxGiorni: _filtroGiorniStorico);
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
                  count: _countCampione,
                  color: const Color(0xFFFACC15),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBachecaBadge(
                  icon: '🤡',
                  label: 'Re Malus',
                  count: _countReMalus,
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
                  label: 'Giudice',
                  count: _countGiudiceSupremo,
                  color: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBachecaBadge(
                  icon: '👻',
                  label: 'Fantasma',
                  count: _countFantasma,
                  color: const Color(0xFF94A3B8),
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
