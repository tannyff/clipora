import 'dart:math';

import '../fonts.dart';
import '../util.dart';

// Холст ASS совпадает с итоговым видео 1080×1920.
const _w = 1080.0;
const _safeW = 960.0;

// ---------- Шаблоны заголовков ----------

class TitlePreset {
  const TitlePreset(this.id, this.name, this.description,
      {required this.main,
      required this.mainSize,
      required this.widthK,
      required this.accent,
      this.accentSize = 104,
      this.lead = 'inter-regular',
      this.upper = true,
      this.accentAbove = false,
      this.accentBelow = false,
      this.track = 0,
      this.accentK = 0.5,
      this.tilt = 6});

  final String id, name, description;
  final String main, accent, lead;
  final double mainSize, accentSize;

  /// Средняя ширина буквы относительно кегля — чтобы длинное слово влезло в кадр.
  final double widthK;
  /// accentBelow — акцент ровно под словом, без наклона (не рукописный).
  final bool upper, accentAbove, accentBelow;
  final double tilt;

  /// Межбуквенный интервал в долях кегля: плотный набор крупных слов выглядит дороже.
  final double track;

  /// Ширина буквы акцента в долях кегля (каллиграфия уже, пиксельный шире).
  final double accentK;

  Map<String, String> toJson() => {'id': id, 'name': name, 'description': description};
}

// Одна пара шрифтов из референсов = один шаблон. Бесплатные замены с кириллицей.
const titlePresets = <TitlePreset>[
  TitlePreset('narrow', 'Узкий + пропись', 'Как Druk + Young Love',
      main: 'oswald-bold', mainSize: 480, widthK: 0.39, track: -0.015, accent: 'badscript', accentSize: 140),
  TitlePreset('wide', 'Широкий + пропись', 'Как Druk Wide и Mayer',
      main: 'unbounded-black', mainSize: 270, widthK: 0.7, track: -0.02, accent: 'badscript', accentSize: 140),
  TitlePreset('wide_serif', 'Широкий + засечки', 'Как AKONY + Berold',
      main: 'unbounded-bold', mainSize: 250, widthK: 0.66, track: -0.01, accent: 'forum', accentSize: 120,
      accentBelow: true, tilt: 0),
  TitlePreset('elegant', 'Засечки + каллиграфия', 'Как Anticva + Astrum',
      main: 'forum', mainSize: 290, widthK: 0.56, track: 0.01, accent: 'greatvibes', accentSize: 190, accentK: 0.34,
      lead: 'inter-light'),
  TitlePreset('thin', 'Тонкий элегантный', 'Как Felidae и Manege',
      main: 'cormorant-light', mainSize: 310, widthK: 0.5, track: 0.01, accent: 'cormorant-italic', accentSize: 130,
      lead: 'inter-light', accentBelow: true, tilt: 0),
  TitlePreset('italic', 'Жирный курсив + пропись', 'Как Gramatika + Baystiq Script',
      main: 'montserrat-xbi', mainSize: 250, widthK: 0.66, track: -0.02, accent: 'marckscript', accentSize: 140),
  TitlePreset('pixel', 'Узкий + пиксельный', 'Как Stadium + Digital Upscaled Pixel',
      main: 'oswald-bold', mainSize: 480, widthK: 0.39, track: -0.015, accent: 'pressstart', accentSize: 58, accentK: 1.0,
      accentBelow: true, tilt: 0),
  TitlePreset('heading', 'Узкий строчный + рукописный', 'Как Heading Now + Denistina',
      main: 'oswald-bold', mainSize: 380, widthK: 0.36, track: -0.02, accent: 'caveat', accentSize: 140, upper: false),
  TitlePreset('typewriter', 'Машинка + технический', 'Как Old Soviet + Neue Machina',
      main: 'ptmono', mainSize: 240, widthK: 0.6, accent: 'unbounded-bold', accentSize: 64,
      upper: false, accentBelow: true, tilt: 0),
  TitlePreset('serif', 'Курсив + рубленый', 'Как Playfair + Helvetica',
      main: 'inter-semibold', mainSize: 260, widthK: 0.56, track: -0.03, accent: 'playfair-italic', accentSize: 160,
      upper: false, accentAbove: true, tilt: 0),
  TitlePreset('caslon', 'Курсив сверху + геометрия', 'Как Caslon + Evolventa («паблик СПИКИНГ»)',
      main: 'jost-semibold', mainSize: 260, widthK: 0.6, track: -0.01, accent: 'cormorant-italic', accentSize: 150,
      accentAbove: true, tilt: 0),
];

TitlePreset titleById(String? id) =>
    titlePresets.firstWhere((t) => t.id == id, orElse: () => titlePresets.first);

// ---------- Палитры ----------

class Palette {
  const Palette(this.id, this.name, this.colors, this.main, this.accent, [this.plate]);
  final String id, name;

  /// Цвета палитры как в референсе — для кружочков в приложении.
  final List<String> colors;

  /// main — главное слово, accent — пропись и выделения,
  /// plate — плашка под главным словом: тёмный цвет палитры поверх видео иначе не читается.
  final String main, accent;
  final String? plate;

  Map<String, Object> toJson() => {'id': id, 'name': name, 'colors': colors, 'main': main, 'accent': accent};
}

// Все 19 палитр из референсов (≈ — цвет переписан приблизительно).
const palettes = <Palette>[
  Palette('burgundy', 'Крем + бордо', ['FBF2E5', '77111B'], 'FBF2E5', 'FBF2E5', '77111B'),
  Palette('terracotta', 'Крем + терракота', ['FBF2E5', 'A04132'], 'FBF2E5', 'FBF2E5', 'A04132'),
  Palette('choco_sky', 'Шоколад + голубой', ['4F2D1B', 'BBD3EE'], 'BBD3EE', 'BBD3EE', '4F2D1B'),
  Palette('choco_milk', 'Шоколад + молочный', ['4D291D', 'F7F0E8'], 'F7F0E8', 'F7F0E8', '4D291D'),
  Palette('plum', 'Слива + фисташка', ['731E52', 'DDEAA1'], 'DDEAA1', 'DDEAA1', '731E52'),
  Palette('butter', 'Чёрный + масло', ['171817', 'FFEFA7'], 'FFEFA7', 'FFFFFF', '171817'),
  Palette('mint', 'Чёрный + мята', ['171817', 'ABE5E1'], 'ABE5E1', 'FFFFFF', '171817'),
  Palette('lemon_pink', 'Лимон + розовый', ['0F1010', 'F4F07D', 'F48290'], 'F4F07D', 'F48290'),
  Palette('cornflower', 'Крем + коричневый + василёк', ['FAF1E8', '6B3419', '8B9DDC'], 'FAF1E8', '8B9DDC', '6B3419'),
  Palette('forest', 'Белый + тёмно-зелёный', ['FAF9F7', '264E32'], 'FAF9F7', 'FAF9F7', '264E32'),
  Palette('aubergine', 'Баклажан + апельсин', ['533259', 'D9772F', 'F8F0E9'], 'F8F0E9', 'D9772F', '533259'),
  Palette('rust', 'Ржавчина + лаванда', ['B24614', 'D8D9FF'], 'D8D9FF', 'D8D9FF', 'B24614'),
  Palette('raspberry', 'Малина + беж + голубой', ['9B1D40', 'EFE5D8', 'BBE6FF'], 'EFE5D8', 'BBE6FF', '9B1D40'),
  Palette('grey', 'Серый + белый', ['737075', 'FCFCFC'], 'FCFCFC', 'FCFCFC', '737075'),
  Palette('olive', 'Олива + жёлтый + беж', ['45472A', 'F6DA75', 'EEE3CF'], 'F6DA75', 'EEE3CF', '45472A'),
  Palette('wine', 'Пудра + вино', ['FBCACF', '7A1D2C', 'EBEBEB'], 'FBCACF', 'EBEBEB', '7A1D2C'),
  Palette('berry', 'Беж + ягодный', ['F5E9DB', '9F2549'], 'F5E9DB', 'F5E9DB', '9F2549'),
  Palette('cocoa', 'Коричневый + молочный', ['563D2A', 'F7F4EF'], 'F7F4EF', 'F7F4EF', '563D2A'),
  Palette('lavender_lime', 'Лаванда + лайм', ['B1ACD6', 'C4DF91', 'F7F4E5'], 'C4DF91', 'B1ACD6'),
];

