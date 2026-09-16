import 'dart:convert';
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
}
