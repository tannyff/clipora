import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../api.dart';

class PickedVideo {
  PickedVideo(this.name, this.size, this._file);
  final String name;
  final int size;
  final web.File _file;
}

/// Системное окно выбора: на телефоне предлагает медиатеку и камеру.
/// camera — сразу открыть камеру (на телефоне); на компьютере браузер покажет обычный выбор файла.
Future<List<PickedVideo>> pickVideos({bool camera = false, bool multiple = true}) {
  final done = Completer<List<PickedVideo>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'video/*'
    ..multiple = multiple && !camera;
  if (camera) input.setAttribute('capture', 'environment');
  // Не display:none — Safari тогда может не прислать событие о выборе.
  input.style
    ..position = 'fixed'
    ..left = '-1000px'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0';
  web.document.body!.appendChild(input);

  List<PickedVideo> read() {
    final files = input.files;
    final out = <PickedVideo>[];
    if (files != null) {
      for (var i = 0; i < files.length; i++) {
        final f = files.item(i);
        if (f != null) out.add(PickedVideo(f.name, f.size, f));
      }
    }
    return out;
  }

  late final JSFunction onFocus;
  void finish(List<PickedVideo> out) {
    if (done.isCompleted) return;
    done.complete(out);
    web.window.removeEventListener('focus', onFocus);
    input.remove();
  }

  void onPicked(web.Event _) => finish(read());
  input.addEventListener('change', onPicked.toJS);
  input.addEventListener('input', onPicked.toJS);
  input.addEventListener('cancel', ((web.Event _) => finish(const [])).toJS);

  // Запасной путь: окно браузера снова в фокусе — проверяем, выбран ли файл.
  // Если файла нет, ждём ещё: Safari может долго готовить видео из «Фото».
  onFocus = ((web.Event _) {
    for (final ms in const [300, 1500, 4000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        final out = read();
        if (out.isNotEmpty) finish(out);
      });
    }
  }).toJS;
  web.window.addEventListener('focus', onFocus);

  input.click();
  return done.future;
}

/// Файл уходит напрямую из браузера, без копирования в память приложения.
/// Возвращает ответ сервера (там id созданной записи).
Future<Map<String, dynamic>> uploadVideo(PickedVideo v, String url, void Function(double) onProgress) {
  final done = Completer<Map<String, dynamic>>();
  final xhr = web.XMLHttpRequest();
  xhr.open('POST', url);
  xhr.setRequestHeader('authorization', 'Bearer ${Api.i.token}');
  xhr.setRequestHeader('content-type', 'application/octet-stream');
  xhr.upload.addEventListener(
      'progress',
      ((web.ProgressEvent e) {
        if (e.lengthComputable && e.total > 0) onProgress(e.loaded / e.total);
      }).toJS);
  xhr.addEventListener(
      'load',
      ((web.Event _) {
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            done.complete((jsonDecode(xhr.responseText) as Map).cast<String, dynamic>());
          } catch (_) {
            done.complete({});
          }
          return;
        }
        var msg = 'Ошибка загрузки ${xhr.status}';
        try {
          msg = (jsonDecode(xhr.responseText) as Map)['error']?.toString() ?? msg;
        } catch (_) {}
        done.completeError(ApiError(msg, xhr.status));
      }).toJS);
  xhr.addEventListener(
      'error',
      ((web.Event _) {
        if (!done.isCompleted) done.completeError(ApiError('Нет связи с сервером'));
      }).toJS);
  xhr.send(v._file);
  return done.future;
}