Palette paletteById(String? id) => palettes.firstWhere((x) => x.id == id, orElse: () => palettes.first);

// ---------- Субтитры ----------

class SubStyle {
  const SubStyle(this.id, this.name, this.description,
      {required this.font,
      required this.size,
      required this.chunk,
      this.upper = false,
      this.y = 1250,
      this.flashes = false,
      this.spacing = 0,
      this.highlight = false});

  final String id, name, description, font;
  final double size, y, spacing;
  final int chunk;
  final bool upper, flashes, highlight;

  Map<String, String> toJson() => {'id': id, 'name': name, 'description': description};
}

const subStyles = <SubStyle>[
  SubStyle('words_flash', 'Слова + вспышки',
      'Мелкие слова по одному на уровне груди, главные слова вспыхивают крупно',
      font: 'inter-regular', size: 68, chunk: 1, flashes: true, y: 1480, spacing: 1),
  SubStyle('words', 'Слова по одному', 'Мелкие спокойные слова по одному на уровне груди',
      font: 'inter-regular', size: 68, chunk: 1, y: 1480, spacing: 1),
  SubStyle('caps', 'Капслок', 'По два слова жирным капслоком, текущее — цветом палитры',
      font: 'unbounded-bold', size: 62, chunk: 2, upper: true, spacing: 2, highlight: true, y: 1480),
  SubStyle('line', 'Строка внизу', 'Короткая строка внизу кадра', font: 'inter-semibold', size: 64, chunk: 4, y: 1560),
  SubStyle('none', 'Без субтитров', 'Только заголовок и вспышки', font: 'inter-regular', size: 60, chunk: 1),
];

SubStyle styleById(String? id) => subStyles.firstWhere((s) => s.id == id, orElse: () => subStyles.first);

// ---------- Оформление целиком ----------

const subOutlines = ['glow', 'stroke', 'none'];

