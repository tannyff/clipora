import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../fonts.dart';
import '../util.dart';
import 'subtitles.dart';

String _f(double x) => x.toStringAsFixed(3);

/// Переводит слова исходника в шкалу времени ролика.
List<Map<String, dynamic>> timelineWords(List segments, List words) {
  final out = <Map<String, dynamic>>[];
  var offset = 0.0;
  for (final seg in segments) {
    final s = d(seg['s']), e = d(seg['e']);
    for (final w in words) {
      final ws = d(w['s']), we = d(w['e']);
      if (ws >= s - 0.01 && we <= e + 0.05) {
        out.add({'w': w['w'], 's': offset + ws - s, 'e': offset + (we < e ? we : e) - s, if (w['x'] == true) 'x': true});
      }
    }
    offset += e - s;
  }
  return out;
}

/// Кусок для сборки: файл, отрезок в нём, есть ли звук, слова речи (в шкале файла).
class RenderClip {
  RenderClip({required this.path, required this.s, required this.e, this.audio = true, this.words = const []});
  final String path;
  final double s, e;
  final bool audio;
  final List words;
}

/// Вставка поверх голоса: картинка на [at, at + (e - s)] ролика, звук основной дорожки не трогаем.
class RenderOverlay {
  RenderOverlay({required this.path, required this.s, required this.e, required this.at});
  final String path;
  final double s, e, at;
}

List<RenderClip> clipsFromSource(String path, List segments, List words) =>
    [for (final seg in segments) RenderClip(path: path, s: d(seg['s']), e: d(seg['e']), words: words)];

List<Map<String, dynamic>> timelineWordsOf(List<RenderClip> clips) {
  final out = <Map<String, dynamic>>[];
  var offset = 0.0;
  for (final c in clips) {
    for (final w in c.words) {
      final ws = d(w['s']), we = d(w['e']);
      if (ws >= c.s - 0.01 && we <= c.e + 0.05) {
        out.add({'w': w['w'], 's': offset + ws - c.s, 'e': offset + (we < c.e ? we : c.e) - c.s, if (w['x'] == true) 'x': true});
      }
    }
    offset += c.e - c.s;
  }
  return out;
}

/// Каждый кусок подаётся отдельным входом с -ss, поэтому фильтру уже не нужен trim.
/// Звук и частоту кадров приводим к одному виду: вставки с телефона бывают 60 к/с, моно или вовсе без звука.
String buildFilter(List<RenderClip> clips, Look look,
    {int width = 1080, int height = 1920, List<RenderOverlay> overlays = const []}) {
  final n = clips.length;
  final fc = StringBuffer();
  for (var i = 0; i < n; i++) {
    // Наезд на каждой второй склейке: говорящая голова не стоит на месте.
    // Кроп чуть выше центра, чтобы при наезде не резало макушку.
    final z = look.zoom && n > 1 && i.isOdd ? 1.12 : 1.0;
    fc.write("[$i:v]setpts=PTS-STARTPTS,crop=w='min(iw,ih*9/16)/$z':h='min(ih,iw*16/9)/$z'"
        ":x='(iw-ow)/2':y='(ih-oh)*0.4',scale=$width:$height,setsar=1,fps=30[v$i];");
    if (clips[i].audio) {
      fc.write('[$i:a]asetpts=PTS-STARTPTS,aresample=48000,aformat=sample_rates=48000:channel_layouts=stereo[a$i];');
    } else {
      fc.write('anullsrc=r=48000:cl=stereo,atrim=0:${_f(clips[i].e - clips[i].s)},asetpts=PTS-STARTPTS[a$i];');
    }
  }
  for (var i = 0; i < n; i++) {
    fc.write('[v$i][a$i]');
  }
  if (look.audioFix) {
    // Громкость как у рилсов (−14 LUFS) и мягкое шумоподавление, без «подводного» звука.
    fc.write('concat=n=$n:v=1:a=1[cv][ca];[ca]afftdn=nr=10:nf=-40,loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000,aformat=sample_rates=48000:channel_layouts=stereo[outa];');
  } else {
    fc.write('concat=n=$n:v=1:a=1[cv][outa];');
  }
  var cur = 'cv';
  for (var k = 0; k < overlays.length; k++) {
    final o = overlays[k];
    final end = o.at + o.e - o.s;
    fc.write("[${n + k}:v]setpts=PTS-STARTPTS+${_f(o.at)}/TB,crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)'"
        ":x='(iw-ow)/2':y='(ih-oh)*0.4',scale=$width:$height,setsar=1,fps=30[ov$k];"
        "[$cur][ov$k]overlay=eof_action=pass:enable='between(t,${_f(o.at)},${_f(end)})'[c$k];");
    cur = 'c$k';
  }
  fc.write('[$cur]');
  if (look.grade) {
    // Лёгкая тёплая обработка: чуть контраста и насыщенности, тёплые света.
    fc.write('eq=contrast=1.05:saturation=1.1,colorbalance=rs=0.03:bs=-0.03:rm=0.02:bm=-0.03:rh=0.02:bh=-0.02,');
  }
  final fonts = Fonts.dir == null ? '' : ":fontsdir='${Fonts.dir!.replaceAll("'", '')}'";
  fc.write('ass=filename=subs.ass$fonts[outv]');
  return fc.toString();
}

