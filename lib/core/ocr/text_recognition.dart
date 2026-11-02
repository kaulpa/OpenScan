import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openscan/core/cv/models/quad.dart';
import 'package:openscan/core/cv/platform_store.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('openscan/text_reader');

/// The long edge a marked region is handed to the recognizer at. A caption
/// marked on a full-resolution photo is often only a few hundred pixels
/// wide, and the recognizer reads small handwriting noticeably better
/// scaled up; past the upper bound it only gets slower.
const int _kMinRegionEdge = 1200;
const int _kMaxRegionEdge = 2400;

/// Reads the text inside [corners] of the photo at [src] — fractions of the
/// photo the right way up, TL, TR, BR, BL, the same way the crop describes
/// the page — turned [quarterTurns] clockwise first, so writing that reads
/// the right way up on the turned page reads the right way up here.
/// [width] x [height] is the region's size in the photo's own pixels.
///
/// Returns the text, '' when the region holds none the recognizer can
/// make out, or null when recognition isn't available at all: not
/// Android, or the region couldn't be cut out of the photo.
Future<String?> readTextInRegion({
  required String src,
  required Quad corners,
  required int width,
  required int height,
  int quarterTurns = 0,
}) async {
  if (!Platform.isAndroid) return null;

  final dir = Directory('${(await getTemporaryDirectory()).path}/staging/ocr');
  if (!await dir.exists()) await dir.create(recursive: true);
  final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';

  final longest = max(1, max(width, height));
  final scale = longest < _kMinRegionEdge
      ? _kMinRegionEdge / longest
      : min(1.0, _kMaxRegionEdge / longest);
  try {
    final cut = await storeOnPlatform(
      src: src,
      quarterTurns: quarterTurns,
      outputs: [
        PlatformOutput(
          dest: dest,
          corners: corners,
          width: max(1, (width * scale).round()),
          height: max(1, (height * scale).round()),
          quality: 95,
        ),
      ],
    );
    if (!cut) return null;
    return await readText(dest);
  } finally {
    final file = File(dest);
    if (file.existsSync()) file.deleteSync();
  }
}

/// Recognizes the text in the image file at [path]. Null when recognition
/// failed or isn't available; '' when it found nothing.
Future<String?> readText(String path) async {
  try {
    final text = await _channel.invokeMethod<String>('read', {'path': path});
    return text?.trim() ?? '';
  } on PlatformException catch (e) {
    debugPrint('Text recognition failed for $path: ${e.message}');
  } on MissingPluginException {
    // Tests, or an engine without the channel registered.
  }
  return null;
}
