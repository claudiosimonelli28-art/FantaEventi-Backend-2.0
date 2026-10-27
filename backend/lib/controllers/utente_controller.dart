import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/utente.dart';
import '../utils/nickname_helper.dart';


String hashPassword(String password) {
  const salt = 'FantaEventi2026_Secure_Salt_#99';
  final bytes = utf8.encode('$password$salt');
  return sha256.convert(bytes).toString();
}

Future<bool> sendResetEmail({
  required String recipientEmail,
  required String recipientName,
  required String code,
}) async {
  final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #121212; color: #FFFFFF; margin: 0; padding: 20px; }
    .card { background-color: #1E1E1E; border-radius: 16px; border: 1px solid #333333; max-width: 500px; margin: 0 auto; padding: 32px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); text-align: center; }
    .logo { font-size: 28px; font-weight: bold; color: #E5A93C; letter-spacing: 1px; margin-bottom: 8px; }
    .subtitle { font-size: 15px; color: #AAAAAA; margin-bottom: 24px; }
    .code-box { background-color: #2A2A2A; border: 2px dashed #E5A93C; border-radius: 12px; padding: 18px 24px; font-size: 32px; font-weight: bold; letter-spacing: 8px; color: #FFD56B; margin: 24px 0; display: inline-block; }
    .info { font-size: 13px; color: #888888; line-height: 1.6; margin-top: 16px; }
    .footer { margin-top: 32px; font-size: 12px; color: #555555; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🎉 FANTA-EVENTI</div>
    <div class="subtitle">Recupero della Password</div>
    <p style="color: #DDDDDD; font-size: 16px;">Ciao <b>$recipientName</b>,</p>
    <p style="color: #BBBBBB; font-size: 14px;">Abbiamo ricevuto una richiesta di reimpostazione della tua password. Usa il seguente codice a 6 cifre per procedere:</p>
    <div class="code-box">$code</div>
    <p class="info">Questo codice scadr&agrave; tra <b>15 minuti</b>.<br>Se non hai richiesto tu il recupero, puoi tranquillamente ignorare questa email.</p>
    <div class="footer">&copy; 2026 Fanta-Eventi. Tutti i diritti riservati.</div>
  </div>
</body>
</html>
''';

  // 1. Invio primario tramite Brevo API (recapito illimitato a tutti i destinatari)
  final brevoKey = DbService.brevoApiKey;
  if (brevoKey.isNotEmpty) {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('https://api.brevo.com/v3/smtp/email'));
      request.headers.set('api-key', brevoKey);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');

      final payload = {
        'sender': {
          'name': 'Fanta-Eventi',
          'email': 'claudio.simonelli28@gmail.com',
        },
        'to': [
          {'email': recipientEmail, 'name': recipientName}
        ],
        'subject': '🔑 Il tuo codice di recupero Fanta-Eventi: $code',
        'htmlContent': htmlContent,
      };

      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      print('📧 [Brevo] Invio email a $recipientEmail - Status: ${response.statusCode} - Body: $body');
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (e) {
      print('❌ [Brevo] Errore invio: $e');
    } finally {
      client.close();
    }
  }

  return false;
}


class UtenteController {
  static List<Map<String, dynamic>>? _cachedUtentiDocs;
  static DateTime? _lastUtentiFetch;
  static const _cacheDuration = Duration(minutes: 2);

  static void invalidateCache() {
    _cachedUtentiDocs = null;
    _lastUtentiFetch = null;
  }

  static Future<List<Map<String, dynamic>>> getCachedUtentiDocs({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedUtentiDocs != null &&
        _lastUtentiFetch != null &&
        now.difference(_lastUtentiFetch!) < _cacheDuration) {
      return _cachedUtentiDocs!;
    }
    final docs = await DbService.instance.utentiCollection.find(where.excludeFields(['avatarUrl'])).toList();
    _cachedUtentiDocs = docs;
    _lastUtentiFetch = now;
    return docs;
  }

  // POST /api/login
  Future<Response> login(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final identifier = (data['username'] ?? data['email'] ?? data['nickname'])?.toString().trim();
      final password = data['password']?.toString().trim() ?? '';

      print('📥 [HTTP POST /api/login] Login per "$identifier"');

      if (identifier == null || identifier.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Inserisci il tuo Username, Nickname o Email'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final rawIdentifier = identifier;
      final cleanIdentifierLower = rawIdentifier.toLowerCase();
      final isEmailLogin = rawIdentifier.contains('@');

      final allDocs = await getCachedUtentiDocs();
      Map<String, dynamic>? doc;

      for (var d in allDocs) {
        final actualNick = (d['nickname'] ?? d['username'] ?? '').toString().trim();
        final actualUser = (d['username'] ?? '').toString().trim();
        final actualNome = (d['nome'] ?? '').toString().trim();
        final actualEmail = (d['email'] ?? '').toString().trim();

        final primaryNick = actualNick.isNotEmpty ? actualNick : (actualUser.isNotEmpty ? actualUser : actualNome);

        if (isEmailLogin) {
          if (actualEmail.toLowerCase() == cleanIdentifierLower) {
            doc = d;
            break;
          }
        } else {
          if (rawIdentifier == primaryNick ||
              rawIdentifier == actualUser ||
              rawIdentifier == actualNome ||
              (cleanIdentifierLower == 'claudio' && (primaryNick.toLowerCase() == 'cloud' || actualEmail.toLowerCase().contains('claudio.simonelli')))) {
            doc = d;
            break;
          } else if (cleanIdentifierLower == primaryNick.toLowerCase() ||
                     cleanIdentifierLower == actualUser.toLowerCase() ||
                     cleanIdentifierLower == actualNome.toLowerCase()) {
            doc = d;
            break;
          }
        }
      }

      if (doc == null) {
        print('⚠️ Utente "$rawIdentifier" non trovato nel database MongoDB.');
        return Response.notFound(
          jsonEncode({
            'error': 'Nessun utente trovato per "$rawIdentifier"',
            'notFound': true,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final existingPassword = (doc['password'] ?? doc['passwordHash'] ?? '').toString().trim();
      final actualUsername = (doc['nome'] ?? doc['username'] ?? doc['nickname'] ?? 'Utente').toString();
      final actualEmail = (doc['email'] ?? '').toString();

      // Riconoscimento Primo Accesso: l'utente esiste ma non ha ancora una password impostata
      if (existingPassword.isEmpty) {
        print('🔑 Utente "$actualUsername" non ha ancora una password impostata. Richiedo setup iniziale.');
        return Response.ok(
          jsonEncode({
            'needsPasswordSetup': true,
            'username': actualUsername,
            'email': actualEmail,
            'message': 'Questo account richiede l\'impostazione di una password per il primo accesso.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Se l'utente ha la password, verifica che sia stata fornita
      if (password.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Inserisci la tua password per accedere'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final incomingHash = hashPassword(password);
      if (incomingHash != existingPassword) {
        print('⛔ Password errata per l\'utente "$actualUsername"');
        return Response.forbidden(
          jsonEncode({'error': 'Password non corretta. Riprova!'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final utente = Utente.fromMap(doc);
      if (utente.isBanned) {
        print('⛔ Utente "${utente.username}" è sospeso/bannato.');
        return Response.forbidden(
          jsonEncode({
            'error': 'Account sospeso. Questo profilo è stato bloccato per violazione delle linee guida della community.',
            'isBanned': true,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      print('✅ Login riuscito con password per utente: ${utente.username}');
      return Response.ok(
        jsonEncode({
          'message': 'Login effettuato con successo',
          'utente': utente.toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore login: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // GET /api/utenti
  Future<Response> getUtenti(Request request) async {
    try {
      print('📥 [HTTP GET /api/utenti] Recupero lista utenti dal database...');
      final docs = await getCachedUtentiDocs();
      print('📦 [MongoDB] Trovati ${docs.length} utenti nel database.');
      final utenti = docs.map((d) => Utente.fromMap(d).toJson()).toList();
      return Response.ok(
        jsonEncode(utenti),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore recupero utenti: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/registrazione oppure POST /api/utenti
  Future<Response> creaUtente(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      
      final username = (data['username'] ?? data['nickname'] ?? data['nome'])?.toString().trim() ?? '';
      final email = data['email']?.toString().trim() ?? '';
      final password = data['password']?.toString().trim() ?? '';

      print('📥 [HTTP POST /api/registrazione] Creazione utente "$username" ($email)...');

      if (username.length < 3) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Il Nickname deve contenere almeno 3 caratteri'}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (password.length < 6) {
        return Response.badRequest(
          body: jsonEncode({'error': 'La password deve contenere almeno 6 caratteri'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final formattedEmail = email.isNotEmpty ? email : '${username.toLowerCase().replaceAll(' ', '')}@fantaeventi.it';

      final allDocs = await DbService.instance.utentiCollection.find(where.excludeFields(['avatarUrl'])).toList();
      final existingLower = <String>{};
      for (var d in allDocs) {
        final uNick = (d['nickname'] ?? d['username'] ?? '').toString().trim().toLowerCase();
        final uUser = (d['username'] ?? '').toString().trim().toLowerCase();
        final uName = (d['nome'] ?? '').toString().trim().toLowerCase();
        final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
        if (uNick.isNotEmpty) existingLower.add(uNick);
        if (uUser.isNotEmpty) existingLower.add(uUser);
        if (uName.isNotEmpty) existingLower.add(uName);
        if (formattedEmail.isNotEmpty && uEmail == formattedEmail.toLowerCase()) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Un account con questa Email esiste già'}),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      if (existingLower.contains(username.toLowerCase())) {
        final suggestions = <String>[];
        final candidates = [
          '${username}1234',
          '${username}2026',
          '${username}99',
          '$username${username[username.length - 1]}',
          '${username}_fanta',
          'il_$username',
        ];
        for (var c in candidates) {
          if (!existingLower.contains(c.toLowerCase()) && !suggestions.contains(c)) {
            suggestions.add(c);
            if (suggestions.length >= 3) break;
          }
        }

        return Response.badRequest(
          body: jsonEncode({
            'error': 'Nome utente già utilizzato',
            'suggerimenti': suggestions,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final hashedPassword = hashPassword(password);
      final now = DateTime.now();
      final dateFormatted = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final nickClean = username.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final codePrefix = nickClean.length >= 3 ? nickClean.substring(0, 3) : 'FE';
      final friendCode = 'FE-$codePrefix${1000 + Random().nextInt(9000)}';
      final avatar = (data['avatarUrl'] ?? '').toString().trim().isNotEmpty
          ? data['avatarUrl'].toString().trim()
          : 'https://i.pravatar.cc/150?u=${Uri.encodeComponent(username)}';

      final utenteMap = {
        'nome': (data['nome'] ?? '').toString().trim().isNotEmpty ? data['nome'].toString().trim() : username,
        'cognome': (data['cognome'] ?? '').toString().trim(),
        'nickname': username,
        'username': username,
        'email': formattedEmail,
        'password': hashedPassword,
        'passwordHash': hashedPassword,
        'ruolo': 'partecipante',
        'avatarUrl': avatar,
        'livello': 1,
        'xp': 100,
        'xpProssimoLivello': 2000,
        'xpTotali': 100,
        'puntiTotali': 0,
        'puntiEsperienza': 100,
        'badgeList': ['🎉 Partecipante FantaEventi'],
        'storicoVoti': <String>[],
        'codiceAmico': friendCode,
        'amici': <String>[],
        'richiesteAmicizia': <Map<String, dynamic>>[],
        'badgeVincitore': <Map<String, dynamic>>[],
        'countGiudice': 0,
        'countReMalus': 0,
        'countFantasma': 0,
        'countSbirro': 0,
        'countGiustiziere': 0,
        'haVistoGuida': false,
        'fcmTokens': <String>[],
        'dataRegistrazione': dateFormatted,
        'createdAt': now.toIso8601String(),
      };

      final res = await DbService.instance.utentiCollection.insertOne(utenteMap);
      final salvato = await DbService.instance.utentiCollection.findOne(where.id(res.id as ObjectId));
      invalidateCache();

      print('✅ [MongoDB] NUOVO UTENTE REGISTRATO CON PASSWORD! ID: ${res.id}');

      return Response.ok(
        jsonEncode({
          'message': 'Nuovo utente salvato automaticamente nel database MongoDB!',
          'utente': Utente.fromMap(salvato!).toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore creazione utente: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/utenti/imposta-password
  Future<Response> impostaPassword(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final username = (data['username'] ?? data['nickname'] ?? data['identifier'])?.toString().trim() ?? '';
      final password = data['password']?.toString().trim() ?? '';

      print('📥 [HTTP POST /api/utenti/imposta-password] Setup password per "$username"');

      if (username.isEmpty || password.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Username e password sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (password.length < 6) {
        return Response.badRequest(
          body: jsonEncode({'error': 'La password deve contenere almeno 6 caratteri'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final hashedPassword = hashPassword(password);

      final selector = where.eq('username', username)
          .or(where.eq('nickname', username))
          .or(where.eq('nome', username))
          .or(where.eq('email', username));

      final doc = await DbService.instance.utentiCollection.findOne(selector);
      if (doc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Utente non trovato'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await DbService.instance.utentiCollection.update(
        selector,
        modify.set('password', hashedPassword).set('passwordHash', hashedPassword),
      );
      invalidateCache();

      final updatedDoc = await DbService.instance.utentiCollection.findOne(selector);
      final utente = Utente.fromMap(updatedDoc!);

      print('✅ Password impostata con successo per utente "$username"');
      return Response.ok(
        jsonEncode({
          'message': 'Password impostata con successo!',
          'utente': utente.toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore impostazione password: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
  Future<Response> aggiornaAvatar(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final utenteName = (data['utente'] ?? data['username'])?.toString().trim() ?? '';
      final avatarUrl = data['avatarUrl']?.toString().trim() ?? '';

      print('📥 [HTTP POST /api/utenti/avatar] Aggiornamento foto profilo per "$utenteName"');

      if (utenteName.isEmpty || avatarUrl.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Utente ed avatarUrl sono obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await DbService.instance.utentiCollection.update(
        where.eq('username', utenteName)
             .or(where.eq('nickname', utenteName))
             .or(where.eq('nome', utenteName)),
        modify.set('avatarUrl', avatarUrl).set('foto', avatarUrl),
      );
      invalidateCache();

      print('📸 [MongoDB] Avatar salvato permanentemente in MongoDB Atlas per l\'utente "$utenteName"!');
      return Response.ok(
        jsonEncode({'message': 'Avatar salvato permanentemente in MongoDB Atlas!'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore salvataggio avatar: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/utenti/richiedi-reset-password
  Future<Response> richiediResetPassword(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final identifier = (data['identifier'] ?? data['email'] ?? data['username'] ?? data['nickname'])?.toString().trim();

      print('📥 [HTTP POST /api/utenti/richiedi-reset-password] Richiesta per "$identifier"');

      if (identifier == null || identifier.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Inserisci il tuo Nickname o la tua Email'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final cleanIdent = identifier.toLowerCase();
      final docs = await DbService.instance.utentiCollection.find(where.excludeFields(['avatarUrl'])).toList();
      Map<String, dynamic>? doc;

      for (var d in docs) {
        final uNick = (d['nickname'] ?? d['username'] ?? '').toString().trim().toLowerCase();
        final uUser = (d['username'] ?? '').toString().trim().toLowerCase();
        final uName = (d['nome'] ?? '').toString().trim().toLowerCase();
        final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
        final isClaudioAlias = (cleanIdent == 'claudio' && (uNick == 'cloud' || uName == 'cloud' || uEmail.contains('claudio.simonelli')));
        if (uNick == cleanIdent || uUser == cleanIdent || uName == cleanIdent || uEmail == cleanIdent || isClaudioAlias) {
          doc = d;
          break;
        }
      }

      if (doc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Nessun account trovato per "$identifier".'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final email = (doc['email'] ?? '').toString().trim();
      final username = (doc['nome'] ?? doc['username'] ?? doc['nickname'] ?? 'Utente').toString();

      if (email.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Nessuna email associata a questo profilo.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Generazione codice casuale a 6 cifre (100000 - 999999)
      final random = Random.secure();
      final code = (100000 + random.nextInt(900000)).toString();
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 15));

      // Salvataggio nel database temporaneo PasswordResetTokens
      await DbService.instance.passwordResetCollection.update(
        where.eq('email', email),
        {
          'email': email,
          'username': username,
          'codice': code,
          'scadenza': expiresAt.toIso8601String(),
          'tentativi': 0,
          'creatoIl': DateTime.now().toUtc().toIso8601String(),
        },
        upsert: true,
      );

      print('🔑 Codice $code generato per $username ($email). Invio email via Brevo...');

      // Invio email via Brevo
      final inviata = await sendResetEmail(
        recipientEmail: email,
        recipientName: username,
        code: code,
      );

      if (!inviata) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Errore durante l\'invio dell\'email. Riprova più tardi.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Oscuramento parziale dell'email per la privacy (es. cla****@gmail.com)
      final parts = email.split('@');
      String maskedEmail = email;
      if (parts.length == 2) {
        final local = parts[0];
        if (local.length > 3) {
          maskedEmail = '${local.substring(0, 3)}****@${parts[1]}';
        } else {
          maskedEmail = '${local[0]}****@${parts[1]}';
        }
      }

      return Response.ok(
        jsonEncode({
          'message': 'Codice inviato con successo!',
          'email': email,
          'maskedEmail': maskedEmail,
          'username': username,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore richiediResetPassword: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // POST /api/utenti/conferma-reset-password
  Future<Response> confermaResetPassword(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final emailOrIdentifier = (data['email'] ?? data['identifier'] ?? data['username'])?.toString().trim() ?? '';
      final codice = data['codice']?.toString().trim() ?? '';
      final nuovaPassword = data['nuovaPassword']?.toString().trim() ?? '';

      print('📥 [HTTP POST /api/utenti/conferma-reset-password] Verifica codice per "$emailOrIdentifier"');

      if (emailOrIdentifier.isEmpty || codice.isEmpty || nuovaPassword.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Email, codice e nuova password sono obbligatori.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (nuovaPassword.length < 6) {
        return Response.badRequest(
          body: jsonEncode({'error': 'La password deve contenere almeno 6 caratteri.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final resetToken = await DbService.instance.passwordResetCollection.findOne(
        where.eq('email', emailOrIdentifier).or(where.eq('username', emailOrIdentifier)),
      );

      if (resetToken == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Nessuna richiesta di recupero attiva. Richiedi un nuovo codice.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final scadenzaStr = resetToken['scadenza']?.toString() ?? '';
      final scadenza = DateTime.tryParse(scadenzaStr);
      if (scadenza == null || DateTime.now().toUtc().isAfter(scadenza)) {
        await DbService.instance.passwordResetCollection.remove(where.id(resetToken['_id'] as ObjectId));
        return Response.badRequest(
          body: jsonEncode({'error': 'Il codice di verifica è scaduto. Richiedine uno nuovo.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final tentativi = (resetToken['tentativi'] ?? 0) as int;
      if (tentativi >= 5) {
        await DbService.instance.passwordResetCollection.remove(where.id(resetToken['_id'] as ObjectId));
        return Response.badRequest(
          body: jsonEncode({'error': 'Troppi tentativi falliti. Per sicurezza richiedi un nuovo codice.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final codiceSalvato = (resetToken['codice'] ?? '').toString().trim();
      if (codiceSalvato != codice) {
        await DbService.instance.passwordResetCollection.update(
          where.id(resetToken['_id'] as ObjectId),
          modify.inc('tentativi', 1),
        );
        return Response.badRequest(
          body: jsonEncode({'error': 'Codice di verifica non corretto. Riprova.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Codice verificato con successo! Aggiornamento password
      final targetEmail = resetToken['email']?.toString() ?? emailOrIdentifier;
      final hashedPassword = hashPassword(nuovaPassword);

      final userDoc = await DbService.instance.utentiCollection.findOne(
        where.eq('email', targetEmail).or(where.eq('username', emailOrIdentifier)),
      );

      if (userDoc == null) {
        return Response.notFound(
          jsonEncode({'error': 'Profilo utente non trovato.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      await DbService.instance.utentiCollection.update(
        where.id(userDoc['_id'] as ObjectId),
        modify.set('password', hashedPassword).set('passwordHash', hashedPassword),
      );
      invalidateCache();

      // Elimina il token monouso
      await DbService.instance.passwordResetCollection.remove(where.id(resetToken['_id'] as ObjectId));

      print('✅ Password reimpostata con successo per l\'utente "${userDoc['username']}"!');
      return Response.ok(
        jsonEncode({
          'message': 'Password reimpostata con successo! Ora puoi accedere con la nuova password.',
          'username': userDoc['username'] ?? userDoc['nome'] ?? '',
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('❌ Errore confermaResetPassword: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // GET /api/utenti/check-nickname
  Future<Response> checkNickname(Request request) async {
    try {
      final nick = request.url.queryParameters['nick']?.trim() ?? request.url.queryParameters['nickname']?.trim() ?? '';
      if (nick.length < 3) {
        return Response.ok(
          jsonEncode({
            'disponibile': false,
            'messaggio': 'Il nickname deve contenere almeno 3 caratteri.',
            'suggerimenti': <String>[],
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final docs = await DbService.instance.utentiCollection.find(where.excludeFields(['avatarUrl'])).toList();
      final existingLower = <String>{};
      for (var d in docs) {
        final uNick = (d['nickname'] ?? d['username'] ?? '').toString().trim().toLowerCase();
        final uUser = (d['username'] ?? '').toString().trim().toLowerCase();
        final uName = (d['nome'] ?? '').toString().trim().toLowerCase();
        if (uNick.isNotEmpty) existingLower.add(uNick);
        if (uUser.isNotEmpty) existingLower.add(uUser);
        if (uName.isNotEmpty) existingLower.add(uName);
      }

      if (existingLower.contains(nick.toLowerCase())) {
        final base = nick.replaceAll(RegExp(r'\d+$'), '');
        final random = Random();
        final suggerimenti = <String>[];
        while (suggerimenti.length < 3) {
          final candidate = '${base}_${random.nextInt(90) + 10}';
          if (!existingLower.contains(candidate.toLowerCase()) && !suggerimenti.contains(candidate)) {
            suggerimenti.add(candidate);
          }
        }
        return Response.ok(
          jsonEncode({
            'disponibile': false,
            'messaggio': 'Nome utente già in uso.',
            'suggerimenti': suggerimenti,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          'disponibile': true,
          'messaggio': 'Nome utente disponibile! ✨',
          'suggerimenti': <String>[],
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

  // POST /api/utenti/elimina-account
  Future<Response> eliminaAccount(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final utenteId = data['utenteId']?.toString();
      final nickname = (data['nickname'] ?? data['username'])?.toString();
      final nome = data['nome']?.toString();

      final cleanNick = (nickname ?? '').trim().toLowerCase();
      final cleanName = (nome ?? '').trim().toLowerCase();

      final allUsers = await DbService.instance.utentiCollection.find().toList();
      Map<String, dynamic>? targetUser;

      for (var u in allUsers) {
        final uIdStr = u['_id'] is ObjectId ? (u['_id'] as ObjectId).oid : u['_id']?.toString() ?? '';
        final uNick = (u['nickname'] ?? u['username'] ?? '').toString().trim().toLowerCase();
        final uNome = (u['nome'] ?? '').toString().trim().toLowerCase();

        if (utenteId != null && utenteId.isNotEmpty && uIdStr == utenteId) {
          targetUser = u;
          break;
        }
        if (cleanNick.isNotEmpty && (uNick == cleanNick || uNome == cleanNick)) {
          targetUser = u;
          break;
        }
        if (cleanName.isNotEmpty && (uNome == cleanName || uNick == cleanName)) {
          targetUser = u;
          break;
        }
      }

      if (targetUser != null) {
        final uId = targetUser['_id'] as ObjectId;
        await DbService.instance.utentiCollection.remove(where.id(uId));

        final matchNames = <String>{};
        if (cleanNick.isNotEmpty) matchNames.add(cleanNick);
        if (cleanName.isNotEmpty) matchNames.add(cleanName);
        final tn = (targetUser['nickname'] ?? targetUser['username'] ?? '').toString();
        final tm = (targetUser['nome'] ?? '').toString();
        if (tn.isNotEmpty) matchNames.add(tn);
        if (tm.isNotEmpty) matchNames.add(tm);

        for (var name in matchNames) {
          try {
            await DbService.instance.notificheCollection.remove(
              where.eq('destinatario', name).or(where.eq('mittente', name)),
            );
          } catch (_) {}
        }
      }

      invalidateCache();
      return Response.ok(
        jsonEncode({'message': 'Account eliminato con successo'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// Blocca un utente, rimuovendolo dagli amici e inviando la notifica
  Future<Response> bloccaUtente(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final utente = (data['utente'] ?? '').toString().trim();
      final target = (data['target'] ?? '').toString().trim();

      if (utente.isEmpty || target.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'utente e target obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final uDocs = await getCachedUtentiDocs();
      final cleanUtente = NicknameHelper.resolve(utente, uDocs);
      final cleanTarget = NicknameHelper.resolve(target, uDocs);

      // 1. Aggiorna l'utente bloccante: aggiungi a utentiBloccati e rimuovi dagli amici
      for (var uDoc in uDocs) {
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
        if (NicknameHelper.isSame(uNick, cleanUtente, uDocs)) {
          final uId = uDoc['_id'] as ObjectId;
          final currentBloccati = List<String>.from((uDoc['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
          if (!currentBloccati.any((b) => NicknameHelper.isSame(b, cleanTarget, uDocs))) {
            currentBloccati.add(cleanTarget);
          }
          final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
          currentAmici.removeWhere((a) => NicknameHelper.isSame(a, cleanTarget, uDocs));

          await DbService.instance.utentiCollection.update(
            where.id(uId),
            modify.set('utentiBloccati', currentBloccati).set('amici', currentAmici),
          );
          break;
        }
      }

      // 2. Rimuovi l'utente bloccante dalla lista amici del target
      for (var uDoc in uDocs) {
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
        if (NicknameHelper.isSame(uNick, cleanTarget, uDocs)) {
          final uId = uDoc['_id'] as ObjectId;
          final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
          currentAmici.removeWhere((a) => NicknameHelper.isSame(a, cleanUtente, uDocs));

          await DbService.instance.utentiCollection.update(
            where.id(uId),
            modify.set('amici', currentAmici),
          );
          break;
        }
      }

      // 3. Rimuovi eventuali richieste amicizia pendenti
      try {
        final nots = await DbService.instance.notificheCollection.find(
          where.eq('tipo', 'richiesta_amicizia'),
        ).toList();
        for (var n in nots) {
          final m = (n['mittente'] ?? '').toString().trim();
          final d = (n['destinatario'] ?? '').toString().trim();
          if ((NicknameHelper.isSame(m, cleanUtente, uDocs) && NicknameHelper.isSame(d, cleanTarget, uDocs)) ||
              (NicknameHelper.isSame(m, cleanTarget, uDocs) && NicknameHelper.isSame(d, cleanUtente, uDocs))) {
            await DbService.instance.notificheCollection.remove(where.id(n['_id'] as ObjectId));
          }
        }
      } catch (_) {}

      // 4. Invia notifica di blocco al target
      await DbService.instance.notificheCollection.insertOne({
        'tipo': 'blocco_utente',
        'titolo': '🚫 Sei stato bloccato',
        'messaggio': '$cleanUtente ti ha bloccato. Momentaneamente non siete più amici fino a quando $cleanUtente non ti sbloccherà.',
        'mittente': cleanUtente,
        'destinatario': cleanTarget,
        'timestamp': DateTime.now().toIso8601String(),
        'letto': false,
      });

      invalidateCache();
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Utente bloccato con successo'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// Sblocca un utente precedentemente bloccato e invia la notifica
  Future<Response> sbloccaUtente(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final utente = (data['utente'] ?? '').toString().trim();
      final target = (data['target'] ?? '').toString().trim();

      if (utente.isEmpty || target.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'utente e target obbligatori'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final uDocs = await getCachedUtentiDocs();
      final cleanUtente = NicknameHelper.resolve(utente, uDocs);
      final cleanTarget = NicknameHelper.resolve(target, uDocs);

      // 1. Rimuovi da utentiBloccati di cleanUtente e ripristina cleanTarget tra gli amici
      for (var uDoc in uDocs) {
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
        if (NicknameHelper.isSame(uNick, cleanUtente, uDocs)) {
          final uId = uDoc['_id'] as ObjectId;
          final currentBloccati = List<String>.from((uDoc['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
          currentBloccati.removeWhere((b) => NicknameHelper.isSame(b, cleanTarget, uDocs));

          final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
          if (!currentAmici.any((a) => NicknameHelper.isSame(a, cleanTarget, uDocs))) {
            currentAmici.add(cleanTarget);
          }

          await DbService.instance.utentiCollection.update(
            where.id(uId),
            modify.set('utentiBloccati', currentBloccati).set('amici', currentAmici),
          );
          break;
        }
      }

      // 2. Ripristina cleanUtente tra gli amici di cleanTarget
      for (var uDoc in uDocs) {
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
        if (NicknameHelper.isSame(uNick, cleanTarget, uDocs)) {
          final uId = uDoc['_id'] as ObjectId;
          final currentAmici = List<String>.from((uDoc['amici'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
          if (!currentAmici.any((a) => NicknameHelper.isSame(a, cleanUtente, uDocs))) {
            currentAmici.add(cleanUtente);
          }

          await DbService.instance.utentiCollection.update(
            where.id(uId),
            modify.set('amici', currentAmici),
          );
          break;
        }
      }

      // 3. Invia notifica di sblocco al target
      await DbService.instance.notificheCollection.insertOne({
        'tipo': 'sblocco_utente',
        'titolo': '🤝 Sei stato sbloccato',
        'messaggio': '$cleanUtente ti ha sbloccato. Siete di nuovo amici!',
        'mittente': cleanUtente,
        'destinatario': cleanTarget,
        'timestamp': DateTime.now().toIso8601String(),
        'letto': false,
      });

      invalidateCache();
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Utente sbloccato con successo'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// Restituisce la lista degli utenti bloccati da un utente
  Future<Response> getUtentiBloccati(Request request) async {
    try {
      final utente = (request.url.queryParameters['utente'] ?? '').toString().trim();
      if (utente.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Parametro utente obbligatorio'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final uDocs = await getCachedUtentiDocs();
      final cleanUtente = NicknameHelper.resolve(utente, uDocs);

      List<String> bloccati = [];
      for (var uDoc in uDocs) {
        final uNick = (uDoc['nickname'] ?? uDoc['username'] ?? uDoc['nome'] ?? '').toString().trim();
        if (NicknameHelper.isSame(uNick, cleanUtente, uDocs)) {
          bloccati = List<String>.from((uDoc['utentiBloccati'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
          break;
        }
      }

      return Response.ok(
        jsonEncode({'bloccati': bloccati}),
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

