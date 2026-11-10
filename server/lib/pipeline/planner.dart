import 'dart:math';

import '../util.dart';
import 'ai.dart';

/// Дополнения к заданию AI: подписи автора как образец стиля и медиатека вставок.
class PlanExtras {
  const PlanExtras({this.captionExamples = const [], this.library = const []});
  final List<String> captionExamples;

  /// Вставки медиатеки: {id, label}. В задании они идут как M1, M2…
  final List<Map<String, String>> library;
}

String _prompt(String phraseBlock, List<String> usedHooks, PlanExtras x, {bool mix = false}) {
  final b = StringBuffer('''
Ты — продюсер коротких вертикальных видео (Reels) для русскоязычной аудитории.
Ниже расшифровка видео автора («говорящая голова»), разбитая на фразы с номерами и тайм-кодами.

Задача: найди в нём 1–5 самостоятельных тем и для каждой темы предложи 3–5 по-настоящему РАЗНЫХ коротких роликов, собранных из этих фраз.

Правила:
- Ролик собирается только из фраз этого видео. В phrase_ids перечисли номера фраз в том порядке, в котором они пойдут в ролике.
- Смело меняй порядок: начинай с самой сильной фразы, выкидывай воду, повторы и оговорки.
- Варианты одной темы должны отличаться: разный хук (первая фраза и текст на экране), разная длина (7–15 с, 20–35 с, 40–60 с), разный набор фраз.
- Автор мог репетировать: если одна и та же мысль сказана несколько раз подряд, бери только один дубль — самый полный и чистый, обычно последний. Оговорки, «так, ещё раз», «блин», недоговорённые фразы не бери.
- Мысль не должна обрываться, ролик должен быть понятен без остального видео.
- hook_text — текст на экране в первые секунды, до 7 слов, цепляющий, но честный, без обмана зрителя.
- hook_type — одно из: вопрос, провокация, цифра, ошибка, обещание, история.
- Хук на экране оформляется как в модных рилсах: маленькая строка + 1–2 слова КРУПНО + рукописный акцент. Разбей hook_text на части, чтобы вместе они читались как hook_text:
  hook_lead — короткая вводная строка, 0–3 слова (чаще пусто);
  hook_main — 1–2 самых цепляющих слова, лучше одно короткое (до 10 букв), его покажем огромным на всю ширину;
  hook_accent — ОБЯЗАТЕЛЬНО 1–4 слова прописью: эмоция, уточнение или продолжение мысли.
  Пример: hook_lead «почему твой», hook_main «КОНТЕНТ», hook_accent «никто не смотрит».
- emphasis — 1–3 ключевых слова из фраз этого ролика, которые вспыхнут крупно в момент произнесения: [{"word": "слово ровно как в расшифровке", "accent": "0–3 слова прописью"}]. Бери сильные слова (главная мысль, цифра, неожиданное), не служебные.
- cta_main — 1–3 слова финальной надписи (например «больше пользы»), cta_accent — 1–2 слова прописью (например «в блоге»).
- caption — описание к рилсу, 1–3 предложения с призывом к действию.
- hashtags — 3–6 хэштегов на русском, с символом #.

Ответ строго в JSON:
{"topics":[{"title":"...","variants":[{"title":"...","hook_text":"...","hook_type":"...","hook_lead":"...","hook_main":"...","hook_accent":"...","emphasis":[{"word":"...","accent":"..."}],"cta_main":"...","cta_accent":"...","phrase_ids":${mix ? '["A3","B1","A7"]' : '[3,4,7]'},"caption":"...","hashtags":["#..."],"broll":[{"phrase_id":${mix ? '"A3"' : '3'},"media":"M1"}]}]}]}
''');
  if (mix) {
    b.writeln('''
Это фразы из НЕСКОЛЬКИХ видео одного автора. Номер фразы — буква видео и число, например "B4".
Собирай ролики из фраз РАЗНЫХ видео, если вместе они раскрывают одну мысль: хук из одного видео, пример из другого, вывод из третьего.
Каждый ролик должен содержать фразы хотя бы из двух видео. Мысль не должна прыгать — склейка должна читаться как один рассказ.''');
  }
  if (x.library.isNotEmpty) {
    b.writeln('\nМедиатека вставок автора (кадры без речи, ставятся поверх голоса):');
    for (final (i, m) in x.library.indexed) {
      b.writeln('[M${i + 1}] ${m['label']}');
    }
    b.writeln('broll — 0–3 вставки на ролик: phrase_id — фраза ролика, во время которой показать вставку, media — номер '
        'вставки. Ставь только там, где кадр по смыслу подходит фразе, не на хук. Нет подходящих — пустой список.');
  } else {
    b.writeln('\nbroll всегда пустой список.');
  }
  if (x.captionExamples.isNotEmpty) {
    b.writeln('\nПодписи, которые автор пишет сам. caption и hashtags пиши в ТОЧНО таком же стиле: длина, тон, '
        'обращение, эмодзи, призыв к действию, вид хэштегов. Не копируй их, пиши новые про этот ролик:');
    for (final c in x.captionExamples.take(8)) {
      b.writeln('<<<\n$c\n>>>');
    }
  }
  if (usedHooks.isNotEmpty) {
    b.writeln('\nЭти хуки уже использованы, не повторяй их и не перефразируй близко:');
    for (final h in usedHooks.take(60)) {
      b.writeln('- $h');
    }
  }
  b.writeln('\nФразы:');
  b.write(phraseBlock);
  return b.toString();
}

