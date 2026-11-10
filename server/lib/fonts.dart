import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Шрифты из server/fonts. В ASS шрифт указывается по имени, а не по файлу,
/// поэтому читаем полное имя прямо из файла — так не зависим от того, как Google его назвал.
class Fonts {
  static String? dir;
  static final Map<String, String> _names = {};
  static final Map<String, _Metrics> _metrics = {};

  static void load(String fontsDir) {
    _names.clear();
    final d = Directory(fontsDir);
    if (!d.existsSync()) return;
    dir = d.absolute.path;
    for (final f in d.listSync().whereType<File>()) {
      final ext = p.extension(f.path).toLowerCase();
      if (ext != '.ttf' && ext != '.otf') continue;
      final key = p.basenameWithoutExtension(f.path);
      final name = _fullName(f);
      if (name != null) _names[key] = name;
      final m = _Metrics.read(f);
      if (m != null) _metrics[key] = m;
    }
  }

  /// Имя шрифта для ASS по ключу файла, либо запасной системный шрифт.
  static String of(String key, [String fallback = 'Arial']) => _names[key] ?? fallback;

  static int get count => _names.length;

  static bool has(String key) => _names.containsKey(key);

  /// Все шрифты папки: ключ файла и полное имя — для списка в приложении.
  static List<Map<String, String>> list() {
    final keys = _names.keys.toList()..sort();
    return [for (final k in keys) {'id': k, 'name': _names[k]!}];
  }

  /// Ширина строки в px холста при кегле [size], как её рисует libass (кегль = winAscent + winDescent).
  /// null — метрик шрифта нет, точно измерить нельзя.
  static double? width(String key, String text, double size, {double spacing = 0}) {
    final m = _metrics[key];
    if (m == null || text.isEmpty) return null;
    var w = 0;
    for (final r in text.runes) {
      final g = m.cmap[r] ?? 0;
      w += m.adv[g < m.adv.length ? g : m.adv.length - 1];
    }
    return w * size / m.em + spacing * text.runes.length;
  }

  /// Высота прописных букв и сдвиг их центра от точки \an5 (вниз — плюс), в px при кегле [size].
  static (double, double)? capBox(String key, double size) {
    final m = _metrics[key];
    if (m == null) return null;
    final sc = size / m.em;
    return (m.cap * sc, (m.asc - m.desc) / 2 * sc - m.cap * sc / 2);
  }

  static String? _fullName(File f) {
    try {
      final b = f.readAsBytesSync();
      final bd = ByteData.sublistView(b);
      final numTables = bd.getUint16(4);
      for (var i = 0; i < numTables; i++) {
        final rec = 12 + 16 * i;
        if (String.fromCharCodes(b.sublist(rec, rec + 4)) != 'name') continue;
        final off = bd.getUint32(rec + 8);
        final count = bd.getUint16(off + 2);
        final strings = off + bd.getUint16(off + 4);
        String? mac;
        for (var j = 0; j < count; j++) {
          final r = off + 6 + 12 * j;
          final platform = bd.getUint16(r), nameId = bd.getUint16(r + 6);
          final len = bd.getUint16(r + 8), o = strings + bd.getUint16(r + 10);
          if (nameId != 4) continue;
          if (platform == 3) {
            final units = [for (var k = 0; k < len; k += 2) bd.getUint16(o + k)];
            return String.fromCharCodes(units);
          }
          if (platform == 1) mac = String.fromCharCodes(b.sublist(o, o + len));
        }
        return mac;
      }
    } catch (_) {}
    return null;
  }
}

class _Metrics {
  _Metrics(this.cmap, this.adv, this.em, this.asc, this.desc, this.cap);
  final Map<int, int> cmap;
  final List<int> adv;
  final int em, asc, desc, cap;

  static _Metrics? read(File f) {
    try {
      final b = f.readAsBytesSync();
      final bd = ByteData.sublistView(b);
      final t = <String, int>{};
      for (var i = 0; i < bd.getUint16(4); i++) {
        final r = 12 + 16 * i;
        t[String.fromCharCodes(b.sublist(r, r + 4))] = bd.getUint32(r + 8);
      }
      final hh = t['hhea'], hm = t['hmtx'], os2 = t['OS/2'], cm = t['cmap'];
      if (hh == null || hm == null || os2 == null || cm == null) return null;
      final nh = bd.getUint16(hh + 34);
      final adv = [for (var i = 0; i < nh; i++) bd.getUint16(hm + 4 * i)];
      final asc = bd.getUint16(os2 + 74), desc = bd.getUint16(os2 + 76);
      final cap = bd.getUint16(os2) >= 2 ? bd.getInt16(os2 + 88) : (asc * 0.7).round();
      final cmap = <int, int>{};
      int? f4, f12;
      for (var i = 0; i < bd.getUint16(cm + 2); i++) {
        final r = cm + 4 + 8 * i;
        final pid = bd.getUint16(r), eid = bd.getUint16(r + 2), o = cm + bd.getUint32(r + 4);
        final fmt = bd.getUint16(o);
        if (fmt == 12) f12 = o;
        if (fmt == 4 && (pid == 0 || (pid == 3 && eid == 1))) f4 = o;
      }
      if (f12 != null) {
        final n = bd.getUint32(f12 + 12);
        for (var k = 0; k < n; k++) {
          final r = f12 + 16 + 12 * k;
          final sc = bd.getUint32(r), ec = bd.getUint32(r + 4), sg = bd.getUint32(r + 8);
          // Нужны только буквы, цифры и знаки — гигантские диапазоны пропускаем.
          if (ec - sc > 70000) continue;
          for (var c = sc; c <= ec; c++) {
            cmap[c] = sg + c - sc;
          }
        }
      } else if (f4 != null) {
        final seg = bd.getUint16(f4 + 6) ~/ 2;
        final ends = f4 + 14, starts = ends + 2 * seg + 2, deltas = starts + 2 * seg, ros = deltas + 2 * seg;
        for (var k = 0; k < seg; k++) {
          final e = bd.getUint16(ends + 2 * k), s = bd.getUint16(starts + 2 * k);
          final dl = bd.getInt16(deltas + 2 * k), ro = bd.getUint16(ros + 2 * k);
          if (s == 0xFFFF) continue;
          for (var c = s; c <= e; c++) {
            var g = 0;
            if (ro == 0) {
              g = (c + dl) & 0xFFFF;
            } else {
              g = bd.getUint16(ros + 2 * k + ro + 2 * (c - s));
              if (g != 0) g = (g + dl) & 0xFFFF;
            }
            cmap[c] = g;
          }
        }
      } else {
        return null;
      }
      return _Metrics(cmap, adv, asc + desc, asc, desc, cap);
    } catch (_) {
      return null;
    }
  }
}
