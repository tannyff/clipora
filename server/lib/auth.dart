import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'db.dart';

const _iterations = 60000;
final _rnd = Random.secure();

List<int> _randomBytes(int n) => List<int>.generate(n, (_) => _rnd.nextInt(256));

List<int> _pbkdf2(List<int> pass, List<int> salt, int iter, int len) {
  final hmac = Hmac(sha256, pass);
  final out = <int>[];
  var block = 1;
  while (out.length < len) {
    var u = hmac.convert([
      ...salt,
      (block >> 24) & 255,
      (block >> 16) & 255,
      (block >> 8) & 255,
      block & 255
    ]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iter; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
    block++;
  }
  return out.sublist(0, len);
}

String hashPassword(String password) {
  final salt = _randomBytes(16);
  final h = _pbkdf2(utf8.encode(password), salt, _iterations, 32);
  return 'pbkdf2\$$_iterations\$${base64.encode(salt)}\$${base64.encode(h)}';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split('\$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iter = int.parse(parts[1]);
  final salt = base64.decode(parts[2]);
  final expected = base64.decode(parts[3]);
  final h = _pbkdf2(utf8.encode(password), salt, iter, expected.length);
  var diff = 0;
  for (var i = 0; i < h.length; i++) {
    diff |= h[i] ^ expected[i];
  }
  return diff == 0;
}

Future<String> createSession(String userId) async {
  final token = base64Url.encode(_randomBytes(32)).replaceAll('=', '');
  await q('insert into sessions(token, user_id) values(@t, @u)', {'t': token, 'u': userId});
  return token;
}

Future<String?> userIdFromToken(String? token) async {
  if (token == null || token.isEmpty) return null;
  final row = await q1('select user_id from sessions where token = @t', {'t': token});
  return row?['user_id'] as String?;
}

Future<String?> userIdFromRequest(Request req) {
  final h = req.headers['authorization'] ?? '';
  final token = h.startsWith('Bearer ') ? h.substring(7) : null;
  return userIdFromToken(token);
}
