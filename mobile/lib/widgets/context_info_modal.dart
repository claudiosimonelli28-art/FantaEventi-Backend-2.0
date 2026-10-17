import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ContextInfoType {
  creazioneEvento,
  dettaglioEvento,
  propostaBonusMalus,
  profilo,
  varSubmission,
  votazioniLive,
}

class InfoSectionData {
  final String icon;
  final String title;
  final String description;
  final List<String>? bulletPoints;

  const InfoSectionData({
    required this.icon,
    required this.title,
    required this.description,
    this.bulletPoints,
  });
}

class ContextInfoModal extends StatelessWidget {
  final ContextInfoType tipo;

  const ContextInfoModal({super.key, required this.tipo});

  static Future<void> mostra(BuildContext context, {required ContextInfoType tipo}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (ctx) => ContextInfoModal(tipo: tipo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _getConfig(tipo);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFF334155), width: 1.5),
          left: BorderSide(color: Color(0xFF334155), width: 1),
          right: BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // DRAG HANDLE
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // INTESTAZIONE MODALE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: config.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: config.gradientColors.first.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      config.badgeEmoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: config.gradientColors.first.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: config.gradientColors.first.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          config.categoryTag.toUpperCase(),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: config.gradientColors.first,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        config.title,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 24),
                  tooltip: 'Chiudi',
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF1E293B), height: 1),

          // LISTA SEZIONI INFORMATIVE
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    config.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFFCBD5E1),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...config.sections.map((section) => _buildSectionCard(section)),
                ],
              ),
            ),
          ),

          // TASTO DI CHIUSURA IN BASSO
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9333EA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Ho capito, grazie!',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(InfoSectionData section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(section.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            section.description,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF94A3B8),
              height: 1.45,
            ),
          ),
          if (section.bulletPoints != null && section.bulletPoints!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...section.bulletPoints!.map(
              (bp) => Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Color(0xFFFACC15), fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        bp,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFFCBD5E1),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _ModalConfig _getConfig(ContextInfoType type) {
    switch (type) {
      case ContextInfoType.creazioneEvento:
        return _ModalConfig(
          title: 'Creazione Evento',
          categoryTag: 'Guida Schermata',
          badgeEmoji: '🎉',
          gradientColors: const [Color(0xFF9333EA), Color(0xFF6366F1)],
          subtitle:
              'Questa schermata ti permette di allestire un nuovo evento FantaEventi. Qui sotto trovi tutti i parametri e come influiscono sulla serata:',
          sections: const [
            InfoSectionData(
              icon: '🎨',
              title: 'Tema & Copertina dell\'Evento',
              description:
                  'Definisce l\'identità visiva della festa. Puoi impostare la copertina in due modalità:',
              bulletPoints: [
                'Temi Preimpostati: Seleziona rapidamente tra Concerto, Cena, Party, Club / DJ o Viaggio.',
                'Foto Personalizzata: Puoi scattare una foto al momento con la fotocamera del tuo smartphone oppure scegliere un\'immagine direttamente dalla tua galleria!',
              ],
            ),
            InfoSectionData(
              icon: '📝',
              title: 'Titolo & Descrizione',
              description:
                  'Il Titolo identifica l\'evento nell\'elenco principale di tutti i partecipanti. La Descrizione serve per specificare dettagli logistici, dress code, luogo di ritrovo o regole speciali concordate con gli amici.',
            ),
            InfoSectionData(
              icon: '⏰',
              title: 'Data, Ora di Inizio e Fine',
              description:
                  'I timestamp temporali regolano la vita dell\'evento attraverso 3 stati automatici:',
              bulletPoints: [
                'In Programma: L\'evento è in attesa dell\'orario stabilito; le iscrizioni sono aperte e puoi invitare altri amici.',
                'In Corso: Scoccata l\'ora di inizio, le iscrizioni si chiudono ufficialmente! Partono le Votazioni Live e l\'assegnazione delle regole.',
                'Concluso: Al termine dell\'evento, le votazioni vengono bloccate, i punteggi si congelano e viene proclamato il Podio Ufficiale dei vincitori.',
              ],
            ),
            InfoSectionData(
              icon: '📍',
              title: 'Destinazione & Luogo',
              description:
                  'Indica il locale, la città o l\'indirizzo in cui si svolge l\'evento, consentendo a tutti i partecipanti di visualizzare dove ci si incontra.',
            ),
            InfoSectionData(
              icon: '⚖️',
              title: 'Penalità Falsa Testimonianza VAR',
              description:
                  'È la sanzione disciplinare anti-imbroglio dell\'evento. Se un partecipante apre una contestazione VAR inventata o palesemente infondata, e il Giudice designato la respinge, sia il richiedente che gli eventuali testimoni complici subiranno questa sottrazione di punti come malus immediato.',
            ),
            InfoSectionData(
              icon: '👥',
              title: 'Selezione & Invito Partecipanti',
              description:
                  'Tu che crei l\'evento sei registrato automaticamente come Organizzatore e partecipante confermato. Gli amici selezionati dalla lista riceveranno una notifica di invito e risulteranno "In Sospeso" finché non premeranno Accetta.',
            ),
          ],
        );

      case ContextInfoType.dettaglioEvento:
        return _ModalConfig(
          title: 'Dettagli Evento',
          categoryTag: 'Guida Schermata',
          badgeEmoji: '📋',
          gradientColors: const [Color(0xFF6366F1), Color(0xFF0EA5E9)],
          subtitle:
              'Il centro di controllo della serata. Qui monitori punteggi, classifica, stato dei partecipanti e le regole attive:',
          sections: const [
            InfoSectionData(
              icon: '🏆',
              title: 'Classifica Live & Punteggi in Tempo Reale',
              description:
                  'Elenca tutti i partecipanti ordinati dal primo all\'ultimo. Ogni volta che una proposta viene approvata o un VAR viene convalidato, i punteggi si ricalcolano istantaneamente.',
            ),
            InfoSectionData(
              icon: '🔍',
              title: 'Scheda Giocatore & Storno Regole (Solo Organizzatore)',
              description:
                  'Toccando il nome o la card di qualsiasi giocatore nella classifica, puoi visualizzare lo storico dettagliato di tutti i suoi singoli bonus e malus accumulati:',
              bulletPoints: [
                'Dettaglio Bonus/Malus: Vedi l\'orario, il motivo e i punti di ogni assegnazione del giocatore.',
                'Storno Disciplinare (Esclusivo per l\'Organizzatore): Se una regola è stata assegnata per errore o scambio di persona, esclusivamente l\'organizzatore dell\'evento ha a disposizione il tasto per stornarla ed eliminarla dalla scheda del giocatore, ripristinando all\'istante il punteggio corretto!',
              ],
            ),
            InfoSectionData(
              icon: '🗳️',
              title: 'Quorum Votazioni Live Dinamico',
              description:
                  'Mostra la soglia di voti favorevoli necessaria per convalidare qualsiasi proposta di bonus. Il Quorum si basa sulla maggioranza assoluta: (Partecipanti / 2) + 1. Ad esempio, con 8 partecipanti effettivi servono almeno 5 voti a favore. Se un nuovo amico entra nell\'evento, il Quorum si ricalcola istantaneamente in tempo reale!',
            ),
            InfoSectionData(
              icon: '👥',
              title: 'Stato Partecipanti ed Inviti',
              description:
                  'Distingue i partecipanti attivi che hanno accettato l\'invito da quelli ancora in sospeso o che hanno rifiutato. L\'organizzatore può invitare ulteriori amici prima che l\'evento abbia inizio.',
            ),
            InfoSectionData(
              icon: '⚡',
              title: 'Pulsante Azione: Proponi Bonus / Regola',
              description:
                  'Ti permette di lanciare al volo una nuova proposta di regola goliardica da sottoporre immediatamente al voto democratico di tutti i partecipanti.',
            ),
            InfoSectionData(
              icon: '🥇',
              title: 'Podio Finale & Condivisione Instagram / Social',
              description:
                  'Quando l\'evento è concluso, appare la schermata del podio ufficiale con le medaglie d\'oro, d\'argento e di bronzo, e si attiva il pulsante di esportazione per condividere la card ad alta risoluzione direttamente nelle storie di Instagram o sui gruppi WhatsApp!',
            ),
          ],
        );

      case ContextInfoType.propostaBonusMalus:
        return _ModalConfig(
          title: 'Proposta Regola',
          categoryTag: 'Guida Schermata',
          badgeEmoji: '💡',
          gradientColors: const [Color(0xFFEC4899), Color(0xFF9333EA)],
          subtitle:
              'In questa schermata puoi ideare una nuova regola goliardica per la serata e sottoporla al giudizio del gruppo:',
          sections: const [
            InfoSectionData(
              icon: '➕ / ➖',
              title: 'Differenza tra Bonus e Malus',
              description:
                  'I Bonus premiano azioni epiche, goliardiche, brindisi o sfide con punti positivi. I Malus penalizzano figuracce, ritardi, bevande rovesciate o comportamenti buffi con punti negativi.',
            ),
            InfoSectionData(
              icon: '🎯',
              title: 'Validità della Regola per Tutti',
              description:
                  'Tutti i Bonus e i Malus approvati dal Quorum sono validi per tutti i partecipanti all\'evento. Chiunque compia l\'azione durante la festa potrà vedersi assegnata la regola con i relativi punti.',
            ),
            InfoSectionData(
              icon: '👍',
              title: 'Voto Favorevole (PRO) Automatico',
              description:
                  'Poiché stai proponendo tu questa regola, il tuo voto favorevole è già automaticamente convalidato e registrato dal sistema. Tutti gli altri partecipanti riceveranno la notifica per votare.',
            ),
            InfoSectionData(
              icon: '🗳️',
              title: 'Iter Votazioni Live & Quorum',
              description:
                  'La proposta viene pubblicata immediatamente nelle Votazioni Live. Per entrare nel regolamento ufficiale dell\'evento e assegnare i punti, i voti "PRO" devono raggiungere il Quorum richiesto.',
            ),
          ],
        );

      case ContextInfoType.profilo:
        return _ModalConfig(
          title: 'Profilo Giocatore',
          categoryTag: 'Guida Schermata',
          badgeEmoji: '👤',
          gradientColors: const [Color(0xFF10B981), Color(0xFF0EA5E9)],
          subtitle:
              'La tua identità su FantaEventi. Da qui gestisci foto, amicizie, punti esperienza e consulti la tua storia di gioco:',
          sections: const [
            InfoSectionData(
              icon: '📸',
              title: 'Foto Profilo & Avatar',
              description:
                  'Toccando l\'icona della fotocamera puoi personalizzare la tua immagine scattando un selfie in tempo reale, caricando una foto dalla galleria del telefono oppure scegliendo uno dei nostri avatar grafici.',
            ),
            InfoSectionData(
              icon: '🤝',
              title: 'Codice Amico Personale Univoco',
              description:
                  'Ogni giocatore possiede un codice personale unico. Puoi copiarlo con un tocco per inviarlo agli amici su WhatsApp, oppure incollare il codice di un amico nella casella sottostante per connettervi all\'istante e potervi invitare a vicenda a tutti gli eventi!',
            ),
            InfoSectionData(
              icon: '⭐',
              title: 'Livello XP, Punti Esperienza & Badge di Carriera',
              description:
                  'Accumuli XP e sali di livello creando eventi, partecipando alle feste, proponendo regole convalidate, votando al VAR e salendo sul podio. I Badge rappresentano i tuoi traguardi speciali e la tua reputazione da vero festaiolo.',
            ),
            InfoSectionData(
              icon: '📜',
              title: 'Storico Voti Personale',
              description:
                  'Un archivio completo che tiene traccia di tutte le decisioni che hai espresso nelle votazioni passate. Puoi filtrare comodamente lo storico per periodo: Ultime 24 ore, Ultimi 7 giorni, Ultimi 30 giorni o Tutto lo storico.',
            ),
          ],
        );

      case ContextInfoType.varSubmission:
        return _ModalConfig(
          title: 'Richiesta VAR',
          categoryTag: 'Guida Schermata',
          badgeEmoji: '📺',
          gradientColors: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
          subtitle:
              'Il tribunale goliardico di FantaEventi per convalidare accadimenti contestati durante la festa:',
          sections: const [
            InfoSectionData(
              icon: '⚖️',
              title: 'Il Ruolo del Giudice Designato',
              description:
                  'Ogni evento ha un Giudice imparziale. Solo il Giudice ha l\'autorità ufficiale di esaminare la richiesta, visionare le prove fotografiche e decretare il verdetto definitivo (APPROVATO o RESPINTO).',
            ),
            InfoSectionData(
              icon: '👁️',
              title: 'Selezione dei Testimoni Oculari',
              description:
                  'Puoi selezionare uno o più partecipanti presenti al momento del fatto. I testimoni riceveranno una notifica per confermare o smentire l\'accaduto prima della sentenza del Giudice.',
            ),
            InfoSectionData(
              icon: '📸',
              title: 'Prova Fotografica Schiacciante',
              description:
                  'Puoi scattare o allegare la foto dell\'azione (o del colpevole) per fornire una prova visiva inconfutabile al Giudice.',
            ),
            InfoSectionData(
              icon: '⚠️',
              title: 'Attenzione alla Falsa Testimonianza',
              description:
                  'Se il Giudice stabilisce che la denuncia è inventata, fittizia o un tentativo di sabotaggio, respingerà il VAR applicando la severa penalità di punti impostata per l\'evento sia al richiedente sia ai falsi testimoni!',
            ),
          ],
        );

      case ContextInfoType.votazioniLive:
        return _ModalConfig(
          title: 'Votazioni Live',
          categoryTag: 'Guida Schermata',
          badgeEmoji: '🗳️',
          gradientColors: const [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
          subtitle:
              'La democrazia diretta della festa. Qui ogni partecipante ha diritto di voto sulle regole proposte:',
          sections: const [
            InfoSectionData(
              icon: '🗳️',
              title: 'Espressione del Voto (PRO o CONTRO)',
              description:
                  'Ogni partecipante all\'evento può votare a favore ("PRO") o contro ("CONTRO") ciascuna regola proposta dagli amici.',
            ),
            InfoSectionData(
              icon: '📊',
              title: 'Barra di Avanzamento Quorum',
              description:
                  'La barra mostra visivamente la percentuale di voti raggiunta rispetto alla soglia necessaria. Quando i voti favorevoli raggiungono la maggioranza assoluta richiesta, la proposta si chiude all\'istante con esito positivo e la regola entra in vigore!',
            ),
            InfoSectionData(
              icon: '❌',
              title: 'Bocciatura della Regola',
              description:
                  'Se i voti contrari superano matematicamente la metà dei partecipanti o rendono impossibile il raggiungimento del quorum, la proposta viene respinta e archiviata.',
            ),
          ],
        );
    }
  }
}

class _ModalConfig {
  final String title;
  final String categoryTag;
  final String badgeEmoji;
  final String subtitle;
  final List<Color> gradientColors;
  final List<InfoSectionData> sections;

  const _ModalConfig({
    required this.title,
    required this.categoryTag,
    required this.badgeEmoji,
    required this.subtitle,
    required this.gradientColors,
    required this.sections,
  });
}