String _hexOr(Object? v, String def) {
  final x = (v ?? '').toString().replaceAll('#', '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(x) ? x : def;
}

double _num(Object? v, double def, double lo, double hi) {
  final x = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  if (x == null || x.isNaN) return def;
  return x.clamp(lo, hi).toDouble();
}

const titleRoles = ['lead', 'main', 'accent'];

// ---------- Анимации появления ----------

const anims = <String, String>{
  'none': 'Без анимации',
  'fade': 'Проявление',
  'pop': 'Выпрыгивает',
  'bounce': 'Пружинит сверху',
  'drop': 'Падает',
  'slide_up': 'Выезжает снизу',
  'slide_down': 'Выезжает сверху',
  'slide_left': 'Выезжает справа',
  'slide_right': 'Выезжает слева',
  'zoom_out': 'Из крупного',
  'stretch': 'Растягивается',
  'blur_in': 'Из размытия',
  'spin': 'Вкручивается',
  'swing': 'Качается',
  'heartbeat': 'Пульс',
  'glitch': 'Глитч',
  'typewriter': 'Печатная машинка',
  'letters': 'По буквам',
  'letters_pop': 'Буквы выпрыгивают',
  'wave': 'Волна букв',
};

const _perCharAnims = {'typewriter', 'letters', 'letters_pop', 'wave'};

/// Готовые наборы: какая анимация у маленькой строки, главного слова и прописи.
const animPresets = <String, (String, String, Map<String, String>)>{
  'soft': ('Мягко', 'Проявление, слово выпрыгивает, пропись печатается', {'lead': 'fade', 'main': 'pop', 'accent': 'typewriter'}),
  'dynamic': ('Динамично', 'Выезд, пружина и буквы', {'lead': 'slide_up', 'main': 'bounce', 'accent': 'letters_pop'}),
  'cinema': ('Кино', 'Из размытия и из крупного плана', {'lead': 'blur_in', 'main': 'zoom_out', 'accent': 'fade'}),
  'drop': ('Падение', 'Всё падает сверху, пропись качается', {'lead': 'drop', 'main': 'drop', 'accent': 'swing'}),
  'type': ('Печать', 'Всё печатается по буквам', {'lead': 'typewriter', 'main': 'letters', 'accent': 'typewriter'}),
  'slide': ('Выезды', 'Части выезжают с разных сторон', {'lead': 'slide_right', 'main': 'slide_left', 'accent': 'slide_up'}),
  'spin': ('Вкрутка', 'Главное слово вкручивается', {'lead': 'fade', 'main': 'spin', 'accent': 'letters'}),
  'pulse': ('Пульс', 'Слово пульсирует, буквы волной', {'lead': 'fade', 'main': 'heartbeat', 'accent': 'wave'}),
  'stretch': ('Растяжка', 'Слово растягивается по ширине', {'lead': 'fade', 'main': 'stretch', 'accent': 'blur_in'}),
  'glitch': ('Глитч', 'Дёрганое цифровое появление', {'lead': 'glitch', 'main': 'glitch', 'accent': 'glitch'}),
};

String _animPos(String a, double x, double y) {
  final xi = x.round(), yi = y.round();
  String mv(int dx, int dy, int ms) => '\\move(${xi + dx},${yi + dy},$xi,$yi,0,$ms)';
  return switch (a) {
    'drop' => mv(0, -420, 380),
    'bounce' => mv(0, -160, 260),
    'slide_up' => mv(0, 180, 320),
    'slide_down' => mv(0, -180, 320),
    'slide_left' => mv(320, 0, 320),
    'slide_right' => mv(-320, 0, 320),
    _ => '\\pos($xi,$yi)',
  };
}

String _animTags(String a, double frz) {
  String f1(double v) => v.toStringAsFixed(1);
  return switch (a) {
    'none' => '',
    'pop' => '\\fad(100,250)\\fscx55\\fscy55\\t(0,200,\\fscx110\\fscy110)\\t(200,300,\\fscx100\\fscy100)',
    'bounce' => '\\fad(80,250)\\t(260,330,\\fscx108\\fscy88)\\t(330,430,\\fscx100\\fscy100)',
    'drop' => '\\fad(60,250)',
    'slide_up' || 'slide_down' || 'slide_left' || 'slide_right' => '\\fad(160,250)',
    'zoom_out' => '\\fad(150,250)\\fscx170\\fscy170\\t(0,320,0.6,\\fscx100\\fscy100)',
    'stretch' => '\\fad(100,250)\\fscx20\\t(0,280,0.5,\\fscx100)',
    'blur_in' => '\\fad(200,250)\\blur18\\t(0,380,\\blur0)',
    'spin' => '\\fad(120,250)\\frz${f1(frz + 90)}\\fscx40\\fscy40\\t(0,350,0.7,\\frz${f1(frz)}\\fscx100\\fscy100)',
    'swing' => '\\fad(100,250)\\frz${f1(frz - 14)}\\t(0,180,\\frz${f1(frz + 7)})\\t(180,300,\\frz${f1(frz - 3)})'
        '\\t(300,400,\\frz${f1(frz)})',
    'heartbeat' => '\\fad(120,250)\\t(300,420,\\fscx112\\fscy112)\\t(420,540,\\fscx100\\fscy100)'
        '\\t(640,760,\\fscx108\\fscy108)\\t(760,880,\\fscx100\\fscy100)',
    'glitch' => '\\fad(0,200)\\fscx130\\t(0,60,\\fscx85)\\t(60,120,\\fscx112)\\t(120,180,\\fscx100)',
    'typewriter' || 'letters' || 'letters_pop' || 'wave' => '\\fad(0,250)',
    _ => '\\fad(300,250)',
  };
}

/// Анимация по буквам: у каждой буквы своя задержка появления.
String _perChar(String a, String text) {
  if (!_perCharAnims.contains(a)) return text;
  final step = switch (a) { 'typewriter' => 55, 'letters' => 45, _ => 38 };
  final b = StringBuffer();
  var i = 0;
  for (final line in text.split('\\N')) {
    if (b.isNotEmpty) b.write('\\N');
    for (final ch in line.runes.map(String.fromCharCode)) {
      final d0 = i * step;
      final tag = switch (a) {
        'typewriter' => '\\alpha&HFF&\\t($d0,${d0 + 1},\\alpha&H00&)',
        'letters' => '\\alpha&HFF&\\t($d0,${d0 + 220},\\alpha&H00&)',
        'letters_pop' => '\\alpha&HFF&\\fscx30\\fscy30\\t($d0,${d0 + 180},\\alpha&H00&\\fscx100\\fscy100)',
        _ => '\\alpha&HFF&\\fscy160\\t($d0,${d0 + 200},\\alpha&H00&\\fscy100)',
      };
      b.write('{$tag}$ch');
      if (ch.trim().isNotEmpty) i++;
    }
  }
  return b.toString();
}

/// Убирает появление из шаблона, когда выбрана своя анимация.
String _stripIntro(String tags) => tags
    .replaceAll(RegExp(r'\\fad\([^)]*\)'), '')
    .replaceAll(RegExp(r'\\fscx94\\fscy94\\t\([^)]*\)'), '');

/// Слои, которые двигают руками: части заголовка, финальная надпись и свои надписи (t…).
final layerKey = RegExp(r'^(lead|main|accent|cta|t[a-z0-9]{1,12})$');

/// Чьё оформление можно поменять отдельно. flash_* — вспышки слов, без своих настроек берут заголовок.
const styleRoles = ['lead', 'main', 'accent', 'cta_main', 'cta_accent', 'flash_main', 'flash_accent'];

String? _hexOpt(Object? v) {
  final x = (v ?? '').toString().replaceAll('#', '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(x) ? x : null;
}

/// Настройки одной надписи: шрифт, цвета букв, обводки, тени и плашки. Только заданные поля.
Map<String, dynamic> _partStyle(Object? v) {
  if (v is! Map) return {};
  final font = '${v['font'] ?? ''}';
  return {
    if (Fonts.has(font)) 'font': font,
    if (_hexOpt(v['color']) != null) 'color': _hexOpt(v['color']),
    if (v['bord'] != null) 'bord': _num(v['bord'], 0, 0, 40).roundToDouble(),
    if (_hexOpt(v['bord_color']) != null) 'bord_color': _hexOpt(v['bord_color']),
    if (v['shadow'] == false) 'shadow': false,
    if (_hexOpt(v['shadow_color']) != null) 'shadow_color': _hexOpt(v['shadow_color']),
    if (_hexOpt(v['plate_color']) != null) 'plate_color': _hexOpt(v['plate_color']),
    if (anims.containsKey(v['anim'])) 'anim': v['anim'],
  };
}

Map<String, Map<String, dynamic>> _stOf(Object? v) {
  final out = <String, Map<String, dynamic>>{};
  if (v is! Map) return out;
  for (final r in styleRoles) {
    final st = _partStyle(v[r]);
    if (st.isNotEmpty) out[r] = st;
  }
  return out;
}

/// Свои надписи: текст, время на экране (s–e, секунды ролика), кегль и оформление как у частей заголовка.
List<Map<String, dynamic>> _textsOf(Object? v) {
  final out = <Map<String, dynamic>>[];
  if (v is! List) return out;
  for (final t in v.take(20)) {
    if (t is! Map) continue;
    final id = '${t['id'] ?? ''}';
    final text = '${t['text'] ?? ''}'.trim();
    if (!RegExp(r'^t[a-z0-9]{1,12}$').hasMatch(id) || text.isEmpty || out.any((x) => x['id'] == id)) continue;
    final s = (_num(t['s'], 0, 0, 600) * 10).round() / 10;
    out.add({
      'id': id,
      'text': text.length > 160 ? text.substring(0, 160) : text,
      'size': _num(t['size'], 110, 20, 400).roundToDouble(),
      's': s,
      'e': max(s + 0.3, (_num(t['e'], 3.3, 0, 600) * 10).round() / 10),
      'plate': t['plate'] == true,
      'plate_r': _num(t['plate_r'], 24, 0, 200).roundToDouble(),
      ..._partStyle(t),
    });
  }
  return out;
}

// Только изменённые части и с округлением, чтобы ключи предпросмотров не плодились.
Map<String, List<double>> _elOf(Object? v) {
  final out = <String, List<double>>{};
  if (v is! Map) return out;
  for (final role in v.keys.map((k) => '$k').where(layerKey.hasMatch)) {
    final e = v[role];
    if (e is! Map) continue;
    final t = [
      _num(e['x'], 0, -1080, 1080).roundToDouble(),
      _num(e['y'], 0, -1920, 1920).roundToDouble(),
      (_num(e['s'], 1, 0.2, 5) * 100).round() / 100,
      (_num(e['r'], 0, -180, 180) * 10).round() / 10,
    ];
    if (t[0] != 0 || t[1] != 0 || t[2] != 1 || t[3] != 0) out[role] = t;
  }
  return out;
}

class Look {
  Look(this.title, this.palette, this.subs,
      {this.zoom = true,
      this.grade = true,
      this.cta = true,
      this.plate = true,
      this.subColor = 'FFFFFF',
      this.outline = 'glow',
      this.outlineColor = '000000',
      this.tx = 0,
      this.ty = 0,
      this.ts = 1,
      this.tr = 0,
      this.hook = true,
      this.el = const {},
      this.plateX = 18,
      this.plateY = 18,
      this.plateR = 0,
      this.st = const {},
      this.texts = const [],
      this.plateColor,
      this.shadowColor = '000000',
      this.subHi,
      this.subFont,
      this.subSize,
      this.subY,
      this.subChunk,
      this.audioFix = true,
      this.animPreset});

  final String? animPreset;

  /// Анимация части заголовка по выбранному набору (null — как в шаблоне).
  String? presetAnim(String role) => animPresets[animPreset]?.$3[role];

  /// Чистый звук: ровная громкость и лёгкое шумоподавление.
  final bool audioFix;

  /// Сколько слов на экране вместо заданного стилем.
  final int? subChunk;

  /// Своё оформление отдельных надписей (styleRoles) поверх шаблона и палитры.
  final Map<String, Map<String, dynamic>> st;
  final List<Map<String, dynamic>> texts;

  /// Цвет плашки вместо цвета палитры; shadowColor — цвет мягкой тени субтитров; subHi — цвет текущего слова.
  final String? plateColor, subHi;
  final String shadowColor;

  /// Шрифт, кегль и высота субтитров вместо заданных стилем.
  final String? subFont;
  final double? subSize, subY;

  final TitlePreset title;
  final Palette palette;
  final SubStyle subs;
  final bool zoom, grade, cta, plate;

  /// Цвет букв субтитров; outline: glow — мягкая тень, stroke — чёткая обводка, none — без неё.
  final String subColor, outline, outlineColor;

  /// Положение заголовка, которое двигают руками: сдвиг в px холста 1080×1920,
  /// масштаб и поворот в градусах по часовой — вокруг центра заголовка.
  final double tx, ty, ts, tr;

  /// false — ролик без заголовка в начале.
  final bool hook;

  /// Отдельные части заголовка (lead, main, accent): [сдвиг x, сдвиг y, масштаб, поворот] вокруг центра части.
  final Map<String, List<double>> el;

  /// Плашка под главным словом: поля по бокам и сверху/снизу и радиус скругления, px холста.
  final double plateX, plateY, plateR;

  /// mix — разный заголовок и палитра для каждого ролика, чтобы ролики не были похожи.
  factory Look.from(Map? m, {String? variantId}) {
    m ??= const {};
    var title = titleById(m['title'] as String?);
    var pal = paletteById(m['palette'] as String?);
    if (m['mix'] == true && variantId != null) {
      final h = variantId.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
      title = titlePresets[h % titlePresets.length];
      pal = palettes[(h ~/ 7) % palettes.length];
    }
    return Look(title, pal, styleById((m['subs'] ?? m['style']) as String?),
        zoom: m['zoom'] != false,
        grade: m['grade'] != false,
        cta: m['cta'] != false,
        plate: m['plate'] == true,
        subColor: _hexOr(m['sub_color'], 'FFFFFF'),
        outline: subOutlines.contains(m['outline']) ? m['outline'] as String : 'glow',
        outlineColor: _hexOr(m['outline_color'], '000000'),
        tx: _num(m['title_x'], 0, -1080, 1080),
        ty: _num(m['title_y'], 0, -1920, 1920),
        ts: _num(m['title_s'], 1, 0.3, 3),
        tr: _num(m['title_r'], 0, -180, 180),
        hook: m['hook'] != false,
        el: _elOf(m['el']),
        plateX: _num(m['plate_px'], 18, 0, 200),
        plateY: _num(m['plate_py'], 18, 0, 150),
        plateR: _num(m['plate_r'], 0, 0, 200),
        st: _stOf(m['st']),
        texts: _textsOf(m['texts']),
        plateColor: _hexOpt(m['plate_color']),
        shadowColor: _hexOr(m['shadow_color'], '000000'),
        subHi: _hexOpt(m['sub_hi']),
        subFont: Fonts.has('${m['sub_font']}') ? '${m['sub_font']}' : null,
        subSize: m['sub_size'] == null ? null : _num(m['sub_size'], 68, 30, 160),
        subY: m['sub_y'] == null ? null : _num(m['sub_y'], 1480, 200, 1850),
        subChunk: m['sub_chunk'] == null ? null : _num(m['sub_chunk'], 2, 1, 6).round(),
        audioFix: m['audio_fix'] != false,
        animPreset: animPresets.containsKey(m['anim_preset']) ? m['anim_preset'] as String : null);
  }

  static Map<String, dynamic> normalize(Map? m) => {
        'title': titleById(m?['title'] as String?).id,
        'palette': paletteById(m?['palette'] as String?).id,
        'subs': styleById((m?['subs'] ?? m?['style']) as String?).id,
        'mix': m?['mix'] == true,
        'zoom': m?['zoom'] != false,
        'grade': m?['grade'] != false,
        'cta': m?['cta'] != false,
        'plate': m?['plate'] == true,
        'sub_color': _hexOr(m?['sub_color'], 'FFFFFF'),
        'outline': subOutlines.contains(m?['outline']) ? m!['outline'] : 'glow',
        'outline_color': _hexOr(m?['outline_color'], '000000'),
        // Округляем, чтобы едва заметное движение не плодило новые предпросмотры.
        'title_x': _num(m?['title_x'], 0, -1080, 1080).roundToDouble(),
        'title_y': _num(m?['title_y'], 0, -1920, 1920).roundToDouble(),
        'title_s': (_num(m?['title_s'], 1, 0.3, 3) * 100).round() / 100,
        'title_r': (_num(m?['title_r'], 0, -180, 180) * 10).round() / 10,
        'hook': m?['hook'] != false,
        'audio_fix': m?['audio_fix'] != false,
        if (animPresets.containsKey(m?['anim_preset'])) 'anim_preset': m?['anim_preset'],
        'plate_px': _num(m?['plate_px'], 18, 0, 200).roundToDouble(),
        'plate_py': _num(m?['plate_py'], 18, 0, 150).roundToDouble(),
        'plate_r': _num(m?['plate_r'], 0, 0, 200).roundToDouble(),
        'st': _stOf(m?['st']),
        'texts': _textsOf(m?['texts']),
        if (_hexOpt(m?['plate_color']) != null) 'plate_color': _hexOpt(m?['plate_color']),
        'shadow_color': _hexOr(m?['shadow_color'], '000000'),
        if (_hexOpt(m?['sub_hi']) != null) 'sub_hi': _hexOpt(m?['sub_hi']),
        if (Fonts.has('${m?['sub_font']}')) 'sub_font': '${m?['sub_font']}',
        if (m?['sub_size'] != null) 'sub_size': _num(m?['sub_size'], 68, 30, 160).roundToDouble(),
        if (m?['sub_y'] != null) 'sub_y': _num(m?['sub_y'], 1480, 200, 1850).roundToDouble(),
        if (m?['sub_chunk'] != null) 'sub_chunk': _num(m?['sub_chunk'], 2, 1, 6).round(),
        'el': {
          for (final e in _elOf(m?['el']).entries)
            e.key: {'x': e.value[0], 'y': e.value[1], 's': e.value[2], 'r': e.value[3]}
        },
      };
}

/// Части хука и надписей. Для старых вариантов без данных от AI собираем из hook_text.
Map<String, dynamic> designFor(Map? design, String hookText) {
  if (design != null && (design['hook_main'] ?? '').toString().trim().isNotEmpty) return design.cast();
  final words = hookText.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final mainCount = words.length <= 2 ? words.length : (words.last.length <= 4 ? 2 : 1);
  return {
    'hook_lead': words.take(words.length - mainCount).join(' '),
    'hook_main': words.skip(words.length - mainCount).join(' '),
    'hook_accent': '',
    'emphasis': const [],
    'cta_main': 'больше пользы',
    'cta_accent': 'в блоге',
  };
}

// ---------- Сборка ASS ----------

String _t(double sec) {
  final cs = (max(0.0, sec) * 100).round();
  final h = cs ~/ 360000, m = (cs ~/ 6000) % 60, s = (cs ~/ 100) % 60, c = cs % 100;
  String two(int x) => x.toString().padLeft(2, '0');
  return '$h:${two(m)}:${two(s)}.${two(c)}';
}

String _esc(String s) =>
    s.replaceAll('\\', '/').replaceAll('{', '(').replaceAll('}', ')').replaceAll('\n', ' ').trim();

/// HEX RRGGBB → цвет ASS &HBBGGRR&
String _c(String hex) => '&H${hex.substring(4, 6)}${hex.substring(2, 4)}${hex.substring(0, 2)}&';

String _norm(String w) => w.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]'), '').replaceAll('ё', 'е');

/// words — слова уже в шкале времени готового ролика.
/// part: all — всё; title — только заголовок в начале (слой, который двигают в окне оформления);
/// rest — всё, кроме него. box — сюда кладём рамку заголовка до сдвига/поворота.
String buildAss(List<Map<String, dynamic>> words, Look look, Map<String, dynamic> design, double total,
    {String part = 'all', Map<String, Map<String, double>>? box}) {
  final tp = look.title, pal = look.palette, st = look.subs;
  final b = StringBuffer()
    ..writeln('[Script Info]')
    ..writeln('ScriptType: v4.00+')
    ..writeln('PlayResX: 1080')
    ..writeln('PlayResY: 1920')
    ..writeln('WrapStyle: 2')
    ..writeln('ScaledBorderAndShadow: yes')
    ..writeln()
    ..writeln('[V4+ Styles]')
    ..writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, '
        'BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, '
        'BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding');
  // Тень у стилей выключена: мягкую тень рисуем отдельным размытым слоем (glow ниже),
  // жёсткая смещённая тень и выглядела «дёшево».
  void style(String name, String font, double size, {double spacing = 0}) =>
      b.writeln('Style: $name,${Fonts.of(font)},${size.round()},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,'
          '0,0,0,0,100,100,$spacing,0,1,0,0,5,0,0,0,1');
  style('Lead', tp.lead, 62, spacing: 3);
  style('Main', tp.main, tp.mainSize);
  final plate = look.plate ? (look.plateColor ?? pal.plate) : null;
  if (plate != null) {
    // BorderStyle 3 — сплошная плашка цвета OutlineColour, Outline — её поля.
    b.writeln('Style: MainBox,${Fonts.of(tp.main)},${tp.mainSize.round()},&H00FFFFFF,&H00FFFFFF,'
        '&H00${plate.substring(4, 6)}${plate.substring(2, 4)}${plate.substring(0, 2)},&H00000000,'
        '0,0,0,0,100,100,0,0,3,18,0,5,0,0,0,1');
  }
  style('Accent', tp.accent, tp.accentSize);
  style('Sub', look.subFont ?? st.font, look.subSize ?? st.size, spacing: st.spacing);
  style('Shade', 'inter-regular', 10);
  b
    ..writeln()
    ..writeln('[Events]')
    ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');

  var group = 'other';
  void ev(int layer, double s, double e, String style, String text) {
    if (e - s < 0.05 || text.isEmpty) return;
    // part: all, rest (всё кроме заголовка), title (весь заголовок) или одна его часть: lead / main / accent.
    final ok = switch (part) {
      'all' => true,
      'rest' => group == 'other',
      'title' => group.startsWith('hook'),
      _ => group == 'hook:$part' || group == 'layer:$part',
    };
    if (!ok) return;
    b.writeln('Dialogue: $layer,${_t(s)},${_t(e)},$style,,0,0,0,,$text');
  }

  // Текст + под ним размытая полупрозрачная копия: мягкое свечение вместо тени.
  void glow(int layer, double s, double e, String style, String tags, String text,
      {double blur = 14, String shade = '000000', bool shadow = true}) {
    ev(layer, s, e, style, '{$tags}$text');
    if (style == 'MainBox' || !shadow) return;
    final shadowTags = tags.replaceAll(RegExp(r'\\1c&H[0-9A-Fa-f]+&'), '');
    final plain = text.replaceAll(RegExp(r'\{[^}]*\}'), '');
    ev(layer - 1, s, e, style, '{$shadowTags\\1c${_c(shade)}\\1a&HA0&\\blur$blur}$plain');
  }

  // Мягкое затемнение верха кадра, пока висит заголовок, — текст читается на любом фоне.
  void topShade(double s, double e, double h) => ev(0, s, e, 'Shade',
      '{\\an7\\pos(0,0)\\1c&H000000&\\1a&H7A&\\blur90\\fad(200,300)\\p1}m 0 -200 l 1080 -200 l 1080 ${h.round()} l 0 ${h.round()}{\\p0}');

  // Маленькая строка + крупное слово (1–2 строки) + акцент.
  // Сначала раскладываем куски вокруг центра кадра, потом (для заголовка в начале) двигаем, масштабируем и крутим
  // всё вместе вокруг центра блока. Поворот каждого куска — вокруг его собственного центра, поэтому \org не нужен.
  void titleBlock(double s, double e, String lead, String main, String accent, double top,
      {bool hook = false, required String kind}) {
    Map<String, dynamic>? psOf(String role) =>
        look.st[kind == 'hook' ? role : '${kind}_$role'] ?? (kind == 'flash' ? look.st[role] : null);
    final psL = psOf('lead'), psM = psOf('main'), psA = psOf('accent');
    final mainFont = (psM?['font'] as String?) ?? tp.main, accFont = (psA?['font'] as String?) ?? tp.accent;
    main = _esc(tp.upper ? main.toUpperCase() : main);
    accent = _esc(accent);
    lead = _esc(lead);
    if (main.isEmpty) return;
    // Без прописи пропадает весь «дорогой» эффект: если AI её не дал, превращаем в неё короткую вводную.
    if (accent.isEmpty && lead.isNotEmpty && lead.split(' ').length <= 4) {
      accent = lead;
      lead = '';
    }

    // Свой шрифт — своя ширина букв, иначе длинное слово вылезло бы за кадр.
    final wk = psM?['font'] == null ? tp.widthK : _kOf(mainFont, main, tp.widthK);
    final ak = psA?['font'] == null ? tp.accentK : _kOf(accFont, accent, tp.accentK);
    final parts = main.split(RegExp(r'\s+'));
    var lines = [main];
    var size = min(tp.mainSize, _safeW / (main.length * wk));
    if (parts.length > 1 && size < tp.mainSize * 0.8) {
      // Два слова не влезают в строку крупно — переносим.
      final mid = (parts.length / 2).ceil();
      lines = [parts.take(mid).join(' '), parts.skip(mid).join(' ')];
      final longest = lines.map((l) => l.length).reduce(max);
      size = min(tp.mainSize, _safeW / (longest * wk));
    }
    // Блок заканчивается над головой (~780 px из 1920), иначе крупное короткое слово налезает на лицо.
    final roomH = 780 - top - (lead.isNotEmpty ? 70 : 0) - (accent.isNotEmpty ? tp.accentSize * 0.7 : 0);
    size = min(size, roomH / lines.length / 0.9);
    // Плашку рисуем сами (можно скруглить и задать поля), если знаем метрики шрифта, иначе — рамкой libass.
    final cap = plate != null ? Fonts.capBox(mainFont, size) : null;
    final mainStyle = plate != null && cap == null ? 'MainBox' : 'Main';
    final lineH = size * (tp.upper ? 0.86 : 0.98) + (plate == null ? 0 : (cap != null ? 2 * look.plateY + 4 : 40));
    // Пропись крупнее при коротком главном слове, но не шире кадра (буква прописи ≈ 0,5 кегля).
    final accSize = [
      tp.accentSize * 1.25,
      max(tp.accentSize * 0.85, size * 0.6),
      if (accent.isNotEmpty) 980 / (accent.length * ak),
    ].reduce(min);
    final track = size * tp.track;
    var y = top;
    final leadColor = _c((psL?['color'] as String?) ?? pal.main);
    final mainColor = _c((psM?['color'] as String?) ?? pal.main);
    final accColor = _c((psA?['color'] as String?) ?? pal.accent);
    // Шрифт и обводка надписи; у плашки рамкой libass своя обводка — её не трогаем.
    String deco(Map<String, dynamic>? ps, {bool box = false}) {
      if (ps == null) return '';
      final b = StringBuffer();
      if (ps['font'] != null) b.write('\\fn${Fonts.of(ps['font'] as String)}');
      final bord = (ps['bord'] as num?)?.toDouble() ?? 0;
      if (bord > 0 && !box) b.write('\\bord${bord.toStringAsFixed(1)}\\3c${_c((ps['bord_color'] as String?) ?? '000000')}');
      return b.toString();
    }
    final items = <_Piece>[];

    if (lead.isNotEmpty) {
      items.add(_Piece(6, s, e, 'Lead', lead, 540, y, 62, lead.length * 62 * 0.5, 62, role: 'lead',
          tags: '\\1c$leadColor${deco(psL)}\\fad(200,250)', blur: 8, fsp: 3, ps: psL));
      y += 70;
    }
    if (tp.accentAbove && accent.isNotEmpty) {
      y += accSize * 0.45;
      items.add(_Piece(8, s + 0.4, e, 'Accent', accent, 540, y, accSize, accent.length * accSize * ak, accSize,
          role: 'accent', tags: '\\1c$accColor${deco(psA)}\\fad(250,250)', ps: psA));
      y += accSize * 0.3;
    }
    for (final l in lines) {
      final tw = cap == null ? null : Fonts.width(mainFont, l, size, spacing: track);
      final w = tw != null ? tw + 2 * look.plateX : l.length * size * wk + (plate != null ? 36 : 0);
      items.add(_Piece(6, s + 0.1, e, mainStyle, l, 540, y + lineH / 2, size, w, lineH, role: 'main',
          tags: '\\1c$mainColor${deco(psM, box: mainStyle == 'MainBox')}\\fad(160,250)\\fscx94\\fscy94\\t(0,260,0.5,\\fscx100\\fscy100)',
          fsp: track,
          ps: psM,
          plate: tw != null && cap != null ? [w, cap.$1 + 2 * look.plateY, cap.$2, look.plateR] : null));
      y += lineH;
    }
    if (tp.accentBelow && accent.isNotEmpty) {
      items.add(_Piece(8, s + 0.4, e, 'Accent', accent, 540, y + accSize * 0.3, accSize,
          accent.length * accSize * ak, accSize, role: 'accent',
          tags: '\\1c$accColor${deco(psA)}\\fad(250,250)', ps: psA));
    } else if (!tp.accentAbove && accent.isNotEmpty) {
      // Пропись наезжает на правый низ крупного слова и проявляется слева направо, будто пишется.
      final mainW = lines.map((l) => l.length).reduce(max) * size * wk;
      final accW = accent.length * accSize * ak;
      final ax = min(_w - 40 - accW / 2, 540 + mainW * 0.5 - accW * 0.35);
      final ay = y - lineH * 0.15 + accSize * 0.3;
      items.add(_Piece(8, s + 0.45, e, 'Accent', accent, ax, ay, accSize, accW, accSize, role: 'accent',
          tags: '\\1c$accColor${deco(psA)}\\fad(60,250)', tilt: tp.tilt, reveal: true, ps: psA));
      y += accSize * 0.4;
    }

    // Рамки до трансформации — по ним приложение рисует ручки: всего блока и каждой части.
    Map<String, double> boxOf(Iterable<_Piece> ps) => {
          'x0': ps.map((it) => it.x - it.w / 2).reduce(min),
          'y0': ps.map((it) => it.y - it.h / 2).reduce(min),
          'x1': ps.map((it) => it.x + it.w / 2).reduce(max),
          'y1': ps.map((it) => it.y + it.h / 2).reduce(max),
        };
    final all = boxOf(items);
    final boxes = {
      for (final r in titleRoles)
        if (items.any((it) => it.role == r)) r: boxOf(items.where((it) => it.role == r)),
    };
    if (hook && box != null) box.addAll({'all': all, ...boxes});
    if (kind == 'cta' && box != null) box['cta'] = all;
    final x0 = all['x0']!, y0 = all['y0']!, x1 = all['x1']!, y1 = all['y1']!;

    // Финальную надпись двигают целиком, как весь заголовок.
    final bt = kind == 'cta' ? look.el['cta'] : null;
    final sc = hook ? look.ts : (bt?[2] ?? 1.0), rot = hook ? look.tr : (bt?[3] ?? 0.0);
    final ox = (x0 + x1) / 2, oy = (y0 + y1) / 2;
    final cx = ox + (hook ? look.tx : (bt?[0] ?? 0.0)), cy = oy + (hook ? look.ty : (bt?[1] ?? 0.0));
    String f1(double v) => v.toStringAsFixed(1);
    // Точка вокруг центра (ox, oy): масштаб, поворот по часовой (экран, y вниз), потом сдвиг.
    (double, double) tf(double x, double y, double ox, double oy, double s, double r, double dx, double dy) {
      final c = cos(r * pi / 180), sn = sin(r * pi / 180);
      final ux = (x - ox) * s, uy = (y - oy) * s;
      return (ox + dx + ux * c - uy * sn, oy + dy + ux * sn + uy * c);
    }

    for (final it in items) {
      // Сначала своя трансформация части, потом общая всего заголовка — так же собирает приложение.
      var px = it.x, py = it.y, s1 = 1.0, r1 = 0.0;
      final el = hook ? look.el[it.role] : null;
      final eb = boxes[it.role];
      if (el != null && eb != null) {
        (px, py) = tf(px, py, (eb['x0']! + eb['x1']!) / 2, (eb['y0']! + eb['y1']!) / 2, el[2], el[3], el[0], el[1]);
        s1 = el[2];
        r1 = el[3];
      }
      if (hook || bt != null) (px, py) = tf(px, py, ox, oy, sc, rot, cx - ox, cy - oy);
      final k = s1 * sc;
      group = hook ? 'hook:${it.role}' : kind == 'cta' ? 'layer:cta' : 'other';
      final frz = it.tilt - r1 - rot;
      final anim = (it.ps?['anim'] as String?) ?? look.presetAnim(it.role);
      final t = StringBuffer('\\an5${anim == null ? '\\pos(${px.round()},${py.round()})' : _animPos(anim, px, py)}'
          '\\fs${(it.fs * k).round()}');
      if (it.fsp != 0) t.write('\\fsp${f1(it.fsp * k)}');
      if (frz.abs() > 0.05) t.write('\\frz${f1(frz)}');
      if (it.style == 'MainBox' && k != 1) t.write('\\bord${f1(18 * k)}');
      t.write(anim == null ? it.tags : '${_stripIntro(it.tags)}${_animTags(anim, frz)}');
      if (it.reveal && anim == null) {
        final left = max(0, px - it.w * k / 2 - 20).round();
        t.write('\\clip($left,0,${left + 1},1920)\\t(0,600,\\clip(0,0,1080,1920))');
      }
      final pl = it.plate;
      if (pl != null && plate != null) {
        // Центр прописных букв ниже точки строки — сдвигаем плашку туда же с учётом поворота.
        final rr = (r1 + rot) * pi / 180;
        final ppx = px - pl[2] * k * sin(rr), ppy = py + pl[2] * k * cos(rr);
        final pw = pl[0] * k, ph = pl[1] * k, rad = min(pl[3] * k, min(pw, ph) / 2);
        // Слой ниже мягкой тени текста, иначе тень легла бы пятном поверх плашки.
        ev(it.layer - 2, it.s, it.e, 'Main',
            '{\\an5\\pos(${ppx.round()},${ppy.round()})${frz.abs() > 0.05 ? '\\frz${f1(frz)}' : ''}'
            '\\1c${_c((it.ps?['plate_color'] as String?) ?? plate)}\\bord0\\shad0\\blur0.6\\fad(160,250)\\fscx94\\fscy94\\t(0,260,0.5,\\fscx100\\fscy100)\\p1}'
            '${_roundRect(pw, ph, rad)}{\\p0}');
      }
      glow(it.layer, it.s, it.e, it.style, t.toString(), anim == null ? it.text : _perChar(anim, it.text),
          blur: it.blur * k,
          shade: (it.ps?['shadow_color'] as String?) ?? '000000',
          // Тень по буквам не анимируется — она появилась бы раньше самих букв.
          shadow: it.ps?['shadow'] != false && !_perCharAnims.contains(anim));
    }
    group = 'other';
    final bottom = hook || bt != null ? cy + (y1 - oy) * sc : y;
    topShade(s, e, (bottom + 140).clamp(300, 1400).toDouble());
  }

  // Заголовок в начале.
  final hookEnd = min(3.3, total);
  if (look.hook) titleBlock(0, hookEnd, (design['hook_lead'] ?? '').toString(), (design['hook_main'] ?? '').toString(),
      (design['hook_accent'] ?? '').toString(), 300,
      hook: true, kind: 'hook');

  // Финальная надпись.
  final ctaMain = (design['cta_main'] ?? '').toString();
  // Для слоя в окне оформления надпись показываем сразу, иначе её не видно на кадре из начала ролика.
  final forceCta = part == 'cta';
  final ctaStart = forceCta ? 0.0 : max(hookEnd + 0.5, total - 2.2);
  final showCta = look.cta && ctaMain.trim().isNotEmpty && (forceCta || box != null || total - ctaStart > 1.0);
  if (showCta) {
    final acc = (design['cta_accent'] ?? '').toString();
    titleBlock(ctaStart, forceCta ? 999 : total, '', ctaMain, acc, 300, kind: 'cta');
  }

  // Вспышки: главное слово крупно наверху в момент, когда его произносят.
  final flashes = <(double, double)>[];
  if (st.flashes) {
    for (final em in (design['emphasis'] as List? ?? const []).take(3)) {
      final word = (em is Map ? em['word'] : em)?.toString() ?? '';
      final key = _norm(word);
      if (key.isEmpty) continue;
      final hit = words.where((w) => w['x'] != true && _norm(w['w'] as String) == key && d(w['s']) > hookEnd + 0.2).firstOrNull;
      if (hit == null) continue;
      final s = d(hit['s']) - 0.05, e = min(s + 1.3, showCta ? ctaStart - 0.1 : total);
      if (flashes.any((f) => s < f.$2 + 0.3) || e - s < 0.6) continue;
      flashes.add((s, e));
      titleBlock(s, e, '', hit['w'] as String, (em is Map ? em['accent'] ?? '' : '').toString(), 330, kind: 'flash');
    }
  }

  // Свои надписи: по центру кадра, дальше их двигают руками (el[id]).
  for (final tx in look.texts) {
    final id = tx['id'] as String;
    final force = part == id;
    final s = force ? 0.0 : d(tx['s']), e = force ? 999.0 : min(d(tx['e']), total);
    final font = (tx['font'] as String?) ?? 'inter-semibold';
    final size = d(tx['size']);
    final lines = [for (final l in (tx['text'] as String).split('\n')) _esc(l)]..removeWhere((l) => l.isEmpty);
    if (lines.isEmpty) continue;
    final lw = lines.map((l) => Fonts.width(font, l, size) ?? l.length * size * 0.55).reduce(max);
    final plateOn = tx['plate'] == true;
    final w = lw + (plateOn ? size * 0.7 : 0), h = size * 1.15 * lines.length + (plateOn ? size * 0.36 : 0);
    const bx = 540.0, by = 960.0;
    box?[id] = {'x0': bx - w / 2, 'y0': by - h / 2, 'x1': bx + w / 2, 'y1': by + h / 2};
    final el = look.el[id];
    final sc = el?[2] ?? 1.0, rot = el?[3] ?? 0.0;
    final anim = (tx['anim'] as String?) ?? 'fade';
    final cx = bx + (el?[0] ?? 0.0), cy = by + (el?[1] ?? 0.0);
    final rz = rot.abs() > 0.05 ? '\\frz${(-rot).toStringAsFixed(1)}' : '';
    final pos = '\\an5\\pos(${cx.round()},${cy.round()})$rz';
    final apos = '\\an5${_animPos(anim, cx, cy)}$rz';
    group = 'layer:$id';
    if (plateOn) {
      final pw = w * sc, ph = h * sc, rad = min(d(tx['plate_r']) * sc, min(pw, ph) / 2);
      ev(5, s, e, 'Main', '{$pos\\1c${_c((tx['plate_color'] as String?) ?? '000000')}\\bord0\\shad0\\blur0.6\\fad(200,200)\\p1}'
          '${_roundRect(pw, ph, rad)}{\\p0}');
    }
    final bord = (tx['bord'] as num?)?.toDouble() ?? 0;
    glow(
        8,
        s,
        e,
        'Main',
        '$apos\\fn${Fonts.of(font)}\\fs${(size * sc).round()}\\fsp0\\1c${_c((tx['color'] as String?) ?? 'FFFFFF')}'
            '${bord > 0 ? '\\bord${(bord * sc).toStringAsFixed(1)}\\3c${_c((tx['bord_color'] as String?) ?? '000000')}' : ''}'
            '${_animTags(anim, -rot)}',
        _perChar(anim, lines.join('\\N')),
        blur: 10 * sc,
        shade: (tx['shadow_color'] as String?) ?? '000000',
        shadow: tx['shadow'] != false && !plateOn && !_perCharAnims.contains(anim));
  }
  group = 'other';

  // Субтитры.
  if (st.id == 'none') return b.toString();
  final chunkN = look.subChunk ?? st.chunk;
  final subSize = look.subSize ?? st.size;
  final subFont = look.subFont ?? st.font;
  double wOf(String t) => Fonts.width(subFont, st.upper ? t.toUpperCase() : t, subSize) ?? t.length * subSize * 0.55;
  // Если в редакторе в одно слово вписали несколько, делим его время между ними по длине —
  // иначе вся фраза висела бы на экране одним куском и вылезала за кадр.
  final flat = <Map<String, dynamic>>[];
  for (final w in words.where((w) => w['x'] != true)) {
    final parts = (w['w'] as String).trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (parts.length <= 1) {
      flat.add(w);
      continue;
    }
    final ws = d(w['s']), we = d(w['e']);
    final totalLen = parts.fold<int>(0, (a, x) => a + x.length);
    var t0 = ws;
    for (final x in parts) {
      final t1 = t0 + (we - ws) * x.length / totalLen;
      flat.add({'w': x, 's': t0, 'e': t1});
      t0 = t1;
    }
  }
  // Кусок на экране: не больше chunkN слов, не шире кадра, рвём на паузе и после точки.
  const maxW = 900.0;
  final chunks = <List<Map<String, dynamic>>>[];
  var cur = <Map<String, dynamic>>[];
  double curW() => cur.isEmpty ? 0 : wOf(cur.map((x) => x['w']).join(' '));
  for (final w in flat) {
    final shortPrev = cur.length == 1 && (cur.first['w'] as String).length <= 2;
    final full = cur.length >= chunkN && !shortPrev;
    final sentence = cur.isNotEmpty && chunkN > 2 && RegExp(r'[.!?…]$').hasMatch(cur.last['w'] as String);
    final tooWide = cur.isNotEmpty && chunkN > 1 && curW() + wOf(' ${w['w']}') > maxW * (chunkN > 3 ? 1.8 : 1);
    if (cur.isNotEmpty && (full || sentence || tooWide || d(w['s']) - d(cur.last['e']) > 0.6)) {
      chunks.add(cur);
      cur = [];
    }
    cur.add(w);
  }
  if (cur.isNotEmpty) chunks.add(cur);

  String text(List<Map<String, dynamic>> ch, int hi) {
    final out = <String>[];
    for (var j = 0; j < ch.length; j++) {
      var w = _esc(ch[j]['w'] as String);
      // Мелкие слова без точек на конце — так спокойнее, как в референсах.
      if (chunkN <= 2) w = w.replaceAll(RegExp(r'[.,!?…;:]+$'), '');
      if (st.upper) w = w.toUpperCase();
      out.add(j == hi ? '{\\1c${_c(look.subHi ?? pal.accent)}}$w{\\1c${_c(look.subColor)}}' : w);
    }
    // Длинную строку переносим на две примерно равные, а одно слово шире кадра уменьшаем.
    final plain = [for (final w in ch) w['w'] as String];
    final full = wOf(plain.join(' '));
    if (full > maxW && out.length > 1) {
      var best = 1, bestD = double.infinity;
      for (var j = 1; j < out.length; j++) {
        final dd = (wOf(plain.take(j).join(' ')) - wOf(plain.skip(j).join(' '))).abs();
        if (dd < bestD) {
          bestD = dd;
          best = j;
        }
      }
      return '${out.take(best).join(' ')}\\N${out.skip(best).join(' ')}';
    }
    if (full > maxW) return '{\\fscx${(maxW / full * 100).floor()}\\fscy${(maxW / full * 100).floor()}}${out.join(' ')}';
    return out.join(' ');
  }

  final pos = '\\an5\\pos(540,${(look.subY ?? st.y).round()})\\1c${_c(look.subColor)}';
  void sub(double s, double e, String txt) {
    switch (look.outline) {
      case 'none':
        ev(2, s, e, 'Sub', '{$pos}$txt');
      case 'stroke':
        // Лёгкое размытие края, иначе обводка на видео выглядит «пиксельной».
        ev(2, s, e, 'Sub', '{$pos\\bord${(subSize * 0.075).toStringAsFixed(1)}\\3c${_c(look.outlineColor)}\\blur0.6}$txt');
      default:
        glow(2, s, e, 'Sub', pos, txt, blur: 8, shade: look.shadowColor);
    }
  }

  for (var ci = 0; ci < chunks.length; ci++) {
    final ch = chunks[ci];
    final nextStart = ci + 1 < chunks.length ? d(chunks[ci + 1].first['s']) : total;
    final end = min(nextStart, d(ch.last['e']) + 0.35);
    if (!st.highlight) {
      sub(d(ch.first['s']), end, text(ch, -1));
    } else {
      for (var k = 0; k < ch.length; k++) {
        final s = d(ch[k]['s']);
        sub(s, k + 1 < ch.length ? d(ch[k + 1]['s']) : end, text(ch, k));
      }
    }
  }
  return b.toString();
}

