import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class GuidaRegolamentoModal extends StatefulWidget {
  const GuidaRegolamentoModal({super.key});

  static Future<void> mostra(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (ctx) => const GuidaRegolamentoModal(),
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

  void _chiudiGuida() {
    _apiService.segnaGuidaRegoleCompletata();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _prossimaPagina() {
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _chiudiGuida();
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
                  onPressed: _chiudiGuida,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _currentPage == 4 ? 'Chiudi' : 'Salta',
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
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _chiudiGuida,
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
                            'HO CAPITO, ANDIAMO A GIOCARE!',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('🚀', style: TextStyle(fontSize: 18)),
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
      subtitle: 'Gamifica qualsiasi momento dal vivo con i tuoi amici!',
      items: [
        _buildInfoItem(
          icon: '🎮',
          title: 'Un gioco a punti dal vivo',
          description:
              'Trasforma compleanni, lauree, serate tra amici, cene e vacanze in un gioco a punti dove tutti i partecipanti sono protagonisti! (Nessun premio fisico, solo gloria e divertimento tra amici).',
        ),
        _buildInfoItem(
          icon: '🤝',
          title: 'Crea o Partecipa agli Eventi',
          description:
              'Entra negli eventi organizzati dai tuoi amici oppure creane uno tuo personalizzato in pochi secondi.',
        ),
        _buildInfoItem(
          icon: '🏆',
          title: 'Sfida gli amici in tempo reale',
          description:
              'Durante la festa compi bonus, evita i malus e scala la Classifica Live per conquistare la vittoria!',
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
      badge: 'DINAMICA DI GIOCO',
      title: 'Bonus, Malus & Punti',
      subtitle: 'Come funziona la convalida e l\'assegnazione',
      items: [
        _buildInfoItem(
          icon: '💡',
          title: 'Proposte della Community',
          description:
              'Chiunque partecipa può proporre nuove idee divertenti di Bonus e Malus personalizzati per la serata.',
        ),
        _buildInfoItem(
          icon: '🗳️',
          title: 'Votazione = Convalida',
          description:
              'I voti dei partecipanti servono solo a convalidare e approvare la proposta tra le opzioni disponibili (non assegnano direttamente i punti ai giocatori!).',
        ),
        _buildInfoItem(
          icon: '👑',
          title: 'Assegnazione dall\'Organizzatore',
          description:
              'È l\'Organizzatore dell\'evento che durante la serata assegna effettivamente il bonus o il malus a chi ha compiuto l\'azione.',
        ),
        _buildInfoItem(
          icon: '📊',
          title: 'Classifica Live & Livelli',
          description:
              'I punti accreditati aggiornano la classifica dal vivo e aumentano il tuo Livello Giocatore (da Recluta a Leggenda Suprema).',
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
      subtitle: 'Prove fotografiche, denunce spia e testimonianze',
      items: [
        _buildInfoItem(
          icon: '⏳',
          title: 'Attivo solo ad Evento "In Corso"',
          description:
              'Il pulsante VAR si sblocca e diventa utilizzabile esclusivamente quando l\'evento è ufficialmente iniziato.',
        ),
        _buildInfoItem(
          icon: '📸',
          title: 'Richiesta Bonus Personale',
          description:
              'Hai compiuto un\'azione leggendaria? Richiedi l\'accredito del bonus allegando una foto prova reale e indicando un testimone che confermi.',
        ),
        _buildInfoItem(
          icon: '🕵️',
          title: 'Denuncia Malus ("Fare la Spia")',
          description:
              'Hai visto un amico commettere un\'infrazione o un malus? Denuncialo al VAR per fargli togliere punti!',
        ),
        _buildInfoItem(
          icon: '🚨',
          title: 'Sanzione Falsa Testimonianza',
          description:
              'Attenzione! Se fai una denuncia falsa e il Giudice del VAR la respinge con sanzione, perderai punti con un malus ufficiale e irrevocabile!',
        ),
      ],
    );
  }

  // ==========================================
  // SLIDE 4: TITOLI D\'ONORE & BACHECA
  // ==========================================
  Widget _buildSlide4() {
    return _buildSlideContainer(
      icon: '🎖️',
      badge: 'RICONOSCIMENTI',
      title: 'Titoli d\'Onore & Bacheca',
      subtitle: 'I premi di fine evento e i trofei del tuo profilo',
      items: [
        _buildInfoItem(
          icon: '👑',
          title: 'I 6 Titoli Ufficiali di Fine Evento',
          description:
              '• 🥇 Campione Assoluto: 1° posto in classifica.\n'
              '• 🤡 Re dei Malus: Chi ha collezionato più penalità.\n'
              '• ⚖️ L\'Avvocato: Chi ha partecipato più attivamente in assoluto alle votazioni e proposte della community.\n'
              '• 👻 Il Fantasma: Chi ha fatto il minimo indispensabile.\n'
              '• 🕵️ Lo Sbirro: Chi ha fatto più denunce malus al VAR per fare la spia agli amici.\n'
              '• ⚡ Il Giustiziere: Chi ha aperto più chiamate VAR convalidate e approvate (il giocatore più onesto e fidato!).',
        ),
        _buildInfoItem(
          icon: '🛡️',
          title: 'La Bacheca nel tuo Profilo',
          description:
              'Nel tuo profilo trovi il contatore delle partecipazioni agli eventi, tutti i titoli vinti e i badge pubblici (come il prestigioso Badge Fondatore) che tutti i tuoi amici possono ammirare.',
        ),
      ],
    );
  }

  // ==========================================
  // SLIDE 5: CODICE AMICO & CONNESSIONI
  // ==========================================
  Widget _buildSlide5() {
    return _buildSlideContainer(
      icon: '👥',
      badge: 'COMMUNITY',
      title: 'Codice Amico & Sfide',
      subtitle: 'Connettiti con gli amici e fai squadra',
      items: [
        _buildInfoItem(
          icon: '🆔',
          title: 'Il tuo Codice Amico Univoco',
          description:
              'Nel tuo profilo trovi un codice personale esclusivo da condividere ai tuoi amici per farti trovare e aggiungere facilmente.',
        ),
        _buildInfoItem(
          icon: '📋',
          title: 'Incolla con 1 Singolo Tocco',
          description:
              'Hai ricevuto il codice di un amico? Usa il pulsante rapido "Incolla" nel profilo per collegarti all\'istante e sfidarlo nei prossimi eventi.',
        ),
        _buildInfoItem(
          icon: '🚀',
          title: 'Tutto Pronto per Iniziare!',
          description:
              'Ora conosci tutte le regole di FantaEventi. Crea la tua prima lega, unisciti alla festa e che vinca il migliore!',
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
