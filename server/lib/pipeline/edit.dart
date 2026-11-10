import 'dart:math';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../db.dart';
import '../util.dart';
import 'render.dart';
import 'transcribe.dart';

/// Кусок монтажа. src: 'source' — исходник с речью, 'media' — вставка из медиатеки.
/// s, e — секунды внутри файла; mute — выключить звук куска.
List<Map<String, dynamic>> clipsFromSegments(String sourceId, List segments) => [
      for (final (i, seg) in segments.indexed)
        {'id': 'ai$i', 'src': 'source', 'ref': sourceId, 's': d(seg['s']), 'e': d(seg['e']), 'mute': false}
    ];

/// Монтаж ролика: правки пользователя, а если их нет — план AI.
List<Map<String, dynamic>> clipsOf(Map v) {
  final edit = jv(v['edit']);
  if (edit is Map && edit['clips'] is List) {
    return [for (final c in edit['clips'] as List) (c as Map).cast<String, dynamic>()];
  }
  return clipsFromSegments(v['source_id'] as String, jv(v['segments']) as List);
}

/// Вставки поверх голоса: {id, ref (вставка из медиатеки), s, e (внутри файла), at (секунда ролика)}.
List<Map<String, dynamic>> overlaysOf(Map v) {
  final edit = jv(v['edit']);
  if (edit is Map && edit['overlays'] is List) {
    return [for (final o in edit['overlays'] as List) (o as Map).cast<String, dynamic>()];
  }
  return const [];
}

/// В монтаже есть кадры из другой съёмки — это и есть b-roll для анализатора.
bool hasBroll(Map v) => overlaysOf(v).isNotEmpty || clipsOf(v).any((c) => c['src'] == 'media');

Future<(List<Map<String, dynamic>>?, String?)> validateOverlays(List raw, String uid, double total) async {
  if (raw.length > 100) return (null, 'Слишком много вставок');
  final out = <Map<String, dynamic>>[];
  final durs = <String, double>{};
  for (final o in raw) {
    if (o is! Map) return (null, 'Неверный формат вставки');
    final ref = '${o['ref']}';
    if (!durs.containsKey(ref)) {
      final r = await q1("select duration from media where id = @id and user_id = @u and status = 'ready'",
          {'id': ref, 'u': uid});
      if (r == null) return (null, 'Вставка не найдена или ещё обрабатывается');
      durs[ref] = d(r['duration']);
    }
    final full = durs[ref]!;
    final s = (o['s'] as num? ?? 0).toDouble().clamp(0.0, full);
    var e = (o['e'] as num? ?? 0).toDouble().clamp(0.0, full);
    final at = (o['at'] as num? ?? 0).toDouble().clamp(0.0, total);
    // Вставка не может торчать за конец ролика.
    if (at + e - s > total) e = s + total - at;
    if (e - s < 0.2) continue;
    out.add({'id': '${o['id'] ?? out.length}', 'ref': ref, 's': round3(s), 'e': round3(e), 'at': round3(at)});
  }
  out.sort((a, b) => d(a['at']).compareTo(d(b['at'])));
  return (out, null);
}

Future<List<RenderOverlay>> resolveOverlays(List<Map<String, dynamic>> overlays) async {
  final out = <RenderOverlay>[];
  for (final o in overlays) {
    final row = await q1('select path from media where id = @id', {'id': o['ref']});
    if (row == null || row['path'] == null) throw Exception('Файл вставки не найден');
    out.add(RenderOverlay(path: row['path'] as String, s: d(o['s']), e: d(o['e']), at: d(o['at'])));
  }
  return out;
}

/// Куски основного исходника — для проверки оригинальности и предпросмотра оформления.
List<Map<String, double>> effectiveSegments(Map v) => [
      for (final c in clipsOf(v))
        if (c['src'] == 'source' && c['ref'] == v['source_id']) {'s': d(c['s']), 'e': d(c['e'])}
    ];

