import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../util.dart';

Future<double> probeDuration(Config c, String path) async {
  final r = await run(c.ffprobe,
      ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', path]);
  return double.tryParse(r.stdout.toString().trim()) ?? 0;
}

/// Возвращает {duration, words: [{w,s,e}], phrases: [{id,s,e,w0,w1,text}]}.
Future<Map<String, dynamic>> transcribe(Config c, String videoPath, String workDir) async {
  final wav = p.join(workDir, 'audio.wav');
  await run(c.ffmpeg,
      ['-y', '-i', videoPath, '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', wav]);
  final duration = await probeDuration(c, videoPath);

  final base = p.join(workDir, 'whisper');
  // -ml 1 + -sow дают отдельный сегмент на каждое слово с тайм-кодами.
  await run(c.whisperBin, [
    // Все ядра процессора: по умолчанию whisper берёт только 4 потока.
    '-m', c.whisperModel, '-f', wav, '-l', 'ru', '-t', '${min(8, Platform.numberOfProcessors)}',
    '-ml', '1', '-sow', '-oj', '-of', base, '-np',
  ]);

  final j = jsonDecode(await File('$base.json').readAsString()) as Map<String, dynamic>;
  final words = <Map<String, dynamic>>[];
  for (final seg in (j['transcription'] as List? ?? const [])) {
    final t = (seg['text'] as String? ?? '').trim();
    if (t.isEmpty || t.startsWith('[')) continue;
    final o = seg['offsets'] as Map;
    words.add({'w': t, 's': d(o['from']) / 1000, 'e': d(o['to']) / 1000});
  }
  File(wav).deleteSync();

  final phrases = buildPhrases(words);
  await addLoudness(c, videoPath, phrases, workDir);
  return {'duration': duration, 'words': words, 'phrases': phrases};
}

final _sentenceEnd = RegExp(r'[.!?…]$');

List<Map<String, dynamic>> buildPhrases(List<Map<String, dynamic>> words) {
  final out = <Map<String, dynamic>>[];
  var start = 0;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final isLast = i == words.length - 1;
    final gap = isLast ? 0.0 : d(words[i + 1]['s']) - d(w['e']);
    final tooLong = d(w['e']) - d(words[start]['s']) > 10;
    if (isLast || _sentenceEnd.hasMatch(w['w'] as String) || gap > 0.7 || tooLong) {
      final ws = words.sublist(start, i + 1);
      out.add({
        'id': out.length,
        's': ws.first['s'],
        'e': ws.last['e'],
        'w0': start,
        'w1': i,
        'text': ws.map((x) => x['w']).join(' '),
      });
      start = i + 1;
    }
  }
  return out;
}

/// Помечает фразы, сказанные заметно тише основной речи (бубнёж под нос, репетиция текста):
/// у каждой фразы появляются db и quiet.
Future<void> addLoudness(Config c, String videoPath, List phrases, String workDir) async {
  const rate = 8000;
  final raw = p.join(workDir, 'loud.raw');
  await run(c.ffmpeg, ['-y', '-i', videoPath, '-vn', '-ac', '1', '-ar', '$rate', '-f', 's16le', raw]);
  final bytes = File(raw).readAsBytesSync();
  File(raw).deleteSync();
  final pcm = Int16List.sublistView(bytes, 0, bytes.length - bytes.length % 2);

  final dbs = <double>[];
  for (final ph in phrases) {
    final i0 = (d(ph['s']) * rate).floor().clamp(0, pcm.length);
    final i1 = (d(ph['e']) * rate).ceil().clamp(i0, pcm.length);
    var sum = 0.0;
    for (var i = i0; i < i1; i++) {
      sum += pcm[i] * pcm[i];
    }
    final rms = i1 > i0 ? sqrt(sum / (i1 - i0)) : 0.0;
    final db = 20 * log(rms / 32768 + 1e-9) / ln10;
    ph['db'] = round2(db);
    dbs.add(db);
  }
  if (dbs.isEmpty) return;
  // Уровень «нормальной» речи — по громким фразам, чтобы тихих могло быть сколько угодно.
  final sorted = [...dbs]..sort();
  final normal = sorted[(sorted.length * 0.75).floor().clamp(0, sorted.length - 1)];
  for (final ph in phrases) {
    ph['quiet'] = d(ph['db']) < normal - 9;
  }
}
