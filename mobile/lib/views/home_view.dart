import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../models/evento.dart';
import '../models/bonus_malus.dart';
import '../models/votazione.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/event_card.dart';
import '../widgets/bonus_malus_card.dart';
import '../widgets/vote_card.dart';
import 'create_event_view.dart';
import 'add_bonus_malus_view.dart';
import 'vote_view.dart';
import 'profile_view.dart';
import 'notifications_modal.dart';
import 'event_detail_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  List<Evento> _eventi = [];
  List<BonusMalus> _bonusMalusList = [];
  List<Votazione> _votazioniList = [];
  int _numeroNotifiche = 0;
  bool _isLoading = true;

  late TabController _tabController;
  Timer? _liveSyncTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadData(silent: true, forceRefresh: false);
    });
  }

  final Set<String> _readNotificaIds = {};

  Future<void> _loadData({bool silent = false, bool forceRefresh = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
      });
      await _apiService.syncCurrentUserFromDb();
    }

    final meEventi = await _apiService.getEventi(forceRefresh: forceRefresh);
    final meBonus = await _apiService.getBonusMalusList();
    final meVoti = await _apiService.getVotazioni();

    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';
    final nots = await _apiService.getNotifiche(nick);
    final unreadNots = nots.where((n) {
      final nId = (n['id'] ?? '').toString();
      if (nId.isNotEmpty && _readNotificaIds.contains(nId)) return false;
      if (n['letto'] == true || n['stato'] == 'letto') return false;
      return true;
    }).toList();

    final inAttesa = unreadNots.length;

    if (!mounted) return;

    setState(() {
      _eventi = meEventi;
      _bonusMalusList = meBonus;
      _votazioniList = meVoti;
      _numeroNotifiche = inAttesa;
      if (!silent) _isLoading = false;
    });
  }

  void _apriNotifiche() async {
    final userNick = _apiService.currentUser?.nome ?? 'Cloud';
    try {
      final nots = await _apiService.getNotifiche(userNick);
      for (var n in nots) {
        final nId = (n['id'] ?? '').toString();
        if (nId.isNotEmpty) _readNotificaIds.add(nId);
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _numeroNotifiche = 0;
      });
    }
    _apiService.segnaNotificheComeLette(userNick);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: NotificationsModal(
          onRefreshHome: () => _loadData(silent: true, forceRefresh: true),
          onNavigateTab: (tabIndex) {
            if (tabIndex >= 0 && tabIndex < _tabController.length) {
              _tabController.animateTo(tabIndex);
            }
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _numeroNotifiche = 0;
        });
        _loadData(silent: true, forceRefresh: true);
      }
    });
  }

  Future<void> _confermaEliminazioneEvento(Evento evento) async {
    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';

    final confermato = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Eliminare l\'evento?',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Sei sicuro di voler eliminare permanentemente l\'evento "${evento.titolo}" da MongoDB Atlas?',
          style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('ELIMINA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confermato == true) {
      try {
        await _apiService.eliminaEvento(evento.id, nick);
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Evento "${evento.titolo}" eliminato con successo! 🗑️', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        );
        _loadData();
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
  }

  Future<void> _partecipaEvento(Evento evento) async {
    final curUser = _apiService.currentUser;
    final nick = curUser?.nome ?? 'Cloud';

    try {
      await _apiService.partecipaAdEvento(evento.id, nick);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Iscritto con successo a "${evento.titolo}"! 🎉', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
      _loadData();
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

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curUser = _apiService.currentUser;
    final userNick = curUser?.nome ?? 'Cloud';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFACC15), Color(0xFF9333EA)],
                ),
              ),
              child: const Icon(Icons.flash_on, color: Color(0xFF0F172A), size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'FantaEventi',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          // Icona Campanellino Notifiche
          IconButton(
            onPressed: _apriNotifiche,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined, color: Colors.white, size: 26),
                if (_numeroNotifiche > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_numeroNotifiche',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // Profile User Chip (Foto Profilo reale + Livello)
          InkWell(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileView()),
              );
              setState(() {});
              _loadData();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundImage: _getStableAvatarProvider(curUser?.avatarUrl),
                    backgroundColor: const Color(0xFF334155),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9333EA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Lvl ${curUser?.livello ?? 1}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFACC15),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFACC15),
          unselectedLabelColor: const Color(0xFF94A3B8),
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Feed Eventi'),
            Tab(text: 'Bonus & Malus'),
            Tab(text: 'Votazioni Live'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFACC15)),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // --- TAB 1: FEED EVENTI ---
                _buildEventiTab(userNick),

                // --- TAB 2: BONUS & MALUS ---
                _buildBonusMalusTab(),

                // --- TAB 3: VOTAZIONI LIVE ---
                _buildVotazioniTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_tabController.index == 0) {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateEventView()));
          } else {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddBonusMalusView()));
          }
          _loadData();
        },
        backgroundColor: const Color(0xFF9333EA),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          _tabController.index == 0
              ? 'NUOVO EVENTO'
              : _tabController.index == 1
                  ? 'NUOVO BONUS'
                  : 'CREA VOTO',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEventiTab(String userNick) {
    Widget child;
    if (_eventi.isEmpty) {
      child = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_busy_rounded, size: 64, color: Color(0xFF64748B)),
                const SizedBox(height: 16),
                Text(
                  'Nessun evento disponibile',
                  style: GoogleFonts.poppins(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tocca + in basso per creare il primo evento!',
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      child = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _eventi.length,
        itemBuilder: (ctx, idx) {
          final ev = _eventi[idx];
          return EventCard(
            evento: ev,
            currentUserNickname: userNick,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EventDetailView(evento: ev, onRefresh: _loadData)),
              );
              _loadData();
            },
            onPartecipa: () => _partecipaEvento(ev),
            onElimina: () => _confermaEliminazioneEvento(ev),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFFACC15),
      backgroundColor: const Color(0xFF1E293B),
      child: child,
    );
  }

  Widget _buildBonusMalusTab() {
    final currentUserNick = _apiService.currentUser?.nome ?? 'Cloud';
    final cleanUser = currentUserNick.trim().toLowerCase();

    final activeEvents = _eventi.where((e) =>
      e.stato.trim().toLowerCase() != 'concluso' && !DateTime.now().isAfter(e.dataFine)
    ).toList();

    Widget child;
    if (activeEvents.isEmpty) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off_rounded, size: 64, color: Color(0xFF64748B)),
                const SizedBox(height: 16),
                Text(
                  'Nessuna cartella evento in corso',
                  style: GoogleFonts.poppins(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Crea o partecipa ad un evento attivo per sbloccare i suoi Bonus/Malus!',
                  style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      child = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: activeEvents.length,
        itemBuilder: (ctx, idx) {
          final ev = activeEvents[idx];
          final cleanCreatore = (ev.creatore.isNotEmpty ? ev.creatore : ev.propostoDa).trim().toLowerCase();
          final isOrganizzatore = cleanCreatore == cleanUser;

          // Filtra tutti i bonus/malus approvati per questo evento
          final approvedForEvent = _bonusMalusList.where((b) {
            final isSameEv = b.eventoId.trim().toLowerCase() == ev.id.trim().toLowerCase() ||
                b.eventoId.trim().toLowerCase() == ev.titolo.trim().toLowerCase();
            final isApprovato = b.stato == 'approvato' || b.stato == 'confermato' || b.approvato;
            final isMine = b.propostoDa.trim().toLowerCase() == cleanUser;
            return isSameEv && (isApprovato || isMine);
          }).toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.folder_special_rounded, color: Color(0xFFC084FC), size: 24),
                ),
                title: Text(
                  ev.titolo,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                subtitle: Text(
                  '${approvedForEvent.length} Bonus/Malus approvati • Org: ${ev.creatore.isNotEmpty ? ev.creatore : ev.propostoDa}',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: approvedForEvent.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Text(
                              'Nessun bonus o malus approvato al momento per questo evento.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                            ),
                          )
                        : Column(
                            children: approvedForEvent.map((bm) {
                              final isMine = bm.propostoDa.trim().toLowerCase() == cleanUser;
                              return BonusMalusCard(
                                bonusMalus: bm,
                                onElimina: isMine
                                    ? () async {
                                        await _apiService.eliminaBonusMalus(bm.id);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Proposta Bonus/Malus eliminata con successo! 🗑️')),
                                        );
                                        _loadData();
                                      }
                                    : null,
                                onAssegna: isOrganizzatore
                                    ? () => _apriSelettoreAssegnazione(ev, bm)
                                    : null,
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFFACC15),
      backgroundColor: const Color(0xFF1E293B),
      child: child,
    );
  }

  ImageProvider? _cachedAvatarProvider;
  String? _cachedAvatarUrl;

  ImageProvider _getStableAvatarProvider(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return const AssetImage('assets/images/cloud.png');
    }
    if (avatarUrl != _cachedAvatarUrl) {
      _cachedAvatarUrl = avatarUrl;
      _cachedAvatarProvider = getAvatarImageProvider(avatarUrl);
    }
    return _cachedAvatarProvider!;
  }

  void _apriSelettoreAssegnazione(Evento ev, BonusMalus bm) {
    final partecipanti = ev.partecipanti.isNotEmpty ? ev.partecipanti : ['Cloud', 'Ugnom'];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assegna "${bm.titolo}"',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            Text(
                              'Seleziona il partecipante all\'evento "${ev.titolo}"',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Partecipanti all\'evento (${partecipanti.length}):',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: partecipanti.length,
                      itemBuilder: (context, i) {
                        final part = partecipanti[i];
                        final giaAssegnato = bm.assegnatoA.any((u) => u.trim().toLowerCase() == part.trim().toLowerCase());

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF9333EA),
                              child: Text(part.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(part, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
                            trailing: (giaAssegnato && !bm.riassegnabileMoltepliciVolte)
                                ? ElevatedButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF94A3B8)),
                                    label: const Text('✓ Già assegnato'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF334155),
                                      foregroundColor: const Color(0xFF94A3B8),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: () async {
                                      final isBonus = bm.punti >= 0;
                                      final ptStr = isBonus ? '+${bm.punti}' : '${bm.punti}';
                                      final xpEarned = isBonus ? bm.punti * 10 : 0;

                                      final confermato = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogCtx) {
                                          return AlertDialog(
                                            backgroundColor: const Color(0xFF1E293B),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            title: Row(
                                              children: [
                                                const Icon(Icons.emoji_events_rounded, color: Color(0xFFFACC15), size: 24),
                                                const SizedBox(width: 10),
                                                Text(
                                                  'Conferma Assegnazione',
                                                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                                ),
                                              ],
                                            ),
                                            content: Text(
                                              'L\'assegnazione del ${isBonus ? "bonus" : "malus"} "${bm.titolo}" comporterà per "$part" una modifica di $ptStr PT ed un incremento di +$xpEarned XP.\n\nSei sicuro di voler procedere?',
                                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1)),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(dialogCtx, false),
                                                child: Text('Annulla', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8))),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => Navigator.pop(dialogCtx, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF10B981),
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                child: Text('Sì, Assegna', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          );
                                        },
                                      );

                                      if (confermato != true) return;

                                      await _apiService.assegnaBonusMalusAPartecipante(
                                        eventoId: ev.id,
                                        bonusId: bm.id,
                                        utenteDestinatario: part,
                                        punti: bm.punti,
                                        eventoTitolo: ev.titolo,
                                        bonusTitolo: bm.titolo,
                                      );

                                      if (!bm.assegnatoA.any((u) => u.trim().toLowerCase() == part.trim().toLowerCase())) {
                                        bm.assegnatoA.add(part);
                                      }

                                      setModalState(() {});
                                      _loadData(silent: true, forceRefresh: true);

                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF10B981),
                                          content: Text(
                                            '🏆 ${bm.punti >= 0 ? "Bonus" : "Malus"} "${bm.titolo}" (${bm.punti >= 0 ? "+${bm.punti}" : bm.punti} PT) assegnato con successo a $part!',
                                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                      );
                                      _loadData();
                                    },
                                    icon: const Icon(Icons.check_rounded, size: 16),
                                    label: const Text('Assegna'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
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

  Widget _buildVotazioniTab() {
    final curUser = _apiService.currentUser;
    final cleanUser = (curUser?.nome ?? 'Cloud').trim().toLowerCase();
    final cleanNick = (curUser?.nickname ?? '').trim().toLowerCase();
    final cleanId = (curUser?.id ?? '').trim().toLowerCase();

    final activeVotazioni = _votazioniList.where((v) {
      final evId = v.bonusMalus?.eventoId.trim().toLowerCase() ?? '';

      final evMatch = _eventi.firstWhere(
        (e) => (evId.isNotEmpty && (e.id.trim().toLowerCase() == evId || e.titolo.trim().toLowerCase() == evId)) ||
               (e.titolo.isNotEmpty && v.titolo.toLowerCase().contains(e.titolo.toLowerCase())) ||
               (e.titolo.isNotEmpty && v.descrizione.toLowerCase().contains(e.titolo.toLowerCase())),
        orElse: () => Evento(
          id: '',
          titolo: '',
          descrizione: '',
          data: DateTime.now(),
          luogo: '',
          stato: '',
          propostoDa: '',
          partecipanti: [],
          bonusMalusApplicati: [],
          votazioniAttive: [],
        ),
      );

      // REGOLA ASSOLUTA: Se l'evento non appartiene alla lista degli eventi dell'utente (_eventi),
      // significa che l'utente non è invitato e non partecipa: LA VOTAZIONE DEVE ESSERE ESCLUSA!
      if (evMatch.id.isEmpty) {
        return false;
      }

      // Se l'evento è concluso o scaduto, non fa più parte delle votazioni live
      if (evMatch.stato.trim().toLowerCase() == 'concluso' || DateTime.now().isAfter(evMatch.dataFine)) {
        return false;
      }

      // Verifica rigorosa di partecipazione: l'utente deve essere confermato come creatore, partecipante o invitato
      final cleanCreatore = (evMatch.creatore.isNotEmpty ? evMatch.creatore : evMatch.propostoDa).trim().toLowerCase();
      final pList = evMatch.partecipanti.map((p) => p.trim().toLowerCase()).toList();
      final iList = evMatch.invitati.map((p) => p.trim().toLowerCase()).toList();

      final bool isCoinvolto = cleanCreatore == cleanUser || cleanCreatore == cleanNick || cleanCreatore == cleanId ||
                               pList.contains(cleanUser) || pList.contains(cleanNick) || pList.contains(cleanId) ||
                               iList.contains(cleanUser) || iList.contains(cleanNick) || iList.contains(cleanId);

      if (!isCoinvolto) {
        return false;
      }

      return true;
    }).toList();

    Widget child;
    if (activeVotazioni.isEmpty) {
      child = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Text(
              'Nessuna votazione attiva al momento per eventi in corso.',
              style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
            ),
          ),
        ),
      );
    } else {
      child = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: activeVotazioni.length,
        itemBuilder: (ctx, idx) {
          final v = activeVotazioni[idx];
          return VoteCard(
            votazione: v,
            currentUserNickname: _apiService.currentUser?.nome ?? 'Cloud',
            onVotaTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => VoteView(votazione: v)),
              );
              _loadData();
            },
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFFACC15),
      backgroundColor: const Color(0xFF1E293B),
      child: child,
    );
  }
}
