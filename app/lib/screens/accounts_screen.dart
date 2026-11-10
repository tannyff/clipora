import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/originality_view.dart';
import '../widgets/subtitle_preview.dart';
import '../widgets/ui.dart';
import 'editor_screen.dart';
import 'project_screen.dart';
import 'subtitles_screen.dart';

String _folderName(String name) => name.isEmpty ? 'Без аккаунта' : name;

/// Вкладка «Аккаунты»: папка на каждый аккаунт Instagram со статистикой.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.visible});
  final bool visible;
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Map> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _load();
  }

  // Вкладка живёт в IndexedStack — обновляем, когда её открыли, а не при запуске приложения.
  @override
  void didUpdateWidget(AccountsScreen old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/api/accounts') as List;
      if (mounted) setState(() => _folders = r.cast<Map>());
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    // Пустую «Без аккаунта» не показываем — она только мешает.
    final folders = _folders.where((f) => (f['name'] as String).isNotEmpty || (f['total'] as int? ?? 0) > 0).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(wide ? 40 : 20, wide ? 36 : 12, wide ? 40 : 20, 40), children: [
        Content(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Аккаунты', style: display(wide ? 34 : 28)),
            const SizedBox(height: 4),
            Text('Собранные ролики по аккаунтам, куда ты их выкладываешь. Аккаунты добавляются в «Настройках».',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            CardGrid(minWidth: 300, children: [for (final f in folders) _folderCard(f)]),
          ]),
        ),
      ]),
    );
  }

  Widget _folderCard(Map f) {
    int n(String k) => f[k] as int? ?? 0;
    final t = Theme.of(context).textTheme;
    final trial = f['kind'] == 'trial';
    return Panel(
      onTap: () async {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => AccountFolderScreen(destination: f['name'] as String)));
        _load();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon((f['name'] as String).isEmpty ? Icons.folder_off_outlined : Icons.folder_rounded,
              color: trial ? C.pink : C.violet),
          const SizedBox(width: 10),
          Expanded(child: Text(_folderName(f['name'] as String), style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('${n('total')}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill('ждут выгрузки: ${n('waiting')}', color: C.yellow),
          Pill('скачаны: ${n('downloaded')}', color: C.violet),
          Pill('опубликованы: ${n('published')}', color: C.green),
          if (n('building') > 0) Pill('собираются: ${n('building')}', dot: true),
        ]),
        const SizedBox(height: 10),
        Text('Сегодня: собрано ${n('built_today')}, опубликовано ${n('published_today')}', style: t.bodySmall),
        Text('За 7 дней: собрано ${n('built_week')}, опубликовано ${n('published_week')}', style: t.bodySmall),
      ]),
    );
  }
}

const _filters = [
  ('all', 'Все'),
  ('waiting', 'Ждут выгрузки'),
  ('downloaded', 'Скачаны'),
  ('unpublished', 'Не опубликованы'),
  ('published', 'Опубликованы'),
];

const _sorts = [('new', 'Сначала новые'), ('old', 'Сначала старые'), ('project', 'По проектам')];

/// Папка одного аккаунта: ролики карточками, фильтр, сортировка и действия сразу с несколькими.
class AccountFolderScreen extends StatefulWidget {
  const AccountFolderScreen({super.key, required this.destination});
  final String destination;
  @override
  State<AccountFolderScreen> createState() => _AccountFolderScreenState();
}

