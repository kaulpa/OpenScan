import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'contours.dart';
import 'edge_detection.dart';
import 'line_quads.dart';
import 'models/detection_result.dart';
import 'models/quad.dart';

/// Longest edge (px) that detection runs at. Keeps the pure-Dart edge/
/// contour pipeline fast on full-resolution camera photos; the resulting
/// quad is scaled back up to the original image size before being
/// returned, since [DetectionSuccess.quad] is always in original-image
/// coordinates.
const int kDetectionMaxDimension = 700;

/// Entry point designed to be run via `compute()`. Takes the image file
/// path and returns a [DetectionResult] — never throws, so a caller can
/// always resolve the returned future without needing to guard against an
/// unhandled isolate exception.
Future<DetectionResult> detectDocumentIsolateEntry(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const DetectionFailure('Could not decode image');
    }

    final originalWidth = decoded.width;
    final originalHeight = decoded.height;

    final longestEdge = max(originalWidth, originalHeight).toDouble();
    final workingScale =
        longestEdge > kDetectionMaxDimension ? kDetectionMaxDimension / longestEdge : 1.0;
    final workWidth = max(1, (originalWidth * workingScale).round());
    final workHeight = max(1, (originalHeight * workingScale).round());

    final rgba = _downscaleRgba(
      decoded.getBytes(order: img.ChannelOrder.rgba),
      originalWidth,
      originalHeight,
      workWidth,
      workHeight,
    );

    final gray = rgbaToGrayscale(rgba, workWidth, workHeight);
    final quad = detectQuadFromGrayscale(gray, workWidth, workHeight);
    if (quad == null) {
      return DetectionNotFound(originalWidth, originalHeight);
    }

    final scaleBackX = originalWidth / workWidth;
    final scaleBackY = originalHeight / workHeight;
    return DetectionSuccess(
      quad.scaled(scaleBackX, scaleBackY),
      originalWidth,
      originalHeight,
    );
  } catch (e) {
    return DetectionFailure(e.toString());
  }
}

/// Entry point designed to be run via `compute()`: detection on pixels
/// the platform decoder has already scaled down to [kDetectionMaxDimension]
/// (see `native_decode.dart`), skipping [detectDocumentIsolateEntry]'s
/// pure-Dart decode — which, on a full-resolution capture, is most of five
/// seconds. Takes `rgba` (a [TransferableTypedData]), `width` and
/// `height`, and optionally `previous`, a [Quad] in those pixels to look
/// for again (see [detectQuadFromGrayscale]); returns the quad in those
/// pixels' coordinates, or null.
Quad? detectQuadInRgbaIsolateEntry(Map<String, dynamic> params) {
  final rgba =
      (params['rgba'] as TransferableTypedData).materialize().asUint8List();
  final width = params['width'] as int;
  final height = params['height'] as int;
  return detectQuadFromGrayscale(
      rgbaToGrayscale(rgba, width, height), width, height,
      previousQuad: params['previous'] as Quad?);
}

/// Multipliers applied to the Otsu threshold to build several binarized
/// edge masks per frame instead of trusting a single one. Otsu recomputes
/// its threshold fresh from each frame's own gradient-magnitude histogram,
/// so it can shift slightly frame-to-frame under sensor noise/lighting
/// flicker even when the scene hasn't changed — a single mask's contour
/// search can then land on a visibly different quad purely because the
/// threshold moved. Mirrors the reference document-scanner app's approach
/// of trying multiple thresholds/channels per frame and scoring the
/// pooled results ([pickBestOutline]) instead of committing to one
/// strategy's output.
const List<double> _thresholdMultipliers = [0.7, 1.0, 1.3];

/// Evidence ([assessQuad]) at which a quad of straight lines is taken to
/// be the outline without asking the contour pipeline as well. Photos and
/// documents lying flat score well above it.
const double _kConvincingLineEvidence = 0.7;