/// Проверяет присланный монтаж и приводит к чистому виду. Ошибка — понятный текст.
Future<(List<Map<String, dynamic>>?, String?)> validateClips(List raw, String uid) async {
  if (raw.isEmpty) return (null, 'В ролике должен быть хотя бы один кусок');
  if (raw.length > 300) return (null, 'Слишком много кусков');
  final srcIds = <String>{}, mediaIds = <String>{};
  for (final c in raw) {
    if (c is! Map) return (null, 'Неверный формат монтажа');
    (c['src'] == 'media' ? mediaIds : srcIds).add('${c['ref']}');
  }
  final durs = <String, double>{};
  for (final id in srcIds) {
    final r = await q1('select duration from sources where id = @id and user_id = @u', {'id': id, 'u': uid});
    if (r == null) return (null, 'Исходник не найден');
    durs['source:$id'] = d(r['duration']);
  }
  for (final id in mediaIds) {
    final r = await q1("select duration from media where id = @id and user_id = @u and status = 'ready'",
        {'id': id, 'u': uid});
    if (r == null) return (null, 'Вставка не найдена или ещё обрабатывается');
    durs['media:$id'] = d(r['duration']);
  }
  final out = <Map<String, dynamic>>[];
  var total = 0.0;
  for (final c in raw.cast<Map>()) {
    final src = c['src'] == 'media' ? 'media' : 'source';
    final ref = '${c['ref']}';
    final max = durs['$src:$ref']!;
    final s = (c['s'] as num? ?? 0).toDouble().clamp(0.0, max);
    final e = (c['e'] as num? ?? 0).toDouble().clamp(0.0, max);
    if (e - s < 0.2) return (null, 'Кусок короче 0,2 секунды — удали его или растяни');
    total += e - s;
    out.add({
      'id': '${c['id'] ?? out.length}',
      'src': src,
      'ref': ref,
      's': round3(s),
      'e': round3(e),
      'mute': c['mute'] == true,
    });
  }
  if (total > 180) return (null, 'Ролик длиннее 3 минут');
  return (out, null);
}

double round3(double x) => (x * 1000).roundToDouble() / 1000;

final _filler = RegExp(r'^(э+м*|м+|а-?а+|хм+|ммм+)$');

bool isFiller(String w) => _filler.hasMatch(w.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё-]'), ''));

/// Убирает паузы длиннее [gap] секунд и «эээ/ммм» внутри кусков речи: кусок делится на части по словам.
List<Map<String, dynamic>> tightenClips(List<Map<String, dynamic>> clips, Map<String, List> wordsBySource,
    {double gap = 0.4}) {
  final out = <Map<String, dynamic>>[];
  for (final c in clips) {
    final words = c['src'] == 'source' ? wordsBySource[c['ref']] : null;
    if (words == null) {
      out.add(c);
      continue;
    }
    final cs = d(c['s']), ce = d(c['e']);
    final inside = [
      for (final w in words)
        if (d(w['s']) >= cs - 0.01 && d(w['e']) <= ce + 0.05 && w['x'] != true) w
    ];
    if (inside.isEmpty) {
      out.add(c);
      continue;
    }
    final pieces = <List>[];
    for (final w in inside) {
      if (isFiller('${w['w']}')) continue;
      if (pieces.isEmpty || d(w['s']) - d(pieces.last.last['e']) > gap) {
        pieces.add([w]);
      } else {
        pieces.last.add(w);
      }
    }
    for (final (k, ws) in pieces.indexed) {
      final s = max(cs, d(ws.first['s']) - 0.06), e = min(ce, d(ws.last['e']) + 0.12);
      if (e - s < 0.25) continue;
      out.add({...c, 'id': '${c['id']}_$k', 's': round3(s), 'e': round3(e)});
    }
  }
  // Если от монтажа ничего не осталось, лучше оставить как было.
  return out.isEmpty ? clips : out;
}

