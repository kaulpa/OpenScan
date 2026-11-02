import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openscan/core/cv/models/point.dart';
import 'package:openscan/core/cv/models/quad.dart';
import 'package:openscan/core/cv/platform_store.dart';
import 'package:openscan/core/metadata/photo_metadata.dart';
import 'package:openscan/core/ocr/caption_finder.dart';
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

/// Long edge a whole page is handed to the recognizer at to find its lines
/// ([findTextLines]): a caption a few percent of the page tall is still
/// tens of pixels high there.
const int _kPageEdge = 2000;

/// Every line of text on the photo at [src] ([width] x [height], the right
/// way up), turned [quarterTurns] clockwise first so writing that reads
/// the right way up on the turned page reads the right way up here. Null
/// when recognition isn't available.
Future<List<TextLine>?> findTextLines({
  required String src,
  required int width,
  required int height,
  int quarterTurns = 0,
}) async {
  if (!Platform.isAndroid) return null;

  final dir = Directory('${(await getTemporaryDirectory()).path}/staging/ocr');
  if (!await dir.exists()) await dir.create(recursive: true);
  final dest = '${dir.path}/page_${DateTime.now().microsecondsSinceEpoch}.jpg';

  final scale = min(1.0, _kPageEdge / max(1, max(width, height)));
  final outWidth = max(1, (width * scale).round());
  final outHeight = max(1, (height * scale).round());
  // The page as read, after the turn.
  final readWidth = quarterTurns.isOdd ? outHeight : outWidth;
  final readHeight = quarterTurns.isOdd ? outWidth : outHeight;
  try {
    final cut = await storeOnPlatform(
      src: src,
      quarterTurns: quarterTurns,
      outputs: [
        PlatformOutput(
          dest: dest,
          corners: PlatformOutput.wholeFrame,
          width: outWidth,
          height: outHeight,
          quality: 92,
        ),
      ],
    );
    if (!cut) return null;
    final found = await _channel.invokeListMethod<Map>('lines', {'path': dest});
    return [
      for (final m in found ?? const <Map>[])
        TextLine(
          (m['text'] as String?) ?? '',
          Rect.fromLTRB(
            (m['left'] as num) / readWidth,
            (m['top'] as num) / readHeight,
            (m['right'] as num) / readWidth,
            (m['bottom'] as num) / readHeight,
          ),
          (m['block'] as num?)?.toInt() ?? 0,
        ),
    ];
  } on PlatformException catch (e) {
    debugPrint('Finding text on $src failed: ${e.message}');
  } on MissingPluginException {
    // Tests, or an engine without the channel registered.
  } finally {
    final file = File(dest);
    if (file.existsSync()) file.deleteSync();
  }
  return null;
}

/// Where the caption of the photo with corners [photo] is on the shot at
/// [src] ([width] x [height], the right way up): the writing nearest the
/// photo outside it ([findCaption]), read with the page turned
/// [quarterTurns] clockwise. [photo] and the result are fractions of the
/// shot the right way up, unturned. Null when there is none, or no
/// recognizer.
Future<Rect?> locateCaption({
  required String src,
  required int width,
  required int height,
  required List<Offset> photo,
  int quarterTurns = 0,
}) async {
  final lines = await findTextLines(
    src: src,
    width: width,
    height: height,
    quarterTurns: quarterTurns,
  );
  if (lines == null) return null;
  final caption = findCaption(lines, [
    for (final p in photo) turnFraction(p, quarterTurns),
  ], aspect: quarterTurns.isOdd ? height / width : width / height);
  if (caption == null) return null;
  return Rect.fromPoints(
    unturnFraction(caption.topLeft, quarterTurns),
    unturnFraction(caption.bottomRight, quarterTurns),
  );
}

/// The caption of the photo with corners [photo] on the shot at [src],
/// found ([locateCaption]) and read: what the crop screen does by itself
/// when it opens, for the pages that never go through it, shot in a
/// batch. [PhotoMetadata.empty] when there is none, or no recognizer.
Future<PhotoMetadata> readCaption({
  required String src,
  required int width,
  required int height,
  required List<Offset> photo,
  int quarterTurns = 0,
}) async {
  final region = await locateCaption(
    src: src,
    width: width,
    height: height,
    photo: photo,
    quarterTurns: quarterTurns,
  );
  if (region == null) return PhotoMetadata.empty;
  final text = await readTextInRegion(
    src: src,
    corners: Quad(
      topLeft: Pt(region.left, region.top),
      topRight: Pt(region.right, region.top),
      bottomRight: Pt(region.right, region.bottom),
      bottomLeft: Pt(region.left, region.bottom),
    ),
    width: max(1, (region.width * width).round()),
    height: max(1, (region.height * height).round()),
    quarterTurns: quarterTurns,
  );
  return text == null || text.isEmpty
      ? PhotoMetadata.empty
      : PhotoMetadata.empty.withRecognizedText(text);
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
