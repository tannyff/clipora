import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'config.dart';
import 'db.dart';
import 'fonts.dart';
import 'jobs.dart';
import 'originality.dart';
import 'pipeline/captions.dart';
import 'pipeline/edit.dart';
import 'pipeline/render.dart';
import 'pipeline/subtitles.dart';
import 'util.dart';

Object? _enc(Object? o) => o is DateTime ? o.toIso8601String() : o.toString();

Response jsonRes(Object? body, {int status = 200}) => Response(status,
    body: jsonEncode(body, toEncodable: _enc),
    headers: {'content-type': 'application/json; charset=utf-8'});

Response err(String msg, [int status = 400]) => jsonRes({'error': msg}, status: status);

Future<Map<String, dynamic>> readJson(Request r) async {
  final s = await r.readAsString();
  return s.isEmpty ? {} : (jsonDecode(s) as Map).cast<String, dynamic>();
}

const _cors = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
};

Middleware _corsMw() => (inner) => (req) async {
      if (req.method == 'OPTIONS') return Response.ok('', headers: _cors);
      final res = await inner(req);
      return res.change(headers: _cors);
    };

Middleware _errorsMw() => (inner) => (req) async {
      try {
        return await inner(req);
      } catch (e, st) {
        stderr.writeln('API ошибка: $e\n$st');
        return err('Внутренняя ошибка сервера: $e', 500);
      }
    };

typedef Authed = Future<Response> Function(Request req, String uid);

// shelf_router передаёт параметры пути позиционно, поэтому принимаем их как необязательные.
Function _auth(Authed fn) => (Request req, [String? a, String? b]) async {
      final uid = await userIdFromRequest(req);
      if (uid == null) return err('Нужно войти', 401);
      return fn(req, uid);
    };

const _defaultDestinations = [
  ('Основной аккаунт', 'account'),
  ('Второй аккаунт', 'account'),
  ('Пробный рилс', 'trial'),
];

const _variantFields = '''id, project_id, source_id, topic, title, hook_text, hook_type, caption,
  hashtags, segments, duration, style, look, status, originality, destination, error,
  rendered_at, exported_at, created_at,
  (edit is not null and not coalesce((edit->>'ai')::boolean, false)) as edited, edited_at, published_at,
  mixed, caption_src''';

class Api {
  Api(this.c);
  final Config c;

  Handler get handler {
    final r = Router()
      ..get('/api/health', (Request _) => jsonRes({'ok': true}))
      ..post('/api/auth/register', _register)
      ..post('/api/auth/login', _login)
      ..post('/api/auth/logout', _auth(_logout))
      ..get('/api/me', _auth(_me))
      ..get('/api/admin/users', _auth(_adminUsers))
      ..put('/api/admin/users/<id>', _auth(_adminUpdateUser))
      ..delete('/api/admin/users/<id>', _auth(_adminDeleteUser))
      ..get('/api/styles', (Request _) => jsonRes({
            'titles': [for (final t in titlePresets) t.toJson()],
            'palettes': [for (final x in palettes) x.toJson()],
            'subs': [for (final x in subStyles) x.toJson()],
            'fonts': Fonts.list(),
            'anims': [for (final e in anims.entries) {'id': e.key, 'name': e.value}],
            'anim_presets': [
              for (final e in animPresets.entries) {'id': e.key, 'name': e.value.$1, 'description': e.value.$2}
            ],
          }))
      ..get('/api/looks', _auth(_listLooks))
      ..post('/api/looks', _auth(_saveMyLook))
      ..delete('/api/looks/<id>', _auth(_deleteMyLook))
      ..get('/fonts/<key>', _font)
      ..get('/api/captions', _auth(_listCaptions))
      ..post('/api/captions', _auth(_addCaptions))
      ..put('/api/captions/settings', _auth(_captionSettings))
      ..delete('/api/captions/<id>', _auth(_deleteCaption))
      ..post('/api/projects/<id>/plan-mix', _auth(_planMixNow))
      ..get('/api/destinations', _auth(_listDestinations))
      ..post('/api/destinations', _auth(_addDestination))
      ..put('/api/destinations/<id>', _auth(_renameDestination))
      ..delete('/api/destinations/<id>', _auth(_deleteDestination))
      ..delete('/api/sources/<id>', _auth(_deleteSource))
      ..get('/api/sources/<id>/words', _auth(_getWords))
      ..put('/api/sources/<id>/words', _auth(_saveWords))
      ..get('/api/projects', _auth(_listProjects))
      ..post('/api/projects', _auth(_createProject))
      ..get('/api/projects/<id>', _auth(_getProject))
      ..put('/api/projects/<id>', _auth(_renameProject))
      ..delete('/api/projects/<id>', _auth(_deleteProject))
      ..post('/api/projects/<id>/sources', _auth(_upload))
      ..post('/api/sources/<id>/replan', _auth(_replan))
      ..post('/api/variants/render', _auth(_render))
      ..post('/api/variants/<id>/check', _auth(_check))
      ..post('/api/variants/<id>/preview', _auth(_makePreview))
      ..post('/api/variants/<id>/preview-grid', _auth(_previewGrid))
      ..put('/api/variants/<id>/design', _auth(_saveDesign))
      ..post('/api/variants/<id>/export', _auth(_export))
      ..delete('/api/variants/<id>', _auth(_deleteVariant))
      ..put('/api/variants/<id>/destination', _auth(_setDestination))
      ..put('/api/variants/<id>/published', _auth(_setPublished))
      ..get('/api/accounts', _auth(_accounts))
      ..get('/api/accounts/videos', _auth(_accountVideos))
      ..post('/api/accounts/bulk', _auth(_accountsBulk))
      ..get('/api/variants/<id>/edit', _auth(_getEdit))
      ..put('/api/variants/<id>/edit', _auth(_saveEdit))
      ..put('/api/variants/<id>/look', _auth(_saveLook))
      ..post('/api/variants/<id>/edit/reset', _auth(_resetEdit))
      ..post('/api/variants/<id>/quick-preview', _auth(_quickPreview))
      ..get('/api/media', _auth(_listMedia))
      ..post('/api/media', _auth(_uploadMedia))
      ..put('/api/media/<id>', _auth(_updateMedia))
      ..delete('/api/media/<id>', _auth(_deleteMedia))
      ..get('/media/sources/<id>/proxy', _sourceProxy)
      ..get('/media/library/<id>/proxy', _libraryProxy)
      ..get('/media/library/<id>/thumb', _libraryThumb)
      ..get('/media/variants/<id>/thumb', _thumb)
      ..get('/media/variants/<id>/preview', _preview)
      ..get('/media/variants/<id>', _media);

    return const Pipeline()
        .addMiddleware(_corsMw())
        .addMiddleware(_errorsMw())
        .addHandler(r.call);
  }

  // ---------- Аккаунт ----------

  Future<Response> _register(Request req) async {
    final b = await readJson(req);
    final email = (b['email'] ?? '').toString().trim().toLowerCase();
    final pass = (b['password'] ?? '').toString();
    final name = (b['name'] ?? '').toString().trim();
    if (!email.contains('@') || pass.length < 6) {
      return err('Укажи email и пароль не короче 6 символов');
    }
    if (await q1('select id from users where email = @e', {'e': email}) != null) {
      return err('Такой email уже зарегистрирован', 409);
    }
    final u = (await q1(
        'insert into users(email, password_hash, name) values(@e, @h, @n) returning id, email, name, plan',
        {'e': email, 'h': hashPassword(pass), 'n': name}))!;
    for (final (i, dst) in _defaultDestinations.indexed) {
      await q('insert into destinations(user_id, name, kind, sort) values(@u, @n, @k, @s)',
          {'u': u['id'], 'n': dst.$1, 'k': dst.$2, 's': i});
    }
    return jsonRes({'token': await createSession(u['id'] as String), 'user': u});
  }

