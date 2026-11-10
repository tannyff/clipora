import 'dart:io';

import 'package:path/path.dart' as p;

class Config {
  Config._(this._v);
  final Map<String, String> _v;

  static Config load([String file = '.env']) {
    final v = <String, String>{};
    final f = File(file);
    if (f.existsSync()) {
      for (final raw in f.readAsLinesSync()) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final i = line.indexOf('=');
        if (i < 0) continue;
        var val = line.substring(i + 1).trim();
        if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
          val = val.substring(1, val.length - 1);
        }
        v[line.substring(0, i).trim()] = val;
      }
    }
    // Переменные окружения важнее файла — так удобнее в Docker.
    v.addAll(Platform.environment);
    return Config._(v);
  }

  String get(String k, [String? def]) {
    final x = _v[k];
    if (x != null && x.isNotEmpty) return x;
    if (def != null) return def;
    throw StateError('В .env не задан $k');
  }

  String? opt(String k) {
    final x = _v[k];
    return (x == null || x.isEmpty) ? null : x;
  }

  int get port => int.parse(get('PORT', '8080'));
  String get dbHost => get('DB_HOST', 'localhost');
  int get dbPort => int.parse(get('DB_PORT', '5432'));
  String get dbName => get('DB_NAME', 'clipora');
  String get dbUser => get('DB_USER', Platform.environment['USER'] ?? 'postgres');
  String? get dbPassword => opt('DB_PASSWORD');
  String get dataDir => p.absolute(get('DATA_DIR', 'data'));
  String get aiProvider => get('AI_PROVIDER', 'gemini');
  String? get aiProxy => opt('AI_PROXY');
  String get geminiKey => get('GEMINI_API_KEY');
  String get openaiBaseUrl => get('OPENAI_BASE_URL', 'http://localhost:11434/v1');
  String? get openaiKey => opt('OPENAI_API_KEY');
  String get openaiModel => get('OPENAI_MODEL', 'qwen3:8b');
  String get geminiModel => get('GEMINI_MODEL', 'gemini-flash-latest');
  String get geminiFallbackModel => get('GEMINI_FALLBACK_MODEL', 'gemini-flash-lite-latest');
  String get whisperBin => get('WHISPER_BIN', 'whisper-cli');
  String get whisperModel => get('WHISPER_MODEL');
  String get fontsDir => p.absolute(get('FONTS_DIR', 'fonts'));
  String get ffmpeg => _ff('FFMPEG', 'ffmpeg');
  String get ffprobe => _ff('FFPROBE', 'ffprobe');

  // Обычный ffmpeg из Homebrew собран без libass (нет субтитров), поэтому
  // если в .env просто «ffmpeg», берём ffmpeg-full, когда он установлен.
  String _ff(String key, String name) {
    final v = get(key, name);
    if (v != name) return v;
    for (final dir in const ['/opt/homebrew/opt/ffmpeg-full/bin', '/usr/local/opt/ffmpeg-full/bin']) {
      if (File('$dir/$name').existsSync()) return '$dir/$name';
    }
    return v;
  }
  String get fpcalc => get('FPCALC', 'fpcalc');
  int get workers => int.parse(get('WORKERS', '1'));
}
