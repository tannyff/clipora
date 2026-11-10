import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Сервер раздаёт и сайт, и API с одного адреса — поэтому берём адрес страницы.
/// Исключение: `flutter run` на порту 5173, тогда API на 8080 того же хоста.
String _resolveBase() {
  const fromDefine = String.fromEnvironment('API_URL');
  if (fromDefine.isNotEmpty) return fromDefine;
  if (!kIsWeb) return 'http://localhost:8080';
  final u = Uri.base;
  if (u.port == 5173) return '${u.scheme}://${u.host}:8080';
  return u.origin;
}

final apiBase = _resolveBase();

class ApiError implements Exception {
  ApiError(this.message, [this.status = 0, this.data]);
  final String message;
  final int status;
  final Map<String, dynamic>? data;
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final Api i = Api._();

  final loggedIn = ValueNotifier<bool>(false);
  String? token;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    token = sp.getString('token');
    loggedIn.value = token != null;
  }

  Future<void> setToken(String? t) async {
    token = t;
    final sp = await SharedPreferences.getInstance();
    if (t == null) {
      await sp.remove('token');
    } else {
      await sp.setString('token', t);
    }
    loggedIn.value = t != null;
  }

  Map<String, String> get _h => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Uri _u(String path) => Uri.parse('$apiBase$path');

  Future<dynamic> get(String path) => _send(http.get(_u(path), headers: _h));
  Future<dynamic> post(String path, [Object? body]) =>
      _send(http.post(_u(path), headers: _h, body: jsonEncode(body ?? {})));
  Future<dynamic> put(String path, [Object? body]) =>
      _send(http.put(_u(path), headers: _h, body: jsonEncode(body ?? {})));
  Future<dynamic> delete(String path) => _send(http.delete(_u(path), headers: _h));

  Future<dynamic> _send(Future<http.Response> f) async {
    http.Response r;
    try {
      r = await f;
    } catch (_) {
      throw ApiError('Нет связи с сервером. Он запущен?');
    }
    final data = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      if (r.statusCode == 401) await setToken(null);
      final map = data is Map ? data.cast<String, dynamic>() : null;
      throw ApiError(map?['error']?.toString() ?? 'Ошибка ${r.statusCode}', r.statusCode, map);
    }
    return data;
  }

  String uploadUrl(String projectId, String name) =>
      '$apiBase/api/projects/$projectId/sources?name=${Uri.encodeQueryComponent(name)}';

  String mediaUploadUrl(String name) => '$apiBase/api/media?name=${Uri.encodeQueryComponent(name)}';

  String sourceProxyUrl(String sourceId) => '$apiBase/media/sources/$sourceId/proxy?t=$token';

  String libraryProxyUrl(String mediaId) => '$apiBase/media/library/$mediaId/proxy?t=$token';

  String libraryThumbUrl(String mediaId) => '$apiBase/media/library/$mediaId/thumb?t=$token';

  String zipUrl(List<String> ids) => '$apiBase/media/zip?t=$token&ids=${ids.join(',')}';

  String mediaUrl(String variantId, {bool download = false}) =>
      '$apiBase/media/variants/$variantId?t=$token${download ? '&download=1' : ''}';

  String thumbUrl(String variantId, Object? version) =>
      '$apiBase/media/variants/$variantId/thumb?t=$token&v=${Uri.encodeQueryComponent('$version')}';

  String fontUrl(String key) => '$apiBase/fonts/$key';

  String previewUrl(String variantId, String key, {bool video = false}) =>
      '$apiBase/media/variants/$variantId/preview?t=$token&k=$key${video ? '&video=1' : ''}';
}