  Future<Response> _login(Request req) async {
    final b = await readJson(req);
    final email = (b['email'] ?? '').toString().trim().toLowerCase();
    final u = await q1('select id, email, name, plan, password_hash from users where email = @e', {'e': email});
    if (u == null || !verifyPassword((b['password'] ?? '').toString(), u['password_hash'] as String)) {
      return err('Неверный email или пароль', 401);
    }
    u.remove('password_hash');
    return jsonRes({'token': await createSession(u['id'] as String), 'user': u});
  }

  Future<Response> _logout(Request req, String uid) async {
    final token = (req.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
    await q('delete from sessions where token = @t', {'t': token});
    return jsonRes({'ok': true});
  }

  Future<Response> _me(Request req, String uid) async {
    final u = await q1('select id, email, name, plan, monthly_render_limit from users where id = @u', {'u': uid});
    final used = await q1('''select count(*)::int as n from variants
        where user_id = @u and rendered_at >= date_trunc('month', now())''', {'u': uid});
    return jsonRes({...?u, 'renders_this_month': used?['n'] ?? 0, 'is_admin': await _isAdmin(uid)});
  }

  // ---------- Админ ----------

  /// Админы — почты из ADMIN_EMAILS в .env (через запятую), а если там пусто — самый первый аккаунт.
  Future<bool> _isAdmin(String uid) async {
    final u = await q1('select email from users where id = @u', {'u': uid});
    if (u == null) return false;
    final list = (c.opt('ADMIN_EMAILS') ?? '')
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (list.isNotEmpty) return list.contains((u['email'] as String).toLowerCase());
    final first = await q1('select id from users order by created_at limit 1');
    return first?['id'] == uid;
  }

  Future<Response> _adminUsers(Request req, String uid) async {
    if (!await _isAdmin(uid)) return err('Только для админа', 403);
    return jsonRes(await q('''select u.id, u.email, u.name, u.plan, u.monthly_render_limit, u.created_at,
        (select count(*)::int from variants v where v.user_id = u.id
           and v.rendered_at >= date_trunc('month', now())) as renders_this_month,
        (select count(*)::int from projects p where p.user_id = u.id) as projects
        from users u order by u.created_at'''));
  }

  Future<Response> _adminUpdateUser(Request req, String uid) async {
    if (!await _isAdmin(uid)) return err('Только для админа', 403);
    final b = await readJson(req);
    final limit = b['monthly_render_limit'];
    if (limit is! int || limit < 0 || limit > 1000000) return err('Лимит — целое число от 0 до 1 000 000');
    final row = await q1('update users set monthly_render_limit = @l where id = @id returning id',
        {'l': limit, 'id': req.params['id']});
    if (row == null) return err('Пользователь не найден', 404);
    return jsonRes({'ok': true});
  }

  Future<Response> _adminDeleteUser(Request req, String uid) async {
    if (!await _isAdmin(uid)) return err('Только для админа', 403);
    final id = req.params['id']!;
    if (id == uid) return err('Свой аккаунт отсюда удалить нельзя');
    // Строки проектов, роликов, сессий удалятся каскадом; файлы пользователя лежат в одной папке.
    final row = await q1('delete from users where id = @id returning id', {'id': id});
    if (row == null) return err('Пользователь не найден', 404);
    final dir = Directory(p.join(c.dataDir, 'users', id));
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (e) {
        stderr.writeln('Не удалилась папка $id: $e');
      }
    }
    return jsonRes({'ok': true});
  }

  // ---------- Куда выкладываем ----------

  Future<Response> _listDestinations(Request req, String uid) async => jsonRes(await q(
      'select id, name, kind from destinations where user_id = @u order by sort, name', {'u': uid}));

  Future<Response> _addDestination(Request req, String uid) async {
    final b = await readJson(req);
    final name = (b['name'] ?? '').toString().trim();
    if (name.isEmpty) return err('Укажи название');
    final kind = b['kind'] == 'trial' ? 'trial' : 'account';
    final row = await q1('''insert into destinations(user_id, name, kind, sort)
        values(@u, @n, @k, (select coalesce(max(sort), 0) + 1 from destinations where user_id = @u))
        returning id, name, kind''', {'u': uid, 'n': name, 'k': kind});
    return jsonRes(row);
  }

  Future<Response> _renameDestination(Request req, String uid) async {
    final b = await readJson(req);
    final name = (b['name'] ?? '').toString().trim();
    if (name.isEmpty) return err('Укажи название');
    final old = await q1('select name from destinations where id = @id and user_id = @u', {'id': req.params['id'], 'u': uid});
    if (old == null) return err('Не найдено', 404);
    final kind = b['kind'] == 'trial' ? 'trial' : (b['kind'] == 'account' ? 'account' : null);
    await q('update destinations set name = @n, kind = coalesce(@k:text, kind) where id = @id',
        {'id': req.params['id'], 'n': name, 'k': kind});
    // Выгруженные ролики помнят место по названию — переименовываем и у них, чтобы история не потерялась.
    await q('update variants set destination = @n where user_id = @u and destination = @o',
        {'u': uid, 'n': name, 'o': old['name']});
    return jsonRes({'ok': true});
  }

