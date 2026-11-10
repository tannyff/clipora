import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Правка текста субтитров исходника. Изменения действуют на все ролики из этого видео.
class SubtitlesScreen extends StatefulWidget {
  const SubtitlesScreen({super.key, required this.sourceId, required this.fileName});
  final String sourceId;
  final String fileName;
  @override
  State<SubtitlesScreen> createState() => _SubtitlesScreenState();
}

class _Line {
  _Line(this.first, this.last);
  final int first;
  int last;
}

String _norm(String w) => w.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]'), '').replaceAll('ё', 'е');

class _SubtitlesScreenState extends State<SubtitlesScreen> {
  List<Map<String, dynamic>> _words = [];
  List<_Line> _lines = [];

  /// Исходный текст каждого слова — чтобы показать, что поменялось, и уметь вернуть.
  List<String> _orig = [];
  // Как слова лежат на сервере сейчас: «вернула как было» — уже не изменение.
  List<String> _savedW = [];
  List<bool> _savedX = [];
  final Set<int> _touched = {};
  Iterable<int> get _dirty =>
      _touched.where((i) => _words[i]['w'].toString() != _savedW[i] || (_words[i]['x'] == true) != _savedX[i]);
  bool _loading = true, _saving = false, _hasProxy = false;
  String? _error;
  String _query = '';

