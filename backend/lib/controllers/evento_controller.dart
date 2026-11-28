import 'dart:async';
import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/evento.dart';
import '../models/utente.dart';
import '../services/fcm_service.dart';
import '../utils/auth_token_helper.dart';
import '../utils/italian_time.dart';
import '../utils/nickname_helper.dart';
import 'utente_controller.dart';

class EventoController {
  // GET /api/eventi
  Future<Response> getEventi(Request request) async {
    try {
      final now = ItalianTime.now();
      final queryUtente = (request.url.queryParameters['utente'] ?? '').toString().trim();
      final utenteRichiedente = queryUtente.isNotEmpty
          ? queryUtente
          : (AuthTokenHelper.getVerifiedNickname(request) ?? '');
      final docs = await DbService.instance.eventiCollection.find().toList();
      final utentiDocs = await UtenteController.getCachedUtentiDocs();

      final List<Map<String, dynamic>> resultList = [];

      for (var d in docs) {
        final evId = d['_id'] is ObjectId ? (d['_id'] as ObjectId) : null;
        final titolo = (d['titolo'] ?? d['nome'] ?? 'Evento').toString().trim();
        final dtStart = d['data'] is DateTime
            ? d['data'] as DateTime
            : (d['data'] != null ? DateTime.tryParse(d['data'].toString()) ?? now : now);
        final dtEnd = d['dataFine'] is DateTime
            ? d['dataFine'] as DateTime
            : (d['dataFine'] != null ? DateTime.tryParse(d['dataFine'].toString()) ?? dtStart.add(const Duration(hours: 4)) : dtStart.add(const Duration(hours: 4)));

        final rawCreator = (d['propostoDa'] ?? d['creatore'] ?? '').toString().trim();
        final creatorNick = NicknameHelper.resolve(rawCreator, utentiDocs);

        final rawPart = (d['partecipanti'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        final cleanPart = rawPart.map((p) => NicknameHelper.resolve(p, utentiDocs)).toList();

        final rawInv = (d['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        final rawRifiutati = (d['rifiutati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        final cleanRifiutati = rawRifiutati
            .where((r) => r.isNotEmpty)
            .map((r) => NicknameHelper.resolve(r, utentiDocs))
            .toSet()
            .toList();
        final cleanInv = rawInv
            .map((i) => NicknameHelper.resolve(i, utentiDocs))
            .where((i) => !rawRifiutati.any((r) => NicknameHelper.isSame(r, i, utentiDocs)))
            .toList();

        final bool haAltriPartecipanti = cleanPart.any((p) => p.isNotEmpty && !NicknameHelper.isSame(p, creatorNick, utentiDocs));
        String stato = (d['stato'] ?? 'in_programma').toString().toLowerCase();

        // 1. Logica di Transizione & Anti-farming
        if (stato == 'annullato') {
          // Rimane annullato
        } else if (now.isAfter(dtEnd)) {
          if (stato != 'concluso' && evId != null) {
            stato = 'concluso';
            await DbService.instance.eventiCollection.update(
              where.id(evId),
              modify.set('stato', 'concluso'),
            );
          }
        } else if (now.isAfter(dtStart)) {
          if (!haAltriPartecipanti) {
            // Orario di inizio scattato ma nessun altro partecipante oltre l'organizzatore: l'evento si annulla!
            if (stato != 'annullato' && evId != null) {
              stato = 'annullato';
              await DbService.instance.eventiCollection.update(
                where.id(evId),
                modify.set('stato', 'annullato').set('xpCreatoreAssegnati', false),
              );
            }
          } else {
            stato = 'in_corso';
            // Accredito +100 XP una tantum al creatore solo quando l'evento parte regolarmente con amici
            if (d['xpCreatoreAssegnati'] != true && evId != null) {
              await DbService.instance.eventiCollection.update(
                where.id(evId),
                modify.set('stato', 'in_corso').set('xpCreatoreAssegnati', true),
              );
              d['xpCreatoreAssegnati'] = true;

              final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] 🏆 Evento "$titolo" avviato con successo (+100 XP)';

              for (var uDoc in utentiDocs) {
                if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['username'] ?? '', creatorNick, utentiDocs)) {
                  final curXp = (uDoc['xp'] as num?)?.toInt() ?? 0;
                  final curLiv = (uDoc['livello'] as num?)?.toInt() ?? 1;
                  final curTot = (uDoc['xpTotali'] as num?)?.toInt() ?? XpProgression.calcolaXpTotaliDaLivello(curLiv, curXp);
                  final prog = XpProgression.aggiungiXp(
                    livelloAttuale: curLiv,
                    xpLivelloAttuale: curXp,
                    deltaXp: 100,
                    xpTotaliAttuali: curTot,
                  );

                  final List<dynamic> curStorico = List.from(uDoc['storicoVoti'] ?? []);
                  curStorico.insert(0, logVoce);

                  await DbService.instance.utentiCollection.update(
                    where.id(uDoc['_id'] as ObjectId),
                    modify
                      .set('xp', prog.xp)
                      .set('livello', prog.livello)
                      .set('xpProssimoLivello', prog.xpProssimoLivello)
                      .set('xpTotali', prog.xpTotali)
                      .set('storicoVoti', curStorico),
                  );
                  UtenteController.invalidateCache();
                  break;
                }
              }
            }
          }
        }

        // Auto-eliminazione definitiva dal feed e dal DB dopo 5 giorni dalla conclusione
        final bool isConcluso = stato != 'annullato' && (now.isAfter(dtEnd) || stato == 'concluso');
        if (isConcluso && now.difference(dtEnd).inDays >= 5) {
          if (evId != null) {
            try {
              final evIdStr = evId.oid;
              await DbService.instance.eventiCollection.remove(where.id(evId));
              final bmDocs = await DbService.instance.bonusMalusCollection.find(where.eq('eventoId', evIdStr)).toList();
              for (var bm in bmDocs) {
                final bmId = bm['_id'] is ObjectId
                    ? (bm['_id'] as ObjectId).oid
                    : (bm['_id']?.toString() ?? '');
                if (bmId.isNotEmpty) {
                  await DbService.instance.votazioniCollection.remove(
                    where.eq('votazioneId', bmId).or(where.eq('bonusId', bmId)),
                  );
                }
              }
              await DbService.instance.votazioniCollection.remove(where.eq('eventoId', evIdStr));
              await DbService.instance.bonusMalusCollection.remove(where.eq('eventoId', evIdStr));
              await DbService.instance.notificheCollection.remove(where.eq('eventoId', evIdStr));
            } catch (e) {
              print('⚠️ Errore auto-eliminazione evento scaduto ($evId): $e');
            }
          }
          continue;
        }

        // Se l'evento è appena finito (negli ultimi 5 giorni), assegna premi/badge/titoli una sola volta
        if (isConcluso && (d['badgeVincitoreAssegnato'] != true || d['titoliAssegnati'] != true)) {
          try {
            final evTitolo = titolo.isNotEmpty ? titolo : 'Evento Fanta';
            final evIdStr = evId?.oid ?? (d['_id']?.toString() ?? d['id']?.toString() ?? '');
            final dateStr = '${dtEnd.day.toString().padLeft(2, '0')}/${dtEnd.month.toString().padLeft(2, '0')}/${dtEnd.year}';
            final partBadge = '🎉 Partecipato a "$evTitolo" ($dateStr)';

            final bmList = await DbService.instance.bonusMalusCollection.find(
              where.eq('eventoId', evIdStr).or(where.eq('eventoId', evTitolo)),
            ).toList();
            final allVotazioni = await DbService.instance.votazioniCollection.find().toList();
            final uDocs = await UtenteController.getCachedUtentiDocs(forceRefresh: true);

            final Map<String, int> punteggi = {for (var p in cleanPart) p: 0};
            final Map<String, int> malusPerUtente = {for (var p in cleanPart) p.trim().toLowerCase(): 0};
            final Map<String, int> attivitaPerUtente = {for (var p in cleanPart) p.trim().toLowerCase(): 0};
            final Map<String, int> azioniTotaliPerUtente = {for (var p in cleanPart) p.trim().toLowerCase(): 0};

            String? findPartKeyLower(String rawUser) {
              final resolved = NicknameHelper.resolve(rawUser, uDocs).trim().toLowerCase();
              if (attivitaPerUtente.containsKey(resolved)) return resolved;
              for (var k in attivitaPerUtente.keys) {
                if (NicknameHelper.isSame(k, rawUser, uDocs)) return k;
              }
              return null;
            }

            String? findPunteggiKey(String rawUser) {
              final resolved = NicknameHelper.resolve(rawUser, uDocs);
              if (punteggi.containsKey(resolved)) return resolved;
              for (var k in punteggi.keys) {
                if (NicknameHelper.isSame(k, rawUser, uDocs)) return k;
              }
              return null;
            }

            final Set<String> bmIds = {};
            for (var bm in bmList) {
              final bmIdStr = (bm['_id'] is ObjectId
                      ? (bm['_id'] as ObjectId).oid
                      : (bm['_id']?.toString() ?? bm['id']?.toString() ?? ''))
                  .toLowerCase();
              if (bmIdStr.isNotEmpty) bmIds.add(bmIdStr);
              final nomeBm = (bm['nome'] ?? bm['titolo'] ?? '').toString().toLowerCase();
              if (nomeBm.isNotEmpty) bmIds.add(nomeBm);

              final bool isVarSanzione = (bm['categoria'] ?? '').toString().toUpperCase() == 'VAR' ||
                  nomeBm.contains('falsa testimonianza') ||
                  (bm['descrizione'] ?? '').toString().toLowerCase().contains('sanzione per denuncia');

              final prop = (bm['propostoDa'] ?? '').toString().trim();
              final propKey = prop.isNotEmpty ? findPartKeyLower(prop) : null;
              if (!isVarSanzione && propKey != null) {
                attivitaPerUtente[propKey] = (attivitaPerUtente[propKey] ?? 0) + 1;
                azioniTotaliPerUtente[propKey] = (azioniTotaliPerUtente[propKey] ?? 0) + 1;
              }

              final ass = (bm['assegnatoA'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              final pt = (bm['punti'] as num?)?.toInt() ?? 0;
              final bool approvato = bm['approvato'] == true || bm['stato'] == 'approvato';

              for (var u in ass) {
                final uLowerKey = findPartKeyLower(u);
                if (uLowerKey != null) {
                  azioniTotaliPerUtente[uLowerKey] = (azioniTotaliPerUtente[uLowerKey] ?? 0) + 1;
                }
                if (approvato) {
                  final pKey = findPunteggiKey(u) ?? NicknameHelper.resolve(u, uDocs);
                  punteggi[pKey] = (punteggi[pKey] ?? 0) + pt;
                  if (pt < 0 && uLowerKey != null) {
                    malusPerUtente[uLowerKey] = (malusPerUtente[uLowerKey] ?? 0) + pt.abs();
                  }
                }
              }
            }

            for (var v in allVotazioni) {
              final vEvId = (v['eventoId'] ?? v['bonusMalus']?['eventoId'] ?? '').toString().trim().toLowerCase();
              final vBonusId = (v['bonusId'] ?? v['votazioneId'] ?? '').toString().trim().toLowerCase();
              final vBonusTit = (v['bonusTitolo'] ?? '').toString().trim().toLowerCase();

              final bool isForThisEvent =
                  (vEvId.isNotEmpty && (vEvId == evIdStr.toLowerCase() || vEvId == evTitolo.toLowerCase())) ||
                  (vBonusId.isNotEmpty && bmIds.contains(vBonusId)) ||
                  (vBonusTit.isNotEmpty && bmIds.contains(vBonusTit));

              if (!isForThisEvent) continue;

              if (v['utente'] != null) {
                final voterKey = findPartKeyLower(v['utente'].toString());
                if (voterKey != null) {
                  attivitaPerUtente[voterKey] = (attivitaPerUtente[voterKey] ?? 0) + 1;
                  azioniTotaliPerUtente[voterKey] = (azioniTotaliPerUtente[voterKey] ?? 0) + 1;
                }
              } else if (v['votiUtenti'] is Map) {
                final votiMap = v['votiUtenti'] as Map;
                for (var voter in votiMap.keys) {
                  final voterKey = findPartKeyLower(voter.toString());
                  if (voterKey != null) {
                    attivitaPerUtente[voterKey] = (attivitaPerUtente[voterKey] ?? 0) + 1;
                    azioniTotaliPerUtente[voterKey] = (azioniTotaliPerUtente[voterKey] ?? 0) + 1;
                  }
                }
              }
            }

            bool usersUpdated = false;
            final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

            // 1. Assegna badge al 1° in classifica
            String? vincitoreNick;
            if (punteggi.isNotEmpty) {
              final sorted = punteggi.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              vincitoreNick = NicknameHelper.resolve(sorted.first.key, uDocs);
              final badgeMap = {
                'titolo': '🏆 Vincitore Evento',
                'evento': evTitolo,
                'punti': sorted.first.value,
                'data': now.toIso8601String(),
              };

              for (var uDoc in uDocs) {
                final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString();
                if (NicknameHelper.isSame(uNick, vincitoreNick, uDocs)) {
                  final List<dynamic> currentBadgeVincitore = List.from(uDoc['badgeVincitore'] ?? []);
                  if (!currentBadgeVincitore.any((b) => b is Map && b['evento'] == badgeMap['evento'])) {
                    currentBadgeVincitore.add(badgeMap);
                    final List<dynamic> currentStorico = List.from(uDoc['storicoVoti'] ?? []);
                    final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] 🏆 Vincitore dell\'evento "$evTitolo" (+${sorted.first.value} PT)';
                    currentStorico.insert(0, logVoce);
                    await DbService.instance.utentiCollection.update(
                      where.id(uDoc['_id'] as ObjectId),
                      modify
                        .set('badgeVincitore', currentBadgeVincitore)
                        .set('storicoVoti', currentStorico),
                    );
                    usersUpdated = true;
                  }
                }
              }
            }

            // 2. Assegna Badge Partecipazione a TUTTI i partecipanti
            for (var part in cleanPart) {
              for (var uDoc in uDocs) {
                final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString();
                if (NicknameHelper.isSame(uNick, part, uDocs)) {
                  final List<dynamic> currentBadgeList = List.from(uDoc['badgeList'] ?? []);
                  if (!currentBadgeList.any((b) => b.toString().contains(evTitolo))) {
                    currentBadgeList.add(partBadge);
                    await DbService.instance.utentiCollection.update(
                      where.id(uDoc['_id'] as ObjectId),
                      modify.set('badgeList', currentBadgeList),
                    );
                    usersUpdated = true;
                  }
                }
              }
            }

            // 3. Assegnazione Titoli Permanenti della Bacheca (Re dei Malus, L'Avvocato, Fantasma, Lo Sbirro, Il Giustiziere)
            if (d['titoliAssegnati'] != true) {
              int maxMalus = 0;
              String? bestMalusUser;
              malusPerUtente.forEach((k, v) {
                if (v > maxMalus) {
                  maxMalus = v;
                  bestMalusUser = NicknameHelper.resolve(k, uDocs);
                }
              });

              int maxAtt = 0;
              String? bestGiudiceUser;
              attivitaPerUtente.forEach((k, v) {
                if (v > maxAtt) {
                  maxAtt = v;
                  bestGiudiceUser = NicknameHelper.resolve(k, uDocs);
                }
              });

              String? bestFantasmaUser;
              int minAzioni = 0;
              if (cleanPart.length > 1) {
                int lowestAz = 999999;
                for (var p in cleanPart) {
                  if (vincitoreNick != null && NicknameHelper.isSame(p, vincitoreNick, uDocs)) continue;
                  final pNorm = p.trim().toLowerCase();
                  final az = azioniTotaliPerUtente[pNorm] ?? 0;
                  if (az < lowestAz) {
                    lowestAz = az;
                    minAzioni = az;
                    bestFantasmaUser = NicknameHelper.resolve(p, uDocs);
                  }
                }
              }

              // Auto-scadenza richieste VAR pendenti ed eliminazione foto
              if (evIdStr.isNotEmpty) {
                try {
                  await DbService.instance.richiesteVarCollection.update(
                    where.eq('eventoId', evIdStr).and(where.eq('stato', 'in_attesa')),
                    modify.set('stato', 'scaduta').unset('fotoBase64'),
                    multiUpdate: true,
                  );
                  await DbService.instance.richiesteVarCollection.update(
                    where.eq('eventoId', evIdStr),
                    modify.unset('fotoBase64'),
                    multiUpdate: true,
                  );
                } catch (_) {}
              }

              // Calcolo Lo Sbirro e Il Giustiziere per questo evento
              final Map<String, int> sbirroPerUtente = {};
              final Map<String, int> giustizierePerUtente = {};
              if (evIdStr.isNotEmpty) {
                try {
                  final varDocs = await DbService.instance.richiesteVarCollection
                      .find(where.eq('eventoId', evIdStr))
                      .toList();
                  for (var r in varDocs) {
                    final tipo = (r['tipo'] ?? '').toString().toLowerCase();
                    final req = NicknameHelper.resolve((r['richiedente'] ?? '').toString(), uDocs);
                    if (req.isEmpty) continue;
                    if (r['stato'] == 'approvata') {
                      giustizierePerUtente[req] = (giustizierePerUtente[req] ?? 0) + 1;
                    }
                    if (tipo == 'malus') {
                      sbirroPerUtente[req] = (sbirroPerUtente[req] ?? 0) + 1;
                    }
                  }
                } catch (_) {}
              }

              int maxSbirro = 0;
              String? bestSbirroUser;
              sbirroPerUtente.forEach((k, v) {
                if (v > maxSbirro) {
                  maxSbirro = v;
                  bestSbirroUser = k;
                }
              });

              int maxGiustiziere = 0;
              String? bestGiustiziereUser;
              giustizierePerUtente.forEach((k, v) {
                if (v > maxGiustiziere) {
                  maxGiustiziere = v;
                  bestGiustiziereUser = k;
                }
              });

              for (var uDoc in uDocs) {
                final uId = uDoc['_id'] as ObjectId;
                final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString();
                var mod = modify;
                bool shouldUpdate = false;

                if (bestMalusUser != null && NicknameHelper.isSame(uNick, bestMalusUser!, uDocs) && maxMalus > 0) {
                  final cur = (uDoc['countReMalus'] as num?)?.toInt() ?? 0;
                  mod = mod.set('countReMalus', cur + 1);
                  shouldUpdate = true;
                }
                if (bestGiudiceUser != null && NicknameHelper.isSame(uNick, bestGiudiceUser!, uDocs) && maxAtt > 0) {
                  final cur = (uDoc['countGiudice'] as num?)?.toInt() ?? (uDoc['countAvvocato'] as num?)?.toInt() ?? 0;
                  mod = mod.set('countGiudice', cur + 1).set('countAvvocato', cur + 1);
                  shouldUpdate = true;
                }
                if (bestFantasmaUser != null && NicknameHelper.isSame(uNick, bestFantasmaUser, uDocs)) {
                  final cur = (uDoc['countFantasma'] as num?)?.toInt() ?? 0;
                  mod = mod.set('countFantasma', cur + 1);
                  shouldUpdate = true;
                }
                if (bestSbirroUser != null && NicknameHelper.isSame(uNick, bestSbirroUser!, uDocs) && maxSbirro > 0) {
                  final cur = (uDoc['countSbirro'] as num?)?.toInt() ?? 0;
                  mod = mod.set('countSbirro', cur + 1);
                  shouldUpdate = true;
                }
                if (bestGiustiziereUser != null && NicknameHelper.isSame(uNick, bestGiustiziereUser!, uDocs) && maxGiustiziere > 0) {
                  final cur = (uDoc['countGiustiziere'] as num?)?.toInt() ?? 0;
                  mod = mod.set('countGiustiziere', cur + 1);
                  shouldUpdate = true;
                }

                if (shouldUpdate) {
                  await DbService.instance.utentiCollection.update(where.id(uId), mod);
                  usersUpdated = true;
                }
              }

              final Map<String, dynamic> titoliMap = {
                'campione': vincitoreNick,
                'campionePunti': (vincitoreNick != null ? (punteggi[vincitoreNick] ?? 0) : 0),
                if (bestMalusUser != null && maxMalus > 0) ...{
                  'reMalus': bestMalusUser,
                  'reMalusPunti': maxMalus,
                },
                if (bestGiudiceUser != null && maxAtt > 0) ...{
                  'avvocato': bestGiudiceUser,
                  'avvocatoAzioni': maxAtt,
                },
                if (bestFantasmaUser != null) ...{
                  'fantasma': bestFantasmaUser,
                  'fantasmaAzioni': minAzioni,
                },
                if (bestSbirroUser != null && maxSbirro > 0) ...{
                  'sbirro': bestSbirroUser,
                  'sbirroDenunce': maxSbirro,
                },
                if (bestGiustiziereUser != null && maxGiustiziere > 0) ...{
                  'giustiziere': bestGiustiziereUser,
                  'giustiziereApprovate': maxGiustiziere,
                },
              };

              d['badgeVincitoreAssegnato'] = true;
              d['titoliAssegnati'] = true;
              d['titoliVincitori'] = titoliMap;
              d['stato'] = 'concluso';

              if (evId != null) {
                await DbService.instance.eventiCollection.update(
                  where.id(evId),
                  modify
                    .set('badgeVincitoreAssegnato', true)
                    .set('titoliAssegnati', true)
                    .set('titoliVincitori', titoliMap)
                    .set('stato', 'concluso'),
                );
              }
            }

            if (usersUpdated) {
              UtenteController.invalidateCache();
            }
          } catch (errPremi) {
            print('⚠️ Errore calcolo fine evento ($evId): $errPremi');
          }
        }

        final evento = Evento.fromMap(d);

        if (utenteRichiedente.isNotEmpty) {
          if (rawRifiutati.any((r) => NicknameHelper.isSame(r, utenteRichiedente, utentiDocs))) {
            continue;
          }
          final bool isCreatore = NicknameHelper.isSame(creatorNick, utenteRichiedente, utentiDocs);
          final bool isPartecipante = isCreatore ||
              cleanPart.any((p) => NicknameHelper.isSame(p, utenteRichiedente, utentiDocs));
          final bool isInvitato = cleanInv.any((i) => NicknameHelper.isSame(i, utenteRichiedente, utentiDocs));

          if (!isCreatore && !isPartecipante && !isInvitato) {
            continue;
          }
          if (!isCreatore && !isPartecipante && isInvitato) {
            final bool isInizioPassatoDa30Min = now.isAfter(dtStart.add(const Duration(minutes: 30)));
            if (isConcluso || isInizioPassatoDa30Min) {
              continue;
            }
          }
        }

        final json = evento.toJson();
        json['stato'] = stato;
        json['propostoDa'] = creatorNick;
        json['creatore'] = creatorNick;
        json['partecipanti'] = cleanPart;
        json['invitati'] = cleanInv;
        json['rifiutati'] = cleanRifiutati;
        json['badgeVincitoreAssegnato'] = d['badgeVincitoreAssegnato'] == true;
        json['titoliAssegnati'] = d['titoliAssegnati'] == true;
        if (d['titoliVincitori'] != null) {
          json['titoliVincitori'] = d['titoliVincitori'];
        }

        resultList.add(json);
      }

      return Response.ok(
        jsonEncode(resultList),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore durante il recupero degli eventi: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/crea
  Future<Response> creaEvento(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final utentiDocs = await UtenteController.getCachedUtentiDocs();

      final titolo = data['titolo'] ?? data['nome'] ?? 'Evento FantaEventi';
      final rawProposto = (data['propostoDa'] ?? data['creatoreId'] ?? 'Cloud').toString().trim();
      final String propostoDa = NicknameHelper.resolve(rawProposto, utentiDocs);

      final rawPartecipanti = (data['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final rawInvitati = (data['invitati'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final Set<String> invitatiSet = {...rawPartecipanti, ...rawInvitati};

      // Solamente il Creatore è confermato nei partecipanti all'inizio
      final List<String> partecipantiConfermati = [propostoDa];
      final List<String> invitatiFinali = invitatiSet
          .where((p) => !NicknameHelper.isSame(p, propostoDa, utentiDocs))
          .map((p) => NicknameHelper.resolve(p, utentiDocs))
          .toList();

      final now = ItalianTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] Creato evento "$titolo" (in attesa di avvio)';

      final dtInizio = data['data'] != null ? DateTime.parse(data['data']) : now;
      final dtFine = data['dataFine'] != null ? DateTime.parse(data['dataFine']) : dtInizio.add(const Duration(hours: 4));

      final eventoMap = {
        'titolo': titolo,
        'nome': titolo,
        'descrizione': data['descrizione'] ?? '',
        'data': dtInizio.toIso8601String(),
        'dataFine': dtFine.toIso8601String(),
        'luogo': data['luogo'] ?? '',
        'latitudine': data['latitudine'],
        'longitudine': data['longitudine'],
        'stato': 'in_programma',
        'propostoDa': propostoDa,
        'creatore': propostoDa,
        'partecipanti': partecipantiConfermati,
        'invitati': invitatiFinali,
        'xpCreatoreAssegnati': false, // Deferito a quando l'evento parte in corso
        'penalitaFalsaTestimonianza': data['penalitaFalsaTestimonianza'] ?? -10,
        'copertinaUrl': data['copertinaUrl'] ?? '',
      };

      // Anti-duplicazione idempotente: se un evento identico è già stato creato dal medesimo creatore, restituiscilo
      final existingRecent = await DbService.instance.eventiCollection.findOne(
        where.eq('titolo', titolo).and(where.eq('propostoDa', propostoDa)),
      );
      if (existingRecent != null) {
        final existingId = existingRecent['_id']?.oid ?? existingRecent['_id']?.toString() ?? '';
        return Response.ok(
          jsonEncode({'message': 'Evento già creato con successo', 'id': existingId}),
          headers: {'content-type': 'application/json'},
        );
      }

      final res = await DbService.instance.eventiCollection.insertOne(eventoMap);
      final insertedId = res.id?.oid ?? '';

      // Aggiungi voce storico al creatore senza accreditare XP (in attesa di avvio effettivo)
      for (var uDoc in utentiDocs) {
        if (NicknameHelper.isSame(uDoc['nickname'] ?? uDoc['username'] ?? '', propostoDa, utentiDocs)) {
          final List<dynamic> curStorico = List.from(uDoc['storicoVoti'] ?? []);
          curStorico.insert(0, logVoce);
          await DbService.instance.utentiCollection.update(
            where.id(uDoc['_id'] as ObjectId),
            modify.set('storicoVoti', curStorico),
          );
          UtenteController.invalidateCache();
          break;
        }
      }

      // Notifiche di invito ai partecipanti invitati
      for (var inv in invitatiFinali) {
        final existingNotif = await DbService.instance.notificheCollection.findOne(
          where.eq('eventoId', insertedId).and(where.eq('destinatario', inv)).and(where.eq('tipo', 'invito')),
        );
        if (existingNotif == null) {
          try {
            await DbService.instance.notificheCollection.insertOne({
              'mittente': propostoDa,
              'destinatario': inv,
              'titolo': 'Invito ad Evento: $titolo',
              'messaggio': '$propostoDa ti ha invitato a partecipare all\'evento "$titolo"!',
              'eventoId': insertedId,
              'tipo': 'invito',
              'stato': 'in_attesa',
              'letto': false,
              'data': now.toIso8601String(),
            });
          } catch (_) {}
        }
      }

      if (invitatiFinali.isNotEmpty) {
        unawaited(
          FcmService.instance.inviaPushAUtenti(
            invitatiFinali,
            titolo: '🎉 Invito ad Evento: $titolo',
            messaggio: '$propostoDa ti ha invitato a partecipare all\'evento "$titolo"!',
            data: {
              'tipo': 'invito',
              'eventoId': insertedId,
            },
          ),
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Evento creato con successo', 'id': insertedId}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/partecipa
  Future<Response> partecipaEvento(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final eventoId = data['eventoId']?.toString() ?? '';
      final utenteName = data['utente']?.toString() ?? '';

      if (eventoId.isEmpty || utenteName.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'ID Evento ed Utente sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('nome', eventoId);
      final doc = await DbService.instance.eventiCollection.findOne(selector);

      if (doc != null) {
        final stato = (doc['stato'] ?? 'in_programma').toString().toLowerCase();
        final dateStr = doc['data']?.toString() ?? '';
        final dtStart = DateTime.tryParse(dateStr);
        final now = ItalianTime.now();

        if (stato == 'concluso' || stato == 'in_corso' || (dtStart != null && now.isAfter(dtStart))) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Le iscrizioni per questo evento sono chiuse'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final utentiDocs = await UtenteController.getCachedUtentiDocs();
        final rawCreator = (doc['propostoDa'] ?? doc['creatore'] ?? '').toString().trim();
        final rawPart = (doc['partecipanti'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        final rawInv = (doc['invitati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
        final rawRifiutati = (doc['rifiutati'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];

        if (rawRifiutati.any((r) => NicknameHelper.isSame(r, utenteName, utentiDocs))) {
          return Response.forbidden(
            jsonEncode({'error': 'Non sei nella lista degli invitati: hai già rifiutato l\'invito a questo evento!'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final bool isCreatore = NicknameHelper.isSame(rawCreator, utenteName, utentiDocs);
        final bool isGiaPart = rawPart.any((p) => NicknameHelper.isSame(p, utenteName, utentiDocs));
        final bool isInvitato = rawInv.any((i) => NicknameHelper.isSame(i, utenteName, utentiDocs));

        if (!isCreatore && !isGiaPart && !isInvitato) {
          return Response.forbidden(
            jsonEncode({'error': 'Non sei nella lista degli invitati per questo evento!'}),
            headers: {'content-type': 'application/json'},
          );
        }

        final pullList = {
          utenteName,
          utenteName.toLowerCase(),
          utenteName.toUpperCase(),
          utenteName.trim(),
        }.toList();

        await DbService.instance.eventiCollection.update(
          selector,
          modify
            .addToSet('partecipanti', utenteName)
            .pullAll('invitati', pullList),
        );

        // Se c'era una notifica di invito per questo utente, segnalala come accettata e letta
        try {
          await DbService.instance.notificheCollection.update(
            where.eq('eventoId', eventoId).and(where.eq('destinatario', utenteName)).and(where.eq('tipo', 'invito')),
            modify.set('stato', 'accettato').set('letto', true),
            multiUpdate: true,
          );
        } catch (_) {}
      }

      return Response.ok(
        jsonEncode({'message': 'Iscrizione all\'evento effettuata con successo!'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/elimina
  Future<Response> eliminaEvento(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final eventoId = data['eventoId']?.toString() ?? '';
      final utente = data['utente']?.toString() ?? '';

      if (eventoId.isEmpty || utente.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'ID Evento ed Utente sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
      final selector = objId != null ? where.id(objId) : where.eq('nome', eventoId);
      final doc = await DbService.instance.eventiCollection.findOne(selector);

      if (doc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Evento non trovato nel database'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final utentiDocs = await UtenteController.getCachedUtentiDocs();
      final creatoreDoc = (doc['propostoDa'] ?? doc['creatore'] ?? '').toString().trim();
      final verifiedCaller = AuthTokenHelper.getVerifiedNickname(request) ?? utente;
      final isAdmin = AuthTokenHelper.isAdminRequest(request);
      final isAllowed = creatoreDoc.isEmpty ||
          NicknameHelper.isSame(creatoreDoc, verifiedCaller, utentiDocs) ||
          isAdmin;

      if (!isAllowed) {
        return Response.forbidden(
          jsonEncode({'error': 'Solo il creatore dell\'evento può eliminarlo!'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await DbService.instance.eventiCollection.remove(selector);
      await DbService.instance.notificheCollection.remove(where.eq('eventoId', eventoId));
      await DbService.instance.bonusMalusCollection.remove(where.eq('eventoId', eventoId));

      return Response.ok(
        jsonEncode({'message': 'Evento eliminato con successo dal database'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/invita
  Future<Response> invitaAmici(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final eventoId = (data['eventoId'] ?? '').toString().trim();
      final rawNuovi = (data['nuoviInvitati'] ?? data['invitati']) as List<dynamic>? ?? [];
      final nuoviInvitati = rawNuovi.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();

      if (eventoId.isEmpty || nuoviInvitati.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'eventoId e nuoviInvitati sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      ObjectId? objId;
      try { objId = ObjectId.fromHexString(eventoId); } catch (_) {}
      final evSelector = objId != null ? where.id(objId) : where.eq('_id', eventoId);
      final evDoc = await DbService.instance.eventiCollection.findOne(evSelector);

      if (evDoc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Evento non trovato nel database.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final stato = (evDoc['stato'] ?? 'in_programma').toString().toLowerCase();
      final dateStr = evDoc['data']?.toString() ?? '';
      final dtStart = DateTime.tryParse(dateStr);
      final now = ItalianTime.now();

      if (stato == 'concluso' || stato == 'in_corso' || (dtStart != null && now.isAfter(dtStart))) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Non è più possibile invitare amici: l\'evento è già in corso o concluso!'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final utentiDocs = await UtenteController.getCachedUtentiDocs();
      final rawCreatore = (evDoc['propostoDa'] ?? evDoc['creatore'] ?? data['utente'] ?? 'Cloud').toString().trim();
      final creatore = NicknameHelper.resolve(rawCreatore, utentiDocs);
      final evTitolo = (evDoc['titolo'] ?? evDoc['nome'] ?? 'Evento').toString();

      final List<dynamic> currentInvitati = List.from(evDoc['invitati'] ?? []);
      final List<dynamic> currentPartecipanti = List.from(evDoc['partecipanti'] ?? []);
      final List<dynamic> currentRifiutati = List.from(evDoc['rifiutati'] ?? []);

      final List<String> aggiuntiEffettivi = [];
      for (var amico in nuoviInvitati) {
        final resolvedAmico = NicknameHelper.resolve(amico, utentiDocs);
        final giaPart = currentPartecipanti.any((p) => NicknameHelper.isSame(p.toString(), resolvedAmico, utentiDocs));
        final giaInv = currentInvitati.any((i) => NicknameHelper.isSame(i.toString(), resolvedAmico, utentiDocs));
        final giaRifiutato = currentRifiutati.any((r) => NicknameHelper.isSame(r.toString(), resolvedAmico, utentiDocs));

        if (!giaPart && !giaInv && !giaRifiutato && !NicknameHelper.isSame(resolvedAmico, creatore, utentiDocs)) {
          currentInvitati.add(resolvedAmico);
          aggiuntiEffettivi.add(resolvedAmico);
        }
      }

      if (aggiuntiEffettivi.isNotEmpty) {
        await DbService.instance.eventiCollection.update(
          evSelector,
          modify.set('invitati', currentInvitati),
        );

        for (var amico in aggiuntiEffettivi) {
          await DbService.instance.notificheCollection.insertOne({
            'mittente': creatore,
            'destinatario': amico,
            'titolo': 'Invito ad Evento: $evTitolo',
            'messaggio': '$creatore ti ha invitato a partecipare all\'evento "$evTitolo"!',
            'eventoId': eventoId,
            'tipo': 'invito',
            'stato': 'in_attesa',
            'letto': false,
            'data': now.toIso8601String(),
          });
        }
        unawaited(
          FcmService.instance.inviaPushAUtenti(
            aggiuntiEffettivi,
            titolo: '🎉 Invito ad Evento: $evTitolo',
            messaggio: '$creatore ti ha invitato a partecipare all\'evento "$evTitolo"!',
            data: {
              'tipo': 'invito',
              'eventoId': eventoId,
            },
          ),
        );
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'aggiuntiEffettivi': aggiuntiEffettivi,
          'invitati': currentInvitati,
          'eventoTitolo': evTitolo,
          'creatore': creatore,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/copertina
  Future<Response> aggiornaCopertina(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final eventoId = (data['eventoId'] ?? '').toString().trim();
      final copertinaUrl = (data['copertinaUrl'] ?? '').toString().trim();

      if (eventoId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'eventoId obbligatorio'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final evDocs = await DbService.instance.eventiCollection.find().toList();
      final target = eventoId.toLowerCase();
      for (var doc in evDocs) {
        final dId = (doc['_id'] is ObjectId ? (doc['_id'] as ObjectId).oid : doc['_id']?.toString() ?? '').trim().toLowerCase();
        final dTit = (doc['titolo'] ?? doc['nome'] ?? '').toString().trim().toLowerCase();
        if (dId == target || dTit == target) {
          await DbService.instance.eventiCollection.update(
            where.id(doc['_id'] as ObjectId),
            modify.set('copertinaUrl', copertinaUrl),
          );
          break;
        }
      }

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Copertina evento aggiornata'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/eventi/riconcilia
  Future<Response> riconciliaEventiETitoli(Request request) async {
    try {
      final now = ItalianTime.now();
      final evDocs = await DbService.instance.eventiCollection.find().toList();
      final uDocs = await UtenteController.getCachedUtentiDocs(forceRefresh: true);
      final bmList = await DbService.instance.bonusMalusCollection.find().toList();

      bool userDocsModified = false;
      final Map<String, int> reMalusTotali = {};
      final Map<String, int> avvocatoTotali = {};
      final Map<String, int> fantasmaTotali = {};
      final Map<String, int> sbirroTotali = {};
      final Map<String, int> giustiziereTotali = {};

      for (var ev in evDocs) {
        final evId = ev['_id'] is ObjectId ? (ev['_id'] as ObjectId).oid : (ev['_id']?.toString() ?? '');
        final evTitolo = (ev['titolo'] ?? ev['nome'] ?? 'Evento Fanta').toString().trim();
        final dtEndStr = ev['dataFine']?.toString() ?? ev['data']?.toString() ?? now.toIso8601String();
        final dtEnd = DateTime.tryParse(dtEndStr) ?? now;
        final bool isConcluso = ev['stato'] != 'annullato' && (now.isAfter(dtEnd) || ev['stato'] == 'concluso');
        if (!isConcluso || ev['stato'] == 'annullato') continue;

        final partecipanti = (ev['partecipanti'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final dateStr = '${dtEnd.day.toString().padLeft(2, '0')}/${dtEnd.month.toString().padLeft(2, '0')}/${dtEnd.year}';
        final partBadge = '🎉 Partecipato a "$evTitolo" ($dateStr)';

        String? vincitoreNick = ev['titoliVincitori']?['campione']?.toString();
        int maxPoints = (ev['titoliVincitori']?['campionePunti'] as num?)?.toInt() ?? 0;

        if (vincitoreNick == null || vincitoreNick.isEmpty) {
          final evBm = bmList.where((b) {
            final bEvId = (b['eventoId'] ?? '').toString().trim().toLowerCase();
            return bEvId == evId.toLowerCase() || bEvId == evTitolo.toLowerCase();
          }).toList();

          final Map<String, int> punteggi = {for (var p in partecipanti) p: 0};
          for (var bm in evBm) {
            final bool approvato = bm['approvato'] == true || bm['stato'] == 'approvato';
            if (!approvato) continue;
            final ass = (bm['assegnatoA'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
            final pt = (bm['punti'] as num?)?.toInt() ?? 0;
            for (var u in ass) {
              punteggi[u] = (punteggi[u] ?? 0) + pt;
            }
          }
          if (punteggi.isNotEmpty) {
            final sorted = punteggi.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            vincitoreNick = sorted.first.key;
            maxPoints = sorted.first.value;
          }
        }

        if (vincitoreNick != null && vincitoreNick.isNotEmpty) {
          final resolvedWinner = NicknameHelper.resolve(vincitoreNick, uDocs);
          final badgeMap = {
            'titolo': '🏆 Vincitore Evento',
            'evento': evTitolo,
            'punti': maxPoints,
            'data': dtEnd.toIso8601String(),
          };

          for (var uDoc in uDocs) {
            final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString();
            if (NicknameHelper.isSame(uNick, resolvedWinner, uDocs)) {
              final List<dynamic> currentBadgeVincitore = List.from(uDoc['badgeVincitore'] ?? []);
              final bool giaAssegnato = currentBadgeVincitore.any((b) => b is Map && b['evento'] == evTitolo);
              if (!giaAssegnato) {
                currentBadgeVincitore.add(badgeMap);
                uDoc['badgeVincitore'] = currentBadgeVincitore;

                final List<dynamic> currentStorico = List.from(uDoc['storicoVoti'] ?? []);
                final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                final logVoce = '[${now.toIso8601String().substring(0, 10)} $timeStr] 🏆 Vincitore dell\'evento "$evTitolo" ($maxPoints PT)';
                if (!currentStorico.any((s) => s.toString().contains('Vincitore dell\'evento "$evTitolo"'))) {
                  currentStorico.insert(0, logVoce);
                  uDoc['storicoVoti'] = currentStorico;
                }

                await DbService.instance.utentiCollection.update(
                  where.id(uDoc['_id'] as ObjectId),
                  modify.set('badgeVincitore', currentBadgeVincitore).set('storicoVoti', uDoc['storicoVoti']),
                );
                userDocsModified = true;
              }
            }
          }
        }

        for (var part in partecipanti) {
          for (var uDoc in uDocs) {
            final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString();
            if (NicknameHelper.isSame(uNick, part, uDocs)) {
              final List<dynamic> currentBadgeList = List.from(uDoc['badgeList'] ?? []);
              if (!currentBadgeList.any((b) => b.toString().contains(evTitolo))) {
                currentBadgeList.add(partBadge);
                uDoc['badgeList'] = currentBadgeList;
                await DbService.instance.utentiCollection.update(
                  where.id(uDoc['_id'] as ObjectId),
                  modify.set('badgeList', currentBadgeList),
                );
                userDocsModified = true;
              }
            }
          }
        }

        final titoli = ev['titoliVincitori'] as Map<String, dynamic>?;
        if (titoli != null) {
          final rm = titoli['reMalus']?.toString();
          if (rm != null && rm.isNotEmpty) {
            final resolved = NicknameHelper.resolve(rm, uDocs);
            reMalusTotali[resolved] = (reMalusTotali[resolved] ?? 0) + 1;
          }
          final avv = (titoli['avvocato'] ?? titoli['giudice'])?.toString();
          if (avv != null && avv.isNotEmpty) {
            final resolved = NicknameHelper.resolve(avv, uDocs);
            avvocatoTotali[resolved] = (avvocatoTotali[resolved] ?? 0) + 1;
          }
          final fts = titoli['fantasma']?.toString();
          if (fts != null && fts.isNotEmpty) {
            final resolved = NicknameHelper.resolve(fts, uDocs);
            fantasmaTotali[resolved] = (fantasmaTotali[resolved] ?? 0) + 1;
          }
          final sb = titoli['sbirro']?.toString();
          if (sb != null && sb.isNotEmpty) {
            final resolved = NicknameHelper.resolve(sb, uDocs);
            sbirroTotali[resolved] = (sbirroTotali[resolved] ?? 0) + 1;
          }
          final gst = titoli['giustiziere']?.toString();
          if (gst != null && gst.isNotEmpty) {
            final resolved = NicknameHelper.resolve(gst, uDocs);
            giustiziereTotali[resolved] = (giustiziereTotali[resolved] ?? 0) + 1;
          }
        }
      }

      for (var uDoc in uDocs) {
        final uId = uDoc['_id'] as ObjectId;
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString();
        var mod = modify;
        bool shouldUpdate = false;

        void checkAndUpdateTitle(String field, Map<String, int> map) {
          int count = 0;
          for (var entry in map.entries) {
            if (NicknameHelper.isSame(uNick, entry.key, uDocs)) {
              count += entry.value;
            }
          }
          final curVal = (uDoc[field] as num?)?.toInt() ?? 0;
          if (count > curVal) {
            mod = mod.set(field, count);
            shouldUpdate = true;
          }
        }

        checkAndUpdateTitle('countReMalus', reMalusTotali);
        checkAndUpdateTitle('countGiudice', avvocatoTotali);
        checkAndUpdateTitle('countAvvocato', avvocatoTotali);
        checkAndUpdateTitle('countFantasma', fantasmaTotali);
        checkAndUpdateTitle('countSbirro', sbirroTotali);
        checkAndUpdateTitle('countGiustiziere', giustiziereTotali);

        if (shouldUpdate) {
          await DbService.instance.utentiCollection.update(where.id(uId), mod);
          userDocsModified = true;
        }
      }

      if (userDocsModified) {
        UtenteController.invalidateCache();
      }

      return Response.ok(
        jsonEncode({'success': true, 'modified': userDocsModified}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
