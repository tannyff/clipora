import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../theme.dart';

/// Ответ окна цвета, когда пользователь выбрал пипетку: цвет возьмут с кадра.
const eyedropperResult = '__eye__';

final List<String> _recent = [];
const _quick = [
  'FFFFFF', '000000', 'FBF2E5', 'FFE94D', 'F4F07D', 'FF8A3D', 'FF5C9A', 'E0245E',
  '77111B', '8B6CFF', '5CD6FF', '3DDC97', '264E32', '4F2D1B', '737075', 'BBD3EE',
];

Color hexColor(String h) => Color(int.parse('FF$h', radix: 16));

String colorHex(Color c) {
  String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

void rememberColor(String h) {
  _recent
    ..remove(h)
    ..insert(0, h);
  if (_recent.length > 10) _recent.removeLast();
}

/// Любой цвет: круг (оттенок и насыщенность), яркость, код #RRGGBB, последние цвета и пипетка.
Future<String?> pickColor(BuildContext context, {required String initial, bool eyedropper = false}) =>
    showDialog<String>(context: context, builder: (_) => _ColorDialog(initial: initial, eyedropper: eyedropper));

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial, required this.eyedropper});
  final String initial;
  final bool eyedropper;
  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(hexColor(widget.initial));
  late final _ctl = TextEditingController(text: widget.initial);

  String get _hex => colorHex(_hsv.toColor());

  void _setHsv(HSVColor c) {
    setState(() => _hsv = c);
    _ctl.text = _hex;
  }

  void _setHex(String h) {
    final x = h.replaceAll('#', '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(x)) return;
    setState(() => _hsv = HSVColor.fromColor(hexColor(x)));
  }

  void _done(String h) {
    rememberColor(h);
    Navigator.pop(context, h);
  }

  Widget _swatch(String h) => InkWell(
        onTap: () {
          _setHex(h);
          _ctl.text = h;
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: hexColor(h),
            shape: BoxShape.circle,
            border: Border.all(color: _hex == h ? C.violet : C.border, width: _hex == h ? 3 : 1),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Цвет'),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: _Wheel(hsv: _hsv, onChanged: _setHsv)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.brightness_6_outlined, size: 18, color: C.muted),
              Expanded(
                child: Slider(
                  value: _hsv.value,
                  activeColor: C.violet,
                  onChanged: (v) => _setHsv(_hsv.withValue(v)),
                ),
              ),
            ]),
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: _hsv.toColor(), borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctl,
                  decoration: const InputDecoration(prefixText: '#', labelText: 'Код цвета', isDense: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: _setHex,
                ),
              ),
              if (widget.eyedropper)
                IconButton(
                  tooltip: 'Пипетка: взять цвет с кадра',
                  onPressed: () => Navigator.pop(context, eyedropperResult),
                  icon: const Icon(Icons.colorize_rounded, color: C.violet),
                ),
            ]),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Недавние', style: TextStyle(color: C.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final h in _recent) _swatch(h)]),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final h in _quick) _swatch(h)]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => _done(_hex), child: const Text('Выбрать')),
      ],
    );
  }
}

/// Круг цветов: угол — оттенок, расстояние от центра — насыщенность.
class _Wheel extends StatelessWidget {
  const _Wheel({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  static const _d = 220.0;

  void _at(Offset p) {
    const r = _d / 2;
    final v = p - const Offset(r, r);
    var hue = math.atan2(v.dy, v.dx) * 180 / math.pi;
    if (hue < 0) hue += 360;
    onChanged(hsv.withHue(hue).withSaturation((v.distance / r).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    const r = _d / 2;
    final a = hsv.hue * math.pi / 180;
    final dot = Offset(r + math.cos(a) * hsv.saturation * r, r + math.sin(a) * hsv.saturation * r);
    return GestureDetector(
      onPanDown: (d) => _at(d.localPosition),
      onPanUpdate: (d) => _at(d.localPosition),
      child: SizedBox(
        width: _d,
        height: _d,
        child: Stack(children: [
          Opacity(
            opacity: 0.25 + 0.75 * hsv.value,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF),
                  Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
                ]),
              ),
              foregroundDecoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)]),
              ),
            ),
          ),
          Positioned(
            left: dot.dx - 11,
            top: dot.dy - 11,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: hsv.toColor(),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- Шрифты ----------

final Map<String, Future<void>> _fontJobs = {};

/// Подгружает шрифт с сервера, чтобы показать название шрифта им самим. Семейство — cf_<ключ>.
Future<void> ensureFont(String key) => _fontJobs[key] ??= () async {
      final r = await http.get(Uri.parse(Api.i.fontUrl(key)));
      if (r.statusCode != 200) return;
      final loader = FontLoader('cf_$key')..addFont(Future.value(ByteData.sublistView(r.bodyBytes)));
      await loader.load();
    }();

/// Список всех шрифтов; null в ответе — «как в шаблоне».
Future<String?> pickFont(BuildContext context, List<Map> fonts, String? current, {String sample = 'Привет, Reels!'}) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Шрифт'),
        content: SizedBox(
          width: 360,
          height: 460,
          child: ListView(children: [
            ListTile(
              dense: true,
              title: const Text('Как в шаблоне'),
              selected: current == null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final f in fonts)
              ListTile(
                selected: current == f['id'],
                selectedTileColor: C.violet.withValues(alpha: 0.15),
                title: FutureBuilder(
                  future: ensureFont(f['id'] as String),
                  builder: (_, snap) => Text(sample,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: snap.connectionState == ConnectionState.done ? 'cf_${f['id']}' : null,
                          fontSize: 22)),
                ),
                subtitle: Text('${f['name']}', style: const TextStyle(fontSize: 11.5, color: C.muted)),
                onTap: () => Navigator.pop(ctx, f['id'] as String),
              ),
          ]),
        ),
      ),
    );
