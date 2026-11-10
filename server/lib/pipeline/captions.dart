import 'dart:math';

/// Файл с подписями: блоки через строку «---», первая строка «Тема: …», последняя — хэштеги.
List<Map<String, dynamic>> parseCaptions(String raw) {
  final out = <Map<String, dynamic>>[];
  final blocks = raw.replaceAll('\r\n', '\n').split(RegExp(r'^\s*-{3,}\s*$', multiLine: true));
  for (final b in blocks) {
    final lines = b.split('\n').map((l) => l.trimRight()).toList();
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) continue;
    var topic = '';
    final m = RegExp(r'^\s*тема\s*:\s*(.*)$', caseSensitive: false).firstMatch(lines.first);
    if (m != null) {
      topic = m[1]!.trim();
      lines.removeAt(0);
    }
    var tags = <String>[];
    if (lines.isNotEmpty) {
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty && parts.every((x) => x.startsWith('#') && x.length > 1)) {
        tags = parts;
        lines.removeLast();
      }
    }
    final body = lines.join('\n').trim();
    if (body.isEmpty) continue;
    out.add({'topic': topic, 'body': body.length > 2200 ? body.substring(0, 2200) : body, 'hashtags': tags});
  }
  return out;
}

Set<String> _stems(String s) => {
      for (final w in s.toLowerCase().replaceAll('ё', 'е').split(RegExp(r'[^a-zа-я0-9]+')))
        if (w.length >= 4) w.substring(0, min(5, w.length))
    };

/// Насколько подпись подходит ролику: общие корни слов темы и текста.
double captionScore(Map cap, String variantText) {
  final a = _stems('${cap['topic']} ${cap['topic']} ${cap['body']}');
  final b = _stems(variantText);
  if (a.isEmpty || b.isEmpty) return 0;
  return a.intersection(b).length / sqrt(a.length * b.length);
}
