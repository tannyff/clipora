import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../theme.dart';
import '../upload/upload.dart';
import '../widgets/subtitle_preview.dart';
import '../widgets/ui.dart';
import 'subtitles_screen.dart';

/// Кусок монтажа. src: 'source' — исходник с речью, 'media' — вставка из медиатеки.
class EditClip {
  EditClip({required this.id, required this.src, required this.ref, required this.s, required this.e, this.mute = false});
  final String id;
  String src, ref;
  double s, e;
  bool mute;

  double get dur => e - s;
  bool get isMedia => src == 'media';
  String get key => '$src:$ref';

  factory EditClip.fromJson(Map m) => EditClip(
        id: '${m['id']}',
        src: m['src'] == 'media' ? 'media' : 'source',
        ref: '${m['ref']}',
        s: (m['s'] as num).toDouble(),
        e: (m['e'] as num).toDouble(),
        mute: m['mute'] == true,
      );

  Map<String, Object> toJson() => {'id': id, 'src': src, 'ref': ref, 's': s, 'e': e, 'mute': mute};
}

/// Вставка поверх голоса: картинка из медиатеки на [at, at + длина] ролика, звук — голос основной дорожки.
class OverlayClip {
  OverlayClip({required this.id, required this.ref, required this.s, required this.e, required this.at});
  final String id;
  String ref;
  double s, e, at;

  double get dur => e - s;
  String get key => 'media:$ref';

  factory OverlayClip.fromJson(Map m) => OverlayClip(
        id: '${m['id']}',
        ref: '${m['ref']}',
        s: (m['s'] as num).toDouble(),
        e: (m['e'] as num).toDouble(),
        at: (m['at'] as num).toDouble(),
      );

  Map<String, Object> toJson() => {'id': id, 'ref': ref, 's': s, 'e': e, 'at': at};
}

final _rnd = Random();
String _newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

String _sec(double s) => '${s.toStringAsFixed(1).replaceAll('.', ',')} с';

String _clock(double s) {
  final t = s.isFinite ? max(0.0, s) : 0.0;
  final m = t ~/ 60;
  final r = t - m * 60;
  return '$m:${r.toStringAsFixed(1).padLeft(4, '0')}';
}

Duration _ms(double s) => Duration(milliseconds: (s * 1000).round());