/// Finds the outline of the photo or document in an already-grayscale
/// frame. Pure function, no I/O — shared by the file-based one-shot entry
/// points above and the live-scan persistent isolate, so the detection
/// logic only exists in one place.
///
/// Candidates come from two places: quads made of the frame's straight
/// lines ([lineQuadCandidates]), which find a photo by its four sides even
/// where its picture fades into the album page, and — when none of those
/// has [_kConvincingLineEvidence] — the contour pipeline: blur, Sobel,
/// binarized at several thresholds around the Otsu one
/// ([_thresholdMultipliers]), dilated, the convex hull of each edge blob
/// simplified to four corners. They are all judged the same way, on the
/// edges along their sides, and the winner is moved onto those edges
/// ([pickBestOutline]).
///
/// [previousQuad], when supplied, nudges the choice toward whichever
/// candidate best corresponds to it. Always null for the one-shot file
/// detection (no "previous frame" there); the live-scan worker isolate
/// supplies its own last-seen quad.
Quad? detectQuadFromGrayscale(Uint8List gray, int width, int height,
    {Quad? previousQuad}) {
  if (max(width, height) <= _kSearchMaxDimension) {
    return _findOutline(gray, width, height, previousQuad: previousQuad);
  }
  // Looked for at half the size, where a deckled edge's scallops and the
  // sensor's noise have blurred into straight lines, then settled onto
  // the edges at the full one.
  final halfWidth = width ~/ 2, halfHeight = height ~/ 2;
  final coarse = _findOutline(
      _halve(gray, width, halfWidth, halfHeight), halfWidth, halfHeight,
      previousQuad: previousQuad?.scaled(0.5, 0.5));
  if (coarse == null) return null;
  final edges =
      EdgeMap.fromBlurred(gaussianBlur3(gray, width, height), width, height);
  return settleOutline(
      edges, coarse.scaled(width / halfWidth, height / halfHeight));
}

/// Longest edge, in pixels, outlines are looked for at
/// ([detectQuadFromGrayscale]): the live scan's frames as they come, a
/// photo at half of [kDetectionMaxDimension].
const int _kSearchMaxDimension = 400;

/// [gray] ([width] wide) at half the size, each pixel the mean of the
/// four it covers.
Uint8List _halve(Uint8List gray, int width, int halfWidth, int halfHeight) {
  final out = Uint8List(halfWidth * halfHeight);
  for (int y = 0; y < halfHeight; y++) {
    final top = 2 * y * width, bottom = top + width;
    for (int x = 0; x < halfWidth; x++) {
      final l = 2 * x;
      final sum = gray[top + l] +
          gray[top + l + 1] +
          gray[bottom + l] +
          gray[bottom + l + 1];
      out[y * halfWidth + x] = (sum + 2) >> 2;
    }
  }
  return out;
}

Quad? _findOutline(Uint8List gray, int width, int height,
    {Quad? previousQuad}) {
  final blurred = gaussianBlur3(gray, width, height);
  final edges = EdgeMap.fromBlurred(blurred, width, height);

  final candidates = lineQuadCandidates(edges);
  // The contour pipeline costs several times all the rest put together,
  // so it is only asked when no straight outline convinces: a page that
  // curls has none.
  if (!candidates.any(
      (q) => assessQuad(edges, q).evidence >= _kConvincingLineEvidence)) {
    final magnitude = edges.clampedMagnitude();
    final baseThreshold = otsuThreshold(magnitude);
    for (final multiplier in _thresholdMultipliers) {
      final t = (baseThreshold * multiplier).round().clamp(0, 255);
      final binary = threshold(magnitude, t);
      final dilated = dilate(binary, width, height, 4);
      candidates.addAll(findDocumentQuadCandidates(dilated, width, height));
    }
  }

  return pickBestOutline(edges, candidates, previousQuad: previousQuad);
}

/// Nearest-neighbor downsample of an RGBA buffer (stride 4).
Uint8List _downscaleRgba(
  Uint8List src,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  if (srcW == dstW && srcH == dstH) return src;

  final dst = Uint8List(dstW * dstH * 4);
  for (int y = 0; y < dstH; y++) {
    final sy = (y * srcH / dstH).floor().clamp(0, srcH - 1);
    for (int x = 0; x < dstW; x++) {
      final sx = (x * srcW / dstW).floor().clamp(0, srcW - 1);
      final srcIdx = (sy * srcW + sx) * 4;
      final dstIdx = (y * dstW + x) * 4;
      dst[dstIdx] = src[srcIdx];
      dst[dstIdx + 1] = src[srcIdx + 1];
      dst[dstIdx + 2] = src[srcIdx + 2];
      dst[dstIdx + 3] = src[srcIdx + 3];
    }
  }
  return dst;
}
