import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db.dart';
import '../util.dart';
import 'ai.dart';

/// Одинаковое задание — тот же ответ из базы. Хранится 30 дней.
class CachedAi implements AiProvider {
  CachedAi(this.inner);
  final AiProvider inner;

  @override
  Future<Map<String, dynamic>> json(String prompt) async {
    final key = sha1.convert(utf8.encode(prompt)).toString();
    final hit = await q1("select response from ai_cache where key = @k and created_at > now() - interval '30 days'",
        {'k': key});
    if (hit != null) return (jv(hit['response']) as Map).cast<String, dynamic>();
    final r = await inner.json(prompt);
    await q('insert into ai_cache(key, response) values(@k, @r:jsonb) on conflict (key) do update set response = @r:jsonb, created_at = now()',
        {'k': key, 'r': r});
    return r;
  }
}
