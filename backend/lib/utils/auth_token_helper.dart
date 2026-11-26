import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import '../db/db_service.dart';

class AuthTokenHelper {
  static String get _secret {
    final envSecret = Platform.environment['JWT_SECRET'];
    if (envSecret != null && envSecret.trim().isNotEmpty) {
      return envSecret.trim();
    }
    return 'FantaEventi_Secure_JWT_2026_#Key_${DbService.brevoApiKey}';
  }

  /// Genera un identificativo univoco crittografico per la singola sessione dispositivo
  static String generateSessionId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _base64UrlNoPad(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static List<int> _base64UrlDecodePad(String input) {
    String normalized = input;
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return base64Url.decode(normalized);
  }

  /// Genera un token JWT firmato HMAC-SHA256 valido 90 giorni, vincolato alla sessione dispositivo (sid)
  static String generateToken({
    required String id,
    required String nickname,
    String? sessionId,
  }) {
    final isAdmin = nickname.trim().toLowerCase() == 'cloud' ||
        nickname.trim().toLowerCase() == 'claudio';
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final expSec = nowSec + (90 * 24 * 3600); // 90 giorni

    final header = _base64UrlNoPad(utf8.encode(jsonEncode({
      'alg': 'HS256',
      'typ': 'JWT',
    })));

    final payloadMap = <String, dynamic>{
      'sub': id,
      'nickname': nickname,
      'isAdmin': isAdmin,
      'iat': nowSec,
      'exp': expSec,
      if (sessionId != null && sessionId.isNotEmpty) 'sid': sessionId,
    };

    final payload = _base64UrlNoPad(utf8.encode(jsonEncode(payloadMap)));

    final signingInput = '$header.$payload';
    final hmac = Hmac(sha256, utf8.encode(_secret));
    final digest = hmac.convert(utf8.encode(signingInput));
    final signature = _base64UrlNoPad(digest.bytes);

    return '$signingInput.$signature';
  }

  /// Verifica il token JWT e restituisce il payload decodificato (o null se non valido/scaduto)
  static Map<String, dynamic>? verifyToken(String token) {
    try {
      final parts = token.trim().split('.');
      if (parts.length != 3) return null;

      final signingInput = '${parts[0]}.${parts[1]}';
      final hmac = Hmac(sha256, utf8.encode(_secret));
      final expectedSig = _base64UrlNoPad(hmac.convert(utf8.encode(signingInput)).bytes);

      if (parts[2] != expectedSig) return null;

      final payloadStr = utf8.decode(_base64UrlDecodePad(parts[1]));
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

      final exp = (payload['exp'] as num?)?.toInt() ?? 0;
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (exp > 0 && nowSec > exp) return null;

      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Estrae il payload verificato dall'header Authorization: Bearer <token>
  static Map<String, dynamic>? getAuthFromRequest(Request request) {
    final authHeader = request.headers['authorization'] ?? request.headers['Authorization'] ?? '';
    if (authHeader.toLowerCase().startsWith('bearer ')) {
      final token = authHeader.substring(7).trim();
      if (token.isNotEmpty) {
        return verifyToken(token);
      }
    }
    return null;
  }

  /// Restituisce il nickname autenticato se il token Bearer è presente e valido
  static String? getVerifiedNickname(Request request) {
    final auth = getAuthFromRequest(request);
    final nick = auth?['nickname']?.toString().trim();
    return (nick != null && nick.isNotEmpty) ? nick : null;
  }

  /// Restituisce il sessionId (sid) contenuto nel token Bearer verificato, se presente
  static String? getVerifiedSessionId(Request request) {
    final auth = getAuthFromRequest(request);
    final sid = auth?['sid']?.toString().trim();
    return (sid != null && sid.isNotEmpty) ? sid : null;
  }

  /// Restituisce l'ID documento utente (sub) contenuto nel token Bearer verificato
  static String? getVerifiedUserId(Request request) {
    final auth = getAuthFromRequest(request);
    final sub = auth?['sub']?.toString().trim();
    return (sub != null && sub.isNotEmpty) ? sub : null;
  }

  /// Verifica crittograficamente se la richiesta proviene dall'Amministratore (Cloud)
  static bool isAdminRequest(Request request) {
    final auth = getAuthFromRequest(request);
    if (auth == null) return false;
    if (auth['isAdmin'] == true) return true;
    final nick = (auth['nickname'] ?? '').toString().trim().toLowerCase();
    return nick == 'cloud' || nick == 'claudio';
  }
}
