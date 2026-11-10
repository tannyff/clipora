import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../theme.dart';
import '../upload/upload.dart';
import '../widgets/ui.dart';

class _Upload {
  _Upload(this.name);
  final String name;
  double progress = 0;
  String? error;
}

/// Медиатека: красивые кадры-вставки (работа, кофе, руки, улица), общие для всех роликов.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Map> _items = [];
  bool _loaded = false;
  String? _tag;
  bool _split = true;
  final _uploads = <_Upload>[];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_items.any((m) => m['status'] == 'uploaded' || m['status'] == 'processing')) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/api/media');
      if (!mounted) return;
      setState(() {
        _items = (r as List).cast<Map>();
        _loaded = true;
      });
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _add({bool camera = false}) async {
    List<PickedVideo> files;
    try {
      files = await pickVideos(camera: camera);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось открыть выбор файла: $e');
      return;
    }
    if (files.isEmpty || !mounted) return;
    final items = [for (final f in files) _Upload(f.name)];
    setState(() => _uploads.insertAll(0, items));
    for (var i = 0; i < files.length; i++) {
      try {
        final url = '${Api.i.mediaUploadUrl(files[i].name)}${_split ? '&split=1' : ''}';
        await uploadVideo(files[i], url, (p) {
          if (mounted) setState(() => items[i].progress = p);
        });
        if (mounted) setState(() => _uploads.remove(items[i]));
      } catch (e) {
        if (mounted) setState(() => items[i].error = e.toString());
      }
      _load();
    }
  }

  Set<String> get _allTags => {
        for (final m in _items)
          for (final t in (m['tags'] as List? ?? const [])) '$t'
      };

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final t = Theme.of(context).textTheme;
    final tags = _allTags.toList()..sort();
    final shown = _tag == null ? _items : _items.where((m) => (m['tags'] as List? ?? const []).contains(_tag)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 16, wide ? 36 : 12, wide ? 40 : 16, 40),
      children: [
        Content(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Вставки', style: display(wide ? 34 : 28)),
            const SizedBox(height: 6),
            Text(
              'Красивые кадры для перебивок: работа за ноутбуком, кофе, руки, улица. '
              'Их можно ставить в начало ролика, между фразами или поверх голоса — в монтаже любого ролика.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 18),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 10, runSpacing: 10, children: [
                  GradientButton(label: 'Загрузить видео', icon: Icons.add_rounded, onPressed: () => _add()),
                  OutlinedButton.icon(
                    onPressed: () => _add(camera: true),
                    icon: const Icon(Icons.videocam_outlined, size: 18),
                    label: const Text('Снять сейчас'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      side: const BorderSide(color: C.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _split,
                  activeColor: C.violet,
                  onChanged: (v) => setState(() => _split = v),
                  title: const Text('Нарезать длинное видео на куски', style: TextStyle(fontSize: 14)),
                  subtitle: Text('По сменам плана, каждый кусок 1–4 секунды. Лишние потом можно удалить.',
                      style: t.bodySmall),
                ),
                for (final u in _uploads)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 10),
                      if (u.error != null)
                        Flexible(child: Text(u.error!, style: const TextStyle(color: C.red, fontSize: 12)))
                      else
                        SizedBox(width: 120, child: LinearProgressIndicator(value: u.progress)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  _tagChip('Все', _tag == null, () => setState(() => _tag = null)),
                  for (final tg in tags) _tagChip(tg, _tag == tg, () => setState(() => _tag = tg)),
                ]),
              ),
            if (_loaded && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyState(
                  icon: Icons.movie_filter_outlined,
                  title: 'Пока пусто',
                  text: 'Загрузи видео с красивыми кадрами — например, минуту работы за столом. '
                      'Clipora сама нарежет его на короткие вставки.',
                ),
              ),
            Wrap(spacing: 10, runSpacing: 12, children: [
              for (final m in shown) _tile(m, wide ? 150 : (MediaQuery.sizeOf(context).width - 32 - 20) / 3),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _tagChip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: C.violet.withValues(alpha: 0.25),
        side: BorderSide(color: selected ? C.violet : C.border),
      );

  Widget _tile(Map m, double w) {
    final ready = m['status'] == 'ready';
    final failed = m['status'] == 'failed';
    final used = (m['used'] as num?)?.toInt() ?? 0;
    final tags = (m['tags'] as List? ?? const []).join(', ');
    return SizedBox(
      width: w,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: C.surface2,
            child: InkWell(
              onTap: ready ? () => _open(m) : null,
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: Stack(fit: StackFit.expand, children: [
                  if (ready)
                    Image.network(Api.i.libraryThumbUrl(m['id'] as String),
                        fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  if (!ready && !failed)
                    const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(height: 8),
                        Text('Обрабатываю', style: TextStyle(fontSize: 11, color: C.muted)),
                      ]),
                    ),
                  if (failed)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(
                        child: Text('Ошибка: ${m['error'] ?? ''}',
                            maxLines: 5, style: const TextStyle(fontSize: 11, color: C.red)),
                      ),
                    ),
                  if (ready)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _badge('${((m['duration'] as num?) ?? 0).toStringAsFixed(1).replaceAll('.', ',')} с'),
                    ),
                  if (used > 0) Positioned(right: 6, bottom: 6, child: _badge('в $used')),
                  if (failed)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => _delete(m),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(tags.isEmpty ? (m['file_name'] as String? ?? '') : tags,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
      ]),
    );
  }

  Widget _badge(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
        child: Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
      );

  Future<void> _delete(Map m) async {
    try {
      await Api.i.delete('/api/media/${m['id']}');
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _open(Map m) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _MediaDialog(item: m, allTags: _allTags));
    if (changed == true) _load();
  }
}

