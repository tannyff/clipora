import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../api.dart';

class PickedVideo {
  PickedVideo(this.name, this.size, this._path);
  final String name;
  final int size;
  final String _path;
}

Future<List<PickedVideo>> pickVideos({bool camera = false, bool multiple = true}) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: multiple && !camera);
  if (res == null) return const [];
  return [
    for (final f in res.files)
      if (f.path != null) PickedVideo(f.name, f.size, f.path!)
  ];
}

Future<Map<String, dynamic>> uploadVideo(PickedVideo v, String url, void Function(double) onProgress) async {
  final file = File(v._path);
  final total = await file.length();
  final req = http.StreamedRequest('POST', Uri.parse(url))
    ..headers['authorization'] = 'Bearer ${Api.i.token}'
    ..headers['content-type'] = 'application/octet-stream'
    ..contentLength = total;
  final sending = req.send();
  var sent = 0;
  await for (final chunk in file.openRead()) {
    req.sink.add(chunk);
    sent += chunk.length;
    onProgress(sent / total);
  }
  await req.sink.close();
  final res = await sending;
  if (res.statusCode >= 300) {
    throw ApiError('Ошибка загрузки ${res.statusCode}: ${await res.stream.bytesToString()}', res.statusCode);
  }
  try {
    return (jsonDecode(await res.stream.bytesToString()) as Map).cast<String, dynamic>();
  } catch (_) {
    return {};
  }
}
