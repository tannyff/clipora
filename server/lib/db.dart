import 'package:postgres/postgres.dart';

import 'config.dart';

late final Pool _pool;

Future<void> openDb(Config c) async {
  _pool = Pool.withEndpoints(
    [
      Endpoint(
        host: c.dbHost,
        port: c.dbPort,
        database: c.dbName,
        username: c.dbUser,
        password: c.dbPassword,
      )
    ],
    settings: PoolSettings(maxConnectionCount: 8, sslMode: SslMode.disable),
  );
  await _pool.execute('select 1');
}

/// Параметры: @name, с типом — @name:jsonb, @name:float8, @name:text.
Future<List<Map<String, dynamic>>> q(String sql,
    [Map<String, Object?> params = const {}]) async {
  final res = await _pool.execute(Sql.named(sql), parameters: params);
  return [for (final r in res) r.toColumnMap()];
}

Future<Map<String, dynamic>?> q1(String sql,
    [Map<String, Object?> params = const {}]) async {
  final rows = await q(sql, params);
  return rows.isEmpty ? null : rows.first;
}

Future<void> exec(String sql) async {
  await _pool.execute(sql);
}

const migrations = <String>[
  '''create table if not exists users (
    id text primary key default gen_random_uuid()::text,
    email text unique not null,
    password_hash text not null,
    name text not null default '',
    plan text not null default 'free',
    monthly_render_limit int not null default 1000,
    created_at timestamptz not null default now())''',
  '''create table if not exists sessions (
    token text primary key,
    user_id text not null references users(id) on delete cascade,
    created_at timestamptz not null default now())''',
  '''create table if not exists destinations (
    id text primary key default gen_random_uuid()::text,
    user_id text not null references users(id) on delete cascade,
    name text not null,
    kind text not null default 'account',
    sort int not null default 0)''',
  '''create table if not exists projects (
    id text primary key default gen_random_uuid()::text,
    user_id text not null references users(id) on delete cascade,
    title text not null,
    created_at timestamptz not null default now())''',
  '''create table if not exists sources (
    id text primary key default gen_random_uuid()::text,
    project_id text not null references projects(id) on delete cascade,
    user_id text not null references users(id) on delete cascade,
    file_name text not null,
    path text,
    duration double precision,
    status text not null default 'uploaded',
    error text,
    transcript jsonb,
    created_at timestamptz not null default now())''',
  '''create table if not exists variants (
    id text primary key default gen_random_uuid()::text,
    project_id text not null references projects(id) on delete cascade,
    source_id text not null references sources(id) on delete cascade,
    user_id text not null references users(id) on delete cascade,
    topic text not null default '',
    title text not null default '',
    hook_text text not null default '',
    hook_type text not null default '',
    caption text not null default '',
    hashtags jsonb not null default '[]',
    segments jsonb not null default '[]',
    duration double precision not null default 0,
    style text not null default 'karaoke',
    status text not null default 'proposed',
    output_path text,
    text text,
    audio_fp jsonb,
    originality jsonb,
    destination text,
    error text,
    rendered_at timestamptz,
    exported_at timestamptz,
    created_at timestamptz not null default now())''',
  '''create table if not exists jobs (
    id bigserial primary key,
    kind text not null,
    payload jsonb not null,
    status text not null default 'queued',
    attempts int not null default 0,
    error text,
    created_at timestamptz not null default now(),
    started_at timestamptz,
    finished_at timestamptz)''',
  'create index if not exists jobs_status_idx on jobs(status, id)',
  'create index if not exists variants_user_status_idx on variants(user_id, status)',
  'create index if not exists variants_project_idx on variants(project_id)',
  // Части хука, вспышки и финальная надпись от AI — для оформления.
  'alter table variants add column if not exists design jsonb',
  // Выбранное оформление: шаблон заголовка, палитра, субтитры, наезды, обработка.
  'alter table variants add column if not exists look jsonb',
  // Ручной монтаж: {clips: [...]}. null — ролик собирается по плану AI из segments.
  'alter table variants add column if not exists edit jsonb',
  'alter table variants add column if not exists edited_at timestamptz',
  'alter table sources add column if not exists proxy_path text',
  'alter table sources add column if not exists proxy_error text',
  'alter table variants add column if not exists published_at timestamptz',
  'alter table variants add column if not exists look_own boolean not null default false',
  'create index if not exists variants_user_dest_idx on variants(user_id, destination)',
  // Медиатека: красивые кадры-вставки пользователя, общие для всех проектов.
  '''create table if not exists media (
    id text primary key default gen_random_uuid()::text,
    user_id text not null references users(id) on delete cascade,
    file_name text not null,
    path text,
    proxy_path text,
    duration double precision,
    has_audio boolean not null default true,
    status text not null default 'uploaded',
    error text,
    tags jsonb not null default '[]',
    created_at timestamptz not null default now())''',
  'create index if not exists media_user_idx on media(user_id, created_at)',
  // Мои подписи к рилсам: примеры стиля для AI и готовые подписи для части роликов.
  '''create table if not exists captions (
    id text primary key default gen_random_uuid()::text,
    user_id text not null references users(id) on delete cascade,
    topic text not null default '',
    body text not null,
    hashtags jsonb not null default '[]',
    used int not null default 0,
    created_at timestamptz not null default now())''',
  'create index if not exists captions_user_idx on captions(user_id, created_at)',
  'alter table users add column if not exists caption_share int not null default 30',
  // mixed — ролик собран AI из нескольких видео проекта; caption_src: mine — моя подпись, ai — написал AI.
  'alter table variants add column if not exists mixed boolean not null default false',
  'alter table variants add column if not exists caption_src text',
  // Монтаж от AI как был — «Вернуть как было» возвращает к нему.
  'alter table variants add column if not exists ai_edit jsonb',
  'alter table sources add column if not exists work_path text',
  // Свои стили оформления: «Мой стиль 1» применяется в один клик к любому ролику.
  '''create table if not exists user_looks (
    id text primary key default gen_random_uuid()::text,
    user_id text not null references users(id) on delete cascade,
    name text not null,
    look jsonb not null,
    created_at timestamptz not null default now(),
    unique (user_id, name))''',
  // Ответы AI на одинаковое задание: повтор после сбоя не тратит лимит Gemini.
  '''create table if not exists ai_cache (
    key text primary key,
    response jsonb not null,
    created_at timestamptz not null default now())''',
  // Убирать паузы и «эээ» в монтаже от AI.
  'alter table users add column if not exists auto_cut boolean not null default true',
];

Future<void> migrate() async {
  for (final m in migrations) {
    await exec(m);
  }
}
