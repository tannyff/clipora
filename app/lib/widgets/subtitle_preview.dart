import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../theme.dart';
import 'color_picker.dart';
import 'ui.dart';

const defaultLook = <String, dynamic>{
  'title': 'narrow',
  'palette': 'burgundy',
  'subs': 'words_flash',
  'mix': false,
  'zoom': true,
  'grade': true,
  'cta': true,
  'plate': true,
  'sub_color': 'FFFFFF',
  'outline': 'glow',
  'outline_color': '000000',
  'title_x': 0.0,
  'title_y': 0.0,
  'title_s': 1.0,
  'title_r': 0.0,
  'hook': true,
  'el': <String, dynamic>{},
  'plate_px': 18.0,
  'plate_py': 18.0,
  'plate_r': 0.0,
  'st': <String, dynamic>{},
  'texts': <dynamic>[],
  'shadow_color': '000000',
  'audio_fix': true,
};

const _roleNames = {
  'all': 'Весь заголовок',
  'lead': 'Маленькая строка',
  'main': 'Главное слово',
  'accent': 'Пропись',
  'cta': 'Надпись в конце',
};
const _hookRoles = ['lead', 'main', 'accent'];
final _layerKey = RegExp(r'^(lead|main|accent|cta|t[a-z0-9]{1,12})$');

const _subColors = ['FFFFFF', '000000', 'FFE94D', 'FF5C9A', '8B6CFF', '5CD6FF', '3DDC97', 'FF8A3D'];

Color hex(String h) => Color(int.parse('FF$h', radix: 16));

/// Короткая подпись выбранного оформления для нижней панели.
String lookSummary(Map look, Map styles) {
  String nameOf(String list, String key) {
    final items = (styles[list] as List?) ?? const [];
    final it = items.cast<Map>().where((x) => x['id'] == look[key]).firstOrNull;
    return it?['name'] as String? ?? '';
  }

  if (look['mix'] == true) return 'Разное каждому ролику · ${nameOf('subs', 'subs')}';
  return '${nameOf('titles', 'title')} · ${nameOf('palettes', 'palette')} · ${nameOf('subs', 'subs')}';
}

