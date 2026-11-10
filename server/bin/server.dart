import 'dart:io';

import 'package:clipora_server/pipeline/ai_cache.dart';
import 'package:clipora_server/api.dart';
import 'package:clipora_server/config.dart';
import 'package:clipora_server/db.dart';
import 'package:clipora_server/fonts.dart';
import 'package:clipora_server/pipeline/ai.dart';
import 'package:clipora_server/util.dart';
import 'package:clipora_server/worker.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

Future<void> main(List<String> args) async {
  final c = Config.load();
  Directory(c.dataDir).createSync(recursive: true);

  Fonts.load(c.fontsDir);
  await openDb(c);
  await migrate();

  final apiOnly = args.contains('--api-only');
  final workerOnly = args.contains('--worker-only');

  if (!apiOnly) {
    final AiProvider ai = c.aiProvider == 'openai'
        ? OpenAiCompatProvider(c.openaiBaseUrl, c.openaiKey, c.openaiModel, proxy: c.aiProxy)
        : GeminiProvider(c.geminiKey, c.geminiModel, proxy: c.aiProxy, fallbackModel: c.geminiFallbackModel);
    await Worker(c, CachedAi(ai)).start();
    stdout.writeln('Обработчик видео запущен (${c.workers} шт.)');
    stdout.writeln('AI: ${c.aiProvider == 'openai' ? '${c.openaiModel} (${c.openaiBaseUrl})' : 'Gemini ${c.geminiModel}'}'
        '${c.aiProxy != null ? ' через прокси ${c.aiProxy}' : ''}');
  }
  if (workerOnly) return;

  // Сайт, собранный командой `flutter build web`, раздаётся с того же адреса, что и API.
  final webDir = p.absolute(c.get('WEB_DIR', '../app/build/web'));
  final hasWeb = File(p.join(webDir, 'index.html')).existsSync();
  var handler = Api(c).handler;
  if (hasWeb) {
    handler = Cascade()
        .add(handler)
        .add(const Pipeline().addMiddleware(_cacheStatic()).addHandler(createStaticHandler(webDir, defaultDocument: 'index.html')))
        .handler;
  }

  // 0.0.0.0 — чтобы можно было зайти с телефона в той же сети Wi-Fi.
  // Логируем только API, чтобы файлы сайта не засоряли окно.
  handler = const Pipeline().addMiddleware(_logApi()).addHandler(handler);
  final server = await io.serve(handler, InternetAddress.anyIPv4, c.port);
  server.autoCompress = true;

  stdout.writeln('');
  stdout.writeln('Clipora запущена');
  stdout.writeln('  на этом компьютере: http://localhost:${server.port}');
  for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in ni.addresses) {
      if (!a.isLoopback) stdout.writeln('  с телефона (тот же Wi-Fi): http://${a.address}:${server.port}');
    }
  }
  if (Fonts.count == 0) {
    stdout.writeln('ВНИМАНИЕ: нет шрифтов для заголовков. Выполни в папке server: bash scripts/get_fonts.sh');
    stdout.writeln('');
  }
  final ff = await ffmpegProblem(c.ffmpeg);
  if (ff != null) {
    stdout.writeln('ВНИМАНИЕ: ролики не соберутся. $ff');
    stdout.writeln('');
  }
  if (!hasWeb) {
    stdout.writeln('');
    stdout.writeln('Сайт ещё не собран. Выполни в папке app: flutter build web');
  }
  stdout.writeln('');
}

// Движок Flutter (canvaskit) и шрифты меняются только с новой версией Flutter — кешируем надолго.
// Остальное браузер перепроверяет при каждом открытии и получает 304, если файл не менялся.
Middleware _cacheStatic() => (inner) => (req) async {
      final res = await inner(req);
      if (res.statusCode != 200) return res;
      final path = req.url.path;
      final long = path.startsWith('canvaskit/') || path.endsWith('.otf') || path.endsWith('.ttf');
      return res.change(headers: {'cache-control': long ? 'public, max-age=2592000' : 'no-cache'});
    };

Middleware _logApi() => (inner) => (req) async {
      final res = await inner(req);
      final path = '/${req.url.path}';
      if (path.startsWith('/api/') && !path.startsWith('/api/projects/') || req.method != 'GET') {
        stdout.writeln('${DateTime.now().toIso8601String().substring(11, 19)}  ${req.method} ${res.statusCode} $path');
      }
      if (res.statusCode >= 500) stdout.writeln('  ошибка на $path');
      return res;
    };