class _MediaDialog extends StatefulWidget {
  const _MediaDialog({required this.item, required this.allTags});
  final Map item;
  final Set<String> allTags;
  @override
  State<_MediaDialog> createState() => _MediaDialogState();
}

class _MediaDialogState extends State<_MediaDialog> {
  late final VideoPlayerController _vc =
      VideoPlayerController.networkUrl(Uri.parse(Api.i.libraryProxyUrl(widget.item['id'] as String)));
  late final List<String> _tags = [for (final t in (widget.item['tags'] as List? ?? const [])) '$t'];
  final _input = TextEditingController();
  bool _dirty = false;

  static const _suggest = ['работа', 'ноутбук', 'кофе', 'руки', 'улица', 'город', 'природа', 'еда', 'спорт', 'детали'];

  @override
  void initState() {
    super.initState();
    _vc.initialize().then((_) {
      if (!mounted) return;
      _vc.setLooping(true);
      _vc.setVolume(0);
      _vc.play();
      setState(() {});
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _vc.dispose();
    _input.dispose();
    super.dispose();
  }

  void _addTag(String t) {
    t = t.trim().toLowerCase();
    if (t.isEmpty || _tags.contains(t)) return;
    setState(() {
      _tags.add(t);
      _dirty = true;
    });
    _input.clear();
  }

  Future<void> _save() async {
    try {
      if (_dirty) await Api.i.put('/api/media/${widget.item['id']}', {'tags': _tags});
      if (mounted) Navigator.pop(context, _dirty);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _delete() async {
    try {
      await Api.i.delete('/api/media/${widget.item['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.sizeOf(context).height * 0.45).clamp(220.0, 480.0);
    final suggest = {..._suggest, ...widget.allTags}.where((t) => !_tags.contains(t)).take(14).toList();
    return Dialog(
      backgroundColor: C.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: SizedBox(
                height: h,
                width: h * 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: _vc.value.isInitialized
                        ? FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                                width: _vc.value.size.width, height: _vc.value.size.height, child: VideoPlayer(_vc)),
                          )
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Метки', style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in _tags)
                InputChip(
                  label: Text(t),
                  onDeleted: () => setState(() {
                    _tags.remove(t);
                    _dirty = true;
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _input,
              decoration: const InputDecoration(hintText: 'Новая метка и Enter', isDense: true),
              onSubmitted: _addTag,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in suggest)
                ActionChip(
                  label: Text('+ $t', style: const TextStyle(fontSize: 12.5)),
                  onPressed: () => _addTag(t),
                  side: const BorderSide(color: C.border),
                ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded, color: C.red, size: 18),
                label: const Text('Удалить', style: TextStyle(color: C.red)),
              ),
              const Spacer(),
              GradientButton(label: 'Готово', onPressed: _save),
            ]),
          ]),
        ),
      ),
    );
  }
}
