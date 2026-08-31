import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../models/evento.dart';
import '../models/utente.dart';

class CreateEventView extends StatefulWidget {
  const CreateEventView({super.key});

  @override
  State<CreateEventView> createState() => _CreateEventViewState();
}

class _CreateEventViewState extends State<CreateEventView> {
  final _formKey = GlobalKey<FormState>();
  final _titoloController = TextEditingController();
  final _descrizioneController = TextEditingController();
  final _luogoController = TextEditingController();
  final _copertinaController = TextEditingController();
  final _searchController = TextEditingController();

  DateTime _selectedStartDate = DateTime.now().add(const Duration(hours: 1));
  DateTime _selectedEndDate = DateTime.now().add(const Duration(days: 1, hours: 1));
  final List<String> _partecipantiSelezionati = [];
  List<Utente> _utentiMongoDB = [];
  List<Utente> _utentiFiltrati = [];
  bool _isLoading = false;
  bool _isLoadingUtenti = true;

  final ApiService _apiService = ApiService();

  Future<void> _pickStartDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedStartDate),
      );
      if (pickedTime != null) {
        setState(() {
          _selectedStartDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          if (_selectedEndDate.isBefore(_selectedStartDate)) {
            _selectedEndDate = _selectedStartDate.add(const Duration(hours: 24));
          }
        });
      }
    }
  }

  Future<void> _pickEndDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate,
      firstDate: _selectedStartDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedEndDate),
      );
      if (pickedTime != null) {
        setState(() {
          _selectedEndDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final curUser = _apiService.currentUser;
    if (curUser != null) {
      final nick = curUser.nome.isNotEmpty ? curUser.nome : 'Cloud';
      _partecipantiSelezionati.add(nick);
    }
    _caricaUtentiMongoDB();
  }

  Future<void> _caricaUtentiMongoDB() async {
    try {
      final amiciUtenti = await _apiService.getGiocatoriInvitabili();
      if (mounted) {
        setState(() {
          _utentiMongoDB = amiciUtenti;
          _utentiFiltrati = amiciUtenti;
          _isLoadingUtenti = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingUtenti = false;
        });
      }
    }
  }

  void _filtraUtenti(String query) {
    final cleanQuery = query.toLowerCase().trim();
    setState(() {
      if (cleanQuery.isEmpty) {
        _utentiFiltrati = _utentiMongoDB;
      } else {
        _utentiFiltrati = _utentiMongoDB.where((u) {
          final nick = u.nome.toLowerCase();
          final email = u.email.toLowerCase();
          return nick.contains(cleanQuery) || email.contains(cleanQuery);
        }).toList();
      }
    });
  }

  void _togglePartecipante(String nickname) {
    setState(() {
      if (_partecipantiSelezionati.contains(nickname)) {
        _partecipantiSelezionati.remove(nickname);
      } else {
        _partecipantiSelezionati.add(nickname);
      }
    });
  }

  @override
  void dispose() {
    _titoloController.dispose();
    _descrizioneController.dispose();
    _luogoController.dispose();
    _copertinaController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState?.validate() ?? false) {
      if (_partecipantiSelezionati.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona almeno un partecipante per l\'evento')),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final curUser = _apiService.currentUser;
      final creatore = curUser?.nome ?? 'Cloud';

      final nuovoEvento = Evento(
        id: 'e_${DateTime.now().millisecondsSinceEpoch}',
        titolo: _titoloController.text.trim(),
        descrizione: _descrizioneController.text.trim(),
        data: _selectedStartDate,
        dataFine: _selectedEndDate,
        luogo: _luogoController.text.trim(),
        stato: 'in_programma',
        propostoDa: creatore,
        partecipanti: _partecipantiSelezionati,
        bonusMalusApplicati: [],
        votazioniAttive: [],
        copertinaUrl: _copertinaController.text.trim().isNotEmpty
            ? _copertinaController.text.trim()
            : 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=800&q=80',
      );

      await _apiService.creaEvento(nuovoEvento);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFACC15),
          content: Text(
            'Evento creato con successo! +100 XP guadagnati! 🎉',
            style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold),
          ),
        ),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Nuovo Evento Fanta',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crea una nuova esperienza',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Seleziona i partecipanti reali registrati nel database MongoDB',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 24),

                // Titolo
                TextFormField(
                  controller: _titoloController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Titolo Evento',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.title, color: Color(0xFFFACC15)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Inserisci il titolo dell\'evento' : null,
                ),
                const SizedBox(height: 16),

                // Descrizione
                TextFormField(
                  controller: _descrizioneController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Descrizione / Regole goliardiche',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.description, color: Color(0xFF9333EA)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Inserisci la descrizione' : null,
                ),
                const SizedBox(height: 16),

                // Luogo
                TextFormField(
                  controller: _luogoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Luogo / Location',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.place, color: Color(0xFFFACC15)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Inserisci il luogo' : null,
                ),
                const SizedBox(height: 20),

                // Date & Time Picker Inizio
                InkWell(
                  onTap: _pickStartDateTime,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Data & Ora di Inizio',
                              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11),
                            ),
                            Text(
                              '${_selectedStartDate.day}/${_selectedStartDate.month}/${_selectedStartDate.year} alle ${_selectedStartDate.hour.toString().padLeft(2, '0')}:${_selectedStartDate.minute.toString().padLeft(2, '0')}',
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded, color: Color(0xFF94A3B8), size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Date & Time Picker Fine
                InkWell(
                  onTap: _pickEndDateTime,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.stop_circle_rounded, color: Color(0xFFEF4444)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Data & Ora di Fine (Rimozione Automatica)',
                              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11),
                            ),
                            Text(
                              '${_selectedEndDate.day}/${_selectedEndDate.month}/${_selectedEndDate.year} alle ${_selectedEndDate.hour.toString().padLeft(2, '0')}:${_selectedEndDate.minute.toString().padLeft(2, '0')}',
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded, color: Color(0xFF94A3B8), size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // SEZIONE INVITO PARTECEPATI CON BARRA DI RICERCA REALE DA MONGODB
                Row(
                  children: [
                    const Icon(Icons.group_add, color: Color(0xFFFACC15), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Invita Partecipanti dal Database',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Cerca gli utenti registrati per Nickname ed aggiungili con un tap:',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 12),

                // Barra di Ricerca Utenti
                TextField(
                  controller: _searchController,
                  onChanged: _filtraUtenti,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Cerca per Nickname (es. Ziogab, Lore8, AleM8...)',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFFFACC15)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Partecipanti Selezionati (Chips)
                if (_partecipantiSelezionati.isNotEmpty) ...[
                  Text(
                    'Partecipanti selezionati (${_partecipantiSelezionati.length}):',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFFACC15)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _partecipantiSelezionati.map((p) {
                      return Chip(
                        label: Text(p, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                        backgroundColor: const Color(0xFF9333EA).withValues(alpha: 0.3),
                        side: const BorderSide(color: Color(0xFF9333EA)),
                        deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white),
                        onDeleted: () => _togglePartecipante(p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Lista Utenti Filtrati da MongoDB
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: _isLoadingUtenti
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(color: Color(0xFFFACC15)),
                        ))
                      : _utentiFiltrati.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                'Nessun utente trovato con questo Nickname.',
                                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _utentiFiltrati.length,
                              separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                              itemBuilder: (ctx, idx) {
                                final user = _utentiFiltrati[idx];
                                final nick = user.nome.isNotEmpty ? user.nome : 'Utente';
                                final isSelected = _partecipantiSelezionati.contains(nick);

                                return ListTile(
                                  onTap: () => _togglePartecipante(nick),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? const Color(0xFFFACC15) : const Color(0xFF334155),
                                    child: Text(
                                      nick.isNotEmpty ? nick[0].toUpperCase() : 'U',
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    nick,
                                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    user.email,
                                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                                  ),
                                  trailing: Icon(
                                    isSelected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                    color: isSelected ? const Color(0xFFFACC15) : const Color(0xFF64748B),
                                  ),
                                );
                              },
                            ),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Color(0xFF0F172A))
                        : Text(
                            'CREA EVENTO (+100 XP)',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
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
