import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';
import '../models/utente.dart';


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

  // 2. Fallback tramite Resend
  final resendKey = DbService.resendApiKey;
  if (resendKey.isNotEmpty) {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('https://api.resend.com/emails'));
      request.headers.set('Authorization', 'Bearer $resendKey');
      request.headers.set('Content-Type', 'application/json');

      final payload = {
        'from': 'Fanta-Eventi <onboarding@resend.dev>',
        'to': [recipientEmail],
        'subject': '🔑 Il tuo codice di recupero Fanta-Eventi: $code',
        'html': htmlContent,
      };

      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      print('📧 [Resend Fallback] Invio email a $recipientEmail - Status: ${response.statusCode} - Body: $body');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ [Resend Fallback] Errore invio email: $e');
      return false;
    } finally {
      client.close();
    }
  }

  return false;
}


class UtenteController {
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

      final doc = await DbService.instance.utentiCollection.findOne(
        where.eq('username', identifier)
             .or(where.eq('nickname', identifier))
             .or(where.eq('nome', identifier))
             .or(where.eq('email', identifier)),
      );

      if (doc == null) {
        print('⚠️ Utente "$identifier" non trovato nel database MongoDB.');
        return Response.notFound(
          jsonEncode({
            'error': 'Nessun utente trovato per "$identifier"',
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
      final docs = await DbService.instance.utentiCollection.find().toList();
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

      if (username.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'L\'Username o Nickname è obbligatorio'}),
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

      final esistente = await DbService.instance.utentiCollection.findOne(
        where.eq('username', username)
             .or(where.eq('nickname', username))
             .or(where.eq('email', formattedEmail)),
      );

      if (esistente != null) {
        final utenteEsistente = Utente.fromMap(esistente);
        print('ℹ️ Utente "$username" era già presente su MongoDB.');
        return Response.ok(
          jsonEncode({
            'message': 'Utente già presente nel database',
            'utente': utenteEsistente.toJson(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final hashedPassword = hashPassword(password);

      final utente = Utente(
        username: username,
        email: formattedEmail,
        password: hashedPassword,
        ruolo: 'partecipante',
        squadra: data['squadra'],
      );

      final res = await DbService.instance.utentiCollection.insertOne(utente.toMap());
      final salvato = await DbService.instance.utentiCollection.findOne(where.id(res.id as ObjectId));

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
      final docs = await DbService.instance.utentiCollection.find().toList();
      Map<String, dynamic>? doc;

      for (var d in docs) {
        final uName = (d['nome'] ?? d['username'] ?? d['nickname'] ?? '').toString().trim().toLowerCase();
        final uEmail = (d['email'] ?? '').toString().trim().toLowerCase();
        final isClaudioAlias = (cleanIdent == 'claudio' && (uName == 'cloud' || uEmail.contains('claudio.simonelli')));
        if (uName == cleanIdent || uEmail == cleanIdent || isClaudioAlias) {
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

      print('🔑 Codice $code generato per $username ($email). Invio email via Resend...');

      // Invio email via Resend
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
}