/// Вставка, которую ещё загружают или обрабатывают: встанет на место, когда будет готова.
class _Pending {
  _Pending(this.name, this.index, {this.replace = false, this.overlayAt, this.overlayReplace});
  final String name;
  int index;
  final bool replace;
  final double? overlayAt;
  final int? overlayReplace;
  String? mediaId;
  double progress = 0;
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.variantId});
  final String variantId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Map<String, dynamic>? _variant;
  List<EditClip> _clips = [];
  List<OverlayClip> _overlays = [];
  int? _selOv;
  int? _activeOv;
  Map<String, Map> _sources = {};
  List<Map> _library = [];
  String? _error;

  int? _sel;
  (double, double) _win = (0, 1);
  final _undo = <String>[], _redo = <String>[];
  Timer? _saveTimer, _poll, _tick;
  String _saveState = '';
  bool _busyRender = false, _busyPreview = false;
  double _pxPerSec = 28;
  final _pending = <_Pending>[];

  // Воспроизведение: по одному плееру на файл, куски играются по очереди.
  final _players = <String, VideoPlayerController>{};
  final _initing = <String>{};
  final _broken = <String>{};
  int _cur = 0;
  double _clipPos = 0;
  bool _playing = false, _switching = false;

  String get _id => widget.variantId;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_needsPoll) _refreshInfo();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    for (final c in _players.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- Данные ----------

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.i.get('/api/variants/$_id/edit'), Api.i.get('/api/media')]);
      if (!mounted) return;
      final e = r[0] as Map;
      setState(() {
        _variant = (e['variant'] as Map).cast<String, dynamic>();
        _clips = [for (final c in e['clips'] as List) EditClip.fromJson(c as Map)];
        _overlays = [for (final o in (e['overlays'] as List? ?? const [])) OverlayClip.fromJson(o as Map)];
        _selOv = null;
        _activeOv = null;
        _sources = {for (final s in e['sources'] as List) s['id'] as String: s as Map};
        _library = (r[1] as List).cast<Map>();
        _cur = 0;
        _clipPos = 0;
        _sel = null;
        _error = null;
      });
      _ensurePlayers();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool get _needsPoll =>
      _sources.values.any((s) => s['proxy'] != true) ||
      _library.any((m) => m['status'] == 'uploaded' || m['status'] == 'processing') ||
      _pending.any((p) => p.mediaId != null);

  Future<void> _refreshInfo() async {
    try {
      final r = await Future.wait([Api.i.get('/api/variants/$_id/edit'), Api.i.get('/api/media')]);
      if (!mounted) return;
      setState(() {
        for (final s in (r[0] as Map)['sources'] as List) {
          _sources[s['id'] as String] = s as Map;
        }
        _library = (r[1] as List).cast<Map>();
      });
      _placePending();
      _ensurePlayers();
    } catch (_) {}
  }

  Map? _mediaInfo(String id) => _library.where((m) => m['id'] == id).firstOrNull;

  double _mediaDur(String id, double fallback) => (_mediaInfo(id)?['duration'] as num?)?.toDouble() ?? fallback;

  double _fileDur(EditClip c) {
    final info = c.isMedia ? _mediaInfo(c.ref) : _sources[c.ref];
    final dur = info == null ? null : info['duration'] as num?;
    return dur?.toDouble() ?? c.e;
  }

  List _words(String sourceId) => (_sources[sourceId]?['words'] as List?) ?? const [];

  String _clipText(EditClip c) {
    if (c.isMedia) return (_mediaInfo(c.ref)?['file_name'] as String?) ?? 'вставка';
    final ws = [
      for (final w in _words(c.ref))
        if ((w['s'] as num) >= c.s - 0.01 && (w['e'] as num) <= c.e + 0.05) w['w']
    ];
    return ws.join(' ');
  }

  // ---------- Правки, отмена, сохранение ----------

  String _snap() => jsonEncode({
        'c': [for (final c in _clips) c.toJson()],
        'o': [for (final o in _overlays) o.toJson()],
      });

  void _restore(String s) {
    final m = jsonDecode(s) as Map;
    _clips = [for (final x in m['c'] as List) EditClip.fromJson(x as Map)];
    _overlays = [for (final x in m['o'] as List) OverlayClip.fromJson(x as Map)];
    if (_selOv != null && _selOv! >= _overlays.length) _selOv = null;
    _activeOv = null;
    if (_sel != null && _sel! >= _clips.length) _sel = null;
    if (_cur >= _clips.length) _cur = max(0, _clips.length - 1);
    _clipPos = 0;
  }

  void _pushUndo() {
    _undo.add(_snap());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _change(VoidCallback fn) {
    _stop();
    _pushUndo();
    setState(fn);
    _scheduleSave();
    _ensurePlayers();
  }

  void _undoRedo(bool undo) {
    final from = undo ? _undo : _redo, to = undo ? _redo : _undo;
    if (from.isEmpty) return;
    _stop();
    to.add(_snap());
    setState(() => _restore(from.removeLast()));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    setState(() => _saveState = 'pending');
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    if (mounted) setState(() => _saveState = 'saving');
    try {
      final r = await Api.i.put('/api/variants/$_id/edit', {
        'clips': [for (final c in _clips) c.toJson()],
        'overlays': [for (final o in _overlays) o.toJson()],
      });
      if (!mounted) return;
      setState(() {
        _saveState = 'saved';
        _variant?['edited'] = true;
        _variant?['duration'] = r['duration'];
        _variant?['edited_at'] = DateTime.now().toIso8601String();
      });
    } catch (e) {
      if (mounted) setState(() => _saveState = 'error:$e');
    }
  }

  Future<void> _flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _save();
    }
  }

  void _select(int i) {
    final c = _clips[i];
    final full = _fileDur(c);
    setState(() {
      _sel = i;
      _selOv = null;
      // Окно ползунка фиксируем при выборе, чтобы оно не «уезжало» под пальцем.
      _win = c.isMedia ? (0.0, full) : (max(0.0, c.s - 4), min(full, c.e + 4));
    });
  }

  bool _snapWords = true;

  String _msLabel(double x) {
    final m = x ~/ 60, sec = x - m * 60;
    return '$m:${sec.toStringAsFixed(2).padLeft(5, '0')}';
  }

  // Точная подрезка: шаг 0,05 и 0,5 с, без прилипания — чтобы убрать лишнее слово.
  void _nudge(EditClip c, int i, {required bool start, required double by}) {
    final full = _fileDur(c);
    _change(() {
      if (start) {
        c.s = (c.s + by).clamp(0.0, c.e - 0.2).toDouble();
      } else {
        c.e = (c.e + by).clamp(c.s + 0.2, full).toDouble();
      }
    });
    // Слушаем сразу место правки: начало — с начала, конец — за 1,5 с до конца.
    _seekTo(i, start ? 0 : max(0.0, c.e - c.s - 1.5));
  }

  Widget _nudgeRow(EditClip c, int i, {required bool start}) {
    Widget b(String t, double by) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: () => _nudge(c, i, start: start, by: by),
            child: Text(t, style: const TextStyle(fontSize: 12.5)),
          ),
        );
    return Row(children: [
      SizedBox(
          width: 62,
          child: Text(start ? 'Начало' : 'Конец', style: const TextStyle(color: C.muted, fontSize: 12.5))),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [b('−0,5', -0.5), b('−0,05', -0.05), b('+0,05', 0.05), b('+0,5', 0.5)]),
        ),
      ),
    ]);
  }

  /// Края куска прилипают к границам слов, чтобы не резать слово пополам.
  void _snapToWords(EditClip c) {
    if (c.isMedia) return;
    double? bestS, bestE;
    for (final w in _words(c.ref)) {
      final ws = (w['s'] as num).toDouble(), we = (w['e'] as num).toDouble();
      if ((ws - c.s).abs() < 0.25 && (bestS == null || (ws - c.s).abs() < (bestS - c.s).abs())) bestS = ws;
      if ((we - c.e).abs() < 0.25 && (bestE == null || (we - c.e).abs() < (bestE - c.e).abs())) bestE = we;
    }
    final full = _fileDur(c);
    if (bestS != null) c.s = max(0.0, bestS - 0.05);
    if (bestE != null) c.e = min(full, bestE + 0.12);
    if (c.e - c.s < 0.2) c.e = min(full, c.s + 0.2);
  }

  void _split(int i) {
    final c = _clips[i];
    final at = c.s + _clipPos;
    _change(() {
      final right = EditClip(id: _newId(), src: c.src, ref: c.ref, s: at, e: c.e, mute: c.mute);
      c.e = at;
      _clips.insert(i + 1, right);
      _sel = i + 1;
      _cur = i + 1;
      _clipPos = 0;
    });
  }

  void _move(int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= _clips.length) return;
    _change(() {
      final c = _clips.removeAt(i);
      _clips.insert(j, c);
      _sel = j;
    });
  }

  void _delete(int i) {
    if (_clips.length == 1) {
      toast(context, 'Это последний кусок — его можно только заменить');
      return;
    }
    _change(() {
      _clips.removeAt(i);
      _sel = null;
      _cur = min(_cur, _clips.length - 1);
      _clipPos = 0;
    });
  }

  void _put(EditClip clip, int index, {bool replace = false}) {
    _change(() {
      if (replace && index < _clips.length) {
        _clips[index] = clip;
      } else {
        _clips.insert(index.clamp(0, _clips.length), clip);
      }
    });
    _select(index.clamp(0, _clips.length - 1));
  }

  void _putOverlay(Map m, double at, int? replaceIdx) {
    final full = (m['duration'] as num?)?.toDouble() ?? 2.0;
    final double len = min(full, 2.0);
    final start = at.clamp(0.0, max(0.0, _total - len)).toDouble();
    final o = OverlayClip(id: _newId(), ref: m['id'] as String, s: 0, e: min<double>(len, _total), at: start);
    _change(() {
      if (replaceIdx != null && replaceIdx < _overlays.length) {
        o.at = _overlays[replaceIdx].at;
        _overlays[replaceIdx] = o;
      } else {
        _overlays.add(o);
      }
      _overlays.sort((a, b) => a.at.compareTo(b.at));
      _selOv = _overlays.indexOf(o);
      _sel = null;
    });
  }

  EditClip _mediaClip(Map m) {
    final dur = (m['duration'] as num?)?.toDouble() ?? 3.0;
    // Вставка по умолчанию на 3 секунды из начала — дальше её можно растянуть.
    return EditClip(id: _newId(), src: 'media', ref: m['id'] as String, s: 0, e: min(dur, 3.0));
  }

  // ---------- Воспроизведение ----------

  bool _mediaReady(String id) {
    final m = _mediaInfo(id);
    return m != null && m['status'] == 'ready';
  }

  bool _proxyReady(String sourceId) {
    final s = _sources[sourceId];
    return s != null && s['proxy'] == true;
  }

  String? _urlFor(EditClip c) {
    if (c.isMedia) return _mediaReady(c.ref) ? Api.i.libraryProxyUrl(c.ref) : null;
    return _proxyReady(c.ref) ? Api.i.sourceProxyUrl(c.ref) : null;
  }

  void _ensurePlayers() {
    final want = <(String, String?)>[
      for (final c in _clips) (c.key, _urlFor(c)),
      for (final o in _overlays)
        (o.key, _mediaReady(o.ref) ? Api.i.libraryProxyUrl(o.ref) : null),
    ];
    for (final (key, url) in want) {
      if (_players.containsKey(key) || _initing.contains(key) || _broken.contains(key)) continue;
      if (url == null) continue;
      _initing.add(key);
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      vc.initialize().then((_) {
        _initing.remove(key);
        if (!mounted) {
          vc.dispose();
          return;
        }
        setState(() => _players[key] = vc);
        // Плеер текущего куска догрузился, пока ждали — продолжаем с того же места.
        if (_cur < _clips.length && _clips[_cur].key == key) _seekTo(_cur, _clipPos, play: _playing);
        _activeOv = null;
        _syncOverlay();
      }).catchError((Object _) {
        _initing.remove(key);
        vc.dispose();
        if (mounted) setState(() => _broken.add(key));
      });
    }
  }

  double get _total => _clips.fold<double>(0.0, (a, c) => a + c.dur);

  double _startOf(int i) {
    var t = 0.0;
    for (var k = 0; k < i && k < _clips.length; k++) {
      t += _clips[k].dur;
    }
    return t;
  }

  double get _time => _clips.isEmpty ? 0 : _startOf(_cur) + _clipPos;

  VideoPlayerController? _ctl(int i) => i >= 0 && i < _clips.length ? _players[_clips[i].key] : null;

  Future<void> _seekTo(int i, double inClip, {bool play = false}) async {
    if (i < 0 || i >= _clips.length) return;
    final prev = _ctl(_cur);
    final c = _ctl(i);
    setState(() {
      _cur = i;
      _clipPos = inClip;
    });
    if (prev != null && prev != c) await prev.pause();
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(_ms(_clips[i].s + inClip));
    await c.setVolume(_clips[i].mute ? 0 : 1);
    if (play) {
      await c.play();
    } else {
      await c.pause();
    }
    _preloadNext();
    _syncOverlay(seek: true);
  }

  int? _overlayAt(double t) {
    for (var k = 0; k < _overlays.length; k++) {
      final o = _overlays[k];
      if (t >= o.at && t < o.at + o.dur) return k;
    }
    return null;
  }

  /// Вставка поверх голоса играет без звука своим плеером над основным.
  void _syncOverlay({bool seek = false}) {
    final t = _time;
    final k = _overlayAt(t);
    final mainCtl = _ctl(_cur);
    if (k != _activeOv) {
      final prev = _activeOv == null || _activeOv! >= _overlays.length ? null : _players[_overlays[_activeOv!].key];
      if (prev != null && prev != mainCtl) prev.pause();
      setState(() => _activeOv = k);
      seek = true;
    }
    if (k == null || !seek) return;
    final o = _overlays[k];
    final c = _players[o.key];
    if (c == null || c == mainCtl || !c.value.isInitialized) return;
    c.setVolume(0);
    c.seekTo(_ms(o.s + (t - o.at)));
    _playing ? c.play() : c.pause();
  }

  // Следующий кусок из другого файла заранее встаёт на нужный кадр — склейка без паузы.
  void _preloadNext() {
    final n = _cur + 1;
    final c = _ctl(n);
    if (c != null && c != _ctl(_cur) && c.value.isInitialized) c.seekTo(_ms(_clips[n].s));
  }

  void _seekGlobal(double t) {
    var acc = 0.0;
    for (var i = 0; i < _clips.length; i++) {
      final dur = _clips[i].dur;
      if (t < acc + dur || i == _clips.length - 1) {
        _seekTo(i, (t - acc).clamp(0.0, dur), play: _playing);
        return;
      }
      acc += dur;
    }
  }

  Future<void> _play({int? from}) async {
    if (_clips.isEmpty) return;
    if (from != null) {
      _cur = from;
      _clipPos = 0;
    } else if (_time >= _total - 0.05) {
      _cur = 0;
      _clipPos = 0;
    }
    setState(() => _playing = true);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 40), (_) => _onTick());
    await _seekTo(_cur, _clipPos, play: true);
  }

  void _stop() {
    _tick?.cancel();
    _ctl(_cur)?.pause();
    if (_activeOv != null && _activeOv! < _overlays.length) _players[_overlays[_activeOv!].key]?.pause();
    if (mounted && _playing) setState(() => _playing = false);
  }

  Future<void> _onTick() async {
    if (_switching || !_playing || _cur >= _clips.length) return;
    final c = _ctl(_cur);
    if (c == null || !c.value.isInitialized) return;
    final clip = _clips[_cur];
    final pos = ((await c.position)?.inMilliseconds ?? 0) / 1000;
    if (!mounted || !_playing || _cur >= _clips.length || _clips[_cur] != clip) return;
    if (pos < clip.e - 0.03) {
      setState(() => _clipPos = (pos - clip.s).clamp(0.0, clip.dur));
      _syncOverlay();
      return;
    }
    _switching = true;
    try {
      final next = _cur + 1;
      if (next >= _clips.length) {
        _stop();
        setState(() => _clipPos = clip.dur);
        return;
      }
      // Соседний кусок того же файла идёт встык — не перематываем, просто играем дальше.
      final contiguous = _ctl(next) == c && (_clips[next].s - clip.e).abs() < 0.08;
      if (contiguous) {
        setState(() {
          _cur = next;
          _clipPos = 0;
        });
        await c.setVolume(_clips[next].mute ? 0 : 1);
        _preloadNext();
      } else {
        await _seekTo(next, 0, play: true);
      }
    } finally {
      _switching = false;
    }
  }

  // ---------- Добавление и замена ----------

  Future<void> _pick({required int index, bool replace = false, double? overlayAt, int? overlayReplace}) async {
    final over = overlayAt != null;
    _stop();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(over ? 'Вставка поверх голоса' : (replace ? 'Чем заменить кусок' : 'Что добавить'),
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          if (!over)
            _sheetTile(ctx, 'phrase', Icons.notes_rounded, 'Фраза из исходника', 'Кусок вашей речи из этой съёмки'),
          _sheetTile(ctx, 'library', Icons.movie_filter_rounded, 'Из «Вставок»',
              'Твои кадры из вкладки «Вставки» — видно, сколько раз каждый уже использован'),
          _sheetTile(ctx, 'file', Icons.photo_library_outlined, 'Из галереи или файлов',
              'Новое видео — оно сохранится во «Вставках», в галерее держать не нужно'),
          _sheetTile(ctx, 'camera', Icons.videocam_outlined, 'Снять сейчас', 'На телефоне откроется камера'),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'phrase':
        final clip = await _pickPhrase();
        if (clip != null) _put(clip, index, replace: replace);
      case 'library':
        final m = await _pickLibrary();
        if (m == null) return;
        if (over) {
          _putOverlay(m, overlayAt!, overlayReplace);
        } else {
          _put(_mediaClip(m), index, replace: replace);
        }
      case 'file' || 'camera':
        await _uploadNew(index,
            replace: replace, camera: choice == 'camera', overlayAt: overlayAt, overlayReplace: overlayReplace);
    }
  }

  Widget _sheetTile(BuildContext ctx, String value, IconData icon, String title, String sub) => ListTile(
        leading: Icon(icon, color: C.violet),
        title: Text(title),
        subtitle: Text(sub, style: const TextStyle(color: C.muted, fontSize: 12.5)),
        onTap: () => Navigator.pop(ctx, value),
      );

  Future<EditClip?> _pickPhrase() async {
    final src = _sources[_variant?['source_id']] ?? _sources.values.firstOrNull;
    if (src == null) return null;
    final phrases = ((src['phrases'] as List?) ?? const []).cast<Map>();
    final used = [for (final c in _clips) if (!c.isMedia && c.ref == src['id']) c];
    return showModalBottomSheet<EditClip>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Выбери фразу', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('Отмеченные галочкой уже стоят в ролике', style: TextStyle(color: C.muted, fontSize: 12.5)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: phrases.length,
              itemBuilder: (_, i) {
                final ph = phrases[i];
                final s = (ph['s'] as num).toDouble(), e = (ph['e'] as num).toDouble();
                final inUse = used.any((c) => c.s < e - 0.1 && c.e > s + 0.1);
                return ListTile(
                  dense: true,
                  leading: Text(_clock(s), style: const TextStyle(color: C.faint, fontSize: 12)),
                  title: Text('${ph['text']}', style: const TextStyle(fontSize: 14)),
                  trailing: inUse ? const Icon(Icons.check_rounded, size: 18, color: C.green) : null,
                  onTap: () {
                    final full = (src['duration'] as num?)?.toDouble() ?? e + 1;
                    Navigator.pop(
                        ctx,
                        EditClip(
                            id: _newId(),
                            src: 'source',
                            ref: src['id'] as String,
                            s: max(0.0, s - 0.05),
                            e: min(full, e + 0.12)));
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<Map?> _pickLibrary() => showModalBottomSheet<Map>(
        context: context,
        backgroundColor: C.surface,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
          final items = _library.where((m) => m['status'] != 'failed').toList();
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.75,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text('Медиатека вставок', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Здесь пока пусто. Добавь вставку из галереи или сними её — она сохранится и для других роликов.',
                      style: TextStyle(color: C.muted)),
                ),
              Expanded(
                child: GridView.extent(
                  maxCrossAxisExtent: 130,
                  childAspectRatio: 9 / 16,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final m in items)
                      _libraryTile(m, onTap: m['status'] == 'ready' ? () => Navigator.pop(ctx, m) : null,
                          onDelete: () async {
                        try {
                          await Api.i.delete('/api/media/${m['id']}');
                          setState(() => _library.remove(m));
                          setSheet(() {});
                        } catch (e) {
                          if (ctx.mounted) toast(ctx, e.toString());
                        }
                      }),
                  ],
                ),
              ),
            ]),
          );
        }),
      );

  Widget _libraryTile(Map m, {VoidCallback? onTap, VoidCallback? onDelete}) {
    final ready = m['status'] == 'ready';
    final used = (m['used'] as num?)?.toInt() ?? 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: C.surface2,
        child: InkWell(
          onTap: onTap,
          child: Stack(fit: StackFit.expand, children: [
            if (ready)
              Image.network(Api.i.libraryThumbUrl(m['id'] as String),
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            if (!ready)
              const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            Positioned(
              left: 6,
              bottom: 6,
              right: 6,
              child: Text(
                '${_sec((m['duration'] as num?)?.toDouble() ?? 0.0)}${used > 0 ? ' · в $used' : ''}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                    shadows: [Shadow(blurRadius: 4)]),
              ),
            ),
            if (onDelete != null)
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                  onPressed: onDelete,
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _uploadNew(int index,
      {bool replace = false, bool camera = false, double? overlayAt, int? overlayReplace}) async {
    List<PickedVideo> files;
    try {
      files = await pickVideos(camera: camera, multiple: false);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось открыть выбор файла: $e');
      return;
    }
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    final p = _Pending(f.name, index, replace: replace, overlayAt: overlayAt, overlayReplace: overlayReplace);
    setState(() => _pending.add(p));
    try {
      final r = await uploadVideo(f, Api.i.mediaUploadUrl(f.name), (x) {
        if (mounted) setState(() => p.progress = x);
      });
      if (!mounted) return;
      setState(() => p.mediaId = r['id'] as String?);
      if (p.mediaId == null) throw ApiError('Сервер не вернул id вставки');
      _refreshInfo();
    } catch (e) {
      if (mounted) {
        setState(() => _pending.remove(p));
        toast(context, e.toString());
      }
    }
  }

  void _placePending() {
    for (final p in [..._pending]) {
      if (p.mediaId == null) continue;
      final m = _mediaInfo(p.mediaId!);
      if (m == null) continue;
      if (m['status'] == 'failed') {
        setState(() => _pending.remove(p));
        toast(context, 'Не получилось обработать «${p.name}»: ${m['error'] ?? ''}');
      } else if (m['status'] == 'ready') {
        setState(() => _pending.remove(p));
        if (p.overlayAt != null) {
          _putOverlay(m, p.overlayAt!, p.overlayReplace);
        } else {
          _put(_mediaClip(m), p.index, replace: p.replace);
        }
      }
    }
  }

  // ---------- Действия с роликом ----------

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вернуть вариант AI?'),
        content: const Text('Все ваши правки монтажа этого ролика пропадут.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Вернуть')),
        ],
      ),
    );
    if (ok != true) return;
    _stop();
    _saveTimer?.cancel();
    try {
      await Api.i.post('/api/variants/$_id/edit/reset');
      _undo.clear();
      _redo.clear();
      await _load();
      if (mounted) setState(() => _saveState = '');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _quickPreview() async {
    _stop();
    setState(() => _busyPreview = true);
    try {
      await _flush();
      final r = await Api.i.post('/api/variants/$_id/quick-preview');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PreviewDialog(url: Api.i.previewUrl(_id, r['key'] as String, video: true)),
      );
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busyPreview = false);
    }
  }

  Future<void> _rebuild() async {
    _stop();
    setState(() => _busyRender = true);
    try {
      await _flush();
      await Api.i.post('/api/variants/render', {
        'ids': [_id],
        'look': _variant?['look'],
      });
      if (!mounted) return;
      toast(context, 'Ролик отправлен на сборку');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busyRender = false);
    }
  }

  bool get _wasRendered => _variant?['rendered_at'] != null;

  Future<void> _openSubtitles() async {
    final sid = _variant?['source_id'] as String?;
    if (sid == null) return;
    _stop();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SubtitlesScreen(sourceId: sid, fileName: 'исходник')));
    if (mounted && _wasRendered) toast(context, 'Чтобы исправления попали в ролик, нажми «Пересобрать»');
  }

  // Оформление этого ролика: выбранное запоминается и применяется при сборке.
  Future<void> _changeLook() async {
    _stop();
    try {
      final styles = await Api.i.get('/api/styles') as Map;
      if (!mounted) return;
      final picked = await showLookDialog(context,
          variant: _variant!, styles: styles, look: (_variant?['look'] as Map?)?.cast<String, dynamic>() ?? const {});
      if (picked == null || !mounted) return;
      // Сохраняем сразу на сервер — иначе при сборке из проекта оформление терялось.
      await Api.i.put('/api/variants/$_id/look', {'look': picked});
      if (!mounted) return;
      setState(() => _variant!['look'] = picked);
      if (_wasRendered) {
        await _rebuild();
      } else {
        toast(context, 'Оформление выбрано — оно применится при сборке');
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  // ---------- Интерфейс ----------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Монтаж', style: TextStyle(fontSize: 17)),
          if (_variant != null)
            Text('«${_variant!['hook_text']}»',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: C.muted)),
        ]),
        actions: [
          IconButton(
              tooltip: 'Отменить', onPressed: _undo.isEmpty ? null : () => _undoRedo(true), icon: const Icon(Icons.undo_rounded)),
          IconButton(
              tooltip: 'Вернуть', onPressed: _redo.isEmpty ? null : () => _undoRedo(false), icon: const Icon(Icons.redo_rounded)),
          IconButton(
              tooltip: 'Текст субтитров', onPressed: _variant == null ? null : _openSubtitles, icon: const Icon(Icons.subtitles_outlined)),
          IconButton(
              tooltip: 'Оформление и надписи', onPressed: _variant == null ? null : _changeLook, icon: const Icon(Icons.palette_outlined)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (a) {
              if (a == 'reset') _reset();
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'reset', child: Text('Вернуть вариант AI'))],
          ),
        ],
      ),
      body: _error != null
          ? EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Не открылось',
              text: _error!,
              action: FilledButton(onPressed: _load, child: const Text('Ещё раз')))
          : _variant == null
              ? const Center(child: CircularProgressIndicator())
              : wide
                  ? _wideLayout(size)
                  : _narrowLayout(size),
    );
  }

  Widget _wideLayout(Size size) => Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _player((size.height - 330).clamp(300.0, 720.0)),
              const SizedBox(width: 24),
              Expanded(child: SingleChildScrollView(child: _selOv != null ? _overlayPanel() : _clipPanel())),
            ]),
          ),
        ),
        _transport(),
        _timeline(),
        _overlayTrack(),
        _bottomBar(),
      ]);

  Widget _narrowLayout(Size size) => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), children: [
            Center(child: _player((size.height * 0.42).clamp(240.0, 520.0))),
            const SizedBox(height: 4),
            _transport(),
            _timeline(),
            _overlayTrack(),
            const SizedBox(height: 8),
            _selOv != null ? _overlayPanel() : _clipPanel(),
          ]),
        ),
        _bottomBar(),
      ]);

  Widget _player(double h) {
    final clip = _cur < _clips.length ? _clips[_cur] : null;
    final c = _ctl(_cur);
    final ready = c != null && c.value.isInitialized;
    String wait = 'Загружаю видео…';
    if (clip != null && _broken.contains(clip.key)) {
      wait = 'Видео не открылось в браузере. Нажми «Быстрое превью» внизу.';
    } else if (clip != null && !clip.isMedia && _sources[clip.ref]?['proxy_error'] != null) {
      wait = 'Не получилось подготовить видео для монтажа: ${_sources[clip.ref]?['proxy_error']}';
    } else if (clip != null && !clip.isMedia && _sources[clip.ref]?['proxy'] != true) {
      wait = 'Готовлю лёгкую копию видео для монтажа. Для 5 минут 4K это 1–3 минуты, страница обновится сама.';
    } else if (clip != null && clip.isMedia && _mediaInfo(clip.ref)?['status'] != 'ready') {
      wait = 'Вставка ещё обрабатывается…';
    }
    return SizedBox(
      height: h,
      width: h * 9 / 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: Colors.black,
          child: GestureDetector(
            onTap: () => _playing ? _stop() : _play(),
            child: Stack(fit: StackFit.expand, children: [
              if (ready)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(width: c!.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      const SizedBox(height: 14),
                      Text(wait, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 13)),
                    ]),
                  ),
                ),
              if (ready && !_playing)
                Center(
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                  ),
                ),
              if (_activeOv != null && _activeOv! < _overlays.length)
                Builder(builder: (_) {
                  final oc = _players[_overlays[_activeOv!].key];
                  if (oc == null || oc == c || !oc.value.isInitialized) return const SizedBox();
                  return FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(width: oc.value.size.width, height: oc.value.size.height, child: VideoPlayer(oc)),
                  );
                }),
              if ((clip != null && clip.isMedia) || _activeOv != null)
                Positioned(
                    top: 10,
                    left: 10,
                    child: Pill(_activeOv != null ? 'поверх голоса' : 'вставка', color: C.pink)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _transport() {
    final total = _total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        IconButton(
          onPressed: _clips.isEmpty ? null : () => _playing ? _stop() : _play(),
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        Text('${_clock(_time)} / ${_clock(total)}', style: const TextStyle(fontSize: 12.5, color: C.muted)),
        Expanded(
          child: Slider(
            value: _time.clamp(0.0, max(total, 0.01)),
            max: max(total, 0.01),
            onChanged: (t) => _seekGlobal(t),
          ),
        ),
        IconButton(
          tooltip: 'Мельче',
          onPressed: () => setState(() => _pxPerSec = max(10, _pxPerSec / 1.4)),
          icon: const Icon(Icons.zoom_out_rounded, size: 20),
        ),
        IconButton(
          tooltip: 'Крупнее',
          onPressed: () => setState(() => _pxPerSec = min(120, _pxPerSec * 1.4)),
          icon: const Icon(Icons.zoom_in_rounded, size: 20),
        ),
      ]),
    );
  }

  Widget _timeline() {
    return SizedBox(
      height: 112,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _clips.length,
        onReorder: (a, b) {
          if (b > a) b--;
          if (a == b) return;
          _change(() {
            final c = _clips.removeAt(a);
            _clips.insert(b, c);
            _sel = b;
            _cur = b;
            _clipPos = 0;
          });
        },
        footer: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _addTile(),
        ),
        itemBuilder: (_, i) => _tile(i),
      ),
    );
  }

  Widget _addTile() => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pick(index: _clips.length),
        child: Container(
          width: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.border, width: 1.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.add_rounded, color: C.muted),
            for (final p in _pending)
              Text(p.mediaId == null ? '${(p.progress * 100).round()}%' : 'обраб.',
                  style: const TextStyle(fontSize: 10.5, color: C.muted)),
          ]),
        ),
      );

  Widget _tile(int i) {
    final c = _clips[i];
    final w = max(84.0, c.dur * _pxPerSec);
    final sel = _sel == i;
    final color = c.isMedia ? C.pink : C.violet;
    final progress = i == _cur ? (_clipPos / max(c.dur, 0.01)).clamp(0.0, 1.0) : 0.0;
    // Перетаскивание долгим нажатием на любом устройстве — ручки по умолчанию налезали на текст.
    return ReorderableDelayedDragStartListener(
      key: ValueKey(c.id),
      index: i,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () {
            _select(i);
            _seekTo(i, 0, play: _playing);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: w,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.10)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? Colors.white : color.withValues(alpha: 0.35), width: sel ? 2 : 1),
            ),
            child: Stack(children: [
              if (c.isMedia)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.55,
                    child: Image.network(Api.i.libraryThumbUrl(c.ref),
                        fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: w * progress,
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                      child: Text(c.isMedia ? 'вставка' : '${i + 1}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    const Spacer(),
                    if (c.mute) const Icon(Icons.volume_off_rounded, size: 13, color: C.muted),
                  ]),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Text(_clipText(c),
                        maxLines: 3,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(fontSize: 11.5, height: 1.25, color: C.text)),
                  ),
                  Text(_sec(c.dur), style: const TextStyle(fontSize: 10.5, color: C.muted, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _overlayTrack() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 17, color: C.pink),
              label: const Text('Вставка поверх голоса', style: TextStyle(fontSize: 13)),
              side: BorderSide(color: C.pink.withValues(alpha: 0.5)),
              onPressed: _clips.isEmpty ? null : () => _pick(index: 0, overlayAt: _time),
            ),
          ),
          for (final (k, o) in _overlays.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                selected: _selOv == k,
                selectedColor: C.pink.withValues(alpha: 0.25),
                side: BorderSide(color: _selOv == k ? C.pink : C.border),
                avatar: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(Api.i.libraryThumbUrl(o.ref),
                      width: 18, height: 24, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                ),
                label: Text('с ${_clock(o.at)} · ${_sec(o.dur)}', style: const TextStyle(fontSize: 12.5)),
                onSelected: (_) {
                  _stop();
                  setState(() {
                    _selOv = k;
                    _sel = null;
                  });
                  _seekGlobal(o.at + 0.01);
                },
              ),
            ),
        ]),
      ),
    );
  }

  Widget _overlayPanel() {
    final k = _selOv!;
    final o = _overlays[k];
    final full = _mediaDur(o.ref, o.e);
    final total = _total;
    final maxAt = max(0.0, total - o.dur);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Pill('Поверх голоса', color: C.pink),
          const SizedBox(width: 8),
          Pill(_sec(o.dur), icon: Icons.timer_outlined),
          const Spacer(),
          IconButton(onPressed: () => setState(() => _selOv = null), icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 8),
        const Text('Голос продолжает звучать, а картинка на это время сменяется вставкой. Звук вставки выключен.',
            style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 14),
        Text('Когда появляется: ${_clock(o.at)}', style: const TextStyle(color: C.muted, fontSize: 12.5)),
        Slider(
          value: o.at.clamp(0.0, maxAt),
          max: max(maxAt, 0.01),
          onChangeStart: (_) {
            _stop();
            _pushUndo();
          },
          onChanged: (v) => setState(() => o.at = v),
          onChangeEnd: (_) {
            setState(() => _overlays.sort((a, b) => a.at.compareTo(b.at)));
            _selOv = _overlays.indexOf(o);
            _scheduleSave();
            _seekGlobal(o.at + 0.01);
          },
        ),
        const Text('Какой кусок вставки', style: TextStyle(color: C.muted, fontSize: 12.5)),
        RangeSlider(
          values: RangeValues(o.s.clamp(0.0, full), o.e.clamp(0.0, full)),
          max: max(full, 0.01),
          onChangeStart: (_) {
            _stop();
            _pushUndo();
          },
          onChanged: (v) {
            if (v.end - v.start < 0.3 || o.at + v.end - v.start > total) return;
            setState(() {
              o.s = v.start;
              o.e = v.end;
            });
          },
          onChangeEnd: (_) {
            _scheduleSave();
            _seekGlobal(o.at + 0.01);
          },
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _act(Icons.play_arrow_rounded, 'Посмотреть', () {
            _seekGlobal(max(0.0, o.at - 0.5));
            Future.delayed(const Duration(milliseconds: 150), _play);
          }),
          _act(Icons.swap_horiz_rounded, 'Заменить', () => _pick(index: 0, overlayAt: o.at, overlayReplace: k)),
          _act(Icons.delete_outline_rounded, 'Удалить', () {
            _change(() {
              _overlays.removeAt(k);
              _selOv = null;
              _activeOv = null;
            });
          }, danger: true),
        ]),
      ]),
    );
  }

  Widget _clipPanel() {
    final i = _sel;
    if (i == null || i >= _clips.length) {
      return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Как монтировать', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          for (final line in const [
            'Нажми на кусок на ленте — его можно обрезать, разрезать, заменить или удалить.',
            'Перетаскивай куски, чтобы поменять порядок. На телефоне — долгим нажатием.',
            '«+» в конце ленты добавляет фразу из исходника, вставку из медиатеки, видео из галереи или съёмку с камеры.',
            'Всё сохраняется само. Ошиблась — стрелка «Отменить» сверху.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $line', style: const TextStyle(color: C.muted, fontSize: 13.5, height: 1.35)),
            ),
        ]),
      );
    }
    final c = _clips[i];
    final (lo, hi) = _win;
    final canSplit = _cur == i && _clipPos > 0.2 && _clipPos < c.dur - 0.2;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Pill(c.isMedia ? 'Вставка' : 'Кусок ${i + 1}', color: c.isMedia ? C.pink : C.violet),
          const SizedBox(width: 8),
          Pill(_sec(c.dur), icon: Icons.timer_outlined),
          const Spacer(),
          IconButton(
              tooltip: 'Закрыть', onPressed: () => setState(() => _sel = null), icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 10),
        Text(_clipText(c), style: const TextStyle(fontSize: 14, height: 1.35)),
        const SizedBox(height: 14),
        const Text('Начало и конец', style: TextStyle(color: C.muted, fontSize: 12.5)),
        RangeSlider(
          values: RangeValues(c.s.clamp(lo, hi), c.e.clamp(lo, hi)),
          min: lo,
          max: hi,
          onChangeStart: (_) {
            _stop();
            _pushUndo();
          },
          onChanged: (v) {
            if (v.end - v.start < 0.2) return;
            setState(() {
              c.s = v.start;
              c.e = v.end;
            });
          },
          onChangeEnd: (_) {
            if (_snapWords) setState(() => _snapToWords(c));
            _scheduleSave();
            _seekTo(i, 0);
          },
        ),
        Row(children: [
          Text(_msLabel(c.s), style: const TextStyle(color: C.faint, fontSize: 12)),
          const Spacer(),
          Text(_msLabel(c.e), style: const TextStyle(color: C.faint, fontSize: 12)),
        ]),
        if (!c.isMedia) ...[
          const SizedBox(height: 6),
          _nudgeRow(c, i, start: true),
          const SizedBox(height: 4),
          _nudgeRow(c, i, start: false),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Прилипать к границам слов', style: TextStyle(fontSize: 13)),
            value: _snapWords,
            onChanged: (x) => setState(() => _snapWords = x),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _act(Icons.play_arrow_rounded, 'Послушать', () => _play(from: i)),
          _act(Icons.content_cut_rounded, 'Разрезать здесь', canSplit ? () => _split(i) : null),
          _act(Icons.chevron_left_rounded, 'Раньше', i > 0 ? () => _move(i, -1) : null),
          _act(Icons.chevron_right_rounded, 'Позже', i < _clips.length - 1 ? () => _move(i, 1) : null),
          _act(Icons.swap_horiz_rounded, 'Заменить', () => _pick(index: i, replace: true)),
          _act(Icons.add_rounded, 'Добавить после', () => _pick(index: i + 1)),
          if (c.isMedia)
            _act(c.mute ? Icons.volume_up_rounded : Icons.volume_off_rounded, c.mute ? 'Вернуть звук' : 'Без звука',
                () => _change(() => c.mute = !c.mute)),
          _act(Icons.delete_outline_rounded, 'Удалить', () => _delete(i), danger: true),
        ]),
        if (!canSplit)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Чтобы разрезать, включи кусок и поставь на паузу в нужном месте.',
                style: TextStyle(color: C.faint, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _act(IconData icon, String label, VoidCallback? onTap, {bool danger = false}) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: onTap == null ? C.faint : (danger ? C.red : C.text)),
        label: Text(label, style: TextStyle(color: onTap == null ? C.faint : (danger ? C.red : C.text), fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: C.border),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Widget _bottomBar() {
    final st = _saveState;
    final saveText = switch (st) {
      'pending' || 'saving' => 'Сохраняю…',
      'saved' => 'Сохранено',
      _ when st.startsWith('error:') => st.substring(6),
      _ => '',
    };
    return Container(
      decoration: const BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(
              child: Text(saveText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: st.startsWith('error:') ? C.red : C.muted)),
            ),
            TextButton.icon(
              onPressed: _busyPreview ? null : _quickPreview,
              icon: _busyPreview
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.slideshow_rounded, size: 18),
              label: const Text('Быстрое превью'),
            ),
            const SizedBox(width: 8),
            if (_wasRendered)
              GradientButton(
                label: 'Пересобрать',
                icon: Icons.movie_creation_rounded,
                busy: _busyRender,
                onPressed: _rebuild,
              )
            else
              GradientButton(
                label: 'Готово',
                icon: Icons.check_rounded,
                onPressed: () async {
                  await _flush();
                  if (mounted) Navigator.pop(context, true);
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.url});
  final String url;
  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late final VideoPlayerController _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  String? _error;

  @override
  void initState() {
    super.initState();
    _vc.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _vc.setLooping(true);
      _vc.play();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.sizeOf(context).height * 0.8).clamp(300.0, 900.0);
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        height: h,
        width: h * 9 / 16,
        child: Stack(fit: StackFit.expand, children: [
          if (_vc.value.isInitialized)
            GestureDetector(
              onTap: () {
                _vc.value.isPlaying ? _vc.pause() : _vc.play();
                setState(() {});
              },
              child: AspectRatio(aspectRatio: _vc.value.aspectRatio, child: VideoPlayer(_vc)),
            )
          else
            Center(
              child: _error != null
                  ? Text(_error!, style: const TextStyle(color: C.red))
                  : const CircularProgressIndicator(),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }
}