/// Окно настройки оформления с живым предпросмотром первых секунд ролика.
Future<Map<String, dynamic>?> showLookDialog(
  BuildContext context, {
  required Map variant,
  required Map styles,
  required Map<String, dynamic> look,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _LookDialog(variant: variant, styles: styles, initial: look),
    );

class _LookDialog extends StatefulWidget {
  const _LookDialog({required this.variant, required this.styles, required this.initial});
  final Map variant;
  final Map styles;
  final Map<String, dynamic> initial;
  @override
  State<_LookDialog> createState() => _LookDialogState();
}

class _LookDialogState extends State<_LookDialog> {
  late final Map<String, dynamic> _look = {...defaultLook, ...widget.initial};
  VideoPlayerController? _video;
  String? _still;

  /// Кадр двумя слоями: фон с субтитрами и заголовок отдельно — его двигаем прямо здесь, без сервера.
  Map? _layers;
  bool _layersLoading = false;
  final _stackKey = GlobalKey();
  ({double x, double y, double s, double r})? _g0;
  Offset _p0 = Offset.zero;

  /// Что сейчас двигаем: all — весь заголовок, lead / main / accent — одну его часть.
  String _sel = 'main';
  bool _wantVideo = false;
  String? _error;
  final Map<String, List<Map>?> _grid = {'title': null, 'palette': null};
  final Map<String, int> _gridReq = {'title': 0, 'palette': 0};
  bool _muted = true;
  int _req = 0;
  Timer? _debounce, _textDeb;

  /// Пипетка включена: следующее нажатие на кадр берёт цвет и отдаёт сюда.
  void Function(String)? _eyeApply;
  final Map<String, TextEditingController> _textCtl = {};
  final Map<String, double> _drag = {};
  List<Map> _myLooks = [];

  @override
  void initState() {
    super.initState();
    _loadMyLooks();
    // Сначала большой кадр: у браузера мало соединений на сайт, сетки не должны его задерживать.
    _load().whenComplete(() {
      if (!mounted) return;
      _loadGrid('title');
      _loadGrid('palette');
    });
  }

  // Сетка показывает все заголовки при текущих цветах и все палитры при текущем заголовке.
  Future<void> _loadGrid(String vary) async {
    final my = _gridReq[vary]! + 1;
    _gridReq[vary] = my;
    // В initState setState вызывать нельзя, а там сетка и так пустая.
    if (_grid[vary] != null) setState(() => _grid[vary] = null);
    try {
      final id = widget.variant['id'] as String;
      final r = await Api.i.post('/api/variants/$id/preview-grid', {'look': _look, 'vary': vary});
      if (!mounted || my != _gridReq[vary]) return;
      setState(() => _grid[vary] = (r as List).cast<Map>());
    } catch (_) {
      if (mounted && my == _gridReq[vary]) setState(() => _grid[vary] = const []);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textDeb?.cancel();
    for (final c in _textCtl.values) {
      c.dispose();
    }
    _video?.dispose();
    super.dispose();
  }

  void _set(String k, Object v) {
    final old = _video;
    setState(() {
      _look[k] = v;
      _video = null;
      _still = null;
      _layersLoading = true;
      _wantVideo = false;
      _error = null;
    });
    old?.dispose();
    _debounce?.cancel();
    // Субтитры и наезды на верх кадра не влияют — сетки не пересобираем.
    final grids = const [
      'subs', 'zoom', 'cta', 'mix', 'sub_color', 'outline', 'outline_color', 'design', 'plate_px', 'plate_py', 'plate_r',
      'st', 'texts', 'shadow_color', 'sub_hi', 'sub_font', 'sub_size', 'sub_y', 'sub_chunk', 'anim_preset', 'audio_fix'
    ].contains(k)
        ? const <String>[]
        : [for (final g in const ['title', 'palette']) if (g != k) g];
    // Старые плитки сразу гасим, чтобы не путать, а собираем новые уже после большого кадра.
    for (final g in grids) {
      _gridReq[g] = _gridReq[g]! + 1;
      _grid[g] = null;
    }
    _debounce = Timer(const Duration(milliseconds: 150), () {
      _load().whenComplete(() {
        if (!mounted) return;
        for (final g in grids) {
          _loadGrid(g);
        }
      });
    });
  }

  void _playVideo() {
    setState(() {
      _wantVideo = true;
      _error = null;
    });
    _load();
  }

  // Сначала кадр (собирается почти мгновенно), видео — только по кнопке.
  Future<void> _load() async {
    final my = ++_req;
    final video = _wantVideo;
    try {
      final id = widget.variant['id'] as String;
      if (!video) {
        final r = await Api.i.post('/api/variants/$id/preview', {'look': _look, 'layers': true});
        if (!mounted || my != _req) return;
        // Обе картинки грузим заранее, чтобы слои сменились одновременно, без мигания.
        final box = (r['box'] as Map?) ?? const {};
        await Future.wait([
          for (final f in ['rest', for (final role in box.keys.map((k) => '$k')) if (_layerKey.hasMatch(role)) role])
            precacheImage(NetworkImage('${Api.i.previewUrl(id, r['key'] as String)}&f=$f'), context),
        ]);
        if (!mounted || my != _req) return;
        setState(() {
          _layers = r as Map;
          _layersLoading = false;
        });
        return;
      }
      final r = await Api.i.post('/api/variants/$id/preview', {'look': _look, 'video': video});
      if (!mounted || my != _req) return;
      final url = Api.i.previewUrl(id, r['key'] as String, video: video);
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      await vc.initialize();
      if (!mounted || my != _req) {
        await vc.dispose();
        return;
      }
      await vc.setLooping(true);
      await vc.setVolume(_muted ? 0 : 1);
      await vc.play();
      setState(() => _video = vc);
    } catch (e) {
      if (mounted && my == _req) {
        setState(() {
          _error = e.toString();
          _layersLoading = false;
        });
      }
    }
  }

  double _n(String k, double def) => (_look[k] as num?)?.toDouble() ?? def;

  double _wrap(double a) {
    while (a > 180) {
      a -= 360;
    }
    while (a < -180) {
      a += 360;
    }
    // Прилипает к ровному положению, иначе ровно поставить почти невозможно.
    return a.abs() < 3 ? 0.0 : a;
  }

  /// Сдвиг, масштаб и поворот части [role] или всего заголовка (all).
  ({double x, double y, double s, double r}) _tfOf(String role) {
    if (role == 'all') return (x: _n('title_x', 0), y: _n('title_y', 0), s: _n('title_s', 1), r: _n('title_r', 0));
    final e = ((_look['el'] as Map?)?[role] as Map?) ?? const {};
    double v(String k, double d) => (e[k] as num?)?.toDouble() ?? d;
    return (x: v('x', 0), y: v('y', 0), s: v('s', 1), r: v('r', 0));
  }

  void _setTf(String role, {double? x, double? y, double? s, double? r}) {
    // Видео собрано со старым положением — убираем, кадр со слоями покажет новое сразу.
    final old = _video;
    setState(() {
      if (role == 'all') {
        if (x != null) _look['title_x'] = x;
        if (y != null) _look['title_y'] = y;
        if (s != null) _look['title_s'] = s.clamp(0.3, 3.0);
        if (r != null) _look['title_r'] = _wrap(r);
      } else {
        final el = {...((_look['el'] as Map?) ?? const {})};
        final e = {...((el[role] as Map?) ?? const {})};
        if (x != null) e['x'] = x;
        if (y != null) e['y'] = y;
        if (s != null) e['s'] = s.clamp(0.2, 5.0);
        if (r != null) e['r'] = _wrap(r);
        el[role] = e;
        _look['el'] = el;
      }
      _video = null;
      _wantVideo = false;
    });
    old?.dispose();
  }

  void _resetTf() {
    final old = _video;
    setState(() {
      _look
        ..['title_x'] = 0.0
        ..['title_y'] = 0.0
        ..['title_s'] = 1.0
        ..['title_r'] = 0.0
        ..['el'] = <String, dynamic>{};
      _video = null;
      _wantVideo = false;
    });
    old?.dispose();
  }

  Future<void> _editTitle() async {
    final d = (_layers?['design'] as Map?) ?? const {};
    final lead = TextEditingController(text: '${d['hook_lead'] ?? ''}');
    final main = TextEditingController(text: '${d['hook_main'] ?? ''}');
    final acc = TextEditingController(text: '${d['hook_accent'] ?? ''}');
    final ctaMain = TextEditingController(text: '${d['cta_main'] ?? ''}');
    final ctaAcc = TextEditingController(text: '${d['cta_accent'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Текст надписей'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Заголовок в начале', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(controller: lead, decoration: const InputDecoration(labelText: 'Маленькая строка сверху')),
            const SizedBox(height: 16),
            TextField(controller: main, autofocus: true, decoration: const InputDecoration(labelText: 'Главное крупное слово')),
            const SizedBox(height: 16),
            TextField(controller: acc, decoration: const InputDecoration(labelText: 'Пропись (рукописный акцент)')),
            const SizedBox(height: 18),
            const Text('Надпись в конце', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(controller: ctaMain, decoration: const InputDecoration(labelText: 'Крупно, например «больше пользы»')),
            const SizedBox(height: 16),
            TextField(controller: ctaAcc, decoration: const InputDecoration(labelText: 'Пропись, например «в блоге»')),
            const SizedBox(height: 8),
            const Text('Пустое поле — этой части не будет. Текст меняется только у этого ролика. '
                'Убрать заголовок или надпись в конце целиком — переключателями в окне оформления.',
                style: TextStyle(color: C.muted, fontSize: 12)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (main.text.trim().isEmpty) {
      toast(context, 'Главное слово не может быть пустым');
      return;
    }
    try {
      await Api.i.put('/api/variants/${widget.variant['id']}/design',
          {
            'hook_lead': lead.text,
            'hook_main': main.text,
            'hook_accent': acc.text,
            'cta_main': ctaMain.text,
            'cta_accent': ctaAcc.text,
          });
      if (!mounted) return;
      // Старые плитки сетки собраны со старым текстом.
      _set('design', DateTime.now().millisecondsSinceEpoch);
      _look.remove('design');
      _loadGrid('title');
      _loadGrid('palette');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  List<Map> _list(String k) => ((widget.styles[k] as List?) ?? const []).cast<Map>();

  // ---------- Мои стили ----------

  Future<void> _loadMyLooks() async {
    try {
      final r = await Api.i.get('/api/looks') as List;
      if (mounted) setState(() => _myLooks = r.cast<Map>());
    } catch (_) {}
  }

  void _applyMyLook(Map look) {
    setState(() => _look
      ..clear()
      ..addAll({...defaultLook, ...(look as Map).cast<String, dynamic>()}));
    _set('design', DateTime.now().millisecondsSinceEpoch);
    _look.remove('design');
    _loadGrid('title');
    _loadGrid('palette');
  }

  Future<void> _saveMyLook() async {
    final ctl = TextEditingController(text: 'Мой стиль ${_myLooks.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранить как мой стиль'),
        content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(helperText: 'То же имя — стиль обновится'),
            onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await Api.i.post('/api/looks', {'name': name.trim(), 'look': _look});
      await _loadMyLooks();
      if (mounted) toast(context, 'Стиль «${name.trim()}» сохранён — он есть в оформлении любого ролика');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _deleteMyLook(Map l) async {
    try {
      await Api.i.delete('/api/looks/${l['id']}');
      await _loadMyLooks();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Widget _myLooksRow() => Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final l in _myLooks)
          InputChip(
            label: Text('${l['name']}'),
            onPressed: () => _applyMyLook(l['look'] as Map),
            onDeleted: () => _deleteMyLook(l),
            deleteIconColor: C.faint,
          ),
        OutlinedButton.icon(
          onPressed: _saveMyLook,
          icon: const Icon(Icons.bookmark_add_outlined, size: 17),
          label: const Text('Сохранить как мой стиль'),
        ),
      ]);

  Widget _animDrop(String? value, void Function(String?) apply, {String empty = 'Как в наборе'}) {
    final items = _list('anims');
    return DropdownButton<String?>(
      value: items.any((a) => a['id'] == value) ? value : null,
      isDense: true,
      hint: Text('Анимация: $empty', style: const TextStyle(fontSize: 12.5)),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(empty, style: const TextStyle(fontSize: 12.5))),
        for (final a in items)
          DropdownMenuItem<String?>(
              value: a['id'] as String, child: Text('${a['name']}', style: const TextStyle(fontSize: 12.5))),
      ],
      onChanged: apply,
    );
  }

  // ---------- Оформление отдельных надписей ----------

  Map<String, dynamic> _stGet(String key) =>
      {...(((_look['st'] as Map?)?[key] as Map?) ?? const {})}.cast<String, dynamic>();

  void _stSet(String key, String field, Object? v) {
    final st = {...((_look['st'] as Map?) ?? const {})};
    final e = {...((st[key] as Map?) ?? const {})};
    if (v == null) {
      e.remove(field);
    } else {
      e[field] = v;
    }
    if (e.isEmpty) {
      st.remove(key);
    } else {
      st[key] = e;
    }
    _set('st', st);
  }

  List<Map<String, dynamic>> _texts() =>
      [for (final t in ((_look['texts'] as List?) ?? const [])) {...(t as Map)}.cast<String, dynamic>()];

  void _textSet(String id, String field, Object? v) {
    final list = _texts();
    for (final t in list) {
      if (t['id'] != id) continue;
      if (v == null) {
        t.remove(field);
      } else {
        t[field] = v;
      }
    }
    _set('texts', list);
  }

  void _addText() {
    final id = 't${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final dur = (widget.variant['duration'] as num?)?.toDouble() ?? 10;
    final list = [
      ..._texts(),
      {'id': id, 'text': 'Новая надпись', 'size': 110.0, 's': 0.0, 'e': math.min(3.3, dur)},
    ];
    _sel = id;
    _set('texts', list);
  }

  void _deleteText(String id) {
    final el = {...((_look['el'] as Map?) ?? const {})}..remove(id);
    _look['el'] = el;
    _textCtl.remove(id)?.dispose();
    _sel = 'main';
    _set('texts', [for (final t in _texts()) if (t['id'] != id) t]);
  }

  String _roleName(String r) {
    if (_roleNames[r] != null) return _roleNames[r]!;
    final t = _texts().where((x) => x['id'] == r).firstOrNull;
    final txt = '${t?['text'] ?? 'Надпись'}'.replaceAll('\n', ' ');
    return txt.length > 16 ? '${txt.substring(0, 16)}…' : txt;
  }

  /// Кнопка цвета: круг и подпись. Пипетка закрывает окно и ждёт нажатия на кадр.
  Widget _colorBtn(String label, String? value, void Function(String?) apply,
      {String def = 'FFFFFF', bool clearable = false}) {
    final v = value ?? def;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final r = await pickColor(context, initial: v, eyedropper: _layers != null && _video == null);
        if (r == null || !mounted) return;
        if (r == eyedropperResult) {
          setState(() => _eyeApply = apply);
          return;
        }
        apply(r);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
        decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value == null && clearable ? null : hexColor(v),
              shape: BoxShape.circle,
              border: Border.all(color: C.border),
            ),
            child: value == null && clearable ? const Icon(Icons.auto_awesome_outlined, size: 12, color: C.muted) : null,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5)),
          if (clearable && value != null) ...[
            const SizedBox(width: 4),
            InkWell(onTap: () => apply(null), child: const Icon(Icons.close_rounded, size: 14, color: C.muted)),
          ],
        ]),
      ),
    );
  }

  Widget _fontBtn(String? font, void Function(String?) apply, {String sample = 'Аа'}) {
    final fonts = _list('fonts');
    final name = fonts.where((f) => f['id'] == font).firstOrNull?['name'] as String?;
    return OutlinedButton(
      onPressed: fonts.isEmpty
          ? null
          : () async {
              final r = await pickFont(context, fonts, font);
              if (r == null || !mounted) return;
              apply(r.isEmpty ? null : r);
            },
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (font != null)
          FutureBuilder(
            future: ensureFont(font),
            builder: (_, snap) => Text(sample,
                style: TextStyle(
                    fontFamily: snap.connectionState == ConnectionState.done ? 'cf_$font' : null, fontSize: 16)),
          ),
        if (font != null) const SizedBox(width: 8),
        Text(name ?? 'Шрифт: как в шаблоне', style: const TextStyle(fontSize: 12.5)),
      ]),
    );
  }

  // Пока тянешь — только число; кадр пересобирается, когда отпустишь.
  Widget _miniSlider(String id, String label, double value, double min, double max, void Function(double) apply) {
    final v = (_drag[id] ?? value).clamp(min, max).toDouble();
    return Row(children: [
      SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12.5, color: C.muted))),
      Expanded(
        child: Slider(
          value: v,
          min: min,
          max: max,
          activeColor: C.violet,
          onChanged: (x) => setState(() => _drag[id] = x.roundToDouble()),
          onChangeEnd: (x) {
            _drag.remove(id);
            apply(x.roundToDouble());
          },
        ),
      ),
      SizedBox(width: 34, child: Text('${v.round()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
    ]);
  }

  /// Шрифт, цвет букв, обводка, тень и плашка одной надписи. ps — текущие значения, set — сохранить поле.
  Widget _styleFields(String id, Map ps, void Function(String, Object?) set, {bool plateField = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _fontBtn(ps['font'] as String?, (f) => set('font', f)),
          _colorBtn('Буквы', ps['color'] as String?, (h) => set('color', h), clearable: true),
          _colorBtn('Обводка', ps['bord_color'] as String?, (h) => set('bord_color', h), def: '000000', clearable: true),
          _colorBtn('Тень', ps['shadow_color'] as String?, (h) => set('shadow_color', h), def: '000000', clearable: true),
          if (plateField)
            _colorBtn('Плашка', ps['plate_color'] as String?, (h) => set('plate_color', h), def: '000000', clearable: true),
          _animDrop(ps['anim'] as String?, (a) => set('anim', a), empty: id.startsWith('t') ? 'Проявление' : 'Как в наборе'),
          FilterChip(
            label: const Text('Тень', style: TextStyle(fontSize: 12)),
            selected: ps['shadow'] != false,
            onSelected: (v) => set('shadow', v ? null : false),
            selectedColor: C.violet.withValues(alpha: 0.25),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
        ]),
        _miniSlider('$id/bord', 'Толщина обводки', (ps['bord'] as num?)?.toDouble() ?? 0, 0, 30,
            (v) => set('bord', v == 0 ? null : v)),
      ]);

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  /// Настройки выбранной надписи под предпросмотром.
  Widget _selectedPanel(String sel) {
    if (sel == 'all') return const SizedBox.shrink();
    if (_hookRoles.contains(sel)) {
      return _section(_roleName(sel),
          _styleFields(sel, _stGet(sel), (f, v) => _stSet(sel, f, v), plateField: sel == 'main'));
    }
    if (sel == 'cta') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _section('Надпись в конце — крупно',
            _styleFields('cta_main', _stGet('cta_main'), (f, v) => _stSet('cta_main', f, v), plateField: true)),
        _section('Надпись в конце — пропись',
            _styleFields('cta_accent', _stGet('cta_accent'), (f, v) => _stSet('cta_accent', f, v))),
      ]);
    }
    final t = _texts().where((x) => x['id'] == sel).firstOrNull;
    if (t == null) return const SizedBox.shrink();
    final ctl = _textCtl[sel] ??= TextEditingController(text: '${t['text']}');
    final total = math.max(1.0, (widget.variant['duration'] as num?)?.toDouble() ?? 30);
    final s0 = ((t['s'] as num?)?.toDouble() ?? 0).clamp(0.0, total).toDouble();
    final e0 = ((t['e'] as num?)?.toDouble() ?? 3.3).clamp(s0, total).toDouble();
    return _section('Своя надпись', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: ctl,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Текст (Enter — новая строка)', isDense: true),
        onChanged: (v) {
          _textDeb?.cancel();
          _textDeb = Timer(const Duration(milliseconds: 600), () {
            if (mounted && v.trim().isNotEmpty) _textSet(sel, 'text', v);
          });
        },
      ),
      const SizedBox(height: 8),
      _styleFields(sel, t, (f, v) => _textSet(sel, f, v), plateField: true),
      _miniSlider('$sel/size', 'Размер', (t['size'] as num?)?.toDouble() ?? 110, 30, 300, (v) => _textSet(sel, 'size', v)),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Плашка под надписью', style: TextStyle(fontSize: 13)),
        value: t['plate'] == true,
        activeColor: C.violet,
        onChanged: (v) => _textSet(sel, 'plate', v),
      ),
      if (t['plate'] == true)
        _miniSlider('$sel/pr', 'Скругление', (t['plate_r'] as num?)?.toDouble() ?? 24, 0, 120,
            (v) => _textSet(sel, 'plate_r', v)),
      Text('На экране: с ${s0.toStringAsFixed(1)} по ${e0.toStringAsFixed(1)} с',
          style: const TextStyle(fontSize: 12.5, color: C.muted)),
      RangeSlider(
        values: RangeValues(s0, e0),
        min: 0,
        max: total,
        activeColor: C.violet,
        onChanged: (v) => setState(() {
          final list = _texts();
          for (final x in list) {
            if (x['id'] == sel) {
              x['s'] = (v.start * 10).round() / 10;
              x['e'] = (v.end * 10).round() / 10;
            }
          }
          _look['texts'] = list;
        }),
        onChangeEnd: (_) => _set('texts', _texts()),
      ),
      TextButton.icon(
        onPressed: () => _deleteText(sel),
        icon: const Icon(Icons.delete_outline_rounded, size: 17, color: C.red),
        label: const Text('Удалить надпись', style: TextStyle(color: C.red)),
      ),
    ]));
  }

  Future<ui.Image> _image(String url) {
    final c = Completer<ui.Image>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!c.isCompleted) c.complete(info.image);
      stream.removeListener(l);
    }, onError: (Object e, _) {
      if (!c.isCompleted) c.completeError(e);
      stream.removeListener(l);
    });
    stream.addListener(l);
    return c.future;
  }

  /// Пипетка: цвет пикселя кадра под пальцем.
  Future<void> _sample(Offset p, Size sz) async {
    final apply = _eyeApply, layers = _layers;
    if (apply == null || layers == null) return;
    final url = '${Api.i.previewUrl(widget.variant['id'] as String, layers['key'] as String)}&f=rest';
    try {
      final img = await _image(url);
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null || !mounted) return;
      final x = (p.dx / sz.width * img.width).floor().clamp(0, img.width - 1);
      final y = (p.dy / sz.height * img.height).floor().clamp(0, img.height - 1);
      final i = (y * img.width + x) * 4;
      String two(int v) => v.toRadixString(16).padLeft(2, '0');
      final h = '${two(bd.getUint8(i))}${two(bd.getUint8(i + 1))}${two(bd.getUint8(i + 2))}'.toUpperCase();
      rememberColor(h);
      setState(() => _eyeApply = null);
      apply(h);
    } catch (e) {
      if (mounted) toast(context, 'Не получилось взять цвет: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > 760;
    final videoH = (wide ? size.height * 0.72 : size.height * 0.45).clamp(240.0, 680.0);
    final mix = _look['mix'] == true;

    final player = Center(
      child: SizedBox(
        height: videoH,
        width: videoH * 9 / 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(color: Colors.black, child: _player()),
        ),
      ),
    );

    final moved = _n('title_x', 0) != 0 ||
        _n('title_y', 0) != 0 ||
        _n('title_s', 1) != 1 ||
        _n('title_r', 0) != 0 ||
        ((_look['el'] as Map?)?.isNotEmpty ?? false);
    final lbox = (_layers?['box'] as Map?) ?? const {};
    final layerRoles = [for (final r in lbox.keys.map((k) => '$k')) if (_layerKey.hasMatch(r)) r];
    final roles = [if (lbox['all'] != null && _look['hook'] != false) 'all', ...layerRoles];
    final canMove = !mix && roles.isNotEmpty;
    final selNow = roles.contains(_sel) ? _sel : (roles.contains('main') ? 'main' : (roles.isEmpty ? 'all' : roles.first));
    final titleTools = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(children: [
        if (canMove) ...[
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final r in roles)
              ChoiceChip(
                label: Text(_roleName(r), style: const TextStyle(fontSize: 12)),
                selected: selNow == r,
                onSelected: (_) => setState(() => _sel = r),
                selectedColor: C.violet.withValues(alpha: 0.25),
                side: BorderSide(color: selNow == r ? C.violet : C.border),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
          ]),
          const SizedBox(height: 8),
        ],
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: _layers == null ? null : _editTitle,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Текст надписей'),
          ),
          OutlinedButton.icon(
            onPressed: _layers == null || mix ? null : _addText,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Надпись'),
          ),
          if (moved)
            TextButton.icon(
              onPressed: _resetTf,
              icon: const Icon(Icons.restart_alt_rounded, size: 17),
              label: const Text('Вернуть на место'),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          mix
              ? 'При «Разном оформлении» заголовок не двигается.'
              : 'Нажми на надпись и тяни, чтобы подвинуть. Фиолетовая ручка — размер и поворот, '
                  'на телефоне можно двумя пальцами. Ниже — шрифт и цвета выбранной надписи.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontSize: 12),
        ),
        if (canMove) Align(alignment: Alignment.centerLeft, child: _selectedPanel(selNow)),
      ]),
    );

    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _label('Мои стили — нажми, чтобы применить'),
      _myLooksRow(),
      const SizedBox(height: 6),
      _switch('Заголовок в начале', 'hook'),
      if (_look['hook'] != false) ...[
        _label(mix ? 'Заголовок — у каждого ролика свой' : 'Заголовок — нажми на понравившийся'),
        _gridView('title', 'titles', mix),
      ],
      _label('Анимация надписей'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ChoiceChip(
          label: const Text('Как в шаблоне'),
          selected: _look['anim_preset'] == null,
          onSelected: (_) => _unset('anim_preset'),
          selectedColor: C.violet.withValues(alpha: 0.25),
          showCheckmark: false,
        ),
        for (final a in _list('anim_presets'))
          Tooltip(
            message: '${a['description']}',
            child: ChoiceChip(
              label: Text('${a['name']}'),
              selected: _look['anim_preset'] == a['id'],
              onSelected: (_) => _set('anim_preset', a['id'] as String),
              selectedColor: C.violet.withValues(alpha: 0.25),
              showCheckmark: false,
            ),
          ),
      ]),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Свою анимацию для любой надписи выбери под кадром, нажав на надпись. Посмотреть — «Видео с анимацией».',
            style: TextStyle(color: C.faint, fontSize: 12)),
      ),
      _label(mix ? 'Цвета — у каждого ролика свои' : 'Цвета'),
      _gridView('palette', 'palettes', mix),
      _label('Субтитры'),
      _chips('subs', 'subs'),
      if (_look['subs'] != 'none') ...[
        _label('Шрифт и размер'),
        Align(
            alignment: Alignment.centerLeft,
            child: _fontBtn(_look['sub_font'] as String?, (f) => f == null ? _unset('sub_font') : _set('sub_font', f),
                sample: 'Субтитры')),
        _miniSlider('sub_size', 'Размер', (_look['sub_size'] as num?)?.toDouble() ?? 68, 36, 140, (v) => _set('sub_size', v)),
        _label('Слов на экране'),
        Wrap(spacing: 8, children: [
          for (final n in const [1, 2, 3, 4, 6])
            ChoiceChip(
              label: Text('$n'),
              selected: (_look['sub_chunk'] as num?)?.toInt() == n,
              onSelected: (v) => v ? _set('sub_chunk', n) : _unset('sub_chunk'),
              selectedColor: C.violet.withValues(alpha: 0.25),
              showCheckmark: false,
            ),
        ]),
        _miniSlider('sub_y', 'Высота на экране', (_look['sub_y'] as num?)?.toDouble() ?? 1480, 900, 1850,
            (v) => _set('sub_y', v)),
        _label('Цвет букв'),
        _colors('sub_color'),
        if (_look['subs'] == 'caps') ...[
          _label('Цвет текущего слова'),
          _colorBtn('Цвет', _look['sub_hi'] as String?, (h) => h == null ? _unset('sub_hi') : _set('sub_hi', h),
              clearable: true),
        ],
        _label('Обводка'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, name) in const [('glow', 'Мягкая тень'), ('stroke', 'Чёткая обводка'), ('none', 'Без обводки')])
            ChoiceChip(
              label: Text(name),
              selected: _look['outline'] == id,
              onSelected: _look['outline'] == id ? null : (_) => _set('outline', id),
              selectedColor: C.violet.withValues(alpha: 0.25),
              side: BorderSide(color: _look['outline'] == id ? C.violet : C.border),
              showCheckmark: false,
            ),
        ]),
        if (_look['outline'] == 'stroke') ...[
          _label('Цвет обводки'),
          _colors('outline_color'),
        ],
        if (_look['outline'] == 'glow') ...[
          _label('Цвет тени'),
          _colors('shadow_color'),
        ],
      ],
      const SizedBox(height: 8),
      _switch('Разное оформление каждому ролику', 'mix'),
      _switch('Плашка под главным словом', 'plate'),
      if (_look['plate'] == true) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: _colorBtn('Цвет плашки', _look['plate_color'] as String?,
              (h) => h == null ? _unset('plate_color') : _set('plate_color', h),
              def: '000000', clearable: true),
        ),
        const SizedBox(height: 6),
        _slider('Ширина плашки', 'plate_px', 0, 120),
        _slider('Высота плашки', 'plate_py', 0, 90),
        _slider('Скругление углов', 'plate_r', 0, 120),
      ],
      _switch('Наезды на склейках', 'zoom'),
      _switch('Тёплая обработка', 'grade'),
      _switch('Чистый звук (ровная громкость и меньше шума)', 'audio_fix'),
      _switch('Надпись в конце (призыв подписаться)', 'cta'),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => Navigator.pop(context, _look),
        style: FilledButton.styleFrom(
          backgroundColor: C.violet,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Готово', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ]);

    return Dialog(
      backgroundColor: C.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 1240 : 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Оформление роликов', style: t.titleMedium)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: C.muted)),
            ]),
            Text(
                'Предпросмотр: кадр и первые 8 секунд «${widget.variant['hook_text']}».'
                '${mix ? ' Здесь показан один из вариантов — у каждого ролика будет свой.' : ''}',
                style: t.bodySmall),
            const SizedBox(height: 14),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(mainAxisSize: MainAxisSize.min, children: [player, SizedBox(width: videoH * 9 / 16, child: titleTools)]),
                const SizedBox(width: 22),
                Expanded(child: controls),
              ])
            else ...[
              player,
              titleTools,
              const SizedBox(height: 14),
              controls,
            ],
          ]),
        ),
      ),
    );
  }

  Widget _gridView(String vary, String list, bool disabled) {
    final items = _grid[vary];
    if (items == null) {
      return const SizedBox(
          height: 120, child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final names = {for (final x in _list(list)) x['id']: x['name']};
    final id = widget.variant['id'] as String;
    // Показываем верх кадра — там заголовок, так он крупнее и его легче сравнивать.
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Wrap(spacing: 10, runSpacing: 12, children: [
        for (final it in items)
          SizedBox(
            width: 150,
            child: InkWell(
              onTap: disabled || _look[vary] == it['id'] ? null : () => _set(vary, it['id'] as String),
              borderRadius: BorderRadius.circular(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: !disabled && _look[vary] == it['id'] ? C.violet : C.border,
                        width: !disabled && _look[vary] == it['id'] ? 2.5 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AspectRatio(
                    aspectRatio: 1,
                    // Плитки собираются на сервере в фоне — каждая появляется, как только готова.
                    child: Image.network(Api.i.previewUrl(id, it['key'] as String),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        frameBuilder: (_, child, frame, sync) => frame != null || sync
                            ? child
                            : const ColoredBox(
                                color: C.surface2,
                                child: Center(
                                    child: SizedBox(
                                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                              ),
                        errorBuilder: (_, __, ___) => const ColoredBox(
                            color: C.surface2,
                            child: Center(child: Icon(Icons.refresh_rounded, color: C.faint, size: 20)))),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${names[it['id']] ?? ''}',
                    maxLines: 2, style: const TextStyle(fontSize: 12, color: C.muted, height: 1.2)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(s, style: const TextStyle(color: C.muted, fontSize: 13)),
      );

  void _unset(String k) {
    _look.remove(k);
    _set('design', DateTime.now().millisecondsSinceEpoch);
    _look.remove('design');
  }

  Widget _colors(String key) => Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _colorBtn('Любой', _subColors.contains(_look[key]) ? null : _look[key] as String?, (h) => _set(key, h ?? 'FFFFFF'),
            clearable: false),
        for (final h in _subColors)
          InkWell(
            onTap: _look[key] == h ? null : () => _set(key, h),
            customBorder: const CircleBorder(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: hex(h),
                shape: BoxShape.circle,
                border: Border.all(color: _look[key] == h ? C.violet : C.border, width: _look[key] == h ? 3 : 1),
              ),
            ),
          ),
      ]);

  Widget _dot(Color c) => Container(width: 22, height: 22, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _chips(String list, String key, {bool disabled = false}) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in _list(list))
          Tooltip(
            message: s['description'] as String? ?? '',
            child: ChoiceChip(
              label: Text(s['name'] as String),
              selected: !disabled && _look[key] == s['id'],
              onSelected: disabled || _look[key] == s['id'] ? null : (_) => _set(key, s['id'] as String),
              selectedColor: C.violet.withValues(alpha: 0.25),
              side: BorderSide(color: !disabled && _look[key] == s['id'] ? C.violet : C.border),
              showCheckmark: false,
            ),
          ),
      ]);

  // Пока тянешь — только число, кадр пересобирается, когда отпустишь.
  Widget _slider(String label, String key, double min, double max) {
    final v = ((_look[key] as num?)?.toDouble() ?? 0).clamp(min, max);
    return Row(children: [
      SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 13, color: C.muted))),
      Expanded(
        child: Slider(
          value: v,
          min: min,
          max: max,
          activeColor: C.violet,
          onChanged: (x) => setState(() => _look[key] = x.roundToDouble()),
          onChangeEnd: (x) => _set(key, x.roundToDouble()),
        ),
      ),
      SizedBox(width: 32, child: Text('${v.round()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
    ]);
  }

  Widget _switch(String label, String key) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label, style: const TextStyle(fontSize: 14)),
        value: _look[key] == true,
        activeColor: C.violet,
        onChanged: (v) => _set(key, v),
      );

  // Поворот вектора по часовой (экран, y вниз) — как на сервере.
  Offset _rot(Offset v, double deg) {
    final a = deg * math.pi / 180;
    return Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
  }

  Widget _layered(Map layers) => LayoutBuilder(builder: (context, cons) {
        final id = widget.variant['id'] as String;
        final url = Api.i.previewUrl(id, layers['key'] as String);
        final k = cons.maxWidth / 1080;
        final boxes = (layers['box'] as Map?) ?? const {};
        Rect? rectOf(String r) {
          final b = boxes[r] as Map?;
          if (b == null) return null;
          double v(String n) => (b[n] as num).toDouble();
          return Rect.fromLTRB(v('x0'), v('y0'), v('x1'), v('y1'));
        }

        final all = rectOf('all');
        bool isHook(String r) => r == 'all' || _hookRoles.contains(r);
        final roles = [for (final r in boxes.keys.map((k) => '$k')) if (_layerKey.hasMatch(r) && rectOf(r) != null) r];
        final hookOn = all != null && _look['hook'] != false;
        final canMove = _look['mix'] != true && roles.isNotEmpty;
        final sel = canMove && ((_sel == 'all' && hookOn) || roles.contains(_sel))
            ? _sel
            : (roles.contains('main') ? 'main' : (roles.isEmpty ? 'all' : roles.first));
        // Финальная надпись в кадре из начала ролика наложилась бы на заголовок — показываем её, только когда выбрана.
        final shown = [
          for (final r in roles)
            if ((r != 'cta' || sel == 'cta') && !(sel == 'cta' && isHook(r))) r
        ];
        final g = _tfOf('all');

        // Матрица в координатах холста 1080×1920: масштаб и поворот вокруг центра, потом сдвиг.
        Matrix4 tfm(Offset c, ({double x, double y, double s, double r}) t) => Matrix4.identity()
          ..translate(c.dx + t.x, c.dy + t.y)
          ..rotateZ(t.r * math.pi / 180)
          ..scale(t.s, t.s)
          ..translate(-c.dx, -c.dy);
        final kk = Matrix4.diagonal3Values(k, k, 1), ki = Matrix4.diagonal3Values(1 / k, 1 / k, 1);
        // Как на сервере: сначала своя трансформация части, потом общая всего заголовка.
        // Финальная надпись и свои надписи двигаются сами по себе, без общей трансформации заголовка.
        Matrix4 widgetM(String role) {
          final m = kk.clone();
          if (isHook(role) && all != null) m.multiply(tfm(all.center, g));
          if (role != 'all') m.multiply(tfm(rectOf(role)!.center, _tfOf(role)));
          return m..multiply(ki);
        }

        Offset centerGlobal(String role) {
          final c = (role == 'all' ? all! : rectOf(role)!).center * k;
          final p = MatrixUtils.transformPoint(widgetM(role), c);
          final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
          return box == null ? p : box.localToGlobal(p);
        }

        void start(String role, Offset p) {
          final whole = _sel == 'all' && isHook(role);
          if (_sel != role && role != 'all' && !whole) setState(() => _sel = role);
          _g0 = _tfOf(whole ? 'all' : role);
          _p0 = p;
        }

        double scaleOf(String role) => role == 'all' ? g.s : (isHook(role) ? g.s : 1.0) * _tfOf(role).s;

        // Перетаскивание и щипок двумя пальцами (на телефоне — размер и поворот).
        Widget dragArea(String role, Rect r, {required bool selected}) {
          final target = sel == 'all' && isHook(role) ? 'all' : role;
          final ts = scaleOf(target);
          return Positioned(
            left: r.left * k,
            top: r.top * k,
            width: r.width * k,
            height: r.height * k,
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _EagerScale: GestureRecognizerFactoryWithHandlers<_EagerScale>(_EagerScale.new, (gr) {
                  gr
                    ..onStart = (d) {
                      start(role, d.focalPoint);
                    }
                    ..onUpdate = (d) {
                      final g0 = _g0;
                      if (g0 == null) return;
                      var delta = (d.focalPoint - _p0) / k;
                      // Сдвиг части задан до общей трансформации — переводим движение пальца в её систему.
                      if (target != 'all' && isHook(target)) delta = _rot(delta, -g.r) / g.s;
                      _setTf(target,
                          x: g0.x + delta.dx,
                          y: g0.y + delta.dy,
                          s: d.pointerCount > 1 ? g0.s * d.scale : null,
                          r: d.pointerCount > 1 ? g0.r + d.rotation * 180 / math.pi : null);
                    };
                }),
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.white.withValues(alpha: selected ? 0.8 : 0.22), width: (selected ? 1.4 : 1) / ts),
                    borderRadius: BorderRadius.circular(6 / ts),
                  ),
                ),
              ),
            ),
          );
        }

        // Ручка в углу: от центра — больше, по кругу — поворот. Работает и мышкой.
        Widget handle(String role, Rect r) {
          final ts = scaleOf(role);
          return Positioned(
            left: r.right * k - 16 / ts,
            top: r.bottom * k - 16 / ts,
            width: 32 / ts,
            height: 32 / ts,
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(_EagerPan.new, (gr) {
                  gr
                    ..onStart = (d) {
                      _g0 = _tfOf(role);
                      _p0 = d.globalPosition - centerGlobal(role);
                    }
                    ..onUpdate = (d) {
                      final g0 = _g0;
                      if (g0 == null || _p0.distance < 4) return;
                      final v = d.globalPosition - centerGlobal(role);
                      _setTf(role,
                          s: g0.s * v.distance / _p0.distance, r: g0.r + (v.direction - _p0.direction) * 180 / math.pi);
                    };
                }),
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                child: Container(
                  margin: EdgeInsets.all(6 / ts),
                  decoration: BoxDecoration(
                    color: C.violet,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2 / ts),
                  ),
                  child: Icon(Icons.open_with_rounded, size: 12 / ts, color: Colors.white),
                ),
              ),
            ),
          );
        }

        Widget layer(String role, List<Widget> children) =>
            Transform(transform: widgetM(role), child: Stack(clipBehavior: Clip.none, children: children));

        return Stack(key: _stackKey, fit: StackFit.expand, children: [
          Image.network('$url&f=rest', fit: BoxFit.fill, gaplessPlayback: true),
          for (final r in shown)
            Transform(
                transform: widgetM(r), child: Image.network('$url&f=$r', fit: BoxFit.fill, gaplessPlayback: true)),
          if (canMove && _eyeApply == null) ...[
            // Невыбранные надписи — тонкая рамка: нажми, чтобы выбрать и двигать.
            for (final r in shown)
              if (r != sel) layer(r, [dragArea(r, rectOf(r)!, selected: sel == 'all' && isHook(r))]),
            if (sel == 'all' && all != null)
              layer('all', [handle('all', all)])
            else if (shown.contains(sel))
              layer(sel, [dragArea(sel, rectOf(sel)!, selected: true), handle(sel, rectOf(sel)!)]),
          ],
          if (_eyeApply != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (_, c) => MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _sample(d.localPosition, Size(c.maxWidth, c.maxHeight)),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Нажми на кадр, чтобы взять цвет',
                              style: TextStyle(color: Colors.white, fontSize: 12.5)),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _eyeApply = null),
                            child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      });

  Widget _player() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: C.red, fontSize: 13)),
        ),
      );
    }
    final v = _video;
    if (v == null) {
      final layers = _layers;
      final busy = layers == null || _wantVideo;
      return Stack(fit: StackFit.expand, children: [
        if (layers != null) _layered(layers),
        if (busy)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(height: 12),
              Text(_wantVideo ? 'Собираю видео…' : 'Секунду…', style: const TextStyle(color: C.muted, fontSize: 13)),
            ]),
          ),
        if (!busy && _layersLoading)
          const Positioned(
              top: 10, right: 10, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        if (!busy)
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Center(
              child: FilledButton.icon(
                onPressed: _playVideo,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Видео с анимацией'),
                style: FilledButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
          ),
      ]);
    }
    return Stack(fit: StackFit.expand, children: [
      FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
      ),
      Positioned(
        right: 8,
        bottom: 8,
        child: IconButton.filledTonal(
          onPressed: () {
            setState(() => _muted = !_muted);
            v.setVolume(_muted ? 0 : 1);
          },
          icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 20),
        ),
      ),
    ]);
  }
}

/// Забирает касание сразу, иначе прокрутка окна перехватывает перетаскивание заголовка на телефоне.
class _EagerScale extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
