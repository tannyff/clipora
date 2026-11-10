import 'dart:math';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'db.dart';
import 'jobs.dart';
import 'originality.dart';
import 'pipeline/ai.dart';
import 'pipeline/captions.dart';
import 'pipeline/edit.dart';
import 'pipeline/planner.dart';
import 'pipeline/render.dart';
import 'pipeline/subtitles.dart';
import 'pipeline/transcribe.dart';
import 'util.dart';

class Worker {
  Worker(this.c, this.ai);
  final Config c;
  final AiProvider ai;

  Future<void> start() async {
    await requeueStuckJobs();
    for (var i = 0; i < c.workers; i++) {
      _loop(i, light: false);
    }
    _loop(c.workers, light: true);
  }

  Future<void> _loop(int n, {required bool light}) async {
    while (true) {
      Map<String, dynamic>? job;
      try {
        job = await claimJob(light: light);
      } catch (e) {
        stderr.writeln('[worker $n] база недоступна: $e');
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }
      if (job == null) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      final id = job['id'] as int;
      final payload = (job['payload'] as Map).cast<String, dynamic>();
      stdout.writeln('[worker $n] ${job['kind']} ${payload.values.join(',')}');
      try {
        switch (job['kind']) {
          case 'transcribe':
            await _transcribe(payload['source_id'] as String);
          case 'plan':
            await _plan(payload['source_id'] as String);
          case 'plan_mix':
            await _planMix(payload['project_id'] as String);
          case 'render':
            await _render(payload['variant_id'] as String);
          case 'proxy':
            await _sourceProxy(payload['source_id'] as String);
          case 'media':
            await _media(payload['media_id'] as String);
          case 'split':
            await _split(payload['media_id'] as String);
        }
        await finishJob(id);
      } catch (e, st) {
        stderr.writeln('[worker $n] ошибка: $e\n$st');
        await failJob(id, '$e');
        final msg = e.toString();
        final short = msg.length > 600 ? msg.substring(0, 600) : msg;
        if (job['kind'] == 'proxy') {
          // Без лёгкой копии исходник всё равно годится для сборки, но монтажу нужно показать причину.
          await q('update sources set proxy_error = @e where id = @id', {'id': payload['source_id'], 'e': short});
          continue;
        }
        if (payload['media_id'] != null) {
          await q("update media set status = 'failed', error = @e where id = @id",
              {'id': payload['media_id'], 'e': short});
        }
        if (payload['source_id'] != null) {
          await q("update sources set status = 'failed', error = @e where id = @id",
              {'id': payload['source_id'], 'e': short});
        }
        if (payload['variant_id'] != null) {
          await q("update variants set status = 'failed', error = @e where id = @id",
              {'id': payload['variant_id'], 'e': short});
        }
      }
    }
  }

  Future<void> _transcribe(String sourceId) async {
    await q("update sources set status = 'transcribing', error = null where id = @id", {'id': sourceId});
    final s = (await q1('select path from sources where id = @id', {'id': sourceId}))!;
    final path = s['path'] as String;
    final t = await transcribe(c, path, p.dirname(path));
    if ((t['words'] as List).isEmpty) throw Exception('В видео не найдена речь');
    await q('''update sources set transcript = @t:jsonb, duration = @d:float8, status = 'planning'
               where id = @id''', {'id': sourceId, 't': t, 'd': t['duration']});
    await enqueue('plan', {'source_id': sourceId});
  }

  Future<void> _plan(String sourceId) async {
    await q("update sources set status = 'planning', error = null where id = @id", {'id': sourceId});
    final s = (await q1('select * from sources where id = @id', {'id': sourceId}))!;
    final t = jv(s['transcript']) as Map;
    final phrases = t['phrases'] as List;
    if (phrases.isNotEmpty && phrases.first['db'] == null) {
      // Исходник расшифрован до появления фильтра тихой речи — досчитываем.
      await addLoudness(c, s['path'] as String, phrases, p.dirname(s['path'] as String));
      await q('update sources set transcript = @t:jsonb where id = @id', {'id': sourceId, 't': t});
    }
    final uid = s['user_id'] as String;
    final used = await q('select hook_text from variants where user_id = @u', {'u': uid});
    final extras = await _extras(uid);
    final variants = await planVariants(ai, t['phrases'] as List, d(s['duration']),
        [for (final u in used) u['hook_text'] as String], extras.$1);
    if (variants.isEmpty) throw Exception('AI не смог подобрать варианты. Попробуй ещё раз.');
    for (final v in variants) {
      v['source_id'] = sourceId;
      v['clips'] = clipsFromSegments(sourceId, v['segments'] as List);
    }
    // Собранные ролики не трогаем, заменяем только несобранные предложения.
    await q("delete from variants where source_id = @id and status = 'proposed' and not mixed", {'id': sourceId});
    await _insertVariants(variants, s['project_id'] as String, uid, extras.$2, mixed: false);
    await q("update sources set status = 'ready' where id = @id", {'id': sourceId});
    // Два и больше готовых видео в проекте — AI собирает ещё и ролики из их кусков.
    final ready = await q1('''select count(*)::int as n from sources where project_id = @p and status = 'ready'
        and transcript is not null''', {'p': s['project_id']});
    final queued = await q1('''select 1 from jobs where kind = 'plan_mix' and status = 'queued'
        and payload->>'project_id' = @p''', {'p': s['project_id']});
    // Ждём, пока доделаются все видео проекта: одно смешивание на всех, а не после каждого.
    final busy = await q1('''select count(*)::int as n from sources where project_id = @p
        and status in ('uploaded', 'transcribing', 'planning')''', {'p': s['project_id']});
    if ((ready?['n'] as int? ?? 0) >= 2 && queued == null && (busy?['n'] as int? ?? 0) == 0) {
      await enqueue('plan_mix', {'project_id': s['project_id']});
    }
  }

