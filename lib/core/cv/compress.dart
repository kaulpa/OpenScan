import 'dart:io';

import 'package:image/image.dart' as img;

/// Entry point designed to be run via `compute()`. Re-encodes the JPEG at
/// `params['src']` at `params['quality']` and writes it to the exact path
/// `params['dest']` — the caller picks that name, since several of these
/// now run concurrently and a name generated in here (like the old
/// `<dest-dir>/<timestamp>.jpg` scheme) can collide when two finish in the
/// same millisecond.
/// An optional `params['maxEdge']` caps the long edge first: an export
/// preset gets small by shedding pixels as well as JPEG quality, and past
/// a point the pixels are where the bytes actually are.
Future<String> compressImageIsolateEntry(Map<String, dynamic> params) async {
  final String src = params['src'] as String;
  final String dest = params['dest'] as String;
  final int quality = params['quality'] as int;
  final int? maxEdge = params['maxEdge'] as int?;

  final bytes = await File(src).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode image: $src');
  }

  final jpg = img.encodeJpg(fitToMaxEdge(decoded, maxEdge), quality: quality);
  await File(dest).writeAsBytes(jpg, flush: true);
  return dest;
}

/// Long edge, in pixels, a stored page is capped at.
///
/// Upstream OpenScan stores 2400px at quality 85: ~200 DPI across an A4
/// page, past which a photo of paper carries no more readable detail.
/// This app keeps photographs, where it does — a 10x15 print filling the
/// frame of a 12MP camera comes out around 3500px on its long side — so
/// pages are kept at what the camera delivers. Kept originals share the
/// cap: a re-crop should start from the same detail the first crop had.
const int kStoredPageMaxEdge = 4096;
const int kStoredPageQuality = 92;
const int kStoredOriginalMaxEdge = 4096;
const int kStoredOriginalQuality = 90;

/// Entry point designed to be run via `compute()`. Downscales the image at
/// `params['src']` so its long edge is at most `params['maxEdge']`,
/// re-encodes it as JPEG at `params['quality']`, and writes it to
/// `params['dest']`.
///
/// A capture straight off the camera — and especially a photo picked from
/// the gallery — is far larger than a page of text needs: normalizing on
/// the way into storage is what keeps a document in the hundreds of KB
/// rather than the tens of MB.
Future<void> normalizeImageIsolateEntry(Map<String, dynamic> params) async {
  final String src = params['src'] as String;
  final String dest = params['dest'] as String;
  final int maxEdge = params['maxEdge'] as int;
  final int quality = params['quality'] as int;

  final bytes = await File(src).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode image: $src');
  }

  await File(dest).writeAsBytes(
      img.encodeJpg(fitToMaxEdge(decoded, maxEdge), quality: quality),
      flush: true);
}

/// [image] scaled down so its long edge is at most [maxEdge], or [image]
/// itself when it already fits or [maxEdge] is null. Never enlarges: a
/// page smaller than the cap is left as it is rather than interpolated up
/// to a size it has no detail for.
img.Image fitToMaxEdge(img.Image image, int? maxEdge) {
  if (maxEdge == null) return image;
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge <= maxEdge) return image;
  return img.copyResize(
    image,
    width: image.width >= image.height ? maxEdge : null,
    height: image.height > image.width ? maxEdge : null,
    interpolation: img.Interpolation.average,
  );
}