/// Входы ffmpeg: читаем из файлов только нужные куски, а не всё видео целиком.
List<String> segmentInputs(List<RenderClip> clips, [List<RenderOverlay> overlays = const []]) => [
      for (final c in [...clips.map((c) => (c.path, c.s, c.e)), ...overlays.map((o) => (o.path, o.s, o.e))]) ...[
        // Аппаратное декодирование на Mac: видео с iPhone (HEVC, 4K) иначе декодируется очень долго.
        if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
        '-ss', _f(c.$2), '-t', _f(c.$3 - c.$2), '-i', c.$1,
      ],
    ];

Future<Map<String, dynamic>> renderClip(
  Config c, {
  required List<RenderClip> clips,
  List<RenderOverlay> overlays = const [],
  required Look look,
  required Map<String, dynamic> design,
  required String outDir,
  bool preview = false,
}) async {
  final problem = await ffmpegProblem(c.ffmpeg);
  if (problem != null) throw ProcessFailure(problem);

  Directory(outDir).createSync(recursive: true);
  final tw = timelineWordsOf(clips);
  final total = clips.fold<double>(0, (a, x) => a + x.e - x.s);
  File(p.join(outDir, 'subs.ass')).writeAsStringSync(buildAss(tw, look, design, total));

  // Предпросмотр — в половинном размере и быстрее: важно только, как выглядят субтитры.
  await run(
    c.ffmpeg,
    [
      '-y', ...segmentInputs(clips, overlays),
      '-filter_complex',
      preview
          ? buildFilter(clips, look, width: 540, height: 960, overlays: overlays)
          : buildFilter(clips, look, overlays: overlays),
      '-map', '[outv]', '-map', '[outa]',
      ...await videoCodec(c, preview),
      '-pix_fmt', 'yuv420p', '-r', '30',
      '-c:a', 'aac', '-b:a', preview ? '96k' : '160k', '-movflags', '+faststart',
      'out.mp4',
    ],
    cwd: outDir, // путь к subs.ass в фильтре — относительный, без экранирования
  );

  if (!preview) {
    // Превью для карточки ролика.
    final at = total > 2 ? 1.0 : total / 2;
    await run(c.ffmpeg,
        ['-y', '-ss', at.toStringAsFixed(2), '-i', 'out.mp4', '-frames:v', '1', '-vf', 'scale=540:-2', '-q:v', '4', 'thumb.jpg'],
        cwd: outDir);
  }

  return {
    'path': p.join(outDir, 'out.mp4'),
    'duration': total,
    'text': tw.map((w) => w['w']).join(' '),
  };
}

