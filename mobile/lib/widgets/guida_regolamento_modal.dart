import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class GuidaRegolamentoModal extends StatefulWidget {
  final bool isFirstAccess;
  const GuidaRegolamentoModal({super.key, this.isFirstAccess = false});

  static Future<bool?> mostra(BuildContext context, {bool isFirstAccess = false}) async {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (ctx) => GuidaRegolamentoModal(isFirstAccess: isFirstAccess),
    );
  }

  @override
  State<GuidaRegolamentoModal> createState() => _GuidaRegolamentoModalState();
}

class _GuidaRegolamentoModalState extends State<GuidaRegolamentoModal> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final ApiService _apiService = ApiService();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _chiudiGuida({bool startTutorial = false}) {
    if (!startTutorial) {
      _apiService.segnaGuidaRegoleCompletata(awardXp: false);
    }
    if (mounted) {
      Navigator.of(context).pop(startTutorial);
    }
  }

  void _prossimaPagina() {
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _chiudiGuida(startTutorial: widget.isFirstAccess);
    }
  }

  void _paginaPrecedente() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF475569),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header con indicatore slide e tasto Salta
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Indicatore pallini
                Row(
                  children: List.generate(5, (index) {
                    final isCurrent = index == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(right: 6),
                      width: isCurrent ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFFFACC15)
                            : const Color(0xFF475569),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),

                // Tasto Salta / Chiudi
                TextButton(
                  onPressed: () => _chiudiGuida(startTutorial: false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _currentPage == 4
                        ? (widget.isFirstAccess ? 'Salta' : 'Chiudi')
                        : 'Salta',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF334155), height: 1),

          // Contenuto PageView
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page;
                });
              },
              children: [
                _buildSlide1(),
                _buildSlide2(),
                _buildSlide3(),
                _buildSlide4(),
                _buildSlide5(),
              ],
            ),
          ),

          const Divider(color: Color(0xFF334155), height: 1),

          // Barra di navigazione inferiore
          Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: MediaQuery.of(context).padding.bottom + 14,
            ),
            child: _currentPage == 4
                ? SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => _chiudiGuida(startTutorial: widget.isFirstAccess),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFACC15),
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.isFirstAccess
                                ? '🎮 INIZIA TUTORIAL GUIDATO (+100 XP)'
                                : 'HO CAPITO, ANDIAMO A GIOCARE!',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(widget.isFirstAccess ? '✨' : '🚀', style: const TextStyle(fontSize: 18)),
                        ],
                      ),
                    ),
                  )
                : Row(
                    children: [
                      if (_currentPage > 0) ...[
                        OutlinedButton(
                          onPressed: _paginaPrecedente,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF94A3B8),
                            side: const BorderSide(color: Color(0xFF475569)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, size: 20),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _prossimaPagina,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9333EA),
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'AVANTI',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_forward_rounded, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SLIDE 1: BENVENUTO SU FANTAEVENTI
  // ==========================================
  Widget _buildSlide1() {
    return _buildSlideContainer(
      icon: '🎉',
      badge: 'BENVENUTO',
      title: 'Cos\'è FantaEventi?',
      subtitle: 'Come trasformare qualsiasi serata in un gioco tra amici',
      items: [
        _buildInfoItem(
          icon: '🎮',
          title: 'Un gioco a punti tra amici dal vivo',
          description:
              'FantaEventi trasforma qualsiasi momento reale (feste di compleanno, cene, lauree, serate o vacanze) in una sfida a punti entusiasmante. Tutti i partecipanti sono giocatori attivi e protagonisti!',
        ),
        _buildInfoItem(
          icon: '📅',
          title: 'Crea l\'Evento o Unisciti alla Festa',
          description:
              'L\'organizzatore crea l\'evento in pochi secondi, seleziona il luogo (anche scegliendolo direttamente sulla mappa interattiva!) e invita gli amici.',
        ),
        _buildInfoItem(
          icon: '🏆',
          title: 'Sfida dal vivo e Classifica Live',
          description:
              'Durante la festa compi bonus, evita i malus e segui la Classifica Live aggiornata in tempo reale per scoprire chi trionferà a fine serata!',
        ),
      ],
    );
  }

  // ==========================================
  // SLIDE 2: MECCANICA BONUS, MALUS & VOTI
  // ==========================================
  Widget _buildSlide2() {
    return _buildSlideContainer(
      icon: '⚡',
      badge: 'LE REGOLE DEL GIOCO',
      title: 'Bonus, Malus & Punti',
      subtitle: 'Cosa sono e come vengono convalidati democraticamente',
      items: [
        _buildInfoItem(
          icon: '🌟',
          title: 'Cosa sono i Bonus (+)',
          description:
              'Sono le azioni divertenti, eroiche o goliardiche della serata (es. cantare al karaoke, portare il dolce, fare un brindisi) che ti fanno guadagnare punti preziosi.',
        ),
        _buildInfoItem(
          icon: '🚨',
          title: 'Cosa sono i Malus (-)',
          description:
              'Sono le gaffe, le distrazioni o le penalità concordate (es. rovesciare un bicchiere, arrivare con 30 minuti di ritardo) che sottraggono punti dal punteggio.',
        ),
        _buildInfoItem(
          icon: '🗳️',
          title: 'La Proposta & Il Quorum Democratico',
          description:
              'Chiunque partecipa all\'evento può proporre una nuova regola di Bonus o Malus. La community vota democraticamente a favore (PRO) o contro (CONTRO): se supera il Quorum, la regola diventa ufficiale!',
        ),
        _buildInfoItem(
          icon: '👑',
          title: 'Chi assegna i punti ai giocatori?',
          description:
              'È l\'Organizzatore dell\'evento che, durante lo svolgimento della serata, assegna effettivamente il bonus o il malus a chi ha compiuto l\'azione!',
        ),
      ],
    );
  }

  // ==========================================
  // SLIDE 3: IL TRIBUNALE DEL VAR
  // ==========================================
  Widget _buildSlide3() {
    return _buildSlideContainer(
      icon: '📺',
      badge: 'GIUSTIZIA ARBITRALE',
      title: 'Il Tribunale del VAR',
      subtitle: 'La moviola ufficiale per chiarire ogni contestazione',
      items: [
        _buildInfoItem(
          icon: '⚖️',
          title: 'Che cos\'è il Tribunale del VAR?',
          description:
              'È la "moviola" ufficiale di FantaEventi! Serve a risolvere pacificamente qualsiasi contestazione o dubbio durante la festa: se qualcuno nega un malus o richiede un bonus contestato, si ricorre al VAR senza discutere!',
        ),
        _buildInfoItem(
          icon: '⏳',
          title: 'Attivo solo ad Evento "In Corso"',
          description:
              'Il pulsante [ 📺 VAR ] si sblocca e può essere utilizzato dai partecipanti esclusivamente quando l\'evento è ufficialmente iniziato e in svolgimento.',
        ),
        _buildInfoItem(
          icon: '👨‍⚖️',
          title: 'Il Giudice Arbitro e i Testimoni',
          description:
              'Chi apre la chiamata al VAR sceglie chi segnalare, descrive l\'accaduto e può indicare un amico testimone presente. L\'Organizzatore (il Giudice di gara) esamina la situazione ed emette il verdetto definitivo.',
        ),
        _buildInfoItem(
          icon: '🚨',
          title: 'Attenzione alla Falsa Testimonianza!',
          description:
              'Non fare il furbetto! Se accusi ingiustamente un amico con una denuncia inventata e il Giudice la respinge, subirai una sanzione d\'ufficio per Falsa Testimonianza con perdita secca di punti!',
        ),
      ],
    );
  }

  // ==========================================
  // SLIDE 4: IL CONSIGLIO PRO: LA FOTO-PROVA
  // ==========================================
  Widget _buildSlide4() {
    return _buildSlideContainer(
      icon: '📸',
      badge: 'CONSIGLIO D\'ORO',
      title: 'La Prova Fotografica',
      subtitle: 'Scatta al momento giusto per vincere ogni contestazione!',
      items: [
        _buildInfoItem(
          icon: '🎯',
          title: 'Scatta quando vedi un Bonus o un Malus',
          description:
              'Quando tu o un tuo amico compiete un Bonus, oppure quando vedi qualcuno fare una figuraccia memorabile o compiere un Malus dell\'evento, tira subito fuori lo smartphone e scatta una foto!',
        ),
        _buildInfoItem(
          icon: '🛡️',
          title: 'Perché la foto è così importante?',
          description:
              'Scattare la foto è opzionale, ma utilissimo: se qualcuno dovesse negare l\'episodio o contestare il punteggio, la foto sarà la prova schiacciante e inconfutabile che potrai allegare al Tribunale del VAR per togliere ogni dubbio al Giudice!',
        ),
        _buildInfoItem(
          icon: '🕵️',
          title: 'Bonus personale o Segnalazione Spia',
          description:
              'Puoi allegare la foto sia per richiedere l\'accredito di un tuo Bonus compiuto, sia per denunciare al VAR un Malus commesso da un altro giocatore.',
        ),
      ],
    );
  }

  // ==========================================
  // SLIDE 5: CLASSIFICA & TITOLI D'ONORE
  // ==========================================
  Widget _buildSlide5() {
    return _buildSlideContainer(
      icon: '🎖️',
      badge: 'GLORIA & BACHECA',
      title: 'Classifica & Titoli d\'Onore',
      subtitle: 'Come si vince e i trofei permanenti della tua bacheca',
      items: [
        _buildInfoItem(
          icon: '🏆',
          title: 'Il Podio e la Gloria Eterna',
          description:
              'A fine evento, chi ha totalizzato più punti vince la coppa e riceve il prestigioso Badge Vincitore permanente nella propria bacheca pubblica!',
        ),
        _buildInfoItem(
          icon: '🎭',
          title: 'I Titoli Speciali di Fine Evento',
          description:
              'Al termine dell\'evento l\'algoritmo incorona i protagonisti della serata:\n'
              '• 🤡 Re dei Malus: Chi ha collezionato più penalità.\n'
              '• ⚖️ L\'Avvocato: Chi ha partecipato a più votazioni e proposte.\n'
              '• 👻 Il Fantasma: Chi ha fatto il minimo indispensabile.\n'
              '• 🕵️ Lo Sbirro: Chi ha fatto più denunce malus al VAR.\n'
              '• ⚡ Il Giustiziere: Chi ha aperto più chiamate VAR approvate con successo.',
        ),
        _buildInfoItem(
          icon: '🆔',
          title: 'Codice Amico nel Profilo',
          description:
              'Nel tuo profilo trovi il tuo Codice Amico esclusivo da condividere ai tuoi compagni di avventure per creare la tua cerchia e sfidarli nei prossimi eventi!',
        ),
      ],
    );
  }

  // Helper per costruire il contenitore della slide
  Widget _buildSlideContainer({
    required String icon,
    required String badge,
    required String title,
    required String subtitle,
    required List<Widget> items,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge e Icona in testata
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F172A),
                  border: Border.all(
                    color: const Color(0xFFFACC15).withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Text(icon, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9333EA).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF9333EA).withValues(alpha: 0.6)),
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFC084FC),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),

          // Elementi informativi
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required String icon,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFACC15),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.45,
                    color: const Color(0xFFE2E8F0),
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