  Future<Response> _deleteSource(Request req, String uid) async {
    final s = await q1('select id, path from sources where id = @id and user_id = @u', {'id': req.params['id'], 'u': uid});
    if (s == null) return err('Исходник не найден', 404);
    final vs = await q('select id, output_path from variants where source_id = @id', {'id': s['id']});
    for (final v in vs) {
      final out = v['output_path'] as String?;
      if (out != null) {
        final dir = Directory(p.dirname(out));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    }
    _deletePreviews(uid, [for (final v in vs) v['id'] as String]);
    final path = s['path'] as String?;
    if (path != null) {
      final dir = Directory(p.dirname(path));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    await q('delete from sources where id = @id', {'id': s['id']});
    return jsonRes({'ok': true});
  }

  // ---------- Текст субтитров ----------
  // Правки живут прямо в расшифровке исходника: ошибка распознавания одна на все ролики из него.

  Future<Response> _getWords(Request req, String uid) async {
    final s = await q1('select id, file_name, duration, proxy_path, transcript from sources where id = @id and user_id = @u',
        {'id': req.params['id'], 'u': uid});
    if (s == null) return err('Исходник не найден', 404);
    final t = (jv(s['transcript']) as Map?) ?? const {};
    final proxy = s['proxy_path'] as String?;
    return jsonRes({
      'id': s['id'],
      'file_name': s['file_name'],
      'duration': s['duration'],
      'has_proxy': proxy != null && File(proxy).existsSync(),
      'words': t['words'] ?? const [],
    });
  }

  Future<Response> _saveWords(Request req, String uid) async {
    final id = req.params['id']!;
    final b = await readJson(req);
    final s = await q1('select transcript from sources where id = @id and user_id = @u', {'id': id, 'u': uid});
    if (s == null) return err('Исходник не найден', 404);
    final t = ((jv(s['transcript']) as Map?) ?? {}).cast<String, dynamic>();
    final words = [for (final w in (t['words'] as List? ?? const [])) (w as Map).cast<String, dynamic>()];
    var n = 0;
    for (final ch in (b['changes'] as List? ?? const [])) {
      final i = (ch as Map)['i'];
      if (i is! int || i < 0 || i >= words.length) continue;
      final w = words[i];
      if (ch['reset'] == true) {
        if (w['o'] != null) w['w'] = w.remove('o');
        w.remove('x');
      } else {
        final text = (ch['w'] ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        // Пусто — слово скрыто, но его время остаётся: по нему монтаж цепляет края кусков.
        if (text.isEmpty || ch['hide'] == true) {
          w['x'] = true;
        } else {
          w.remove('x');
          if (text != w['w']) {
            w['o'] ??= w['w'];
            w['w'] = text;
            if (w['o'] == text) w.remove('o');
          }
        }
      }
      n++;
    }
    if (n == 0) return jsonRes({'ok': true, 'changed': 0});
    t['words'] = words;
    t['rev'] = ((t['rev'] as num?)?.toInt() ?? 0) + 1;
    await q('update sources set transcript = @t:jsonb where id = @id', {'id': id, 't': t});
    // Готовые ролики собраны со старым текстом — помечаем, что их надо пересобрать.
    await q('''update variants set edited_at = now()
        where source_id = @id and status in ('ready', 'exported')''', {'id': id});
    return jsonRes({'ok': true, 'changed': n});
  }

  Future<Response> _deleteDestination(Request req, String uid) async {
    await q('delete from destinations where id = @id and user_id = @u', {'id': req.params['id'], 'u': uid});
    return jsonRes({'ok': true});
  }

  // ---------- Проекты ----------

  Future<Response> _listProjects(Request req, String uid) async => jsonRes(await q('''
      select p.id, p.title, p.created_at,
        (select count(*)::int from sources s where s.project_id = p.id) as sources,
        (select count(*)::int from variants v where v.project_id = p.id and v.status = 'proposed') as proposed,
        (select count(*)::int from variants v where v.project_id = p.id and v.status in ('ready', 'exported')) as ready
      from projects p where p.user_id = @u order by p.created_at desc''', {'u': uid}));

  Future<Response> _createProject(Request req, String uid) async {
    final b = await readJson(req);
    final title = (b['title'] ?? '').toString().trim();
    return jsonRes(await q1('insert into projects(user_id, title) values(@u, @t) returning id, title, created_at',
        {'u': uid, 't': title.isEmpty ? 'Новый проект' : title}));
  }

  Future<Map<String, dynamic>?> _ownedProject(String id, String uid) =>
      q1('select id, title, created_at from projects where id = @id and user_id = @u', {'id': id, 'u': uid});

  Future<Response> _getProject(Request req, String uid) async {
    final id = req.params['id']!;
    final project = await _ownedProject(id, uid);
    if (project == null) return err('Проект не найден', 404);
    final sources = await q('''select id, file_name, duration, status, error, created_at,
        coalesce(jsonb_array_length(transcript -> 'phrases'), 0) as phrases
        from sources where project_id = @id order by created_at''', {'id': id});
    final variants = await q('select $_variantFields from variants where project_id = @id order by created_at',
        {'id': id});
    return jsonRes({'project': project, 'sources': sources, 'variants': variants});
  }

  Future<Response> _renameProject(Request req, String uid) async {
    final id = req.params['id']!;
    final b = await readJson(req);
    final title = (b['title'] ?? '').toString().trim();
    if (title.isEmpty) return err('Укажи название');
    if (title.length > 120) return err('Слишком длинное название');
    if (await _ownedProject(id, uid) == null) return err('Проект не найден', 404);
    return jsonRes(await q1('update projects set title = @t where id = @id returning id, title, created_at',
        {'id': id, 't': title}));
  }

  Future<Response> _deleteProject(Request req, String uid) async {
    final id = req.params['id']!;
    if (await _ownedProject(id, uid) == null) return err('Проект не найден', 404);
    final paths = await q('''select path from sources where project_id = @id
        union all select output_path from variants where project_id = @id''', {'id': id});
    for (final r in paths) {
      final path = r['path'] as String?;
      if (path != null) {
        final dir = Directory(p.dirname(path));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    }
    final vids = await q('select id from variants where project_id = @id', {'id': id});
    _deletePreviews(uid, [for (final r in vids) r['id'] as String]);
    await q('delete from projects where id = @id', {'id': id});
    return jsonRes({'ok': true});
  }

  // ---------- Исходники ----------

  Future<Response> _upload(Request req, String uid) async {
    final pid = req.params['id']!;
    if (await _ownedProject(pid, uid) == null) return err('Проект не найден', 404);
    final name = req.url.queryParameters['name'] ?? 'video.mp4';
    final ext = p.extension(name).toLowerCase();
    if (!const ['.mp4', '.mov', '.m4v', '.webm', '.mkv'].contains(ext)) {
      return err('Поддерживаются видео mp4, mov, m4v, webm, mkv');
    }
    final row = (await q1('insert into sources(project_id, user_id, file_name) values(@p, @u, @f) returning id',
        {'p': pid, 'u': uid, 'f': name}))!;
    final sid = row['id'] as String;
    final dir = Directory(p.join(c.dataDir, 'users', uid, 'sources', sid))..createSync(recursive: true);
    final path = p.join(dir.path, 'original$ext');
    final sink = File(path).openWrite();
    try {
      await sink.addStream(req.read());
      await sink.close();
    } catch (_) {
      // Загрузка оборвалась — не оставляем пустую запись.
      await sink.close().catchError((_) {});
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      await q('delete from sources where id = @id', {'id': sid});
      return err('Загрузка прервалась, попробуй ещё раз');
    }
    await q('update sources set path = @path where id = @id', {'path': path, 'id': sid});
    await enqueue('transcribe', {'source_id': sid});
    // Копия для монтажа готовится параллельно с расшифровкой, а не после неё.
    await enqueue('proxy', {'source_id': sid});
    return jsonRes({'id': sid});
  }

  Future<Response> _replan(Request req, String uid) async {
    final s = await q1('select id, status from sources where id = @id and user_id = @u',
        {'id': req.params['id'], 'u': uid});
    if (s == null) return err('Исходник не найден', 404);
    final t = await q1('select transcript is not null as ok from sources where id = @id', {'id': s['id']});
    await enqueue(t?['ok'] == true ? 'plan' : 'transcribe', {'source_id': s['id']});
    await q("update sources set status = @st, error = null where id = @id",
        {'id': s['id'], 'st': t?['ok'] == true ? 'planning' : 'uploaded'});
    return jsonRes({'ok': true});
  }

  // ---------- Мои стили оформления ----------

  Future<Response> _listLooks(Request req, String uid) async =>
      jsonRes(await q('select id, name, look from user_looks where user_id = @u order by created_at', {'u': uid}));

  Future<Response> _saveMyLook(Request req, String uid) async {
    final b = await readJson(req);
    final name = (b['name'] ?? '').toString().trim();
    if (name.isEmpty) return err('Назови стиль');
    final look = Look.normalize(b['look'] as Map? ?? const {});
    // Тот же name — перезаписываем, чтобы можно было обновить стиль.
    final row = await q1('''insert into user_looks(user_id, name, look) values(@u, @n, @l:jsonb)
        on conflict (user_id, name) do update set look = @l:jsonb returning id, name, look''',
        {'u': uid, 'n': name.length > 40 ? name.substring(0, 40) : name, 'l': look});
    return jsonRes(row);
  }

  Future<Response> _deleteMyLook(Request req, String uid) async {
    await q('delete from user_looks where id = @id and user_id = @u', {'id': req.params['id'], 'u': uid});
    return jsonRes({'ok': true});
  }

  // ---------- Мои подписи ----------

  Future<Response> _listCaptions(Request req, String uid) async {
    final u = await q1('select caption_share from users where id = @u', {'u': uid});
    final items = await q('''select id, topic, body, hashtags, used from captions where user_id = @u
        order by created_at desc''', {'u': uid});
    final ac = await q1('select auto_cut from users where id = @u', {'u': uid});
    return jsonRes({'share': u?['caption_share'] ?? 30, 'auto_cut': ac?['auto_cut'] ?? true, 'items': items});
  }

  Future<Response> _addCaptions(Request req, String uid) async {
    final b = await readJson(req);
    final items = parseCaptions((b['text'] ?? '').toString());
    if (items.isEmpty) return err('Не нашла подписей. Раздели их строкой --- и проверь, что файл не пустой.');
    final total = await q1('select count(*)::int as n from captions where user_id = @u', {'u': uid});
    if ((total?['n'] as int? ?? 0) + items.length > 2000) return err('Слишком много подписей: максимум 2000');
    var added = 0;
    for (final it in items) {
      // Ту же подпись второй раз не добавляем.
      final dup = await q1('select 1 from captions where user_id = @u and body = @b', {'u': uid, 'b': it['body']});
      if (dup != null) continue;
      await q('insert into captions(user_id, topic, body, hashtags) values(@u, @t, @b, @h:jsonb)',
          {'u': uid, 't': it['topic'], 'b': it['body'], 'h': it['hashtags']});
      added++;
    }
    return jsonRes({'added': added, 'skipped': items.length - added});
  }

  Future<Response> _captionSettings(Request req, String uid) async {
    final b = await readJson(req);
    if (b['auto_cut'] is bool) {
      await q('update users set auto_cut = @a where id = @u', {'a': b['auto_cut'], 'u': uid});
    }
    if (b['share'] is num) {
      await q('update users set caption_share = @s where id = @u',
          {'s': (b['share'] as num).round().clamp(0, 100), 'u': uid});
    }
    return jsonRes({'ok': true});
  }

  Future<Response> _deleteCaption(Request req, String uid) async {
    final id = req.params['id']!;
    if (id == 'all') {
      await q('delete from captions where user_id = @u', {'u': uid});
    } else {
      await q('delete from captions where id = @id and user_id = @u', {'id': id, 'u': uid});
    }
    return jsonRes({'ok': true});
  }

  Future<Response> _planMixNow(Request req, String uid) async {
    final p0 = await q1('select id from projects where id = @id and user_id = @u', {'id': req.params['id'], 'u': uid});
    if (p0 == null) return err('Проект не найден', 404);
    final n = await q1('''select count(*)::int as n from sources where project_id = @p and status = 'ready'
        and transcript is not null''', {'p': p0['id']});
    if ((n?['n'] as int? ?? 0) < 2) return err('Нужно хотя бы два готовых видео в проекте');
    await enqueue('plan_mix', {'project_id': p0['id']});
    return jsonRes({'ok': true});
  }

  // ---------- Ролики ----------

  Future<Response> _render(Request req, String uid) async {
    final b = await readJson(req);
    final ids = [for (final x in (b['ids'] as List? ?? const [])) x.toString()];
    final look = Look.normalize((b['look'] as Map?) ?? {'subs': b['style']});
    if (ids.isEmpty) return err('Выбери хотя бы один вариант');

    final u = (await q1('select monthly_render_limit from users where id = @u', {'u': uid}))!;
    final used = (await q1('''select count(*)::int as n from variants
        where user_id = @u and rendered_at >= date_trunc('month', now())''', {'u': uid}))!;
    final left = (u['monthly_render_limit'] as int) - (used['n'] as int);
    // Пересборка ролика, уже собранного в этом месяце, лимит не тратит.
    var fresh = 0;
    for (final id in ids) {
      final r = await q1('''select 1 from variants where id = @id and user_id = @u
          and rendered_at >= date_trunc('month', now())''', {'id': id, 'u': uid});
      if (r == null) fresh++;
    }
    if (fresh > left) return err('Лимит тарифа на этот месяц: осталось $left роликов', 402);

    var queued = 0;
    for (final id in ids) {
      // Своё оформление ролика (из монтажа или меню ролика) важнее общего оформления проекта.
      final own = b['force_look'] == true
          ? null
          : await q1('select look from variants where id = @id and user_id = @u and look_own', {'id': id, 'u': uid});
      final l = own != null && own['look'] != null ? Look.normalize(jv(own['look']) as Map) : look;
      final row = await q1('''update variants set status = 'queued', style = @s, look = @l:jsonb, error = null
          where id = @id and user_id = @u and status in ('proposed', 'failed', 'ready', 'exported') returning id''',
          {'id': id, 'u': uid, 's': l['subs'], 'l': l});
      if (row != null) {
        await enqueue('render', {'variant_id': id});
        queued++;
      }
    }
    return jsonRes({'queued': queued});
  }

  Future<Response> _check(Request req, String uid) async {
    final v = await q1('select id, status from variants where id = @id and user_id = @u',
        {'id': req.params['id'], 'u': uid});
    if (v == null) return err('Ролик не найден', 404);
    if (v['status'] != 'ready' && v['status'] != 'exported') return err('Ролик ещё не собран');
    final report = await checkOriginality(c, v['id'] as String);
    await q('update variants set originality = @o:jsonb where id = @id', {'id': v['id'], 'o': report});
    return jsonRes(report);
  }

  Future<Response> _export(Request req, String uid) async {
    final b = await readJson(req);
    final v = await q1('select id, status from variants where id = @id and user_id = @u',
        {'id': req.params['id'], 'u': uid});
    if (v == null) return err('Ролик не найден', 404);
    if (v['status'] != 'ready' && v['status'] != 'exported') return err('Ролик ещё не собран');
    // Без аккаунта тоже можно скачать — ролик останется в папке «Без аккаунта».
    final destination = (b['destination'] ?? '').toString().trim();

    // Перепроверяем прямо перед выгрузкой: с момента сборки могли выгрузить похожие ролики.
    final report = await checkOriginality(c, v['id'] as String);
    if (report['level'] == 'red' && b['force'] != true) {
      await q('update variants set originality = @o:jsonb where id = @id', {'id': v['id'], 'o': report});
      return jsonRes({'needs_confirm': true, 'originality': report}, status: 409);
    }
    await q('''update variants set status = 'exported', destination = coalesce(@d:text, destination), exported_at = now(),
        originality = @o:jsonb where id = @id''', {'id': v['id'], 'd': destination.isEmpty ? null : destination, 'o': report});
    return jsonRes({'ok': true, 'originality': report});
  }

  // ---------- Папки аккаунтов ----------
  // В папку попадает каждый собранный ролик (не вариант) по полю destination; пусто — «Без аккаунта».

  static const _builtSql = "v.status <> 'proposed'";

  Future<Response> _setDestination(Request req, String uid) async {
    final b = await readJson(req);
    final d = (b['destination'] ?? '').toString().trim();
    final row = await q1('update variants set destination = @d where id = @id and user_id = @u returning id',
        {'d': d.isEmpty ? null : d, 'id': req.params['id'], 'u': uid});
    if (row == null) return err('Ролик не найден', 404);
    return jsonRes({'ok': true});
  }

  Future<Response> _setPublished(Request req, String uid) async {
    final b = await readJson(req);
    final row = await q1(
        b['published'] == true
            ? 'update variants set published_at = coalesce(published_at, now()) where id = @id and user_id = @u returning id'
            : 'update variants set published_at = null where id = @id and user_id = @u returning id',
        {'id': req.params['id'], 'u': uid});
    if (row == null) return err('Ролик не найден', 404);
    return jsonRes({'ok': true});
  }

  // Одним запросом считаем все папки: так экран открывается сразу, даже при тысячах роликов.
  Future<Response> _accounts(Request req, String uid) async {
    final dests = await q('select name, kind from destinations where user_id = @u order by sort, name', {'u': uid});
    final stats = await q('''select coalesce(v.destination, '') as d,
        count(*)::int as total,
        count(*) filter (where v.status = 'ready' and v.published_at is null)::int as waiting,
        count(*) filter (where v.status = 'exported' and v.published_at is null)::int as downloaded,
        count(*) filter (where v.published_at is not null)::int as published,
        count(*) filter (where v.status in ('queued', 'rendering'))::int as building,
        count(*) filter (where v.published_at >= date_trunc('day', now()))::int as published_today,
        count(*) filter (where v.published_at >= now() - interval '7 days')::int as published_week,
        count(*) filter (where v.rendered_at >= date_trunc('day', now()))::int as built_today,
        count(*) filter (where v.rendered_at >= now() - interval '7 days')::int as built_week
        from variants v where v.user_id = @u and $_builtSql group by 1''', {'u': uid});
    final byName = {for (final r in stats) r['d'] as String: r};
    Map<String, dynamic> folder(String name, String? kind) {
      final st = {...?byName[name]}..remove('d');
      return {'name': name, 'kind': kind, ...st};
    }

    final known = {for (final d in dests) d['name'] as String};
    return jsonRes([
      for (final d in dests) folder(d['name'] as String, d['kind'] as String?),
      // Ролики с аккаунтом, который потом удалили из настроек, не должны пропадать.
      for (final name in byName.keys)
        if (name.isNotEmpty && !known.contains(name)) folder(name, null),
      folder('', null),
    ]);
  }

  Future<Response> _accountVideos(Request req, String uid) async {
    final qp = req.url.queryParameters;
    final d = qp['destination'] ?? '';
    final filter = switch (qp['filter']) {
      'waiting' => "and v.status = 'ready' and v.published_at is null",
      'downloaded' => "and v.status = 'exported' and v.published_at is null",
      'published' => 'and v.published_at is not null',
      'unpublished' => 'and v.published_at is null',
      _ => '',
    };
    final order = switch (qp['sort']) {
      'old' => 'coalesce(v.rendered_at, v.created_at) asc',
      'project' => 'p.title asc, coalesce(v.rendered_at, v.created_at) desc',
      _ => 'coalesce(v.rendered_at, v.created_at) desc',
    };
    final fields = _variantFields.split(',').map((x) => 'v.${x.trim()}').join(', ');
    return jsonRes(await q('''select $fields, p.title as project_title from variants v
        join projects p on p.id = v.project_id
        where v.user_id = @u and $_builtSql and coalesce(v.destination, '') = @d $filter
        order by $order limit 500''', {'u': uid, 'd': d}));
  }

  Future<Response> _accountsBulk(Request req, String uid) async {
    final b = await readJson(req);
    final ids = [for (final x in (b['ids'] as List? ?? const [])) x.toString()];
    if (ids.isEmpty) return err('Ничего не выбрано');
    if (ids.length > 500) return err('Не больше 500 роликов за раз');
    final action = b['action'];
    var n = 0;
    for (final id in ids) {
      final prm = {'id': id, 'u': uid};
      Map<String, dynamic>? row;
      switch (action) {
        case 'move':
          final d = (b['destination'] ?? '').toString().trim();
          row = await q1('update variants set destination = @d where id = @id and user_id = @u returning id',
              {...prm, 'd': d.isEmpty ? null : d});
        case 'publish':
          row = await q1(
              'update variants set published_at = coalesce(published_at, now()) where id = @id and user_id = @u returning id',
              prm);
        case 'unpublish':
          row = await q1('update variants set published_at = null where id = @id and user_id = @u returning id', prm);
        case 'delete':
          row = await q1('select id, output_path from variants where id = @id and user_id = @u', prm);
          if (row != null) {
            final path = row['output_path'] as String?;
            if (path != null) {
              final dir = Directory(p.dirname(path));
              if (dir.existsSync()) dir.deleteSync(recursive: true);
            }
            _deletePreviews(uid, [id]);
            await q('delete from variants where id = @id', {'id': id});
          }
        default:
          return err('Неизвестное действие');
      }
      if (row != null) n++;
    }
    return jsonRes({'ok': true, 'changed': n});
  }

  Future<Response> _deleteVariant(Request req, String uid) async {
    final v = await q1('select id, output_path from variants where id = @id and user_id = @u',
        {'id': req.params['id'], 'u': uid});
    if (v == null) return err('Ролик не найден', 404);
    final path = v['output_path'] as String?;
    if (path != null) {
      final dir = Directory(p.dirname(path));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    _deletePreviews(uid, [v['id'] as String]);
    await q('delete from variants where id = @id', {'id': v['id']});
    return jsonRes({'ok': true});
  }

  Future<Response> _thumb(Request req, String id) async {
    final uid = await userIdFromToken(req.url.queryParameters['t']);
    if (uid == null) return Response.forbidden('Нужно войти');
    final v = await q1('select output_path from variants where id = @id and user_id = @u', {'id': id, 'u': uid});
    final path = v?['output_path'] as String?;
    final f = path == null ? null : File(p.join(p.dirname(path), 'thumb.jpg'));
    if (f == null || !f.existsSync()) return Response.notFound('Нет превью');
    return Response.ok(f.openRead(), headers: {
      'content-type': 'image/jpeg',
      'content-length': '${f.lengthSync()}',
      'cache-control': 'private, max-age=86400',
    });
  }

  // Видео отдаём по токену в ссылке: тег <video> и скачивание не умеют слать заголовки.
  Future<Response> _media(Request req, String id) async {
    final uid = await userIdFromToken(req.url.queryParameters['t']);
    if (uid == null) return Response.forbidden('Нужно войти');
    final v = await q1('select output_path from variants where id = @id and user_id = @u', {'id': id, 'u': uid});
    final path = v?['output_path'] as String?;
    if (path == null || !File(path).existsSync()) return Response.notFound('Файл не найден');
    final download = req.url.queryParameters['download'] == '1';
    return serveVideo(req, File(path),
        disposition: '${download ? 'attachment' : 'inline'}; filename="clipora-$id.mp4"');
  }

  // ---------- Монтаж ----------

  Future<Map<String, dynamic>?> _ownedVariant(String id, String uid) =>
      q1('select * from variants where id = @id and user_id = @u', {'id': id, 'u': uid});

  // Лёгкая копия могла не собраться у старых исходников — ставим в очередь, но не чаще раза в 10 минут.
  Future<void> _ensureProxyJob(String sourceId) async {
    final recent = await q1('''select id from jobs where kind = 'proxy' and payload->>'source_id' = @id
        and (status in ('queued', 'running') or finished_at > now() - interval '10 minutes')''', {'id': sourceId});
    if (recent == null) await enqueue('proxy', {'source_id': sourceId});
  }

  Future<Response> _getEdit(Request req, String uid) async {
    final v = await _ownedVariant(req.params['id']!, uid);
    if (v == null) return err('Ролик не найден', 404);
    final clips = clipsOf(v);
    // Все расшифрованные видео проекта — чтобы в ролик можно было добавить фразу из любого.
    final others = await q('''select id from sources where project_id = @p and user_id = @u
        and transcript is not null order by created_at''', {'p': v['project_id'], 'u': uid});
    final srcIds = {
      v['source_id'] as String,
      for (final c in clips)
        if (c['src'] == 'source') c['ref'] as String,
      for (final o in others) o['id'] as String,
    };
    final sources = <Map<String, dynamic>>[];
    for (final id in srcIds) {
      final s = await q1('select id, file_name, path, duration, proxy_path, proxy_error, transcript from sources where id = @id and user_id = @u',
          {'id': id, 'u': uid});
      if (s == null) continue;
      final ready = s['proxy_path'] != null && File(s['proxy_path'] as String).existsSync();
      if (!ready && s['path'] != null) await _ensureProxyJob(id);
      final t = (jv(s['transcript']) as Map?) ?? const {};
      sources.add({
        'id': id,
        'file_name': s['file_name'],
        'duration': s['duration'],
        'proxy': ready,
        'proxy_error': s['proxy_error'],
        'words': t['words'] ?? const [],
        'phrases': [
          for (final ph in (t['phrases'] as List? ?? const []))
            if (ph['quiet'] != true) {'id': ph['id'], 's': ph['s'], 'e': ph['e'], 'text': ph['text']}
        ],
      });
    }
    return jsonRes({
      'variant': {
        for (final k in const ['id', 'project_id', 'title', 'hook_text', 'status', 'source_id', 'look', 'duration',
          'rendered_at', 'edited_at'])
          k: v[k],
        'edited': v['edit'] != null,
      },
      'clips': clips,
      'overlays': overlaysOf(v),
      'sources': sources,
    });
  }

  Future<Response> _saveEdit(Request req, String uid) async {
    final v = await _ownedVariant(req.params['id']!, uid);
    if (v == null) return err('Ролик не найден', 404);
    if (const ['queued', 'rendering'].contains(v['status'])) return err('Ролик сейчас собирается, подожди минуту');
    final b = await readJson(req);
    final (clips, problem) = await validateClips(b['clips'] as List? ?? const [], uid);
    if (problem != null) return err(problem);
    final dur = clips!.fold<double>(0, (a, x) => a + d(x['e']) - d(x['s']));
    final (overlays, problem2) = await validateOverlays(b['overlays'] as List? ?? const [], uid, dur);
    if (problem2 != null) return err(problem2);
    await q('update variants set edit = @e:jsonb, edited_at = now(), duration = @d:float8 where id = @id',
        {'id': v['id'], 'e': {'clips': clips, 'overlays': overlays}, 'd': dur});
    return jsonRes({'ok': true, 'duration': dur});
  }

  // Оформление, выбранное для конкретного ролика: общая сборка из проекта его больше не перетирает.
  Future<Response> _saveLook(Request req, String uid) async {
    final v = await _ownedVariant(req.params['id']!, uid);
    if (v == null) return err('Ролик не найден', 404);
    final b = await readJson(req);
    final look = Look.normalize((b['look'] as Map?) ?? const {});
    await q('update variants set look = @l:jsonb, style = @s, look_own = true where id = @id',
        {'id': v['id'], 'l': look, 's': look['subs']});
    return jsonRes({'ok': true, 'look': look});
  }

  Future<Response> _resetEdit(Request req, String uid) async {
    final v = await _ownedVariant(req.params['id']!, uid);
    if (v == null) return err('Ролик не найден', 404);
    final ai = jv(v['ai_edit']);
    if (ai is Map && ai['clips'] is List) {
      final dur = (ai['clips'] as List).fold<double>(0, (a, x) => a + d(x['e']) - d(x['s']));
      await q('update variants set edit = ai_edit, edited_at = now(), duration = @d:float8 where id = @id',
          {'id': v['id'], 'd': dur});
    } else {
      final segs = jv(v['segments']) as List;
      final dur = segs.fold<double>(0, (a, x) => a + d(x['e']) - d(x['s']));
      await q('update variants set edit = null, edited_at = now(), duration = @d:float8 where id = @id',
          {'id': v['id'], 'd': dur});
    }
    return jsonRes({'ok': true});
  }

  // Черновой ролик целиком в низком качестве — то же, что получится при сборке.
  Future<Response> _quickPreview(Request req, String uid) async {
    final id = req.params['id']!;
    final v = await _ownedVariant(id, uid);
    if (v == null) return err('Ролик не найден', 404);
    final clips = clipsOf(v);
    final overlays = overlaysOf(v);
    final look = Look.normalize(jv(v['look']) as Map? ?? {'subs': v['style']});
    final key = sha1
        .convert(utf8.encode(jsonEncode(
            {'clips': clips, 'overlays': overlays, 'look': look, 'hook': v['hook_text'], 'design': v['design']})))
        .toString()
        .substring(0, 12);
    final file = _previewFile(uid, id, key, true);
    if (file.existsSync() && !_previewJobs.containsKey('$id/$key/q')) return jsonRes({'key': key});
    try {
      final resolved = await resolveClips(clips);
      final resolvedOv = await resolveOverlays(overlays);
      await (_previewJobs['$id/$key/q'] ??= renderClip(c,
              clips: resolved,
              overlays: resolvedOv,
              look: Look.from(look, variantId: id),
              design: designFor(jv(v['design']) as Map?, v['hook_text'] as String? ?? ''),
              outDir: file.parent.path,
              preview: true)
          .whenComplete(() {
            _previewJobs.remove('$id/$key/q');
          }));
    } on ProcessFailure catch (e) {
      if (file.existsSync()) file.deleteSync();
      return err('Не получилось собрать превью: ${e.message}', 500);
    }
    return jsonRes({'key': key});
  }

  // ---------- Медиатека вставок ----------

  Future<Response> _listMedia(Request req, String uid) async => jsonRes(await q('''
      select m.id, m.file_name, m.duration, m.has_audio, m.status, m.error, m.tags, m.created_at,
        (select count(*)::int from variants v
          where v.user_id = m.user_id and v.edit is not null and v.edit::text like '%' || m.id || '%') as used
      from media m where m.user_id = @u order by m.created_at desc''', {'u': uid}));

  Future<Response> _uploadMedia(Request req, String uid) async {
    final name = req.url.queryParameters['name'] ?? 'video.mp4';
    final ext = p.extension(name).toLowerCase();
    if (!const ['.mp4', '.mov', '.m4v', '.webm', '.mkv', '.3gp'].contains(ext)) {
      return err('Поддерживаются видео mp4, mov, m4v, webm, mkv');
    }
    final row = (await q1('insert into media(user_id, file_name) values(@u, @f) returning id', {'u': uid, 'f': name}))!;
    final mid = row['id'] as String;
    final dir = Directory(p.join(c.dataDir, 'users', uid, 'media', mid))..createSync(recursive: true);
    final path = p.join(dir.path, 'original$ext');
    final sink = File(path).openWrite();
    try {
      await sink.addStream(req.read());
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      await q('delete from media where id = @id', {'id': mid});
      return err('Загрузка прервалась, попробуй ещё раз');
    }
    await q('update media set path = @p where id = @id', {'p': path, 'id': mid});
    await enqueue(req.url.queryParameters['split'] == '1' ? 'split' : 'media', {'media_id': mid});
    return jsonRes({'id': mid});
  }

  Future<Response> _updateMedia(Request req, String uid) async {
    final b = await readJson(req);
    final m = await q1('select id from media where id = @id and user_id = @u', {'id': req.params['id'], 'u': uid});
    if (m == null) return err('Вставка не найдена', 404);
    if (b['tags'] is List) {
      final tags = <String>{
        for (final t in b['tags'] as List)
          if (t.toString().trim().isNotEmpty) t.toString().trim().toLowerCase()
      }.take(12).toList();
      await q('update media set tags = @t:jsonb where id = @id', {'id': m['id'], 't': tags});
    }
    final name = (b['file_name'] ?? '').toString().trim();
    if (name.isNotEmpty) await q('update media set file_name = @n where id = @id', {'id': m['id'], 'n': name});
    return jsonRes({'ok': true});
  }

  Future<Response> _deleteMedia(Request req, String uid) async {
    final m = await q1('select id, path from media where id = @id and user_id = @u', {'id': req.params['id'], 'u': uid});
    if (m == null) return err('Вставка не найдена', 404);
    final used = await q1('''select count(*)::int as n from variants
        where user_id = @u and edit is not null and edit::text like '%' || @id || '%' ''', {'u': uid, 'id': m['id']});
    final n = used?['n'] as int? ?? 0;
    if (n > 0) return err('Вставка стоит в монтаже $n ${n == 1 ? 'ролика' : 'роликов'} — сначала убери её оттуда');
    final path = m['path'] as String?;
    if (path != null) {
      final dir = Directory(p.dirname(path));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    await q('delete from media where id = @id', {'id': m['id']});
    return jsonRes({'ok': true});
  }

  Future<Response> _sourceProxy(Request req, String id) async {
    final uid = await userIdFromToken(req.url.queryParameters['t']);
    if (uid == null) return Response.forbidden('Нужно войти');
    final s = await q1('select proxy_path from sources where id = @id and user_id = @u', {'id': id, 'u': uid});
    final path = s?['proxy_path'] as String?;
    if (path == null || !File(path).existsSync()) return Response.notFound('Лёгкая копия ещё не готова');
    return serveVideo(req, File(path), cache: true);
  }

  Future<Response> _libraryProxy(Request req, String id) async {
    final uid = await userIdFromToken(req.url.queryParameters['t']);
    if (uid == null) return Response.forbidden('Нужно войти');
    final m = await q1('select proxy_path from media where id = @id and user_id = @u', {'id': id, 'u': uid});
    final path = m?['proxy_path'] as String?;
    if (path == null || !File(path).existsSync()) return Response.notFound('Вставка ещё обрабатывается');
    return serveVideo(req, File(path), cache: true);
  }

  Future<Response> _libraryThumb(Request req, String id) async {
    final uid = await userIdFromToken(req.url.queryParameters['t']);
    if (uid == null) return Response.forbidden('Нужно войти');
    final m = await q1('select path from media where id = @id and user_id = @u', {'id': id, 'u': uid});
    final path = m?['path'] as String?;
    final f = path == null ? null : File(p.join(p.dirname(path), 'thumb.jpg'));
    if (f == null || !f.existsSync()) return Response.notFound('Нет превью');
    return Response.ok(f.openRead(), headers: {
      'content-type': 'image/jpeg',
      'content-length': '${f.lengthSync()}',
      'cache-control': 'private, max-age=86400',
    });
  }

  final _previewJobs = <String, Future<void>>{};

  void _deletePreviews(String uid, List<String> variantIds) {
    for (final id in variantIds) {
      final dir = Directory(p.join(c.dataDir, 'users', uid, 'previews', id));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }

  // Короткий кусок ролика в выбранном стиле субтитров — собирается по запросу и кешируется.
  Future<Map<String, dynamic>?> _previewSource(String id, String uid) => q1('''select v.segments, v.edit, v.source_id, v.hook_text, v.design, s.path as source_path, s.proxy_path, s.transcript
        from variants v join sources s on s.id = v.source_id
        where v.id = @id and v.user_id = @u and s.transcript is not null and s.path is not null''',
      {'id': id, 'u': uid});

  Future<Response> _makePreview(Request req, String uid) async {
    final id = req.params['id']!;
    final body = await readJson(req);
    final v = await _previewSource(id, uid);
    if (v == null) return err('Вариант не найден или исходник ещё не обработан', 404);
    try {
      await _ensureBaseFrame(uid, id, v);
      if (body['layers'] == true) return jsonRes(await _ensureLayers(uid, id, v, body['look'] as Map?));
      final key = await _ensurePreview(uid, id, v, body['look'] as Map?, body['video'] == true);
      return jsonRes({'key': key});
    } on ProcessFailure catch (e) {
      return err('Не получилось собрать предпросмотр: ${e.message}', 500);
    }
  }

  // Сразу все варианты одного параметра (заголовки или палитры) — чтобы смотреть сеткой, а не по одному.
  // Ключи отдаём сразу, картинки собираются в фоне: каждая плитка появляется, как только готова.
  Future<Response> _previewGrid(Request req, String uid) async {
    final id = req.params['id']!;
    final body = await readJson(req);
    final v = await _previewSource(id, uid);
    if (v == null) return err('Вариант не найден или исходник ещё не обработан', 404);
    final base = {...?(body['look'] as Map?), 'mix': false};
    final vary = body['vary'] == 'palette' ? 'palette' : 'title';
    final ids = vary == 'palette' ? [for (final x in palettes) x.id] : [for (final x in titlePresets) x.id];
    try {
      await _ensureBaseFrame(uid, id, v);
      final out = <Map<String, String>>[];
      final missing = <StillTile>[];
      for (final o in ids) {
        final look = Look.normalize({...base, vary: o});
        // sq — плитка квадратная, не путать с кешем старых полноразмерных плиток.
        final key = sha1.convert(utf8.encode(jsonEncode({...look, 'w': 360, 'sq': 1}))).toString().substring(0, 12);
        out.add({'id': o, 'key': key});
        final file = _previewFile(uid, id, key, false);
        if (!file.existsSync()) missing.add(StillTile(Look.from({...look, 'cta': false}), file.path));
      }
      if (missing.isNotEmpty) {
        // Одинаковый запрос, пока первый ещё собирается (быстрые переключения), ждёт тот же запуск.
        final job = '$id/grid/${out.map((x) => x['key']).join()}';
        final f = _previewJobs[job] ??= _gridGate
            .run(() => renderStillBatch(c,
                segments: firstSeconds(effectiveSegments(v), 6),
                words: (jv(v['transcript']) as Map)['words'] as List,
                design: designFor(jv(v['design']) as Map?, v['hook_text'] as String? ?? ''),
                baseFrame: _basePath(uid, id),
                tiles: missing,
                grade: base['grade'] != false,
                workDir: p.join(c.dataDir, 'users', uid, 'previews', id, 'grid-$vary-${DateTime.now().microsecondsSinceEpoch}')))
            .whenComplete(() {
            _previewJobs.remove(job);
          });
        await f;
      }
      return jsonRes(out);
    } on ProcessFailure catch (e) {
      return err('Не получилось собрать предпросмотр: ${e.message}', 500);
    }
  }

  // Сетка заголовков и сетка цветов — по одному процессу ffmpeg на каждую.
  final _gridGate = _Gate(2);

  /// Лёгкая копия уже 9:16 и маленькая — кадры и видео предпросмотра из неё собираются в разы быстрее.
  String _previewInput(Map v) {
    final proxy = v['proxy_path'] as String?;
    return proxy != null && File(proxy).existsSync() ? proxy : v['source_path'] as String;
  }

  String _basePath(String uid, String id) => p.join(c.dataDir, 'users', uid, 'previews', id, 'base540.png');

  Future<void> _ensureBaseFrame(String uid, String id, Map<String, dynamic> v) async {
    final file = File(_basePath(uid, id));
    if (file.existsSync()) return;
    final job = '$id/base';
    final f = _previewJobs[job] ??= renderStill(c,
            sourcePath: _previewInput(v),
            segments: firstSeconds(effectiveSegments(v), 6),
            words: (jv(v['transcript']) as Map)['words'] as List,
            look: Look.from(const {'cta': false}),
            design: designFor(jv(v['design']) as Map?, v['hook_text'] as String? ?? ''),
            outDir: p.join(file.parent.path, 'base-tmp'),
            baseFrame: file.path)
        .whenComplete(() {
            _previewJobs.remove(job);
          });
    await f;
  }

  Future<String> _ensurePreview(String uid, String id, Map<String, dynamic> v, Map? rawLook, bool video,
      {int width = 540, bool wait = true}) async {
    final look = Look.normalize(rawLook ?? const {});
    // Ключ кеша — само оформление и размер, чтобы каждое сочетание собиралось один раз.
    // rev — версия правок текста субтитров, иначе после правки показывался бы старый кадр.
    final rev = ((jv(v['transcript']) as Map?)?['rev'] as num?)?.toInt() ?? 0;
    final key = sha1
        .convert(utf8.encode(jsonEncode({...look, 'w': width, if (rev > 0) 'r': rev})))
        .toString()
        .substring(0, 12);
    final file = _previewFile(uid, id, key, video);
    final job = '$id/$key/$video';
    if (!_previewJobs.containsKey(job) && file.existsSync()) return key;
    // Ролик в предпросмотре короткий — финальная надпись наложилась бы на заголовок.
    final previewLook = Look.from({...look, 'cta': false}, variantId: id);
    final segs = firstSeconds(effectiveSegments(v), 6);
    final design = designFor(jv(v['design']) as Map?, v['hook_text'] as String? ?? '');
    final words = (jv(v['transcript']) as Map)['words'] as List;
    final input = _previewInput(v);
    Future<void> build() => video
        ? renderClip(c,
            clips: clipsFromSource(input, segs, words),
            look: previewLook,
            design: design,
            outDir: file.parent.path,
            preview: true)
        : renderStill(c,
            sourcePath: input,
            segments: segs,
            words: words,
            look: previewLook,
            design: design,
            outDir: file.parent.path,
            baseFrame: _basePath(uid, id),
            width: width);
    final f = _previewJobs[job] ??= (wait ? build() : _gridGate.run(build)).then<void>((_) {}, onError: (Object e) {
      if (file.existsSync()) file.deleteSync();
      throw e;
    }).whenComplete(() {
            _previewJobs.remove(job);
          });
    if (!wait) {
      f.catchError((Object e) => stderr.writeln('Предпросмотр $job: $e'));
      return key;
    }
    await f;
    return key;
  }

  Map<String, dynamic> _designOf(Map v) => designFor(jv(v['design']) as Map?, v['hook_text'] as String? ?? '');

  Future<Map<String, dynamic>> _ensureLayers(String uid, String id, Map<String, dynamic> v, Map? rawLook) async {
    // Положение заголовка в ключ не входит: его применяет приложение, слои от него не зависят.
    final look = {
      ...Look.normalize(rawLook ?? const {}),
      'title_x': 0.0,
      'title_y': 0.0,
      'title_s': 1.0,
      'title_r': 0.0,
      'el': const {},
    };
    final rev = ((jv(v['transcript']) as Map?)?['rev'] as num?)?.toInt() ?? 0;
    final key = sha1.convert(utf8.encode(jsonEncode({...look, 'layers': 2, 'r': rev}))).toString().substring(0, 12);
    final dir = p.join(c.dataDir, 'users', uid, 'previews', id, key);
    final boxFile = File(p.join(dir, 'box.json'));
    final design = _designOf(v);
    final job = '$id/$key/layers';
    if (_previewJobs.containsKey(job) || !boxFile.existsSync()) {
      final f = _previewJobs[job] ??= renderLayers(c,
              segments: firstSeconds(effectiveSegments(v), 6),
              words: (jv(v['transcript']) as Map)['words'] as List,
              look: Look.from(look, variantId: id),
              design: design,
              outDir: dir,
              baseFrame: _basePath(uid, id))
          .then((box) => boxFile.writeAsStringSync(jsonEncode(box)))
          .whenComplete(() {
            _previewJobs.remove(job);
          });
      await f;
    }
    return {
      'key': key,
      'box': jsonDecode(boxFile.readAsStringSync()),
      'design': {
        for (final k in const ['hook_lead', 'hook_main', 'hook_accent', 'cta_main', 'cta_accent']) k: design[k] ?? ''
      },
    };
  }

  // Текст заголовка правят руками — старые предпросмотры этого ролика больше не верны.
  Future<Response> _saveDesign(Request req, String uid) async {
    final id = req.params['id']!;
    final v = await q1('select id, design, hook_text from variants where id = @id and user_id = @u', {'id': id, 'u': uid});
    if (v == null) return err('Ролик не найден', 404);
    final b = await readJson(req);
    final design = {..._designOf(v)};
    for (final k in const ['hook_lead', 'hook_main', 'hook_accent', 'cta_main', 'cta_accent']) {
      if (b[k] != null) design[k] = b[k].toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if ((design['hook_main'] ?? '').toString().isEmpty) return err('Главное слово не может быть пустым');
    await q('update variants set design = @d:jsonb where id = @id', {'id': id, 'd': design});
    await q('''update variants set edited_at = now() where id = @id and status in ('ready', 'exported')''', {'id': id});
    final dir = Directory(p.join(c.dataDir, 'users', uid, 'previews', id));
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        if (p.basename(e.path).startsWith('base')) continue;
        try {
          e.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    return jsonRes({'ok': true, 'design': design});
  }

  File _previewFile(String uid, String id, String key, bool video) =>
      File(p.join(c.dataDir, 'users', uid, 'previews', id, key, video ? 'out.mp4' : 'still.jpg'));

  // Файл шрифта — чтобы в приложении названия шрифтов были написаны ими самими.
  Response _font(Request req, String key) {
    if (!Fonts.has(key) || Fonts.dir == null) return Response.notFound('Нет шрифта');
    for (final ext in const ['.ttf', '.otf']) {
      final f = File(p.join(Fonts.dir!, '$key$ext'));
      if (f.existsSync()) {
        return Response.ok(f.openRead(), headers: {
          'content-type': 'font/${ext.substring(1)}',
          'content-length': '${f.lengthSync()}',
          'cache-control': 'public, max-age=604800',
        });
      }
    }
    return Response.notFound('Нет шрифта');
  }

  Future<Response> _preview(Request req, String id) async {
    final uid = await userIdFromToken(req.url.queryParameters['t']);
    if (uid == null) return Response.forbidden('Нужно войти');
    final key = (req.url.queryParameters['k'] ?? '').replaceAll(RegExp(r'[^a-f0-9]'), '');
    if (key.isEmpty) return Response.notFound('Нет ключа');
    final video = req.url.queryParameters['video'] == '1';
    final layer = req.url.queryParameters['f'];
    if (layer != null && (layer == 'rest' || layerKey.hasMatch(layer))) {
      final lf = File(p.join(c.dataDir, 'users', uid, 'previews', id, key, layer == 'rest' ? 'rest.jpg' : '$layer.png'));
      if (!lf.existsSync()) return Response.notFound('Предпросмотр ещё не собран');
      return Response.ok(lf.openRead(), headers: {
        'content-type': layer == 'rest' ? 'image/jpeg' : 'image/png',
        'content-length': '${lf.lengthSync()}',
        'cache-control': 'private, max-age=86400',
      });
    }
    final f = _previewFile(uid, id, key, video);
    // Плитка сетки ещё собирается в фоне — ждём её, а не отвечаем ошибкой.
    final pending = _previewJobs['$id/$key/$video'];
    if (!f.existsSync() && pending != null) {
      try {
        await pending.timeout(const Duration(seconds: 90));
      } catch (_) {}
    }
    if (!f.existsSync()) return Response.notFound('Предпросмотр ещё не собран');
    if (!video) {
      return Response.ok(f.openRead(), headers: {
        'content-type': 'image/jpeg',
        'content-length': '${f.lengthSync()}',
        'cache-control': 'private, max-age=86400',
      });
    }
    return serveVideo(req, f);
  }
}

/// Отдаёт mp4 с поддержкой Range — без этого видео не играет в Safari и на iPhone.
Response serveVideo(Request req, File f, {String? disposition, bool cache = false}) {
  final len = f.lengthSync();
  final h = <String, String>{
    'content-type': 'video/mp4',
    'accept-ranges': 'bytes',
    // Видео по одному адресу не меняется — браузер не скачивает его заново при каждом открытии монтажа.
    if (cache) 'cache-control': 'private, max-age=3600',
    if (disposition != null) 'content-disposition': disposition,
  };
  final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers['range'] ?? '');
  if (m == null) {
    return Response.ok(f.openRead(), headers: {...h, 'content-length': '$len'});
  }
  var start = int.tryParse(m[1]!);
  var end = int.tryParse(m[2]!);
  if (start == null) {
    // bytes=-500 — последние 500 байт
    start = len - (end ?? len);
    end = len - 1;
  }
  end = (end == null || end >= len) ? len - 1 : end;
  if (start < 0 || start > end) {
    return Response(416, headers: {'content-range': 'bytes */$len'});
  }
  return Response(206, body: f.openRead(start, end + 1), headers: {
    ...h,
    'content-range': 'bytes $start-$end/$len',
    'content-length': '${end - start + 1}',
  });
}

/// Не больше n задач одновременно: фоновые плитки не должны забивать Mac.
class _Gate {
  _Gate(this._free);
  int _free;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_free > 0) {
      _free--;
    } else {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _free++;
      }
    }
  }
}