  /// Примеры моих подписей для AI и медиатека вставок: id, метка, длительность.
  Future<(PlanExtras, Map<String, double>)> _extras(String uid) async {
    final caps = await q('select body, hashtags from captions where user_id = @u order by created_at desc limit 8', {'u': uid});
    final media = await q('''select id, file_name, tags, duration from media where user_id = @u and status = 'ready'
        order by created_at desc limit 40''', {'u': uid});
    final dur = {for (final m in media) m['id'] as String: d(m['duration'])};
    return (
      PlanExtras(
        captionExamples: [
          for (final c in caps) '${c['body']}\n${((jv(c['hashtags']) as List?) ?? const []).join(' ')}'.trim()
        ],
        library: [
          for (final m in media)
            {
              'id': m['id'] as String,
              'label': ((jv(m['tags']) as List?) ?? const []).isNotEmpty
                  ? (jv(m['tags']) as List).join(', ')
                  : (m['file_name'] as String).replaceAll(RegExp(r'\.[^.]+$'), ''),
            }
        ],
      ),
      dur
    );
  }

  /// Часть роликов получает мои подписи: самые подходящие по смыслу и ещё не использованные.
  Future<void> _assignCaptions(String uid, List<Map<String, dynamic>> vs) async {
    final caps = await q('select id, topic, body, hashtags, used from captions where user_id = @u', {'u': uid});
    for (final v in vs) {
      v['caption_src'] = caps.isEmpty ? null : 'ai';
    }
    if (caps.isEmpty) return;
    final share = ((await q1('select caption_share from users where id = @u', {'u': uid}))?['caption_share'] as int?) ?? 30;
    final n = (vs.length * share / 100).round();
    if (n <= 0) return;
    String textOf(Map v) => '${v['topic']} ${v['title']} ${v['hook_text']} ${v['caption']}';
    final order = [...vs]..sort((a, b) {
        double best(Map v) => caps.map((c) => captionScore(c, textOf(v))).reduce(max);
        return best(b).compareTo(best(a));
      });
    for (final v in order.take(n)) {
      final minUsed = caps.map((c) => c['used'] as int).reduce(min);
      final pool = caps.where((c) => c['used'] == minUsed).toList()
        ..sort((a, b) => captionScore(b, textOf(v)).compareTo(captionScore(a, textOf(v))));
      final c = pool.first;
      v['caption'] = c['body'];
      v['hashtags'] = [for (final h in (jv(c['hashtags']) as List?) ?? const []) '$h'];
      v['caption_src'] = 'mine';
      c['used'] = (c['used'] as int) + 1;
      await q('update captions set used = used + 1 where id = @id', {'id': c['id']});
    }
  }

  /// Вставки от AI → вставки поверх голоса в монтаже: не на хуке, не друг на друге, до 3 с.
  List<Map<String, dynamic>> _overlays(List broll, Map<String, double> mediaDur, double total) {
    final out = <Map<String, dynamic>>[];
    var free = 3.5;
    for (final b in [...broll]..sort((a, b) => d(a['at']).compareTo(d(b['at'])))) {
      final full = mediaDur[b['media']] ?? 0;
      final at = max(d(b['at']) + 0.2, free);
      final len = [full, max(1.2, d(b['len'])), 3.0, total - at - 0.3].reduce(min);
      if (len < 0.8) continue;
      out.add({'id': 'ai${out.length}', 'ref': b['media'], 's': 0.0, 'e': round3(len), 'at': round3(at)});
      free = at + len + 1.0;
    }
    return out;
  }