/// Куски с путями к файлам и словами — всё, что нужно для сборки.
Future<List<RenderClip>> resolveClips(List<Map<String, dynamic>> clips) async {
  final cache = <String, Map<String, dynamic>?>{};
  final out = <RenderClip>[];
  for (final c in clips) {
    final key = '${c['src']}:${c['ref']}';
    final row = cache[key] ??= c['src'] == 'media'
        ? await q1('select path, has_audio from media where id = @id', {'id': c['ref']})
        : await q1('select coalesce(work_path, path) as path, transcript from sources where id = @id', {'id': c['ref']});
    if (row == null || row['path'] == null) throw Exception('Файл для куска монтажа не найден');
    final words = c['src'] == 'source' ? ((jv(row['transcript']) as Map?)?['words'] as List? ?? const []) : const [];
    out.add(RenderClip(
      path: row['path'] as String,
      s: d(c['s']),
      e: d(c['e']),
      audio: c['mute'] != true && (c['src'] == 'source' || row['has_audio'] == true),
      words: words,
    ));
  }
  return out;
}

Future<bool> hasAudio(Config c, String path) async {
  final r = await run(c.ffprobe,
      ['-v', 'error', '-select_streams', 'a', '-show_entries', 'stream=index', '-of', 'csv=p=0', path]);
  return r.stdout.toString().trim().isNotEmpty;
}

/// Лёгкая копия для монтажа в браузере: уже 9:16 с тем же кропом, что в ролике,
/// частые ключевые кадры — чтобы перемотка по кускам была быстрой.
Future<void> makeProxy(Config c, String input, String outPath, {String? thumbPath}) async {
  await run(c.ffmpeg, [
    '-y',
    if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
    '-i', input,
    '-vf', "crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)':x='(iw-ow)/2':y='(ih-oh)*0.4',scale=540:960,setsar=1,fps=30",
    // Битрейт ниже, чем у предпросмотра: копия грузится на телефон по Wi-Fi целиком.
    ...(await videoCodec(c, true)).map((x) => x == '2500k' ? '1200k' : (x == '26' ? '28' : x)),
    '-g', '15', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '96k', '-ac', '2', '-movflags', '+faststart',
    '$outPath.part.mp4',
  ]);
  File('$outPath.part.mp4').renameSync(outPath);
  if (thumbPath != null) {
    final dur = await probeDuration(c, outPath);
    await run(c.ffmpeg, [
      '-y', '-ss', (dur > 1 ? 0.5 : 0).toString(), '-i', outPath, '-frames:v', '1',
      '-vf', 'scale=270:-2', '-q:v', '5', thumbPath,
    ]);
  }
}

String proxyPathFor(String original) => p.join(p.dirname(original), 'proxy.mp4');

String workPathFor(String original) => p.join(p.dirname(original), 'work.mp4');

/// Рабочая копия нужна, если исходник не H.264, не вертикальный 9:16 или больше 1080×1920.
Future<bool> needsWorkCopy(Config c, String input) async {
  final r = await run(c.ffprobe, [
    '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=codec_name,width,height:stream_side_data=rotation',
    '-of', 'default=nw=1', input,
  ]);
  final out = r.stdout.toString();
  String? f(String k) => RegExp('^$k=(.+)\$', multiLine: true).firstMatch(out)?[1]?.trim();
  final w = int.tryParse(f('width') ?? '') ?? 0, h = int.tryParse(f('height') ?? '') ?? 0;
  final rot = (int.tryParse(f('rotation') ?? '') ?? 0).abs() % 180 == 90;
  final vw = rot ? h : w, vh = rot ? w : h;
  if (vw == 0 || vh == 0) return false;
  return f('codec_name') != 'h264' || vw * 16 != vh * 9 || vw > 1080;
}

Future<void> makeWorkCopy(Config c, String input, String outPath) async {
  await run(c.ffmpeg, [
    '-y',
    if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
    '-i', input,
    '-vf', "crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)':x='(iw-ow)/2':y='(ih-oh)*0.4',scale=1080:1920,setsar=1,fps=30",
    ...(await videoCodec(c, false)).map((x) => x == '9M' ? '14M' : (x == '21' ? '17' : x)),
    '-g', '30', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '192k', '-ac', '2', '-movflags', '+faststart',
    '$outPath.part.mp4',
  ], timeout: const Duration(hours: 1));
  File('$outPath.part.mp4').renameSync(outPath);
}
