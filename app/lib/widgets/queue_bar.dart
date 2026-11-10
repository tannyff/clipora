import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// Что сейчас делает сервер и сколько ждёт. Пока очередь пустая — ничего не показывает.
class QueueBar extends StatefulWidget {
  const QueueBar({super.key});
  @override
  State<QueueBar> createState() => _QueueBarState();
}

class _QueueBarState extends State<QueueBar> {
  Map? _q;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  // Пока идёт работа — опрос раз в 4 с, без работы — раз в 15 с.
  Future<void> _tick() async {
    try {
      final r = await Api.i.get('/api/queue') as Map;
      if (mounted) setState(() => _q = r);
    } catch (_) {}
    if (!mounted) return;
    _t = Timer(Duration(seconds: _busy ? 4 : 15), _tick);
  }

  List get _running => (_q?['running'] as List?) ?? const [];
  int get _queued => (_q?['queued'] as num?)?.toInt() ?? 0;
  bool get _busy => _running.isNotEmpty || _queued > 0;

  static const _kinds = {
    'transcribe': 'расшифровывает речь',
    'plan': 'AI подбирает варианты',
    'plan_mix': 'AI смешивает видео',
    'render': 'собирает ролик',
    'proxy': 'готовит видео для монтажа',
    'media': 'обрабатывает вставку',
    'split': 'нарезает вставки',
  };

  String _line(Map r) => '${_kinds[r['kind']] ?? r['kind']}${r['title'] != null ? ' «${r['title']}»' : ''}';

  void _details() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: C.surface,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Сервер сейчас', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 10),
              for (final r in _running)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_line(r as Map), style: const TextStyle(fontSize: 13.5))),
                  ]),
                ),
              Text(_queued == 0 ? 'Больше ничего не ждёт' : 'Ждут очереди: $_queued',
                  style: const TextStyle(color: C.muted, fontSize: 13)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_busy) return const SizedBox.shrink();
    final first = _running.isEmpty ? null : _running.first as Map;
    final renders = (_q?['renders'] as num?)?.toInt() ?? 0;
    return Material(
      color: C.violet.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _details,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  if (first != null) 'Сервер ${_line(first)}',
                  if (_running.length > 1) 'ещё ${_running.length - 1} параллельно',
                  if (_queued > 0) 'в очереди $_queued',
                  if (renders > 0) 'роликов на сборке: $renders',
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