// Тихие фразы (бубнёж под нос) AI вообще не показываем.
String _phraseLines(List phrases, [String prefix = '']) {
  final b = StringBuffer();
  for (final ph in phrases.where((x) => x['quiet'] != true)) {
    b.writeln('[$prefix${ph['id']}] ${d(ph['s']).toStringAsFixed(1)}–${d(ph['e']).toStringAsFixed(1)} с: ${ph['text']}');
  }
  return b.toString();
}

Map<String, dynamic> _common(String topic, Map v) => {
      'topic': topic,
      'title': (v['title'] ?? '').toString(),
      'hook_text': (v['hook_text'] ?? '').toString(),
      'hook_type': (v['hook_type'] ?? '').toString(),
      'caption': (v['caption'] ?? '').toString(),
      'hashtags': [for (final h in (v['hashtags'] as List? ?? const [])) h.toString()],
      'design': {
        'hook_lead': (v['hook_lead'] ?? '').toString(),
        'hook_main': (v['hook_main'] ?? '').toString(),
        'hook_accent': (v['hook_accent'] ?? '').toString(),
        'emphasis': [
          for (final e in (v['emphasis'] as List? ?? const []))
            if (e is Map) {'word': (e['word'] ?? '').toString(), 'accent': (e['accent'] ?? '').toString()}
        ],
        'cta_main': (v['cta_main'] ?? '').toString(),
        'cta_accent': (v['cta_accent'] ?? '').toString(),
      },
    };

/// Вставки от AI: какая вставка медиатеки и во время какой фразы (номер как в phrase_ids).
List<Map<String, dynamic>> _broll(Map v, PlanExtras x) => [
      for (final b in (v['broll'] as List? ?? const []).take(3))
        if (b is Map)
          if (int.tryParse('${b['media']}'.replaceAll(RegExp(r'[^0-9]'), '')) case final n?)
            if (n >= 1 && n <= x.library.length) {'phrase': '${b['phrase_id']}', 'media': x.library[n - 1]['id']}
    ];

class MixSource {
  MixSource(this.id, this.phrases, this.duration);
  final String id;
  final List phrases;
  final double duration;
}

/// Ролики из фраз нескольких видео. clips — монтаж в формате редактора, segments — куски основного видео.
Future<List<Map<String, dynamic>>> planMix(
    AiProvider ai, List<MixSource> sources, List<String> usedHooks, PlanExtras extras) async {
  const letters = 'ABCDEFGHIJ';
  final src = sources.take(letters.length).toList();
  final block = StringBuffer();
  for (final (i, s) in src.indexed) {
    block
      ..writeln('— Видео ${letters[i]} —')
      ..write(_phraseLines(s.phrases, letters[i]));
  }
  final res = await ai.json(_prompt(block.toString(), usedHooks, extras, mix: true));
  (int, int)? ref(Object? x) {
    final m = RegExp(r'^\s*([A-J])\s*(\d+)\s*$').firstMatch('$x'.toUpperCase());
    if (m == null) return null;
    final si = letters.indexOf(m[1]!), pi = int.parse(m[2]!);
    if (si >= src.length || pi >= src[si].phrases.length || src[si].phrases[pi]['quiet'] == true) return null;
    return (si, pi);
  }

  final out = <Map<String, dynamic>>[];
  for (final t in (res['topics'] as List? ?? const [])) {
    final topic = (t['title'] ?? '').toString();
    for (final v in (t['variants'] as List? ?? const [])) {
      final refs = <(int, int)>[];
      for (final x in (v['phrase_ids'] as List? ?? const [])) {
        final r = ref(x);
        if (r != null && !refs.contains(r)) refs.add(r);
      }
      if (refs.map((r) => r.$1).toSet().length < 2) continue;
      // Соседние фразы одного видео — один кусок, без лишней склейки.
      final clips = <Map<String, dynamic>>[];
      (int, int)? prev;
      for (final r in refs) {
        final ph = src[r.$1].phrases[r.$2];
        final s = (d(ph['s']) - 0.05).clamp(0.0, src[r.$1].duration).toDouble();
        final e = (d(ph['e']) + 0.12).clamp(0.0, src[r.$1].duration).toDouble();
        if (prev != null && prev.$1 == r.$1 && prev.$2 + 1 == r.$2) {
          clips.last['e'] = e;
        } else {
          clips.add({'id': 'ai${clips.length}', 'src': 'source', 'ref': src[r.$1].id, 's': s, 'e': e, 'mute': false});
        }
        prev = r;
      }
      final dur = clips.fold<double>(0, (a, c) => a + (c['e'] as double) - (c['s'] as double));
      if (dur < 4 || dur > 90) continue;
      // Основное видео — откуда больше всего речи: по нему превью и проверка оригинальности.
      final byDur = <String, double>{};
      for (final c in clips) {
        byDur[c['ref'] as String] = (byDur[c['ref']] ?? 0) + (c['e'] as double) - (c['s'] as double);
      }
      final main = byDur.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      final segIdx = src.indexWhere((x) => x.id == main);
      out.add({
        ..._common(topic, v),
        'source_id': main,
        'clips': clips,
        'segments': [
          for (final c in clips)
            if (c['ref'] == main) {'s': c['s'], 'e': c['e']}
        ],
        'duration': dur,
        // Вставки: переводим номер фразы во время внутри ролика.
        'broll': [
          for (final b in _broll(v, extras))
            if (ref(b['phrase']) case final r?)
              if (_at(clips, src[r.$1].id, src[r.$1].phrases[r.$2]) case final at?)
                {'media': b['media'], 'at': at, 'len': d(src[r.$1].phrases[r.$2]['e']) - d(src[r.$1].phrases[r.$2]['s'])}
        ],
        'seg_source': segIdx,
      });
    }
  }
  return out;
}