/// Один кадр с оформлением — для мгновенного предпросмотра. Базовый кадр из исходника кешируется.
Future<String> renderStill(
  Config c, {
  required String sourcePath,
  required List segments,
  required List words,
  required Look look,
  required Map<String, dynamic> design,
  required String outDir,
  required String baseFrame,
  double at = 1.4,
  int width = 540,
}) async {
  final problem = await ffmpegProblem(c.ffmpeg);
  if (problem != null) throw ProcessFailure(problem);
  Directory(outDir).createSync(recursive: true);
  final first = segments.first;
  final t = at < d(first['e']) - d(first['s']) ? at : (d(first['e']) - d(first['s'])) / 2;
  if (!File(baseFrame).existsSync()) {
    await run(c.ffmpeg, [
      '-y', '-ss', _f(d(first['s']) + t), '-i', sourcePath, '-frames:v', '1',
      '-vf', "crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)':x='(iw-ow)/2':y='(ih-oh)*0.4',scale=540:960,setsar=1",
      baseFrame,
    ], timeout: const Duration(seconds: 120));
  }
  final tw = timelineWords(segments, words);
  final total = segments.fold<double>(0, (a, s) => a + d(s['e']) - d(s['s']));
  File(p.join(outDir, 'subs.ass')).writeAsStringSync(buildAss(tw, look, design, total));
  final fonts = Fonts.dir == null ? '' : ":fontsdir='${Fonts.dir!.replaceAll("'", '')}'";
  final grade = look.grade
      ? 'eq=contrast=1.05:saturation=1.1,colorbalance=rs=0.03:bs=-0.03:rm=0.02:bm=-0.03:rh=0.02:bh=-0.02,'
      : '';
  // Кадр сдвигаем во времени, чтобы субтитры показали момент, когда заголовок уже полностью появился.
  await run(c.ffmpeg, [
    '-y', '-i', baseFrame,
    // libass сам масштабирует разметку 1080×1920 под размер кадра — маленький кадр рисуется в разы быстрее.
    '-vf', 'scale=$width:${width * 16 ~/ 9},setpts=PTS+${t.toStringAsFixed(2)}/TB,${grade}ass=filename=subs.ass$fonts',
    '-frames:v', '1', '-q:v', '3', 'still.jpg',
  ], cwd: outDir, timeout: const Duration(seconds: 60));
  return p.join(outDir, 'still.jpg');
}