  Future<void> _insertVariants(List<Map<String, dynamic>> variants, String projectId, String uid,
      Map<String, double> mediaDur, {required bool mixed}) async {
    await _assignCaptions(uid, variants);
    final autoCut = ((await q1('select auto_cut from users where id = @u', {'u': uid}))?['auto_cut'] as bool?) ?? true;
    final words = <String, List>{};
    for (final v in variants) {
      if (autoCut) {
        for (final c in v['clips'] as List) {
          final ref = c['ref'] as String;
          if (words.containsKey(ref)) continue;
          final r = await q1('select transcript from sources where id = @id', {'id': ref});
          words[ref] = ((jv(r?['transcript']) as Map?)?['words'] as List?) ?? const [];
        }
        final before = d(v['duration']);
        final tight = tightenClips((v['clips'] as List).cast<Map<String, dynamic>>(), words);
        final after = tight.fold<double>(0, (a, c) => a + d(c['e']) - d(c['s']));
        if (after < before - 0.05 && after > 3) {
          v['clips'] = tight;
          v['duration'] = after;
          v['cut'] = true;
          // Вставки сдвигаются вместе с монтажом.
          for (final b in (v['broll'] as List? ?? const [])) {
            b['at'] = d(b['at']) * after / before;
          }
        }
      }
      final overlays = _overlays(v['broll'] as List? ?? const [], mediaDur, d(v['duration']));
      // Монтаж от AI помечен ai: true — карточка не показывает «Есть правки», пока я сама ничего не меняла.
      final edit = mixed || overlays.isNotEmpty || v['cut'] == true
          ? {'ai': true, 'clips': v['clips'], 'overlays': overlays}
          : null;
      await q('''insert into variants(project_id, source_id, user_id, topic, title, hook_text, hook_type,
                   caption, hashtags, segments, duration, design, edit, ai_edit, mixed, caption_src)
                 values(@pr, @src, @u, @topic, @title, @hook, @ht, @cap, @tags:jsonb, @segs:jsonb, @dur:float8,
                   @design:jsonb, @edit:jsonb, @edit2:jsonb, @mixed, @cs)''', {
        'pr': projectId,
        'src': v['source_id'],
        'u': uid,
        'topic': v['topic'],
        'title': v['title'],
        'hook': v['hook_text'],
        'ht': v['hook_type'],
        'cap': v['caption'],
        'tags': v['hashtags'],
        'segs': v['segments'],
        'dur': v['duration'],
        'design': v['design'],
        'edit': edit,
        'edit2': edit,
        'mixed': mixed,
        'cs': v['caption_src'],
      });
    }
  }

  Future<void> _planMix(String projectId) async {
    final rows = await q('''select id, user_id, duration, transcript from sources
        where project_id = @p and status = 'ready' and transcript is not null order by created_at''', {'p': projectId});
    if (rows.length < 2) return;
    final uid = rows.first['user_id'] as String;
    final used = await q('select hook_text from variants where user_id = @u', {'u': uid});
    final extras = await _extras(uid);
    final variants = await planMix(
        ai,
        [for (final r in rows) MixSource(r['id'] as String, (jv(r['transcript']) as Map)['phrases'] as List, d(r['duration']))],
        [for (final u in used) u['hook_text'] as String],
        extras.$1);
    if (variants.isEmpty) return;
    await q("delete from variants where project_id = @p and mixed and status = 'proposed'", {'p': projectId});
    await _insertVariants(variants, projectId, uid, extras.$2, mixed: true);
  }

  Future<void> _render(String variantId) async {
    await q("update variants set status = 'rendering', error = null where id = @id", {'id': variantId});
    final v = (await q1('''select v.*, s.path as source_path, s.transcript
                           from variants v join sources s on s.id = v.source_id
                           where v.id = @id''', {'id': variantId}))!;
    final outDir = p.join(c.dataDir, 'users', v['user_id'] as String, 'variants', variantId);
    final r = await renderClip(c,
        clips: await resolveClips(clipsOf(v)),
        overlays: await resolveOverlays(overlaysOf(v)),
        look: Look.from(jv(v['look']) as Map? ?? {'subs': v['style']}, variantId: variantId),
        design: designFor(jv(v['design']) as Map?, v['hook_text'] as String),
        outDir: outDir);
    final fp = await audioFingerprint(c, r['path'] as String);
    await q('''update variants set output_path = @p, text = @tx, audio_fp = @fp:jsonb,
               duration = @d:float8, rendered_at = now() where id = @id''',
        {'id': variantId, 'p': r['path'], 'tx': r['text'], 'fp': fp, 'd': r['duration']});
    final report = await checkOriginality(c, variantId);
    await q("update variants set status = 'ready', originality = @o:jsonb where id = @id",
        {'id': variantId, 'o': report});
  }