/// Кусок заголовка до трансформации: центр (x, y), кегль, примерные ширина и высота.
class _Piece {
  _Piece(this.layer, this.s, this.e, this.style, this.text, this.x, this.y, this.fs, this.w, this.h,
      {required this.tags,
      required this.role,
      this.blur = 14,
      this.fsp = 0,
      this.tilt = 0,
      this.reveal = false,
      this.plate,
      this.ps});
  final int layer;
  final double s, e;
  final String style, text, tags, role;
  final double x, y, fs, w, h, blur, fsp, tilt;
  final bool reveal;

  /// Своя плашка: [ширина, высота, сдвиг центра букв вниз, радиус] до масштаба.
  final List<double>? plate;

  /// Своё оформление этой надписи (шрифт, цвета, тень, плашка).
  final Map<String, dynamic>? ps;
}

/// Средняя ширина буквы шрифта в долях кегля для этого текста.
double _kOf(String font, String text, double def) {
  if (text.isEmpty) return def;
  final w = Fonts.width(font, text, 100);
  return w == null ? def : w / 100 / text.length;
}

/// Прямоугольник со скруглёнными углами в разметке рисования ASS (\p1), начало в левом верхнем углу.
String _roundRect(double w, double h, double r) {
  String n(double v) => v.round().toString();
  if (r < 1) return 'm 0 0 l ${n(w)} 0 l ${n(w)} ${n(h)} l 0 ${n(h)}';
  final c = r * 0.448; // кривая Безье, близкая к четверти окружности: 1 − 0,552
  return 'm ${n(r)} 0 l ${n(w - r)} 0 b ${n(w - c)} 0 ${n(w)} ${n(c)} ${n(w)} ${n(r)} '
      'l ${n(w)} ${n(h - r)} b ${n(w)} ${n(h - c)} ${n(w - c)} ${n(h)} ${n(w - r)} ${n(h)} '
      'l ${n(r)} ${n(h)} b ${n(c)} ${n(h)} 0 ${n(h - c)} 0 ${n(h - r)} '
      'l 0 ${n(r)} b 0 ${n(c)} ${n(c)} 0 ${n(r)} 0';
}