/// Кадр для окна оформления двумя слоями: всё, кроме заголовка (rest.jpg), и сам заголовок на прозрачном фоне
/// (title.png). Приложение двигает, масштабирует и крутит заголовок само, без нового запроса на сервер.
/// libass не пишет прозрачность, поэтому рисуем заголовок на чёрном и на белом и вычисляем её по разнице.
Future<Map<String, Map<String, double>>> renderLayers(
  Config c, {
  required List segments,
  required List words,
  required Look look,
  required Map<String, dynamic> design,
  required String outDir,
  required String baseFrame,
  double at = 1.4,
  int width = 540,
}) async {
  final problem = await ffmpegProblem(c.ffmpeg);
  if (problem != null) throw ProcessFailure(problem);
  Directory(outDir).createSync(recursive: true);
  final first = segments.first;
  final t = at < d(first['e']) - d(first['s']) ? at : (d(first['e']) - d(first['s'])) / 2;
  final tw = timelineWords(segments, words);
  final total = segments.fold<double>(0, (a, s) => a + d(s['e']) - d(s['s']));
  final box = <String, Map<String, double>>{};
  File(p.join(outDir, 'rest.ass')).writeAsStringSync(buildAss(tw, look, design, total, part: 'rest', box: box));
  // Каждая часть заголовка — свой прозрачный слой, чтобы двигать и увеличивать их по отдельности.
  final roles = [for (final r in box.keys) if (layerKey.hasMatch(r)) r];
  for (final r in roles) {
    File(p.join(outDir, '$r.ass')).writeAsStringSync(buildAss(tw, look, design, total, part: r));
  }
  final fonts = Fonts.dir == null ? '' : ":fontsdir='${Fonts.dir!.replaceAll("'", '')}'";
  final h = width * 16 ~/ 9;
  final ts = 'setpts=PTS+${t.toStringAsFixed(2)}/TB';
  final grade = look.grade
      ? 'eq=contrast=1.05:saturation=1.1,colorbalance=rs=0.03:bs=-0.03:rm=0.02:bm=-0.03:rh=0.02:bh=-0.02,'
      : '';
  // Каждый слой кешируется по своему содержимому: поменяла цвет главного слова — перерисуется только оно.
  final cacheDir = Directory(p.join(p.dirname(outDir), '_layers'))..createSync(recursive: true);
  String cached(String name, String ext) {
    final ass = File(p.join(outDir, '$name.ass')).readAsStringSync();
    final key = sha1.convert(utf8.encode('$ass|$width|$t|$grade|$baseFrame|${name == 'rest'}')).toString().substring(0, 16);
    return p.join(cacheDir.path, '$key.$ext');
  }

  final restCache = cached('rest', 'jpg');
  final restMissing = !File(restCache).existsSync();
  final missing = [for (final r in roles) if (!File(cached(r, 'png')).existsSync()) r];
  final n = missing.length;
  if (restMissing || n > 0) {
    final fc = StringBuffer();
    final outs = <String>[];
    if (restMissing) {
      fc.write('[0:v]scale=$width:$h,$ts,${grade}ass=filename=rest.ass$fonts[r];');
      outs.addAll(['-map', '[r]', '-frames:v', '1', '-q:v', '3', 'rest.jpg']);
    }
    if (n > 0) {
      String sp(String inp, String pre) =>
          n == 1 ? '[$inp]null[${pre}0];' : '[$inp]split=$n${[for (var i = 0; i < n; i++) '[$pre$i]'].join()};';
      fc
        ..write(sp('1:v', 'k'))
        ..write(sp('2:v', 'w'));
      for (var i = 0; i < n; i++) {
        final a = 'format=rgb24,$ts,ass=filename=${missing[i]}.ass$fonts';
        fc.write('[k$i]$a,split[b${i}a][b${i}b];[w$i]$a[w${i}x];'
            "[w${i}x][b${i}a]blend=all_expr='255-(A-B)',format=gray[a$i];"
            '[b${i}b][a$i]alphamerge,unpremultiply=inplace=1[o$i];');
        outs.addAll(['-map', '[o$i]', '-frames:v', '1', '${missing[i]}.png']);
      }
    }
    var graph = fc.toString();
    graph = graph.substring(0, graph.length - 1);
    await run(c.ffmpeg, [
      '-y', '-i', baseFrame,
      '-f', 'lavfi', '-i', 'color=c=black:s=${width}x$h:r=25:d=0.04',
      '-f', 'lavfi', '-i', 'color=c=white:s=${width}x$h:r=25:d=0.04',
      '-filter_complex', graph,
      ...outs,
    ], cwd: outDir, timeout: const Duration(seconds: 60));
    if (restMissing) File(p.join(outDir, 'rest.jpg')).copySync(restCache);
    for (final r in missing) {
      File(p.join(outDir, '$r.png')).copySync(cached(r, 'png'));
    }
  }
  if (!restMissing) File(restCache).copySync(p.join(outDir, 'rest.jpg'));
  for (final r in roles) {
    if (!missing.contains(r)) File(cached(r, 'png')).copySync(p.join(outDir, '$r.png'));
  }
  return box;
}

