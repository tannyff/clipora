import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Любой AI, который умеет вернуть JSON. Провайдер выбирается в .env (AI_PROVIDER).
abstract class AiProvider {
  Future<Map<String, dynamic>> json(String prompt);
}

http.Client _client(String? proxy) {
  final hc = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  hc.findProxy = (uri) {
    if (proxy != null && proxy.isNotEmpty) {
      final u = Uri.parse(proxy.contains('://') ? proxy : 'http://$proxy');
      return 'PROXY ${u.host}:${u.port}';
    }
    return HttpClient.findProxyFromEnvironment(uri);
  };
  return IOClient(hc);
}

Map<String, dynamic> _parseJson(String text) {
  var s = text.trim();
  if (s.startsWith('```')) {
    s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '').replaceFirst(RegExp(r'```$'), '').trim();
  }
  // Локальные модели иногда пишут текст до или после JSON.
  final a = s.indexOf('{'), b = s.lastIndexOf('}');
  if (a > 0 || (b >= 0 && b < s.length - 1)) s = s.substring(a, b + 1);
  return jsonDecode(s) as Map<String, dynamic>;
}

/// Текст ошибки показывается в приложении как есть, без «Exception:» и сырого JSON.
class AiError implements Exception {
  AiError(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _overloaded(int code) => code == 429 || code >= 500;

Future<http.Response> _postWithRetry(http.Client c, Uri url, Map<String, String> headers, String body,
    {int attempts = 6}) async {
  for (var attempt = 1;; attempt++) {
    http.Response r;
    try {
      r = await c.post(url, headers: headers, body: body).timeout(const Duration(minutes: 5));
    } on SocketException catch (e) {
      throw AiError('Нет связи с AI (${url.host}): ${e.message}. Проверь интернет, VPN или AI_PROXY в .env');
    }
    // 429 — закончились бесплатные запросы в минуту, 503 — модель перегружена. Обе проходят сами.
    if (_overloaded(r.statusCode) && attempt < attempts) {
      await Future.delayed(Duration(seconds: 15 * attempt));
      continue;
    }
    return r;
  }
}

class GeminiProvider implements AiProvider {
  GeminiProvider(this.apiKey, String model, {String? proxy, this.fallbackModel = 'gemini-flash-lite-latest'})
      : _model = model,
        _http = _client(proxy);
  final String apiKey;
  final String fallbackModel;
  String _model;
  final http.Client _http;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  /// Google регулярно отключает старые модели — берём самую свежую доступную Flash.
  Future<String?> _latestFlash() async {
    final r = await _http.get(Uri.parse('$_base/models?pageSize=200'), headers: {'x-goog-api-key': apiKey});
    if (r.statusCode != 200) return null;
    final models = (jsonDecode(utf8.decode(r.bodyBytes))['models'] as List? ?? const [])
        .where((m) => ((m['supportedGenerationMethods'] as List?) ?? const []).contains('generateContent'))
        .map((m) => (m['name'] as String).replaceFirst('models/', ''))
        .where((n) => RegExp(r'^gemini-\d+(\.\d+)?-flash$').hasMatch(n))
        .toList();
    if (models.isEmpty) return null;
    double ver(String n) => double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(n)!.group(0)!) ?? 0;
    models.sort((a, b) => ver(b).compareTo(ver(a)));
    return models.first;
  }

  @override
  Future<Map<String, dynamic>> json(String prompt) async {
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.9},
    });
    final hasFallback = fallbackModel.isNotEmpty && fallbackModel != _model;
    for (var tries = 0;; tries++) {
      // Основную модель не мучаем долго: если перегружена, быстрее уйти на запасную.
      var r = await _call(_model, body, attempts: hasFallback ? 3 : 6);
      if (r.statusCode == 404 && tries == 0) {
        final next = await _latestFlash();
        if (next != null && next != _model) {
          stdout.writeln('Модель $_model недоступна, переключаюсь на $next');
          _model = next;
          continue;
        }
      }
      var used = _model;
      if (_overloaded(r.statusCode) && hasFallback) {
        stdout.writeln('Модель $_model перегружена (${r.statusCode}), пробую запасную $fallbackModel');
        r = await _call(fallbackModel, body);
        used = fallbackModel;
      }
      final raw = utf8.decode(r.bodyBytes);
      if (r.statusCode != 200) {
        stderr.writeln('Gemini ($used) ответил ${r.statusCode}: $raw');
        if (raw.contains('location is not supported')) {
          throw AiError('Gemini не работает из России. Включи VPN для всего трафика, укажи AI_PROXY в .env '
              'или переключись на другой AI (AI_PROVIDER=openai).');
        }
        if (r.statusCode == 429) {
          throw AiError('Закончились бесплатные запросы к Gemini. Нажми «Повторить» через несколько минут '
              '(если не поможет — завтра, дневной лимит обновляется раз в сутки).');
        }
        if (r.statusCode >= 500) {
          throw AiError('Gemini сейчас перегружен — так бывает у Google. Нажми «Повторить» через пару минут.');
        }
        if (r.statusCode == 400 || r.statusCode == 403) {
          throw AiError('Gemini отклонил запрос (${r.statusCode}). Проверь GEMINI_API_KEY в server/.env.');
        }
        throw AiError('Gemini ($used) ответил ошибкой ${r.statusCode}. Нажми «Повторить».');
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final parts = data['candidates']?[0]?['content']?['parts'] as List?;
      return _parseJson(parts?.map((x) => x['text'] ?? '').join() ?? '');
    }
  }

  Future<http.Response> _call(String model, String body, {int attempts = 6}) => _postWithRetry(
      _http,
      Uri.parse('$_base/models/$model:generateContent'),
      {'x-goog-api-key': apiKey, 'content-type': 'application/json'},
      body,
      attempts: attempts);
}

class OpenAiCompatProvider implements AiProvider {
  OpenAiCompatProvider(this.baseUrl, this.apiKey, this.model, {String? proxy}) : _http = _client(proxy);
  final String baseUrl;
  final String? apiKey;
  final String model;
  final http.Client _http;

  @override
  Future<Map<String, dynamic>> json(String prompt) async {
    final url = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final body = jsonEncode({
      'model': model,
      'temperature': 0.8,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': 'Отвечай только валидным JSON без пояснений.'},
        {'role': 'user', 'content': prompt},
      ],
    });
    final r = await _postWithRetry(_http, url, {
      'content-type': 'application/json',
      if (apiKey != null && apiKey!.isNotEmpty) 'authorization': 'Bearer $apiKey',
    }, body);
    final raw = utf8.decode(r.bodyBytes);
    if (r.statusCode != 200) throw Exception('AI ($model) ответил ${r.statusCode}: $raw');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final text = data['choices']?[0]?['message']?['content'] as String? ?? '';
    return _parseJson(text);
  }
}
