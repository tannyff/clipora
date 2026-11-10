import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ProcessFailure implements Exception {
  ProcessFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// timeout — после него процесс убиваем: зависший ffmpeg не должен вешать запрос навсегда.
Future<ProcessResult> run(String exe, List<String> args,
    {String? cwd, bool binaryOut = false, Duration? timeout}) async {
  // Без баннера в тексте ошибки видна сама причина, а не список опций сборки.
  // -nostdin: ffmpeg не ждёт команд с клавиатуры.
  final base = exe.split('/').last;
  if (base == 'ffmpeg') args = ['-hide_banner', '-nostdin', ...args];
  if (base == 'ffprobe') args = ['-hide_banner', ...args];
  final Process proc;
  try {
    proc = await Process.start(exe, args, workingDirectory: cwd);
  } on ProcessException {
    throw ProcessFailure('Не найдена программа «$exe». Установи её через Homebrew (см. README).');
  }
  proc.stdin.close().ignore();
  final out = BytesBuilder(copy: false), err = BytesBuilder(copy: false);
  final outDone = proc.stdout.forEach(out.add), errDone = proc.stderr.forEach(err.add);
  int code;
  if (timeout == null) {
    code = await proc.exitCode;
  } else {
    try {
      code = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      throw ProcessFailure('$base не ответил за ${timeout.inSeconds} с и был остановлен');
    }
  }
  await Future.wait([outDone, errDone]).timeout(const Duration(seconds: 5), onTimeout: () => []);
  final errText = utf8.decode(err.takeBytes(), allowMalformed: true);
  final outBytes = out.takeBytes();
  final r = ProcessResult(proc.pid, code, binaryOut ? outBytes : utf8.decode(outBytes, allowMalformed: true), errText);
  if (code != 0) {
    final tail = errText.length > 1500 ? errText.substring(errText.length - 1500) : errText;
    throw ProcessFailure('$exe завершился с ошибкой $code: $tail');
  }
  return r;
}

double d(Object? x) => x == null ? 0 : (x as num).toDouble();

/// jsonb из postgres приходит уже разобранным, но на всякий случай.
dynamic jv(Object? x) => x is String ? jsonDecode(x) : x;

double clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

double round2(double x) => (x * 100).roundToDouble() / 100;

String? _ffmpegProblem;
bool _ffmpegChecked = false;

/// null — всё в порядке, иначе понятный текст, что поставить.
Future<String?> ffmpegProblem(String ffmpeg) async {
  if (_ffmpegChecked) return _ffmpegProblem;
  try {
    final r = await Process.run(ffmpeg, ['-hide_banner', '-filters']);
    final hasAss = RegExp(r'^\s*\S+\s+ass\s', multiLine: true).hasMatch(r.stdout.toString());
    _ffmpegProblem = hasAss
        ? null
        : 'В установленном ffmpeg нет поддержки субтитров (libass). '
            'Выполни в Терминале: brew install ffmpeg-full — и перезапусти сервер.';
  } on ProcessException {
    _ffmpegProblem = 'Не найден ffmpeg. Выполни в Терминале: brew install ffmpeg-full';
  }
  _ffmpegChecked = true;
  return _ffmpegProblem;
}