class _AccountFolderScreenState extends State<AccountFolderScreen> {
  List<Map> _items = [];
  List<String> _accounts = [];
  Map _styles = {};
  bool _loading = true, _busy = false;
  String _filter = 'all', _sort = 'new';
  final Set<String> _sel = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStatic();
    // Пока что-то собирается — тихо обновляем статус.
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_items.any((v) => const ['queued', 'rendering'].contains(v['status']))) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatic() async {
    try {
      final r = await Future.wait([Api.i.get('/api/destinations'), Api.i.get('/api/styles')]);
      if (!mounted) return;
      setState(() {
        _accounts = [for (final d in r[0] as List) (d as Map)['name'] as String];
        _styles = r[1] as Map;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final q = 'destination=${Uri.encodeQueryComponent(widget.destination)}&filter=$_filter&sort=$_sort';
      final r = await Api.i.get('/api/accounts/videos?$q') as List;
      if (!mounted) return;
      setState(() {
        _items = r.cast<Map>();
        _sel.removeWhere((id) => !_items.any((v) => v['id'] == id));
      });
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Один ролик ----------

  Future<bool> _download(Map v, {bool ask = true}) async {
    final id = v['id'] as String;
    try {
      await Api.i.post('/api/variants/$id/export', {'destination': widget.destination});
    } on ApiError catch (e) {
      if (e.status == 409 && e.data?['needs_confirm'] == true) {
        if (!ask || !mounted) return false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ролик почти копия'),
            content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                    child: OriginalityView(report: (e.data!['originality'] as Map).cast<String, dynamic>()))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Всё равно скачать')),
              FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не скачивать')),
            ],
          ),
        );
        if (ok != true) return false;
        await Api.i.post('/api/variants/$id/export', {'destination': widget.destination, 'force': true});
      } else {
        rethrow;
      }
    }
    await launchUrl(Uri.parse(Api.i.mediaUrl(id, download: true)), webOnlyWindowName: '_blank');
    return true;
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    _load();
  }

  Future<String?> _pickAccount(String title) => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: Text(title), children: [
          for (final a in [..._accounts, ''])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(a.isEmpty ? Icons.folder_off_outlined : Icons.folder_rounded, size: 18, color: C.violet),
                  const SizedBox(width: 10),
                  Text(_folderName(a)),
                  if (a == widget.destination) const Text('  · сейчас здесь', style: TextStyle(color: C.muted)),
                ]),
              ),
            ),
        ]),
      );

  Future<void> _changeLook(Map v) async {
    if (_styles.isEmpty) await _loadStatic();
    if (!mounted || _styles.isEmpty) return;
    final picked = await showLookDialog(context,
        variant: v, styles: _styles, look: (v['look'] as Map?)?.cast<String, dynamic>() ?? const {});
    if (picked == null) return;
    await _run(() async {
      await Api.i.post('/api/variants/render', {
        'ids': [v['id']],
        'look': picked,
      });
      if (mounted) toast(context, 'Пересобираю ролик с новым оформлением');
    });
  }

  Future<void> _menu(Map v, String a) async {
    final id = v['id'] as String;
    switch (a) {
      case 'move':
        final to = await _pickAccount('Перенести в папку');
        if (to == null || to == widget.destination) return;
        await _run(() => Api.i.put('/api/variants/$id/destination', {'destination': to}));
      case 'edit':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(variantId: id)));
        _load();
      case 'look':
        await _changeLook(v);
      case 'subs':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => SubtitlesScreen(sourceId: v['source_id'] as String, fileName: 'исходник')));
        _load();
      case 'project':
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: v['project_id'] as String)));
        _load();
      case 'copy':
        final tags = ((v['hashtags'] as List?) ?? const []).join(' ');
        await Clipboard.setData(ClipboardData(text: '${v['caption'] ?? ''}\n\n$tags'));
        if (mounted) toast(context, 'Описание скопировано');
      case 'delete':
        if (await _confirmDelete(1)) await _run(() => Api.i.delete('/api/variants/$id'));
    }
  }

  Future<bool> _confirmDelete(int n) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(n == 1 ? 'Удалить ролик?' : 'Удалить роликов: $n?'),
          content: const Text('Видео удалится с сервера. Вернуть его будет нельзя.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ) ==
      true;

  void _play(Map v) => showDialog(context: context, builder: (_) => _VideoDialog(url: Api.i.mediaUrl(v['id'] as String)));

  // ---------- Несколько сразу ----------

  Future<void> _bulk(String action, {String? destination}) async {
    final ids = _sel.toList();
    if (action == 'delete' && !await _confirmDelete(ids.length)) return;
    setState(() => _busy = true);
    await _run(() async {
      final r = await Api.i.post('/api/accounts/bulk', {'ids': ids, 'action': action, if (destination != null) 'destination': destination});
      if (mounted) toast(context, 'Готово: ${r['changed']}');
      setState(_sel.clear);
    });
    if (mounted) setState(() => _busy = false);
  }

  // Браузер скачивает по одному с паузой, иначе часть файлов он молча отбросит.
  Future<void> _bulkDownload() async {
    final list = _items.where((v) => _sel.contains(v['id']) && const ['ready', 'exported'].contains(v['status'])).toList();
    setState(() => _busy = true);
    var ok = 0, skipped = 0;
    for (final v in list) {
      try {
        if (await _download(v, ask: false)) {
          ok++;
        } else {
          skipped++;
        }
      } catch (_) {
        skipped++;
      }
      await Future.delayed(const Duration(milliseconds: 700));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sel.clear();
    });
    toast(context,
        'Скачано: $ok${skipped > 0 ? '. Пропущено: $skipped — почти копии или ещё не собраны, скачай их по одному' : ''}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final selecting = _sel.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? 'Выбрано: ${_sel.length}' : _folderName(widget.destination)),
        actions: [
          if (selecting)
            TextButton(
                onPressed: () => setState(() => _sel.addAll(_items.map((v) => v['id'] as String))),
                child: const Text('Все'))
          else
            PopupMenuButton<String>(
              tooltip: 'Сортировка',
              icon: const Icon(Icons.sort_rounded),
              onSelected: (s) {
                setState(() => _sort = s);
                _load();
              },
              itemBuilder: (_) => [
                for (final (id, name) in _sorts)
                  CheckedPopupMenuItem(value: id, checked: _sort == id, child: Text(name)),
              ],
            ),
          if (selecting) IconButton(onPressed: () => setState(_sel.clear), icon: const Icon(Icons.close_rounded)),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: selecting ? _bulkBar() : null,
      body: Column(children: [
        Content(
          child: SizedBox(
            height: 52,
            child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 16, vertical: 8),
                children: [
                  for (final (id, name) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: _filter == id,
                        onSelected: (_) {
                          setState(() => _filter = id);
                          _load();
                        },
                        selectedColor: C.violet.withValues(alpha: 0.25),
                        side: BorderSide(color: _filter == id ? C.violet : C.border),
                        showCheckmark: false,
                      ),
                    ),
                ]),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'Здесь пока пусто',
                      text: 'Выбери этот аккаунт на карточке готового ролика в проекте — ролик появится в папке.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: EdgeInsets.fromLTRB(wide ? 40 : 16, 4, wide ? 40 : 16, 40), children: [
                        Content(child: CardGrid(minWidth: 340, gap: 12, children: [for (final v in _items) _card(v)])),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _bulkBar() => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))),
          child: _busy
              ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                      onPressed: _bulkDownload,
                      style: FilledButton.styleFrom(backgroundColor: C.violet),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Скачать')),
                  OutlinedButton.icon(
                      onPressed: () async {
                        final to = await _pickAccount('Перенести в папку');
                        if (to != null && to != widget.destination) await _bulk('move', destination: to);
                      },
                      icon: const Icon(Icons.drive_file_move_outline, size: 18),
                      label: const Text('Перенести')),
                  OutlinedButton.icon(
                      onPressed: () => _bulk('publish'),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: const Text('Опубликованы')),
                  OutlinedButton.icon(
                      onPressed: () => _bulk('unpublish'),
                      icon: const Icon(Icons.remove_done_rounded, size: 18),
                      label: const Text('Снять отметку')),
                  OutlinedButton.icon(
                      onPressed: () => _bulk('delete'),
                      style: OutlinedButton.styleFrom(foregroundColor: C.red),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Удалить')),
                ]),
        ),
      );

  Widget _card(Map v) {
    final id = v['id'] as String;
    final status = v['status'] as String;
    final published = v['published_at'] != null;
    final built = status == 'ready' || status == 'exported';
    final selected = _sel.contains(id);
    final (label, color) = switch (status) {
      _ when published => ('Опубликован', C.green),
      'exported' => ('Скачан', C.violet),
      'ready' => ('Ждёт выгрузки', C.yellow),
      'failed' => ('Ошибка сборки', C.red),
      _ => ('Собирается', C.muted),
    };
    final t = Theme.of(context).textTheme;
    return Panel(
      padding: EdgeInsets.zero,
      onTap: _sel.isNotEmpty ? () => setState(() => selected ? _sel.remove(id) : _sel.add(id)) : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: selected ? C.violet : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Превью 9:16: нажми — посмотреть ролик.
          GestureDetector(
            onTap: _sel.isNotEmpty ? null : (built ? () => _play(v) : null),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 72,
                height: 128,
                child: Stack(fit: StackFit.expand, children: [
                  Container(color: C.surface2),
                  if (built)
                    Image.network(Api.i.thumbUrl(id, v['rendered_at']),
                        fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  if (built) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 28)),
                  if (!built && status != 'failed')
                    const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text('«${v['hook_text'] ?? v['title'] ?? ''}»',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  constraints: const BoxConstraints(minWidth: 220),
                  icon: const Icon(Icons.more_horiz_rounded, color: C.muted),
                  onSelected: (a) => _menu(v, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'move', child: Text('Перенести в другую папку')),
                    if (status != 'queued' && status != 'rendering') ...[
                      const PopupMenuItem(value: 'edit', child: Text('Монтаж')),
                      const PopupMenuItem(value: 'look', child: Text('Оформление и надписи')),
                      const PopupMenuItem(value: 'subs', child: Text('Текст субтитров')),
                    ],
                    const PopupMenuItem(value: 'copy', child: Text('Скопировать описание')),
                    const PopupMenuItem(value: 'project', child: Text('Открыть проект')),
                    const PopupMenuItem(value: 'delete', child: Text('Удалить ролик')),
                  ],
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: selected,
                    onChanged: (x) => setState(() => x == true ? _sel.add(id) : _sel.remove(id)),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text('${v['project_title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill(label, color: color, dot: true),
                if (v['duration'] != null) Pill(formatDuration(v['duration'] as num), icon: Icons.timer_outlined),
              ]),
              const SizedBox(height: 8),
              // Wrap: на узкой карточке кнопки переносятся, а не вылезают за край.
              Wrap(spacing: 4, runSpacing: 0, children: [
                if (built)
                  TextButton.icon(
                    onPressed: () => _run(() async {
                      await _download(v);
                    }),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Скачать'),
                  ),
                if (built)
                  TextButton.icon(
                    onPressed: () => _run(() => Api.i.put('/api/variants/$id/published', {'published': !published})),
                    icon: Icon(published ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18, color: published ? C.green : null),
                    label: Text(published ? 'Опубликован' : 'Опубликовала'),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _VideoDialog extends StatefulWidget {
  const _VideoDialog({required this.url});
  final String url;
  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c
        ..setLooping(true)
        ..play();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.sizeOf(context).height * 0.8).clamp(300.0, 800.0);
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: h,
        width: h * 9 / 16,
        child: Stack(children: [
          Positioned.fill(
            child: _ready
                ? GestureDetector(
                    onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(width: _c.value.size.width, height: _c.value.size.height, child: VideoPlayer(_c)),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
                onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}
