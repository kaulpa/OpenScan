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
/// A region much taller than wide that holds nothing readable is tried on
/// its side as well, either way: a caption written up the edge of a print.
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
  final upright = await _readTurned(src, corners, width, height, quarterTurns);
  final readWidth = quarterTurns.isOdd ? height : width;
  final readHeight = quarterTurns.isOdd ? width : height;
  if (upright == null || upright.isNotEmpty || readHeight < 1.5 * readWidth) {
    return upright;
  }
  for (final extra in const [1, 3]) {
    final text = await _readTurned(
      src,
      corners,
      width,
      height,
      (quarterTurns + extra) % 4,
    );
    if (text != null && text.isNotEmpty) return text;
  }
  return upright;
}

Future<String?> _readTurned(
  String src,
  Quad corners,
  int width,
  int height,
  int quarterTurns,
) async {
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
/// ([locateCaption]): a caption a few percent of the page tall is still
/// tens of pixels high there.
const int _kPageEdge = 2000;

/// The photo at [src] ([width] x [height], the right way up), cut out at
/// [_kPageEdge] turned [quarterTurns] clockwise, for its lines to be found
/// on ([_linesOn]). Null when that fails.
Future<({String path, int width, int height})?> _cutPage(
  String src,
  int width,
  int height,
  int quarterTurns,
) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/staging/ocr');
  if (!await dir.exists()) await dir.create(recursive: true);
  final dest = '${dir.path}/page_${DateTime.now().microsecondsSinceEpoch}.jpg';
  final scale = min(1.0, _kPageEdge / max(1, max(width, height)));
  final outWidth = max(1, (width * scale).round());
  final outHeight = max(1, (height * scale).round());
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
  return (
    path: dest,
    width: quarterTurns.isOdd ? outHeight : outWidth,
    height: quarterTurns.isOdd ? outWidth : outHeight,
  );
}

/// Every line of text on [page], turned [extraTurns] clockwise further,
/// with boxes as fractions of the page as turned. Null when recognition
/// isn't available.
Future<List<TextLine>?> _linesOn(
  ({String path, int width, int height}) page,
  int extraTurns,
) async {
  final width = extraTurns.isOdd ? page.height : page.width;
  final height = extraTurns.isOdd ? page.width : page.height;
  try {
    final found = await _channel.invokeListMethod<Map>('lines', {
      'path': page.path,
      'turns': extraTurns,
    });
    return [
      for (final m in found ?? const <Map>[])
        TextLine(
          (m['text'] as String?) ?? '',
          Rect.fromLTRB(
            (m['left'] as num) / width,
            (m['top'] as num) / height,
            (m['right'] as num) / width,
            (m['bottom'] as num) / height,
          ),
          (m['block'] as num?)?.toInt() ?? 0,
        ),
    ];
  } on PlatformException catch (e) {
    debugPrint('Finding text on ${page.path} failed: ${e.message}');
  } on MissingPluginException {
    // Tests, or an engine without the channel registered.
  }
  return null;
}

/// Where the caption of the photo with corners [photo] is on the shot at
/// [src] ([width] x [height], the right way up): the writing nearest the
/// photo outside it ([findCaption]), with the page turned [quarterTurns]
/// clockwise — or, when there is none that way, a quarter turn further
/// either way, for a caption written up the side of a print lying on its
/// side. Returns the caption's box, in fractions of the shot the right
/// way up and unturned like [photo], and the turns it reads the right way
/// up at. Null when there is none, or no recognizer.
Future<({Rect region, int quarterTurns})?> locateCaption({
  required String src,
  required int width,
  required int height,
  required List<Offset> photo,
  int quarterTurns = 0,
}) async {
  if (!Platform.isAndroid) return null;
  final page = await _cutPage(src, width, height, quarterTurns);
  if (page == null) return null;
  try {
    for (final extra in const [0, 1, 3]) {
      final lines = await _linesOn(page, extra);
      if (lines == null) return null;
      final turns = (quarterTurns + extra) % 4;
      final caption = findCaption(lines, [
        for (final p in photo) turnFraction(p, turns),
      ], aspect: turns.isOdd ? height / width : width / height);
      if (caption != null) {
        return (
          region: Rect.fromPoints(
            unturnFraction(caption.topLeft, turns),
            unturnFraction(caption.bottomRight, turns),
          ),
          quarterTurns: turns,
        );
      }
    }
    return null;
  } finally {
    final file = File(page.path);
    if (file.existsSync()) file.deleteSync();
  }
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
  final found = await locateCaption(
    src: src,
    width: width,
    height: height,
    photo: photo,
    quarterTurns: quarterTurns,
  );
  if (found == null) return PhotoMetadata.empty;
  final region = found.region;
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
    quarterTurns: found.quarterTurns,
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
