import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/utente.dart';
import '../services/api_service.dart';
import 'login_view.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();
  late Utente _utente;
  File? _fotoLocaleFile;

  final List<String> _avatarsPredefiniti = [
    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1580489944761-15a19d654956?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1628157582853-a796fa650a6a?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80',
  ];

  @override
  void initState() {
    super.initState();
    _utente = _apiService.currentUser ?? _apiService.getCurrentUser();
    _caricaProfiloAggiornato();
  }

  Future<void> _caricaProfiloAggiornato() async {
    try {
      final utenti = await _apiService.getUtenti();
      final cur = _apiService.currentUser ?? _utente;
      final match = utenti.firstWhere(
        (u) => u.nome.trim().toLowerCase() == cur.nome.trim().toLowerCase(),
        orElse: () => cur,
      );

      final List<String> finalBadges = match.badgeList.length >= cur.badgeList.length
          ? match.badgeList
          : cur.badgeList;

      final List<String> finalStorico = match.storicoVoti.length >= cur.storicoVoti.length
          ? match.storicoVoti
          : cur.storicoVoti;

      final int highestXp = [
        _utente.xp,
        cur.xp,
        match.xp,
      ].reduce((a, b) => a > b ? a : b);

      final String finalAvatar = _utente.avatarUrl.contains('data:image')
          ? _utente.avatarUrl
          : (match.avatarUrl.isNotEmpty
              ? match.avatarUrl
              : (cur.avatarUrl.isNotEmpty ? cur.avatarUrl : _utente.avatarUrl));

      final merged = cur.copyWith(
        avatarUrl: finalAvatar,
        xp: highestXp,
        badgeList: finalBadges,
        storicoVoti: finalStorico,
      );

      final hasChanged = _utente.xp != merged.xp ||
          _utente.avatarUrl != merged.avatarUrl ||
          _utente.badgeList.length != merged.badgeList.length ||
          _utente.storicoVoti.length != merged.storicoVoti.length;

      if (mounted && hasChanged) {
        setState(() {
          _utente = merged;
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

    ImageProvider avatarImage;
    if (_utente.avatarUrl.contains('base64,')) {
      try {
        final cleanB64 = _utente.avatarUrl.substring(_utente.avatarUrl.indexOf('base64,') + 7).trim();
        avatarImage = MemoryImage(base64Decode(cleanB64));
      } catch (_) {
        avatarImage = NetworkImage(_avatarsPredefiniti[0]);
      }
    } else if (_fotoLocaleFile != null && _fotoLocaleFile!.existsSync()) {
      avatarImage = FileImage(_fotoLocaleFile!);
    } else if ((_utente.avatarUrl.startsWith('/') || _utente.avatarUrl.startsWith('C:') || _utente.avatarUrl.contains('data/user')) && File(_utente.avatarUrl).existsSync()) {
      avatarImage = FileImage(File(_utente.avatarUrl));
    } else if (_utente.avatarUrl.startsWith('http://') || _utente.avatarUrl.startsWith('https://')) {
      avatarImage = NetworkImage(_utente.avatarUrl);
    } else {
      avatarImage = NetworkImage(_avatarsPredefiniti[0]);
    }

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
                                  '${_utente.badgeList.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF9333EA),
                                  ),
                                ),
                                Text(
                                  'Badge Sbloccati',
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

              // Storico Attività
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Storico Voti & Attività 📜',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_utente.storicoVoti.isEmpty)
                Text(
                  'Nessuna attività registrata finora.',
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _utente.storicoVoti.length,
                  itemBuilder: (context, index) {
                    final item = _utente.storicoVoti[index];
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}
