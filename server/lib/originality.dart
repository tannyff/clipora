import 'dart:math';

import 'config.dart';
import 'db.dart';
import 'pipeline/edit.dart';
import 'util.dart';

// ---------- Аудио-отпечаток (chromaprint) ----------
// Картинка у «говорящей головы» почти не меняется, поэтому кадры сравнивать бесполезно:
// любые два ролика с одной съёмки будут «похожи». Звук речи различает ролики надёжно,
// и на него не влияют зеркало, кроп и цветокоррекция.

Future<List<int>> audioFingerprint(Config c, String path) async {
  final r = await run(c.fpcalc, ['-raw', '-length', '900', path]);
  final line = r.stdout
      .toString()
      .split('\n')
      .firstWhere((l) => l.startsWith('FINGERPRINT='), orElse: () => '');
  if (line.isEmpty) return [];
  return [
    for (final x in line.substring(12).split(','))
      if (x.trim().isNotEmpty) int.parse(x.trim()) & 0xFFFFFFFF
  ];
}

int _pop(int x) {
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

/// Какая доля звука ролика A встречается в ролике B (0..1).
double audioOverlap(List<int> a, List<int> b) {
  const win = 40; // ~5 секунд
  const maxBits = win * 32 * 0.2;
  if (a.length < win || b.length < win) return 0;
  var matched = 0, total = 0;
  for (var i = 0; i + win <= a.length; i += win) {
    total++;
    var best = 1.0;
    for (var o = 0; o + win <= b.length; o++) {
      var bits = 0;
      for (var k = 0; k < win; k++) {
        bits += _pop(a[i + k] ^ b[o + k]);
        if (bits > maxBits) break;
      }
      final ber = bits / (win * 32);
      if (ber < best) best = ber;
      if (best < 0.12) break;
    }
    if (best < 0.2) matched++;
  }
  return total == 0 ? 0 : matched / total;
}

// ---------- Монтаж ----------

double _dur(List segs) => segs.fold<double>(0, (a, s) => a + d(s['e']) - d(s['s']));

/// Какая доля ролика A взята из тех же секунд исходника, что и ролик B.
double rangeOverlap(List a, List b) {
  var inter = 0.0;
  for (final x in a) {
    for (final y in b) {
      final lo = max(d(x['s']), d(y['s'])), hi = min(d(x['e']), d(y['e']));
      if (hi > lo) inter += hi - lo;
    }
  }
  final da = _dur(a);
  return da == 0 ? 0 : clamp01(inter / da);
}

// ---------- Текст ----------

List<String> _norm(String t) => t
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

Set<String> _shingles(List<String> w, [int n = 3]) {
  if (w.length < n) return {w.join(' ')};
  return {for (var i = 0; i + n <= w.length; i++) w.sublist(i, i + n).join(' ')};
}

/// Какая доля текста A есть в тексте B.
double containment(String a, String b) {
  final sa = _shingles(_norm(a)), sb = _shingles(_norm(b));
  if (sa.isEmpty || (sa.length == 1 && sa.first.isEmpty)) return 0;
  return sa.intersection(sb).length / sa.length;
}

bool _sameHook(String a, String b) {
  final na = _norm(a), nb = _norm(b);
  if (na.isEmpty || nb.isEmpty) return false;
  if (na.join(' ') == nb.join(' ')) return true;
  final common = na.toSet().intersection(nb.toSet()).length;
  return common / min(na.length, nb.length) >= 0.7;
}

bool _sameOpening(String a, String b) {
  final na = _norm(a), nb = _norm(b);
  if (na.length < 4 || nb.length < 4) return false;
  return na.take(6).join(' ') == nb.take(6).join(' ');
}

// ---------- Проверка ----------

Future<Map<String, dynamic>> checkOriginality(Config c, String variantId) async {
  final v = (await q1('''
    select v.*, s.duration as source_duration, s.transcript as source_transcript
    from variants v join sources s on s.id = v.source_id where v.id = @id''', {'id': variantId}))!;

  final segs = effectiveSegments(v);
  final clipDur = _dur(segs);
  final srcDur = max(d(v['source_duration']), clipDur);
  final myText = (v['text'] as String?) ?? '';
  final myHook = (v['hook_text'] as String?) ?? '';
  final myFp = [for (final x in (jv(v['audio_fp']) as List? ?? const [])) (x as num).toInt()];

  // 1. Монтажная структура относительно исходника
  final longest = segs.isEmpty
      ? 1.0
      : segs.map((s) => d(s['e']) - d(s['s'])).reduce(max) / max(clipDur, 0.001);
  var reordered = false;
  for (var i = 1; i < segs.length; i++) {
    if (d(segs[i]['s']) < d(segs[i - 1]['s'])) reordered = true;
  }
  final cuts = max(0, segs.length - 1);
  final coverage = clipDur / srcDur;
  final structure = 35 * clamp01((1 - longest) / 0.5) +
      25 * (reordered ? 1 : 0) +
      20 * min(cuts, 4) / 4 +
      20 * clamp01((1 - coverage) / 0.5);

  // Сколько слов выкинуто из куска исходника, который охватывает ролик.
  final srcWords = ((jv(v['source_transcript']) as Map?)?['words'] as List?) ?? const [];
  var removed = 0.0;
  if (segs.isNotEmpty && srcWords.isNotEmpty) {
    final lo = segs.map((s) => d(s['s'])).reduce(min);
    final hi = segs.map((s) => d(s['e'])).reduce(max);
    final region = srcWords.where((w) => d(w['s']) >= lo - 0.01 && d(w['e']) <= hi + 0.05).length;
    final mine = _norm(myText).length;
    if (region > 0) removed = clamp01(1 - mine / region);
  }

  // 2. Сравнение с уже выгруженными роликами
  final others = await q('''
    select id, title, source_id, segments, edit, audio_fp, text, hook_text from variants
    where user_id = @u and status = 'exported' and id <> @id
    order by exported_at desc limit 200''', {'u': v['user_id'], 'id': variantId});

  var maxNear = 0.0, maxScript = 0.0;
  var hookSame = false, openingSame = false;
  Map<String, dynamic>? closest;
  for (final o in others) {
    final oSegs = effectiveSegments(o);
    final ro = o['source_id'] == v['source_id'] ? rangeOverlap(segs, oSegs) : 0.0;
    final oFp = [for (final x in (jv(o['audio_fp']) as List? ?? const [])) (x as num).toInt()];
    final ao = audioOverlap(myFp, oFp);
    final near = max(ro, ao);
    final sc = containment(myText, (o['text'] as String?) ?? '');
    if (near > maxNear || (near == maxNear && sc > maxScript)) {
      closest = {'id': o['id'], 'title': o['title']};
    }
    maxNear = max(maxNear, near);
    maxScript = max(maxScript, sc);
    if (_sameHook(myHook, (o['hook_text'] as String?) ?? '')) hookSame = true;
    if (_sameOpening(myText, (o['text'] as String?) ?? '')) openingSame = true;
  }

  // 3. Сценарий
  final script = 45 * (1 - maxScript) +
      25 * (myHook.trim().isNotEmpty && !hookSame ? 1 : 0) +
      15 * (openingSame ? 0 : 1) +
      15 * clamp01(removed * 2 + (reordered ? 0.5 : 0));

  // 4. Авторская составляющая. Косметика (фильтры, скорость, зеркало) сюда не входит намеренно.
  final authorItems = [
    {'key': 'hook', 'name': 'Текст-хук на экране', 'done': myHook.trim().isNotEmpty, 'available': true, 'points': 40},
    {'key': 'broll', 'name': 'Вставки b-roll', 'done': hasBroll(v), 'available': true, 'points': 30},
    {'key': 'voice', 'name': 'Новая озвучка или комментарий', 'done': false, 'available': false, 'points': 30},
  ];
  final authorial = authorItems
      .where((x) => x['done'] == true)
      .fold<int>(0, (a, x) => a + (x['points'] as int))
      .toDouble();

  final total = 0.35 * structure + 0.40 * script + 0.25 * authorial;
  final sourceCopy = coverage >= 0.85 && longest >= 0.85;

  final tips = <String>[];
  if (sourceCopy) tips.add('Ролик почти целиком повторяет исходник. Выкинь воду или переставь фразы.');
  if (maxNear >= 0.5 && closest != null) {
    tips.add('${(maxNear * 100).round()}% ролика совпадает с «${closest['title']}». Возьми другие фразы.');
  }
  if (hookSame) tips.add('Такой хук уже был в выгруженном ролике. Выбери другой текст на экране.');
  if (openingSame) tips.add('Ролик начинается теми же словами, что и уже выгруженный. Начни с другой фразы.');
  if (longest >= 0.9 && !sourceCopy) {
    tips.add('Ролик — один непрерывный кусок. Переставь фразы или вырежи паузы и повторы.');
  }
  if (myHook.trim().isEmpty) tips.add('Добавь текст-хук на первые секунды.');
  if (tips.isEmpty && total < 70) tips.add('Чтобы усилить ролик, добавь в монтаже вставки из медиатеки.');

  final level = (maxNear >= 0.8 || sourceCopy)
      ? 'red'
      : (total < 55 || maxNear >= 0.5 || hookSame || maxScript >= 0.6)
          ? 'yellow'
          : 'green';

  return {
    'level': level,
    'total': total.round(),
    'structure': {
      'score': structure.round(),
      'longest_piece': round2(longest),
      'reordered': reordered,
      'cuts': cuts,
      'source_coverage': round2(coverage),
    },
    'script': {
      'score': script.round(),
      'max_text_match': round2(maxScript),
      'hook_repeated': hookSame,
      'opening_repeated': openingSame,
      'removed_words': round2(removed),
    },
    'authorial': {'score': authorial.round(), 'items': authorItems},
    'near_copy': {
      'max_overlap': round2(maxNear),
      'closest': closest,
      'source_copy': sourceCopy,
      'compared_with': others.length,
    },
    'tips': tips,
    'checked_at': DateTime.now().toUtc().toIso8601String(),
  };
}
