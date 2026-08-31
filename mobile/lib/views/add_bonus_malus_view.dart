import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../models/bonus_malus.dart';
import '../models/evento.dart';

class AddBonusMalusView extends StatefulWidget {
  final Evento? evento;
  const AddBonusMalusView({super.key, this.evento});

  @override
  State<AddBonusMalusView> createState() => _AddBonusMalusViewState();
}

class _AddBonusMalusViewState extends State<AddBonusMalusView> {
  final _formKey = GlobalKey<FormState>();
  final _titoloController = TextEditingController();
  final _descrizioneController = TextEditingController();
  final _puntiController = TextEditingController(text: '10');

  bool _isBonus = true;
  bool _riassegnabileMoltepliciVolte = false;
  String _categoriaSelezionata = 'Goliardia';
  Evento? _eventoSelezionato;
  bool _isLoading = false;

  final List<String> _categorie = [
    'Goliardia',
    'Cibo & Drink',
    'Stile & Outfit',
    'Puntualità',
    'Performance',
    'Special',
  ];

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _eventoSelezionato = widget.evento;
  }

  @override
  void dispose() {
    _titoloController.dispose();
    _descrizioneController.dispose();
    _puntiController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState?.validate() ?? false) {
      if (_eventoSelezionato == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona un evento a cui collegare il bonus/malus!')),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      int mePunti = int.tryParse(_puntiController.text.trim()) ?? 10;
      if (!_isBonus && mePunti > 0) {
        mePunti = -mePunti;
      } else if (_isBonus && mePunti < 0) {
        mePunti = mePunti.abs();
      }

      final meUser = _apiService.getCurrentUser();

      final nuovoBonus = BonusMalus(
        id: 'bm_${DateTime.now().millisecondsSinceEpoch}',
        titolo: _titoloController.text.trim(),
        descrizione: _descrizioneController.text.trim(),
        punti: mePunti,
        categoria: _categoriaSelezionata,
        propostoDa: meUser.nome,
        approvato: false,
        riassegnabileMoltepliciVolte: _riassegnabileMoltepliciVolte,
      );

      await _apiService.proponiBonusMalusPerEvento(_eventoSelezionato!.id, nuovoBonus);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF9333EA),
          content: Text(
            'Proposta per "${_eventoSelezionato!.titolo}" inviata! +50 XP guadagnati! 🚀',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
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
          'Proponi Bonus / Malus',
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
                // Event Banner
                if (_eventoSelezionato != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available_rounded, color: Color(0xFFFACC15)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Evento Collegato:',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                              ),
                              Text(
                                _eventoSelezionato!.titolo,
                                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  FutureBuilder<List<Evento>>(
                    future: _apiService.getEventi(),
                    builder: (context, snapshot) {
                      final eventi = snapshot.data ?? [];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        child: DropdownButtonFormField<Evento>(
                          dropdownColor: const Color(0xFF1E293B),
                          decoration: InputDecoration(
                            labelText: 'Seleziona Evento',
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          items: eventi.map((e) {
                            return DropdownMenuItem(
                              value: e,
                              child: Text(e.titolo, style: const TextStyle(color: Colors.white)),
                            );
                          }).toList(),
                          onChanged: (ev) {
                            setState(() {
                              _eventoSelezionato = ev;
                            });
                          },
                        ),
                      );
                    },
                  ),

                Text(
                  'Nuova Regola Goliardica',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Proponi un bonus o malus legato all\'evento. Verrà creata una votazione con quorum democratico.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 24),

                // Toggle Switch BONUS vs MALUS
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isBonus = true;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _isBonus ? const Color(0xFFFACC15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: _isBonus ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'BONUS (+)',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: _isBonus ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isBonus = false;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: !_isBonus ? const Color(0xFF9333EA) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.dangerous_rounded,
                                  color: !_isBonus ? Colors.white : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'MALUS (-)',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: !_isBonus ? Colors.white : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Titolo
                TextFormField(
                  controller: _titoloController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Titolo Regola',
                    hintText: _isBonus ? 'Es. Canto epico al Karaoke' : 'Es. Bicchiere rovesciato',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: Icon(
                      _isBonus ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: _isBonus ? const Color(0xFFFACC15) : const Color(0xFF9333EA),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Inserisci un titolo' : null,
                ),
                const SizedBox(height: 16),

                // Descrizione
                TextFormField(
                  controller: _descrizioneController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Descrizione / Regola di ingaggio',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.notes, color: Color(0xFF94A3B8)),
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

                // Punteggio & Categoria
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _puntiController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Punti',
                          prefixIcon: Icon(
                            Icons.score,
                            color: _isBonus ? const Color(0xFFFACC15) : const Color(0xFF9333EA),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Punti?';
                          if (int.tryParse(val) == null) return 'Numero valido';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _categoriaSelezionata,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Categoria',
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                        items: _categorie.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(c, style: GoogleFonts.inter(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _categoriaSelezionata = val;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Checkbox Riassegnabile Molteplici Volte
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: CheckboxListTile(
                    value: _riassegnabileMoltepliciVolte,
                    onChanged: (val) {
                      setState(() {
                        _riassegnabileMoltepliciVolte = val ?? false;
                      });
                    },
                    activeColor: const Color(0xFFFACC15),
                    checkColor: const Color(0xFF0F172A),
                    title: Text(
                      'Riassegnabile più di una volta',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    subtitle: Text(
                      'Consente di riassegnare questo bonus/malus più volte alla stessa persona',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isBonus ? const Color(0xFFFACC15) : const Color(0xFF9333EA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'PROPONI ALL\'EVENTO (+50 XP)',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _isBonus ? const Color(0xFF0F172A) : Colors.white,
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