/// Плитка для сетки предпросмотра: своё оформление и куда положить картинку.
class StillTile {
  StillTile(this.look, this.outPath);
  final Look look;
  final String outPath;
}

/// Все плитки сетки одним запуском ffmpeg: кадр читается и масштабируется один раз,
/// а не 30 отдельных процессов. Плитка — только верхний квадрат, там заголовок.
Future<void> renderStillBatch(
  Config c, {
  required List segments,
  required List words,
  required Map<String, dynamic> design,
  required String baseFrame,
  required List<StillTile> tiles,
  required String workDir,
  required bool grade,
  double at = 1.4,
  int width = 360,
}) async {
  if (tiles.isEmpty) return;
  final problem = await ffmpegProblem(c.ffmpeg);
  if (problem != null) throw ProcessFailure(problem);
  Directory(workDir).createSync(recursive: true);
  final first = segments.first;
  final t = at < d(first['e']) - d(first['s']) ? at : (d(first['e']) - d(first['s'])) / 2;
  final tw = timelineWords(segments, words);
  final total = segments.fold<double>(0, (a, s) => a + d(s['e']) - d(s['s']));
  final fonts = Fonts.dir == null ? '' : ":fontsdir='${Fonts.dir!.replaceAll("'", '')}'";
  final n = tiles.length;
  final fc = StringBuffer('[0:v]scale=$width:${width * 16 ~/ 9},setpts=PTS+${t.toStringAsFixed(2)}/TB,');
  if (grade) fc.write('eq=contrast=1.05:saturation=1.1,colorbalance=rs=0.03:bs=-0.03:rm=0.02:bm=-0.03:rh=0.02:bh=-0.02,');
  fc.write(n == 1 ? 'null[i0];' : 'split=$n${[for (var i = 0; i < n; i++) '[i$i]'].join()};');
  final outs = <String>[];
  for (var i = 0; i < n; i++) {
    File(p.join(workDir, 's$i.ass')).writeAsStringSync(buildAss(tw, tiles[i].look, design, total));
    Directory(p.dirname(tiles[i].outPath)).createSync(recursive: true);
    fc.write('[i$i]ass=filename=s$i.ass$fonts,crop=$width:$width:0:0[o$i]${i < n - 1 ? ';' : ''}');
    outs.addAll(['-map', '[o$i]', '-frames:v', '1', '-q:v', '4', tiles[i].outPath]);
  }
  try {
    await run(c.ffmpeg, ['-y', '-i', baseFrame, '-filter_complex', fc.toString(), ...outs],
        cwd: workDir, timeout: const Duration(seconds: 90));
  } finally {
    try {
      Directory(workDir).deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Первые [maxSec] секунд будущего ролика — для предпросмотра субтитров.
List<Map<String, dynamic>> firstSeconds(List segments, double maxSec) {
  final out = <Map<String, dynamic>>[];
  var acc = 0.0;
  for (final seg in segments) {
    if (acc >= maxSec) break;
    final s = d(seg['s']), e = d(seg['e']);
    final take = (e - s) < (maxSec - acc) ? (e - s) : (maxSec - acc);
    out.add({'s': s, 'e': s + take});
    acc += take;
  }
  return out;
}

bool? _hasVt;

/// На Mac кодируем видеочипом (в разы быстрее), иначе — libx264.
Future<List<String>> videoCodec(Config c, bool preview) async {
  _hasVt ??= Platform.isMacOS &&
      (await Process.run(c.ffmpeg, ['-hide_banner', '-encoders'])).stdout.toString().contains('h264_videotoolbox');
  if (_hasVt!) {
    return ['-c:v', 'h264_videotoolbox', '-b:v', preview ? '2500k' : '9M', '-profile:v', 'high'];
  }
  return ['-c:v', 'libx264', '-preset', preview ? 'ultrafast' : 'veryfast', '-crf', preview ? '26' : '21'];
}
