import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../theme.dart';
import '../upload/upload.dart';
import '../widgets/captions_dialog.dart';
import '../widgets/originality_view.dart';
import '../widgets/project_actions.dart';
import '../widgets/subtitle_preview.dart';
import '../widgets/ui.dart';
import 'editor_screen.dart';
import 'subtitles_screen.dart';

const _sourceStatus = {
  'uploaded': ('В очереди', C.muted),
  'transcribing': ('Расшифровываю речь', C.yellow),
  'planning': ('AI подбирает варианты', C.violet),
  'ready': ('Готово', C.green),
  'failed': ('Ошибка', C.red),
};

const _variantStatus = {
  'queued': ('В очереди на сборку', C.muted),
  'rendering': ('Собираю видео', C.yellow),
  'ready': ('Готов к выгрузке', C.green),
  'exported': ('Выгружен', C.violet),
  'failed': ('Ошибка сборки', C.red),
};

class _Upload {
  _Upload(this.name, this.size);
  final String name;
  final int size;
  double progress = 0;
  String? error;
}

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.projectId});
  final String projectId;
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  Map<String, dynamic>? _project;
  List<dynamic> _sources = [];
  List<dynamic> _variants = [];
  Map _styles = {};
  List<dynamic> _destinations = [];
  final Set<String> _selected = {};
  final Map<String, String> _destFor = {};
  final List<_Upload> _uploads = [];
  Map<String, dynamic> _look = {...defaultLook};
  bool _rendering = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadStatic();
    _load();
    _loadAutoCut();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_hasWorkInProgress) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Map? _mix;
  bool get _mixing => const ['queued', 'running'].contains(_mix?['status']);

  bool get _hasWorkInProgress =>
      _mixing ||
      _sources.any((s) => const ['uploaded', 'transcribing', 'planning'].contains(s['status'])) ||
      _variants.any((v) => const ['queued', 'rendering'].contains(v['status']));

  Future<void> _loadStatic() async {
    try {
      final r = await Future.wait([Api.i.get('/api/styles'), Api.i.get('/api/destinations')]);
      if (!mounted) return;
      setState(() {
        _styles = r[0] as Map;
        _destinations = r[1] as List;
      });
    } catch (_) {}
  }

  final Set<String> _warmed = {};

  // Окно оформления открывается на первом варианте — собираем его кадры заранее, пока ты смотришь список.
  void _warmLook() {
    final v = _variants.where((x) => x['status'] == 'proposed').firstOrNull;
    if (v == null || !_warmed.add(v['id'] as String)) return;
    final path = '/api/variants/${v['id']}';
    Api.i.post('$path/preview', {'look': _look, 'layers': true}).then((_) {
      for (final g in const ['title', 'palette']) {
        Api.i.post('$path/preview-grid', {'look': _look, 'vary': g}).ignore();
      }
    }).ignore();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/api/projects/${widget.projectId}');
      if (!mounted) return;
      setState(() {
        _project = (r['project'] as Map).cast<String, dynamic>();
        _sources = r['sources'] as List;
        _variants = r['variants'] as List;
        _mix = r['mix'] as Map?;
      });
      _warmLook();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  bool _picking = false;
  bool? _autoCut;

  Future<void> _loadAutoCut() async {
    try {
      final r = await Api.i.get('/api/captions') as Map;
      if (mounted) setState(() => _autoCut = r['auto_cut'] != false);
    } catch (_) {}
  }

  Future<void> _setAutoCut(bool v) async {
    setState(() => _autoCut = v);
    try {
      await Api.i.put('/api/captions/settings', {'auto_cut': v});
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _upload() async {
    setState(() => _picking = true);
    List<PickedVideo> files;
    try {
      files = await pickVideos();
    } catch (e) {
      if (mounted) setState(() => _picking = false);
      if (mounted) toast(context, 'Не удалось открыть выбор файла: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _picking = false);
    if (files.isEmpty) return;

    final items = [for (final f in files) _Upload(f.name, f.size)];
    setState(() => _uploads.insertAll(0, items));
    for (var i = 0; i < files.length; i++) {
      try {
        await uploadVideo(files[i], Api.i.uploadUrl(widget.projectId, files[i].name), (p) {
          if (mounted) setState(() => items[i].progress = p);
        });
        if (mounted) setState(() => _uploads.remove(items[i]));
      } catch (e) {
        if (mounted) setState(() => items[i].error = e.toString());
      }
      _load();
    }
  }

  // AI собирает новые ролики из кусков всех готовых видео проекта.
  Future<void> _planMix() async {
    try {
      await Api.i.post('/api/projects/${widget.projectId}/plan-mix');
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _replan(String sourceId) async {
    try {
      await Api.i.post('/api/sources/$sourceId/replan');
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _render() async {
    setState(() => _rendering = true);
    try {
      final r = await Api.i.post('/api/variants/render', {'ids': _selected.toList(), 'look': _look});
      if (!mounted) return;
      toast(context, 'Отправлено на сборку: ${r['queued']}');
      setState(_selected.clear);
      await _load();
      _tabs.animateTo(2);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _retry(Map v) async {
    try {
      await Api.i.post('/api/variants/render', {'ids': [v['id']], 'look': v['look'] ?? _look});
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  // Готовый ролик: новое оформление (субтитры, заголовок, плашка…) и сразу пересборка.
  Future<void> _changeLook(Map v) async {
    if (_styles.isEmpty) await _loadStatic();
    if (!mounted || _styles.isEmpty) return;
    final current = (v['look'] as Map?)?.cast<String, dynamic>() ?? _look;
    final picked = await showLookDialog(context, variant: v, styles: _styles, look: current);
    if (picked == null || !mounted) return;
    try {
      await Api.i.put('/api/variants/${v['id']}/look', {'look': picked});
      await Api.i.post('/api/variants/render', {
        'ids': [v['id']],
        'look': picked,
      });
      if (mounted) toast(context, 'Пересобираю ролик с новым оформлением');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    _load();
  }

  Future<void> _openSubtitles(Map v) async {
    final s = _sources.where((x) => x['id'] == v['source_id']).firstOrNull;
    if (s == null) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => SubtitlesScreen(sourceId: s['id'] as String, fileName: s['file_name'] as String)));
    _load();
  }

  Future<void> _preview(List<dynamic> proposed) async {
    if (proposed.isEmpty || _styles.isEmpty) return;
    // Показываем на первом отмеченном варианте, а если ничего не отмечено — на первом в списке.
    final v = proposed.firstWhere((x) => _selected.contains(x['id']), orElse: () => proposed.first) as Map;
    final picked = await showLookDialog(context, variant: v, styles: _styles, look: _look);
    if (picked != null && mounted) setState(() => _look = picked);
  }

  String? _defaultDest(Map v) {
    final names = [for (final d in _destinations) d['name'] as String];
    return _destFor[v['id']] ?? (v['destination'] as String?) ?? (names.isNotEmpty ? names.first : null);
  }

  Future<void> _export(Map v, {bool force = false}) async {
    final id = v['id'] as String;
    final dest = _defaultDest(v);
    if (dest == null) {
      toast(context, 'Добавь аккаунт в настройках');
      return;
    }
    try {
      await Api.i.post('/api/variants/$id/export', {'destination': dest, 'force': force});
      await launchUrl(Uri.parse(Api.i.mediaUrl(id, download: true)), webOnlyWindowName: '_blank');
      _load();
    } on ApiError catch (e) {
      if (e.status == 409 && e.data?['needs_confirm'] == true && mounted) {
        final report = (e.data!['originality'] as Map).cast<String, dynamic>();
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ролик почти копия'),
            content: SizedBox(width: 420, child: SingleChildScrollView(child: OriginalityView(report: report))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Всё равно выгрузить')),
              FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Доработать')),
            ],
          ),
        );
        if (ok == true) await _export(v, force: true);
        _load();
      } else if (mounted) {
        toast(context, e.toString());
      }
    }
  }

  Future<void> _openEditor(String id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(variantId: id)));
    _load();
  }

  /// После сборки ролик правили в монтаже — видео на сервере уже не совпадает с монтажом.
  bool _editedAfterRender(Map v) {
    final e = DateTime.tryParse('${v['edited_at']}'), r = DateTime.tryParse('${v['rendered_at']}');
    return e != null && r != null && e.isAfter(r);
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
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

  Future<void> _deleteVariant(String id) async {
    if (!await _confirm('Удалить ролик?', 'Видео и монтаж этого ролика удалятся с сервера.')) return;
    try {
      await Api.i.delete('/api/variants/$id');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    _load();
  }

  Future<void> _deleteSource(Map s) async {
    final n = _variants.where((v) => v['source_id'] == s['id']).length;
    if (!await _confirm('Удалить исходник?',
        'Удалится видео «${s['file_name']}» и все $n вариантов и роликов из него. Освободится место на диске.')) {
      return;
    }
    try {
      await Api.i.delete('/api/sources/${s['id']}');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final proposed = _variants.where((v) => v['status'] == 'proposed').toList();
    final made = _variants.where((v) => v['status'] != 'proposed').toList().reversed.toList();
    final wide = isWide(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(_project?['title'] as String? ?? ''),
        actions: [
          if (_project != null)
            ProjectMenu(
              onRename: () async {
                final t = await renameProject(context, widget.projectId, _project!['title'] as String);
                if (t != null && mounted) setState(() => _project!['title'] = t);
              },
              onDelete: () async {
                if (await deleteProject(context, widget.projectId, _project!['title'] as String) && mounted) {
                  toast(context, 'Проект удалён');
                  Navigator.pop(context);
                }
              },
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Content(
            child: Container(
              margin: EdgeInsets.fromLTRB(wide ? 40 : 16, 4, wide ? 40 : 16, 12),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.border),
              ),
              child: TabBar(
                controller: _tabs,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(10)),
                labelColor: Colors.white,
                unselectedLabelColor: C.muted,
                labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13),
                splashBorderRadius: BorderRadius.circular(10),
                tabs: [
                  Tab(height: 36, text: 'Исходники ${_sources.length}'),
                  Tab(height: 36, text: 'Варианты ${proposed.length}'),
                  Tab(height: 36, text: 'Ролики ${made.length}'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _sourcesTab(wide),
        _variantsTab(proposed, wide),
        _madeTab(made, wide),
      ]),
    );
  }

  EdgeInsets _pad(bool wide) => EdgeInsets.fromLTRB(wide ? 40 : 16, 8, wide ? 40 : 16, 40);

  // ---------- Исходники ----------

  Widget _sourcesTab(bool wide) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: _pad(wide), children: [
      Content(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(
            onTap: _upload,
            padding: EdgeInsets.symmetric(vertical: wide ? 40 : 28, horizontal: 20),
            child: Column(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              Text('Загрузить видео', style: t.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Из галереи телефона или с компьютера. Лучше всего — куски по 3–5 минут, где ты говоришь в камеру.',
                textAlign: TextAlign.center,
                style: t.bodySmall,
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => showCaptionsDialog(context),
              icon: const Icon(Icons.notes_rounded, size: 18),
              label: const Text('Мои подписи'),
            ),
            if (_autoCut != null)
              FilterChip(
                label: const Text('Убирать паузы и «эээ»'),
                selected: _autoCut!,
                onSelected: _setAutoCut,
                selectedColor: C.violet.withValues(alpha: 0.25),
                tooltip: 'Для новых вариантов от AI. Монтаж потом можно поправить вручную.',
              ),
            if (_sources.where((s) => s['status'] == 'ready').length >= 2)
              OutlinedButton.icon(
                onPressed: _mixing ? null : _planMix,
                icon: const Icon(Icons.merge_rounded, size: 18),
                label: const Text('Смешать видео'),
              ),
          ]),
          if (_mix != null) ...[
            const SizedBox(height: 12),
            _mixRow(),
          ],
          const SizedBox(height: 16),
          if (_picking) ...[
            Panel(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Ожидаю выбор файла. Видео из «Фото» Safari сначала подготавливает — это может занять минуту.',
                      style: t.bodySmall),
                ),
                TextButton(onPressed: () => setState(() => _picking = false), child: const Text('Отмена')),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          for (final u in _uploads) ...[
            Panel(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(u.error != null ? Icons.error_outline_rounded : Icons.upload_rounded,
                      size: 18, color: u.error != null ? C.red : C.violet),
                  const SizedBox(width: 10),
                  Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (u.error == null)
                    Text('${(u.progress * 100).round()}% · ${formatSize(u.size)}', style: t.bodySmall)
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18, color: C.faint),
                      onPressed: () => setState(() => _uploads.remove(u)),
                    ),
                ]),
                const SizedBox(height: 10),
                if (u.error != null)
                  Text('Не загрузилось: ${u.error}', style: t.bodySmall?.copyWith(color: C.red))
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: u.progress, minHeight: 6),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          for (final s in _sources) ...[_sourceRow(s), const SizedBox(height: 10)],
        ]),
      ),
    ]);
  }

  Widget _sourceRow(Map s) {
    final t = Theme.of(context).textTheme;
    final status = s['status'] as String;
    final (label, color) = _sourceStatus[status] ?? ('', C.muted);
    final count = _variants.where((v) => v['source_id'] == s['id']).length;
    final working = const ['uploaded', 'transcribing', 'planning'].contains(status);

    return Panel(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: working
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(status == 'failed' ? Icons.error_outline_rounded : Icons.check_rounded, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['file_name'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              status == 'failed'
                  ? '${s['error']}'
                  : [
                      label,
                      if (s['duration'] != null) formatDuration(s['duration'] as num),
                      if (status == 'ready') '$count вариантов',
                    ].join(' · '),
              maxLines: status == 'failed' ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: status == 'failed' ? C.red : null),
            ),
          ]),
        ),
        if (s['phrases'] is int && (s['phrases'] as int) > 0)
          IconButton(
            tooltip: 'Текст субтитров',
            icon: const Icon(Icons.subtitles_outlined, color: C.muted, size: 20),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SubtitlesScreen(sourceId: s['id'] as String, fileName: s['file_name'] as String)));
              _load();
            },
          ),
        if (status == 'ready' || status == 'failed')
          TextButton.icon(
            onPressed: () => _replan(s['id'] as String),
            icon: Icon(status == 'failed' ? Icons.refresh_rounded : Icons.auto_awesome_rounded, size: 17),
            label: Text(status == 'failed' ? 'Повторить' : 'Ещё варианты'),
          ),
        if (status == 'ready' || status == 'failed')
          IconButton(
            tooltip: 'Удалить исходник',
            icon: const Icon(Icons.delete_outline_rounded, color: C.faint, size: 20),
            onPressed: () => _deleteSource(s),
          ),
      ]),
    );
  }

  // ---------- Варианты ----------

  // Состояние «Смешать видео»: идёт, готово (сколько роликов) или ошибка.
  Widget _mixRow() {
    final st = _mix?['status'];
    final count = (_mix?['count'] as num?)?.toInt() ?? 0;
    final (IconData icon, Color color, String text) = switch (st) {
      'queued' => (Icons.schedule_rounded, C.muted, 'Смешивание видео в очереди — начнётся, как только сервер освободится'),
      'running' => (Icons.merge_rounded, C.violet, 'AI собирает ролики из кусков разных видео… обычно 1–2 минуты'),
      'failed' => (Icons.error_outline_rounded, C.red, 'Смешать не получилось: ${_mix?['error'] ?? ''}'),
      _ => (Icons.check_circle_rounded, C.green, count > 0
          ? 'Готово: $count ${count == 1 ? 'ролик' : 'роликов'} из нескольких видео — во «Вариантах», с пометкой «Из нескольких видео»'
          : 'Смешивание закончилось, но новых роликов нет'),
    };
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        if (_mixing)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: st == 'failed' ? C.red : C.text))),
        if (st == 'done' && count > 0)
          TextButton(onPressed: () => _tabs.animateTo(1), child: const Text('Открыть')),
        if (st == 'failed') TextButton(onPressed: _planMix, child: const Text('Ещё раз')),
      ]),
    );
  }

  Widget _variantsTab(List<dynamic> proposed, bool wide) {
    if (proposed.isEmpty) {
      return EmptyState(
        icon: Icons.auto_awesome_rounded,
        title: _sources.isEmpty ? 'Сначала загрузи видео' : 'Новых вариантов пока нет',
        text: _sources.isEmpty
            ? 'Во вкладке «Исходники» загрузи съёмку, и AI предложит варианты роликов.'
            : _hasWorkInProgress
                ? 'AI ещё работает. Варианты появятся здесь автоматически.'
                : 'Нажми «Ещё варианты» у исходника, чтобы AI предложил новые.',
      );
    }
    final topics = <String, List<dynamic>>{};
    for (final v in proposed) {
      topics.putIfAbsent(v['topic'] as String? ?? '', () => []).add(v);
    }
    final t = Theme.of(context).textTheme;

    return Column(children: [
      Expanded(
        child: ListView(padding: _pad(wide), children: [
          for (final e in topics.entries)
            Content(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 12, 2, 12),
                  child: Row(children: [
                    Expanded(child: Text(e.key.isEmpty ? 'Без темы' : e.key, style: t.titleLarge)),
                    TextButton(
                      onPressed: () => setState(() {
                        final ids = e.value.map((v) => v['id'] as String);
                        if (ids.every(_selected.contains)) {
                          _selected.removeAll(ids);
                        } else {
                          _selected.addAll(ids);
                        }
                      }),
                      child: const Text('Выбрать тему'),
                    ),
                  ]),
                ),
                CardGrid(minWidth: 300, children: [for (final v in e.value) _variantCard(v)]),
                const SizedBox(height: 12),
              ]),
            ),
        ]),
      ),
      _renderBar(proposed, wide),
    ]);
  }

  Widget _renderBar(List<dynamic> proposed, bool wide) {
    return Container(
      decoration: const BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))),
      child: SafeArea(
        top: false,
        child: Content(
          child: Padding(
            padding: EdgeInsets.fromLTRB(wide ? 40 : 16, 12, wide ? 40 : 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: proposed.isEmpty || _styles.isEmpty ? null : () => _preview(proposed),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: C.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.palette_outlined, size: 19, color: C.violet),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Оформление', style: TextStyle(color: C.muted, fontSize: 12)),
                        Text(_styles.isEmpty ? '…' : lookSummary(_look, _styles),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ]),
                    ),
                    const Text('Настроить и посмотреть', style: TextStyle(color: C.violet, fontSize: 13)),
                    const Icon(Icons.chevron_right_rounded, color: C.violet),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(
                    _selected.isEmpty ? 'Отметь варианты, которые нужно собрать' : 'Выбрано: ${_selected.length}',
                    style: const TextStyle(color: C.muted, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == proposed.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(proposed.map((v) => v['id'] as String));
                    }
                  }),
                  child: Text(_selected.length == proposed.length ? 'Снять все' : 'Все'),
                ),
                const SizedBox(width: 6),
                GradientButton(
                  label: 'Собрать ${_selected.isEmpty ? '' : _selected.length}'.trim(),
                  icon: Icons.movie_creation_rounded,
                  onPressed: _selected.isEmpty ? null : _render,
                  busy: _rendering,
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _variantCard(Map v) {
    final t = Theme.of(context).textTheme;
    final id = v['id'] as String;
    final sel = _selected.contains(id);
    void toggle() => setState(() => sel ? _selected.remove(id) : _selected.add(id));

    return Panel(
      selected: sel,
      onTap: toggle,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Pill(v['hook_type'] as String, color: C.pink),
          const SizedBox(width: 6),
          Pill(formatDuration(v['duration'] as num?), icon: Icons.timer_outlined),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: sel ? C.grad : null,
              border: sel ? null : Border.all(color: C.faint, width: 1.5),
            ),
            child: sel ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
          ),
        ]),
        const SizedBox(height: 14),
        Text('«${v['hook_text']}»', style: display(20)),
        const SizedBox(height: 8),
        Text(v['title'] as String, style: t.bodyMedium?.copyWith(color: C.muted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        Text(v['caption'] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (v['mixed'] == true) const Pill('Из нескольких видео', color: C.violet, icon: Icons.merge_rounded),
          if (v['caption_src'] == 'mine') const Pill('Моя подпись', color: C.pink, icon: Icons.notes_rounded),
          if (v['caption_src'] == 'ai') const Pill('AI в моём стиле', icon: Icons.auto_awesome_rounded),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          if (v['edited'] == true) Pill('Есть правки', color: C.violet, icon: Icons.edit_rounded),
          const Spacer(),
          IconButton(
            tooltip: 'Удалить вариант',
            onPressed: () => _deleteVariant(id),
            icon: const Icon(Icons.delete_outline_rounded, size: 19, color: C.faint),
          ),
          TextButton.icon(
            onPressed: () => _openEditor(id),
            icon: const Icon(Icons.content_cut_rounded, size: 17),
            label: const Text('Монтаж'),
          ),
        ]),
      ]),
    );
  }

  // ---------- Готовые ролики ----------

  Widget _madeTab(List<dynamic> made, bool wide) {
    if (made.isEmpty) {
      return const EmptyState(
        icon: Icons.movie_rounded,
        title: 'Здесь появятся готовые ролики',
        text: 'Выбери варианты во вкладке «Варианты» и нажми «Собрать».',
      );
    }
    return ListView(padding: _pad(wide), children: [
      Content(child: CardGrid(minWidth: 320, children: [for (final v in made) _madeCard(v)])),
    ]);
  }

  Widget _madeCard(Map v) {
    final t = Theme.of(context).textTheme;
    final id = v['id'] as String;
    final status = v['status'] as String;
    final (label, color) = _variantStatus[status] ?? (status, C.muted);
    final report = (v['originality'] as Map?)?.cast<String, dynamic>();
    final done = status == 'ready' || status == 'exported';
    final names = [for (final d in _destinations) d['name'] as String];
    final dest = _defaultDest(v);
    final tags = ((v['hashtags'] as List?) ?? const []).join(' ');

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: C.surface2),
            if (done)
              Image.network(
                Api.i.thumbUrl(id, v['rendered_at']),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            if (!done && status != 'failed')
              const Center(child: SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5))),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 110,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Text('«${v['hook_text']}»',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: display(17).copyWith(color: Colors.white)),
            ),
            Positioned(top: 12, left: 12, child: _badge(label, color)),
            Positioned(top: 12, right: 12, child: _badge(formatDuration(v['duration'] as num?), Colors.white)),
            if (done)
              Center(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => launchUrl(Uri.parse(Api.i.mediaUrl(id)), webOnlyWindowName: '_blank'),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(v['title'] as String, style: t.titleSmall)),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded, color: C.muted),
                onSelected: (a) {
                  if (a == 'edit') _openEditor(id);
                  if (a == 'delete') _deleteVariant(id);
                  if (a == 'retry') _retry(v);
                  if (a == 'look') _changeLook(v);
                  if (a == 'pub') {
                    Api.i.put('/api/variants/$id/published', {'published': v['published_at'] == null}).then((_) => _load(),
                        onError: (Object e) {
                      if (mounted) toast(context, e.toString());
                    });
                  }
                  if (a == 'subs') _openSubtitles(v);
                  if (a == 'copy') {
                    Clipboard.setData(ClipboardData(text: '${v['caption']}\n\n$tags'));
                    toast(context, 'Описание скопировано');
                  }
                },
                itemBuilder: (_) => [
                  if (status != 'queued' && status != 'rendering')
                    const PopupMenuItem(value: 'edit', child: Text('Монтаж')),
                  if (status != 'queued' && status != 'rendering') ...[
                    const PopupMenuItem(value: 'look', child: Text('Оформление и надписи')),
                    const PopupMenuItem(value: 'subs', child: Text('Текст субтитров')),
                  ],
                  if (status == 'ready' || status == 'exported')
                    PopupMenuItem(
                        value: 'pub',
                        child: Text(v['published_at'] == null ? 'Отметить: опубликовала' : 'Снять отметку «опубликован»')),
                  if (status == 'failed' || _editedAfterRender(v))
                    const PopupMenuItem(value: 'retry', child: Text('Собрать заново')),
                  const PopupMenuItem(value: 'copy', child: Text('Скопировать описание')),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить ролик')),
                ],
              ),
            ]),
            if (status == 'failed')
              Text('${v['error']}', style: t.bodySmall?.copyWith(color: C.red)),
            if (status == 'exported') Text('Выгружен → ${v['destination']}', style: t.bodySmall),
            if (done && _editedAfterRender(v))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  onTap: () => _retry(v),
                  child: Text('Монтаж изменён после сборки — нажми, чтобы пересобрать',
                      style: t.bodySmall?.copyWith(color: C.yellow)),
                ),
              ),
            if (status != 'queued' && status != 'rendering') ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openEditor(id),
                    icon: const Icon(Icons.content_cut_rounded, size: 17),
                    label: const Text('Монтаж'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      side: const BorderSide(color: C.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteVariant(id),
                  icon: const Icon(Icons.delete_outline_rounded, size: 17, color: C.red),
                  label: const Text('Удалить', style: TextStyle(color: C.red)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    side: const BorderSide(color: C.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ]),
            ],
            if (report != null) ...[
              const SizedBox(height: 12),
              OriginalityView(report: report, compact: true),
            ],
            if (done) ...[
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: '${v['caption']}\n\n$tags'));
                  toast(context, 'Описание скопировано');
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text('${v['caption']}\n$tags',
                          maxLines: 4, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy_rounded, size: 16, color: C.faint),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                if (names.isNotEmpty)
                  Expanded(
                    child: ChoiceField(
                      value: names.contains(dest) ? dest : names.first,
                      options: names,
                      icon: Icons.alternate_email_rounded,
                      onChanged: (x) {
                        setState(() => _destFor[id] = x);
                        // Сразу запоминаем на сервере — ролик появится в папке этого аккаунта.
                        Api.i.put('/api/variants/$id/destination', {'destination': x}).then((_) {
                          v['destination'] = x;
                        }, onError: (Object e) {
                          if (mounted) toast(context, e.toString());
                        });
                      },
                    ),
                  ),
                const SizedBox(width: 10),
                GradientButton(
                  label: status == 'exported' ? 'Скачать' : 'Выгрузить',
                  icon: Icons.download_rounded,
                  onPressed: () => _export(v),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}