  VideoPlayerController? _player;
  bool _playerReady = false;
  int? _playingLine;
  double _stopAt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/api/sources/${widget.sourceId}/words') as Map;
      final words = [for (final w in r['words'] as List) Map<String, dynamic>.from(w as Map)];
      if (!mounted) return;
      setState(() {
        _words = words;
        _orig = [for (final w in words) (w['o'] ?? w['w']).toString()];
        _savedW = [for (final w in words) w['w'].toString()];
        _savedX = [for (final w in words) w['x'] == true];
        _lines = _split(words);
        _hasProxy = r['has_proxy'] == true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // Строка — фраза до паузы или конца предложения, но не длиннее 10 слов, чтобы легко читалось.
  List<_Line> _split(List<Map<String, dynamic>> words) {
    final out = <_Line>[];
    for (var i = 0; i < words.length; i++) {
      final cur = out.isEmpty ? null : out.last;
      final prev = i > 0 ? words[i - 1] : null;
      final len = cur == null ? 0 : cur.last - cur.first + 1;
      final pause = prev != null && _d(words[i]['s']) - _d(prev['e']) > 0.7;
      final sentence = prev != null && RegExp(r'[.!?…]$').hasMatch(prev['w'].toString()) && len >= 3;
      if (cur == null || pause || sentence || len >= 10) {
        out.add(_Line(i, i));
      } else {
        cur.last = i;
      }
    }
    return out;
  }

  double _d(Object? x) => (x as num?)?.toDouble() ?? 0;

  bool _hidden(int i) => _words[i]['x'] == true;
  bool _changed(int i) => _hidden(i) || _words[i]['w'].toString() != _orig[i];

  void _apply(int i, {String? text, bool? hide}) {
    final w = _words[i];
    if (text != null) {
      final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) {
        w['x'] = true;
      } else {
        w['w'] = t;
      }
    }
    if (hide != null) {
      if (hide) {
        w['x'] = true;
      } else {
        w.remove('x');
      }
    }
    _touched.add(i);
  }

  Future<void> _editWord(int i) async {
    final ctrl = TextEditingController(text: _words[i]['w'].toString());
    final key = _norm(_orig[i]);
    final same = [
      for (var j = 0; j < _words.length; j++)
        if (j != i && key.isNotEmpty && _norm(_orig[j]) == key) j
    ];
    var everywhere = false;
    final hidden = _hidden(i);

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Слово в субтитрах'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_orig[i] != _words[i]['w'].toString() || hidden)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Распознано: «${_orig[i]}»', style: const TextStyle(color: C.muted, fontSize: 13)),
                ),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Как должно быть написано'),
                onSubmitted: (_) => Navigator.pop(ctx, 'save'),
              ),
              if (same.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: everywhere,
                  onChanged: (v) => setD(() => everywhere = v == true),
                  title: Text('Исправить везде, где распознано «${_orig[i]}» (ещё ${same.length})'),
                ),
            ]),
          ),
          actions: [
            if (_changed(i)) TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('Как было')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, hidden ? 'show' : 'hide'),
              child: Text(hidden ? 'Показать слово' : 'Скрыть слово', style: TextStyle(color: hidden ? null : C.red)),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Готово')),
          ],
        ),
      ),
    );
    if (res == null || !mounted) return;
    final targets = [i, if (everywhere) ...same];
    setState(() {
      for (final j in targets) {
        switch (res) {
          case 'save':
            _apply(j, text: ctrl.text, hide: ctrl.text.trim().isEmpty ? null : false);
          case 'hide':
            _apply(j, hide: true);
          case 'show':
            _apply(j, hide: false);
          case 'reset':
            _apply(j, text: _orig[j], hide: false);
        }
      }
    });
  }

  /// Правка фразы целиком. Новые слова раскладываются по старым местам: лишние места скрываются,
  /// а если слов стало больше — в одно место ложится несколько слов, сервер поделит его время.
  Future<void> _editLine(int li) async {
    final line = _lines[li];
    final idx = [for (var i = line.first; i <= line.last; i++) i];
    final ctrl = TextEditingController(text: [for (final i in idx) if (!_hidden(i)) _words[i]['w']].join(' '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Фраза в субтитрах'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Распознано: «${[for (final i in idx) _orig[i]].join(' ')}»',
                style: const TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(controller: ctrl, autofocus: true, minLines: 1, maxLines: 4),
            const SizedBox(height: 8),
            const Text('Пиши как угодно: можно добавить, убрать или переставить слова — время подстроится само.',
                style: TextStyle(color: C.faint, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.text = [for (final i in idx) _orig[i]].join(' ');
            },
            child: const Text('Как было'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Готово')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nw = ctrl.text.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    setState(() {
      if (nw.isEmpty) {
        for (final i in idx) {
          _apply(i, hide: true);
        }
        return;
      }
      if (nw.length <= idx.length) {
        for (var k = 0; k < idx.length; k++) {
          if (k < nw.length) {
            _apply(idx[k], text: nw[k], hide: false);
          } else {
            _apply(idx[k], hide: true);
          }
        }
        return;
      }
      // Слов больше, чем мест: раздаём их поровну по местам.
      var from = 0;
      for (var k = 0; k < idx.length; k++) {
        final to = ((k + 1) * nw.length / idx.length).round();
        _apply(idx[k], text: nw.sublist(from, to).join(' '), hide: false);
        from = to;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final changes = [
      for (final i in _dirty.toList())
        if (!_changed(i)) {'i': i, 'reset': true} else {'i': i, 'w': _words[i]['w'], 'hide': _hidden(i)}
    ];
    try {
      await Api.i.put('/api/sources/${widget.sourceId}/words', {'changes': changes});
      if (!mounted) return;
      setState(() {
        for (final i in _touched) {
          _savedW[i] = _words[i]['w'].toString();
          _savedX[i] = _words[i]['x'] == true;
        }
        _touched.clear();
      });
      toast(context, 'Сохранено. Готовые ролики из этого видео нужно собрать заново — у них появится кнопка.');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _play(int li) async {
    final line = _lines[li];
    final start = _d(_words[line.first]['s']), end = _d(_words[line.last]['e']);
    var p = _player;
    if (p == null) {
      p = VideoPlayerController.networkUrl(Uri.parse(Api.i.sourceProxyUrl(widget.sourceId)));
      _player = p;
      try {
        await p.initialize();
      } catch (_) {
        if (mounted) toast(context, 'Не получилось открыть видео для прослушивания');
        _player = null;
        await p.dispose();
        return;
      }
      p.addListener(_tick);
      if (mounted) setState(() => _playerReady = true);
    }
    _stopAt = end + 0.15;
    setState(() => _playingLine = li);
    await p.seekTo(Duration(milliseconds: ((start - 0.15).clamp(0, double.infinity) * 1000).round()));
    await p.play();
  }

  void _tick() {
    final p = _player;
    if (p == null || !p.value.isPlaying) return;
    if (p.value.position.inMilliseconds / 1000 >= _stopAt) {
      p.pause();
      if (mounted) setState(() => _playingLine = null);
    }
  }

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Сохранить исправления?'),
          content: Text('Изменено слов: ${_dirty.length}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти без сохранения')),
            FilledButton(
              onPressed: () async {
                await _save();
                if (ctx.mounted) Navigator.pop(ctx, _dirty.isEmpty);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ) ==
      true;

  String _time(double s) => '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final visible = <int>[
      for (var li = 0; li < _lines.length; li++)
        if (_query.isEmpty ||
            [for (var i = _lines[li].first; i <= _lines[li].last; i++) _words[i]['w'].toString()]
                .join(' ')
                .toLowerCase()
                .contains(_query))
          li
    ];
    final changedCount = [for (var i = 0; i < _words.length; i++) if (_changed(i)) i].length;

    return PopScope(
      canPop: _dirty.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Субтитры · ${widget.fileName}', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _dirty.isEmpty || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Сохранить'),
                style: FilledButton.styleFrom(backgroundColor: C.violet),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: C.red)))
                : Column(children: [
                    Content(
                      maxWidth: 900,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 12, wide ? 24 : 16, 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(
                            'Нажми на слово, чтобы исправить или скрыть его. Исправления попадут во все ролики из этого видео.'
                            '${changedCount > 0 ? ' Изменено слов: $changedCount.' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded, size: 20),
                              hintText: 'Найти слово',
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                          ),
                          if (_playerReady && _player != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Center(
                                child: SizedBox(
                                  height: 150,
                                  child: AspectRatio(
                                    aspectRatio: _player!.value.aspectRatio,
                                    child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10), child: VideoPlayer(_player!)),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 40),
                        itemCount: visible.length,
                        itemBuilder: (_, k) => Content(maxWidth: 900, child: _lineView(visible[k], wide)),
                      ),
                    ),
                  ]),
      ),
    );
  }

  Widget _lineView(int li, bool wide) {
    final line = _lines[li];
    final playing = _playingLine == li;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        decoration: BoxDecoration(
          color: playing ? C.violet.withValues(alpha: 0.12) : C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: playing ? C.violet : C.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 64,
            child: Column(children: [
              if (_hasProxy)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Послушать',
                  icon: Icon(playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                      color: playing ? C.violet : C.muted, size: 20),
                  onPressed: () => _play(li),
                ),
              Text(_time(_d(_words[line.first]['s'])), style: const TextStyle(color: C.faint, fontSize: 11)),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Править фразу целиком',
                icon: const Icon(Icons.edit_note_rounded, color: C.muted, size: 20),
                onPressed: () => _editLine(li),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (var i = line.first; i <= line.last; i++) _wordChip(i),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _wordChip(int i) {
    final hidden = _hidden(i), changed = _changed(i);
    return InkWell(
      onTap: () => _editWord(i),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: changed && !hidden ? C.violet.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _words[i]['w'].toString(),
          style: TextStyle(
            fontSize: 15,
            color: hidden ? C.faint : C.text,
            decoration: hidden ? TextDecoration.lineThrough : null,
            decorationColor: C.faint,
          ),
        ),
      ),
    );
  }
}