  Future<void> _sourceProxy(String sourceId) async {
    final s = await q1('select path, proxy_path from sources where id = @id', {'id': sourceId});
    if (s == null || s['path'] == null) return;
    final out = proxyPathFor(s['path'] as String);
    await q('update sources set proxy_error = null where id = @id', {'id': sourceId});
    if (!File(out).existsSync()) await makeProxy(c, s['path'] as String, out);
    await q('update sources set proxy_path = @p where id = @id', {'id': sourceId, 'p': out});
    // Рабочая копия 1080×1920: все ролики из этой съёмки собираются из неё, без повторного кропа и декодирования.
    final work = workPathFor(s['path'] as String);
    if (!File(work).existsSync() && await needsWorkCopy(c, s['path'] as String)) {
      await makeWorkCopy(c, s['path'] as String, work);
    }
    if (File(work).existsSync()) await q('update sources set work_path = @p where id = @id', {'id': sourceId, 'p': work});
  }

  Future<void> _media(String mediaId) async {
    await q("update media set status = 'processing', error = null where id = @id", {'id': mediaId});
    final m = (await q1('select path from media where id = @id', {'id': mediaId}))!;
    final path = m['path'] as String;
    final dur = await probeDuration(c, path);
    if (dur < 0.3) throw Exception('Не получилось прочитать видео');
    final audio = await hasAudio(c, path);
    final proxy = proxyPathFor(path);
    await makeProxy(c, path, proxy, thumbPath: p.join(p.dirname(path), 'thumb.jpg'));
    await q('''update media set status = 'ready', duration = @d:float8, has_audio = @a, proxy_path = @p
               where id = @id''', {'id': mediaId, 'd': dur, 'a': audio, 'p': proxy});
  }

  /// Длинное видео с кадрами-вставками режется на куски по сменам плана (и не длиннее 4 секунд).
  /// Каждый кусок становится отдельной вставкой, сам длинный файл удаляется.
  Future<void> _split(String mediaId) async {
    await q("update media set status = 'processing', error = null where id = @id", {'id': mediaId});
    final m = (await q1('select user_id, file_name, path from media where id = @id', {'id': mediaId}))!;
    final path = m['path'] as String;
    final dur = await probeDuration(c, path);
    if (dur < 0.3) throw Exception('Не получилось прочитать видео');
    final audio = await hasAudio(c, path);

    // Поиск смен плана на уменьшенной картинке — так быстро даже для 4K.
    final r = await run(c.ffmpeg, [
      if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
      '-i', path, '-an', '-vf', "scale=320:-2,select='gt(scene,0.32)',showinfo", '-f', 'null', '-',
    ]);
    final cuts = [
      for (final mt in RegExp(r'pts_time:([\d.]+)').allMatches(r.stderr.toString())) double.parse(mt[1]!)
    ];
    final points = <double>[0, ...cuts.where((t) => t > 0.8 && t < dur - 0.8), dur];
    final pieces = <(double, double)>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      if (b - a < 1.0) {
        // Слишком короткий план приклеиваем к предыдущему куску.
        if (pieces.isNotEmpty) pieces[pieces.length - 1] = (pieces.last.$1, b);
        continue;
      }
      final n = ((b - a) / 4).ceil();
      for (var k = 0; k < n; k++) {
        pieces.add((a + (b - a) * k / n, a + (b - a) * (k + 1) / n));
      }
    }
    if (pieces.isEmpty) pieces.add((0, dur));

    final base = (m['file_name'] as String).replaceAll(RegExp(r'\.[^.]+$'), '');
    final root = p.dirname(p.dirname(path));
    for (final (i, piece) in pieces.take(60).indexed) {
      final row = (await q1('insert into media(user_id, file_name, status) values(@u, @f, \'processing\') returning id',
          {'u': m['user_id'], 'f': '$base · ${i + 1}'}))!;
      final id = row['id'] as String;
      final dir = Directory(p.join(root, id))..createSync(recursive: true);
      final out = p.join(dir.path, 'original.mp4');
      await run(c.ffmpeg, [
        '-y',
        if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
        '-ss', piece.$1.toStringAsFixed(3), '-t', (piece.$2 - piece.$1).toStringAsFixed(3), '-i', path,
        '-vf', "crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)':x='(iw-ow)/2':y='(ih-oh)*0.4',scale=1080:1920,setsar=1,fps=30",
        ...await videoCodec(c, false),
        '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k', '-ac', '2', '-movflags', '+faststart', out,
      ]);
      final proxy = proxyPathFor(out);
      await makeProxy(c, out, proxy, thumbPath: p.join(dir.path, 'thumb.jpg'));
      await q('''update media set path = @path, proxy_path = @p, duration = @d:float8, has_audio = @a, status = 'ready'
                 where id = @id''',
          {'id': id, 'path': out, 'p': proxy, 'd': piece.$2 - piece.$1, 'a': audio});
    }
    final dir = Directory(p.dirname(path));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await q('delete from media where id = @id', {'id': mediaId});
  }
}
