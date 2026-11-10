import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'ui.dart';

/// Мои подписи к рилсам: файл .txt (блоки через ---, «Тема:» первой строкой, хэштеги последней).
Future<void> showCaptionsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _CaptionsDialog());

class _CaptionsDialog extends StatefulWidget {
  const _CaptionsDialog();
  @override
  State<_CaptionsDialog> createState() => _CaptionsDialogState();
}

class _CaptionsDialogState extends State<_CaptionsDialog> {
  List<Map> _items = [];
  double _share = 30;
  bool _loading = true, _busy = false;
  final _paste = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/api/captions') as Map;
      if (!mounted) return;
      setState(() {
        _items = (r['items'] as List).cast<Map>();
        _share = (r['share'] as num).toDouble();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, e.toString());
      }
    }
  }

  Future<void> _add(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await Api.i.post('/api/captions', {'text': text});
      if (!mounted) return;
      final skipped = (r['skipped'] as num?)?.toInt() ?? 0;
      toast(context, 'Добавлено подписей: ${r['added']}${skipped > 0 ? ', уже были: $skipped' : ''}');
      _paste.clear();
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['txt', 'md'], withData: true);
    final bytes = r?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    await _add(utf8.decode(bytes, allowMalformed: true));
  }

  Future<void> _delete(String id) async {
    try {
      await Api.i.delete('/api/captions/$id');
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Мои подписи к рилсам'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text(
                      'AI пишет подписи в твоём стиле, а часть роликов получает твои готовые подписи — '
                      'самые подходящие по теме. Файл .txt: подписи через строку ---, первая строка «Тема: …», '
                      'последняя — хэштеги.',
                      style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.35)),
                  const SizedBox(height: 12),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Загрузить файл'),
                      style: FilledButton.styleFrom(backgroundColor: C.violet),
                    ),
                    const SizedBox(width: 10),
                    if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _paste,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Или вставь текст сюда', isDense: true),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _busy ? null : () => _add(_paste.text), child: const Text('Добавить')),
                  ),
                  Text('Роликов с моими подписями: ${_share.round()}%',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _share,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: C.violet,
                    onChanged: (v) => setState(() => _share = v),
                    onChangeEnd: (v) => Api.i.put('/api/captions/settings', {'share': v.round()}).ignore(),
                  ),
                  const Text('Остальным AI напишет новые подписи в том же стиле. Работает для новых вариантов.',
                      style: TextStyle(color: C.faint, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text('Всего: ${_items.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_items.isNotEmpty)
                      TextButton(
                          onPressed: () => _delete('all'),
                          child: const Text('Удалить все', style: TextStyle(color: C.red))),
                  ]),
                  for (final it in _items)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      decoration:
                          BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(10)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if ('${it['topic']}'.isNotEmpty)
                              Text('${it['topic']}',
                                  style: const TextStyle(fontSize: 12, color: C.violet, fontWeight: FontWeight.w600)),
                            Text('${it['body']}',
                                maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            Text(
                                '${((it['hashtags'] as List?) ?? const []).join(' ')}'
                                '${(it['used'] as num? ?? 0) > 0 ? ' · использована ${it['used']} раз' : ''}',
                                style: const TextStyle(fontSize: 11.5, color: C.muted)),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Удалить',
                          onPressed: () => _delete(it['id'] as String),
                          icon: const Icon(Icons.close_rounded, size: 18, color: C.faint),
                        ),
                      ]),
                    ),
                ]),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Готово'))],
    );
  }
}
