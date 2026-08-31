import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class NotificationsModal extends StatefulWidget {
  final VoidCallback onRefreshHome;
  final void Function(int tabIndex)? onNavigateTab;
  const NotificationsModal({super.key, required this.onRefreshHome, this.onNavigateTab});

  @override
  State<NotificationsModal> createState() => _NotificationsModalState();
}

class _NotificationsModalState extends State<NotificationsModal> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _notifiche = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _caricaNotifiche();
  }

  Future<void> _caricaNotifiche() async {
    setState(() {
      _isLoading = true;
    });

    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';
    final res = await _apiService.getNotifiche(nick);

    if (mounted) {
      setState(() {
        _notifiche = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _rispondi(String notificaId, String azione, {String? mittente, String? tipo}) async {
    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';

    if (tipo == 'richiesta_amicizia' && mittente != null) {
      await _apiService.rispondiRichiestaAmicizia(notificaId, mittente, azione == 'accetta');
    } else {
      await _apiService.rispondiNotifica(notificaId, azione, nick);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: azione == 'accetta' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(
            tipo == 'richiesta_amicizia'
                ? (azione == 'accetta' ? 'Richiesta di amicizia accettata! 👥' : 'Richiesta di amicizia rifiutata.')
                : (azione == 'accetta' ? 'Invito accettato con successo! 🎉' : 'Invito rifiutato.'),
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    widget.onRefreshHome();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active, color: Color(0xFFFACC15), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Centro Notifiche & Inviti',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _isLoading
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: Color(0xFFFACC15)),
                ))
              : _notifiche.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          const Icon(Icons.notifications_none_rounded, size: 48, color: Color(0xFF64748B)),
                          const SizedBox(height: 12),
                          Text(
                            'Nessun nuovo invito o notifica al momento.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.65,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _notifiche.length,
                          itemBuilder: (ctx, idx) {
                            final not = _notifiche[idx];
                            final isPending = not['stato'] == 'in_attesa';
                            final isProposal = not['tipo'] == 'info' || not['tipo'] == 'bonus_malus';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isPending ? const Color(0xFFFACC15).withValues(alpha: 0.5) : const Color(0xFF334155),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          not['titolo'] ?? 'Notifica',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (!isPending && !isProposal) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: not['stato'] == 'accettato' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            (not['stato'] as String).toUpperCase(),
                                            style: GoogleFonts.poppins(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    not['messaggio'] ?? '',
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                                  ),
                                  const SizedBox(height: 12),

                                  if (isProposal) ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          if (widget.onNavigateTab != null) {
                                            widget.onNavigateTab!(2);
                                          }
                                        },
                                        icon: const Icon(Icons.how_to_vote_rounded, size: 16, color: Colors.white),
                                        label: Text(
                                          '🗳️ VAI A VOTAZIONI LIVE',
                                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6366F1),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ] else if (isPending) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _rispondi(not['id'], 'accetta', mittente: not['mittente'], tipo: not['tipo']),
                                            icon: const Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                                            label: const Text('ACCETTA'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF10B981),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _rispondi(not['id'], 'rifiuta', mittente: not['mittente'], tipo: not['tipo']),
                                            icon: const Icon(Icons.cancel_rounded, size: 16, color: Colors.white),
                                            label: const Text('RIFIUTA'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFEF4444),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
        ],
      ),
    );
  }
}