/// Секунда ролика, на которой начинается фраза, или null, если её нет в монтаже.
double? _at(List<Map<String, dynamic>> clips, String ref, Map ph) {
  var off = 0.0;
  final ps = d(ph['s']);
  for (final c in clips) {
    final s = d(c['s']), e = d(c['e']);
    if (c['ref'] == ref && ps >= s - 0.1 && ps < e) return off + max(0.0, ps - s);
    off += e - s;
  }
  return null;
}

/// Соседние фразы склеиваются в один кусок, чтобы не было лишних склеек.
List<Map<String, double>> segmentsFor(List<int> ids, List phrases, double sourceDuration) {
  final segs = <Map<String, double>>[];
  int? prev;
  for (final id in ids) {
    final ph = phrases[id];
    final s = (d(ph['s']) - 0.05).clamp(0.0, sourceDuration).toDouble();
    final e = (d(ph['e']) + 0.12).clamp(0.0, sourceDuration).toDouble();
    if (prev != null && id == prev + 1 && segs.isNotEmpty) {
      segs.last['e'] = e;
    } else {
      segs.add({'s': s, 'e': e});
    }
    prev = id;
  }
  return segs;
}

Future<List<Map<String, dynamic>>> planVariants(
    AiProvider ai, List phrases, double sourceDuration, List<String> usedHooks,
    [PlanExtras extras = const PlanExtras()]) async {
  final res = await ai.json(_prompt(_phraseLines(phrases), usedHooks, extras));
  final out = <Map<String, dynamic>>[];
  for (final t in (res['topics'] as List? ?? const [])) {
    final topic = (t['title'] ?? '').toString();
    for (final v in (t['variants'] as List? ?? const [])) {
      final ids = <int>[];
      for (final x in (v['phrase_ids'] as List? ?? const [])) {
        if (x is num &&
            x.toInt() >= 0 &&
            x.toInt() < phrases.length &&
            phrases[x.toInt()]['quiet'] != true &&
            !ids.contains(x.toInt())) {
          ids.add(x.toInt());
        }
      }
      if (ids.isEmpty) continue;
      final segs = segmentsFor(ids, phrases, sourceDuration);
      final dur = segs.fold<double>(0, (a, s) => a + s['e']! - s['s']!);
      if (dur < 4 || dur > 90) continue;
      final clips = [
        for (final (i, sg) in segs.indexed)
          {'id': 'ai$i', 'src': 'source', 'ref': '', 's': sg['s'], 'e': sg['e'], 'mute': false}
      ];
      out.add({
        ..._common(topic, v),
        'segments': segs,
        'duration': dur,
        'broll': [
          for (final b in _broll(v, extras))
            if (int.tryParse(b['phrase'] as String) case final pi?)
              if (pi >= 0 && pi < phrases.length)
                if (_at(clips, '', phrases[pi] as Map) case final at?)
                  {'media': b['media'], 'at': at, 'len': d(phrases[pi]['e']) - d(phrases[pi]['s'])}
        ],
      });
    }
  }
  return out;
}
