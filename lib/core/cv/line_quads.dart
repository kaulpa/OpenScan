import 'dart:math';
import 'dart:typed_data';

import 'contours.dart';
import 'models/point.dart';
import 'models/quad.dart';

/// Finding a photo (or a document) by its four straight sides, and judging
/// any candidate quad by how well the frame backs those sides up.
///
/// The contour pipeline in `contours.dart` takes the convex hull of all the
/// edge pixels that touch each other. That works for a white sheet on a
/// dark table, but not for a photo in an album: wherever the picture has no
/// detail of its own near its border — a pale sky against a cream page —
/// the hull cuts across the picture along the first texture it meets, and
/// the next photo or the edge of the page can join it. Here a side is a
/// straight line instead, found by a Hough transform in which each edge
/// pixel only votes along the direction its edge runs: a faint but long
/// straight border adds up, scattered texture doesn't.
///
/// Every candidate — from these lines or from the contour pipeline — is
/// then scored on the evidence along its four sides ([assessQuad]): how
/// much of each side carries an edge, and whether all four agree on which
/// side is the brighter one. A photo on a light page is darker than the
/// page all the way round; a quad that borrows the table's edge, or the
/// next photo's, has a side that disagrees.

/// Gradient magnitude (3x3 Sobel on the blurred frame) an edge needs to
/// count. Paper grain stays below 10 at the sizes detection runs at; the
/// faintest photo border measured — pale sky against a cream album page —
/// sits around 18.
const double kEdgeThreshold = 14;

/// How closely an edge's gradient has to point across a side to count for
/// it: cos(~32 degrees).
const double _kAlignment = 0.85;

/// How far either side of a line, in pixels, an edge may sit and still
/// count for it: Hough lines are only as exact as their bins.
const int _kSearch = 2;

/// Share of each side left out at both ends when weighing it: old prints
/// have rounded corners, and their sides only reach the corner as lines.
const double _kCornerTrim = 0.08;

/// What a quad keeps of its evidence when one of its sides disagrees with
/// the other three about which way round the contrast goes. Not zero: a
/// print with a sleeve or the next page lying along one side is still a
/// print. Two against two is no one object on one background, and counts
/// for nothing.
const double _kMixedPolarity = 0.6;

/// Pixels at the frame's border whose gradients are ignored ([EdgeMap]):
/// as far in as the blur and the Sobel kernel carry the border's own
/// pixels.
const int _kBorder = 3;

/// Evidence below which a quad isn't taken as an outline at all.
const double kMinQuadEvidence = 0.45;

/// The gradients of a blurred grayscale frame: what every candidate quad
/// is judged against.
class EdgeMap {
  EdgeMap._(this.width, this.height, this.gx, this.gy, this.magnitude);

  final int width;
  final int height;

  /// Sobel responses: positive where the frame gets brighter to the right
  /// (gx) or downwards (gy).
  final Int16List gx;
  final Int16List gy;
  final Float32List magnitude;

  factory EdgeMap.fromBlurred(Uint8List blurred, int width, int height) {
    final n = width * height;
    final gx = Int16List(n);
    final gy = Int16List(n);
    final magnitude = Float32List(n);
    for (int y = 0; y < height; y++) {
      final above = (y > 0 ? y - 1 : 0) * width;
      final row = y * width;
      final below = (y < height - 1 ? y + 1 : y) * width;
      for (int x = 0; x < width; x++) {
        final left = x > 0 ? x - 1 : 0;
        final right = x < width - 1 ? x + 1 : x;
        final a = blurred[above + left], b = blurred[above + x];
        final c = blurred[above + right], d = blurred[row + left];
        final f = blurred[row + right], g = blurred[below + left];
        final h = blurred[below + x], k = blurred[below + right];
        final sx = (c + 2 * f + k) - (a + 2 * d + g);
        final sy = (g + 2 * h + k) - (a + 2 * b + c);
        gx[row + x] = sx;
        gy[row + x] = sy;
        magnitude[row + x] = sqrt((sx * sx + sy * sy).toDouble());
      }
    }
    return EdgeMap._(width, height, gx, gy, magnitude);
  }

  /// The magnitude clamped into a byte, as the contour pipeline's
  /// thresholds expect it.
  Uint8List clampedMagnitude() {
    final out = Uint8List(magnitude.length);
    for (int i = 0; i < out.length; i++) {
      final m = magnitude[i];
      out[i] = m >= 255 ? 255 : m.round();
    }
    return out;
  }

  /// Whether ([xi], [yi]) is far enough in from the frame's border for its
  /// gradient to mean anything: there the Sobel kernel reads the border
  /// pixels twice, and a frame that ends in a dark line or a vignette
  /// would otherwise offer its own outline as the photo's.
  bool _inside(int xi, int yi) =>
      xi >= _kBorder &&
      yi >= _kBorder &&
      xi < width - _kBorder &&
      yi < height - _kBorder;

  /// Whether an edge crosses ([x], [y]) along unit normal ([nx], [ny]):
  /// 1 when it gets brighter towards the normal, -1 when darker, 0 for no
  /// edge or one running another way.
  int _crossing(double x, double y, double nx, double ny) {
    final xi = x.round(), yi = y.round();
    if (!_inside(xi, yi)) return 0;
    final i = yi * width + xi;
    final m = magnitude[i];
    if (m < kEdgeThreshold) return 0;
    final along = gx[i] * nx + gy[i] * ny;
    if (along >= _kAlignment * m) return 1;
    if (-along >= _kAlignment * m) return -1;
    return 0;
  }

  /// Signed gradient across the normal at ([x], [y]), 0 off the frame.
  double _across(double x, double y, double nx, double ny) {
    final xi = x.round(), yi = y.round();
    if (!_inside(xi, yi)) return 0;
    final i = yi * width + xi;
    return gx[i] * nx + gy[i] * ny;
  }
}

/// Edge evidence along one stretch of a line, sampled a pixel apart: per
/// sample, whether the nearest edge within [_kSearch] crosses it brighter
/// towards the normal (`plus`) or darker (`minus`), kept
/// as running totals so any stretch of it can be weighed in constant time.
class _Profile {
  _Profile(this.start, this.plus, this.minus);

  /// Line parameter of the first sample.
  final double start;
  final Int32List plus;
  final Int32List minus;

  int get length => plus.length - 1;

  /// Shares of the samples between [from] and [to] (line parameters, in
  /// either order, trimmed by [_kCornerTrim]) with an edge each way round,
  /// and for each way the longest run of samples without one, as a share
  /// too. Stretches beyond the sampled part count as having none.
  _Shares between(double from, double to) {
    var a = min(from, to), b = max(from, to);
    final trim = (b - a) * _kCornerTrim;
    a += trim;
    b -= trim;
    final first = (a - start).ceil(), last = (b - start).floor();
    final expected = last - first + 1;
    if (expected <= 0) return _Shares.none;
    final i0 = first.clamp(0, length), i1 = (last + 1).clamp(0, length);
    if (i1 <= i0) return _Shares.none;

    double longestGap(Int32List hits) {
      var longest = 0, run = i0 - first;
      for (int k = i0; k < i1; k++) {
        if (hits[k + 1] > hits[k]) {
          longest = max(longest, run);
          run = 0;
        } else {
          run++;
        }
      }
      return max(longest, run + last + 1 - i1) / expected;
    }

    return _Shares(
      plus: (plus[i1] - plus[i0]) / expected,
      minus: (minus[i1] - minus[i0]) / expected,
      plusGap: longestGap(plus),
      minusGap: longestGap(minus),
    );
  }

  static _Profile sample(
    EdgeMap edges,
    double ox,
    double oy,
    double dx,
    double dy,
    double from,
    double to,
  ) {
    final nx = dy, ny = -dx;
    final count = max(0, (to - from).floor() + 1);
    final plus = Int32List(count + 1);
    final minus = Int32List(count + 1);
    for (int k = 0; k < count; k++) {
      final t = from + k;
      final px = ox + t * dx, py = oy + t * dy;
      // The edge nearest the line decides: an edge of another thing
      // running alongside — a sleeve, the next print, a few pixels off —
      // is no evidence against this one. (At these sizes that strip of
      // page between them looks just like a thin line drawn on it, so a
      // grid's line counts as an edge too; a print lying on the grid still
      // wins on edges all round.)
      var up = false, down = false;
      for (int d = 0; d <= _kSearch && !up && !down; d++) {
        for (final side in d == 0 ? const [0] : [d, -d]) {
          final c = edges._crossing(px + side * nx, py + side * ny, nx, ny);
          if (c > 0) up = true;
          if (c < 0) down = true;
        }
      }
      plus[k + 1] = plus[k] + (up ? 1 : 0);
      minus[k + 1] = minus[k] + (down ? 1 : 0);
    }
    return _Profile(from, plus, minus);
  }
}

/// What a stretch of line has to show for itself ([_Profile.between]).
class _Shares {
  const _Shares({
    required this.plus,
    required this.minus,
    required this.plusGap,
    required this.minusGap,
  });

  static const none = _Shares(plus: 0, minus: 0, plusGap: 1, minusGap: 1);

  final double plus, minus, plusGap, minusGap;

  /// Support for the side being brighter towards the normal, and for it
  /// being darker ([_support]).
  double get brighterTowards => _support(plus, minus, plusGap);
  double get darkerTowards => _support(minus, plus, minusGap);
}

/// How strongly the frame backs [quad] up as the outline of one object.
///
/// `evidence` (0-1) is how well its four sides carry edges that agree on
/// which side is brighter; `score` weighs that against the quad's size,
/// shape and how central it sits, and is what candidates of one frame are
/// compared on.
({double evidence, double score}) assessQuad(EdgeMap edges, Quad quad) {
  final pts = quad.points;
  final brighterOut = <double>[];
  final darkerOut = <double>[];
  for (int i = 0; i < 4; i++) {
    final a = pts[i], b = pts[(i + 1) % 4];
    final len = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
    if (len < 4) return (evidence: 0, score: 0);
    final dx = (b.x - a.x) / len, dy = (b.y - a.y) / len;
    // Corners run clockwise on screen, so (dy, -dx) points out of the quad.
    final shares = _Profile.sample(
      edges,
      a.x,
      a.y,
      dx,
      dy,
      0,
      len,
    ).between(0, len);
    brighterOut.add(shares.brighterTowards);
    darkerOut.add(shares.darkerTowards);
  }
  return _assess(quad, brighterOut, darkerOut, edges.width, edges.height);
}

/// Longest stretch of a side, as a share of it, that may have no edge
/// without counting against it: a photo corner mount, a fleck of glare.
const double _kGapAllowance = 0.1;

/// A side's support for one polarity: edges that way round, less those
/// the other way — a real border is one-sided, while texture crosses both
/// ways about equally — and less
/// again for the longest stretch with none at all. A print's border runs
/// on unbroken; the bottom of a line of text stops where the line does,
/// and a quad round two prints has the page showing between them.
double _support(double wanted, double opposite, double gap) {
  final net = (wanted - opposite).clamp(0.0, 1.0);
  final broken = ((gap - _kGapAllowance) / (0.5 - _kGapAllowance)).clamp(
    0.0,
    1.0,
  );
  return net * (1 - broken);
}

({double evidence, double score}) _assess(
  Quad quad,
  List<double> brighterOut,
  List<double> darkerOut,
  int width,
  int height,
) {
  double geo(Iterable<double> v) =>
      pow(v.fold<double>(1, (p, s) => p * max(s, 0.02)), 0.25).toDouble();
  var evidence = max(geo(brighterOut), geo(darkerOut));
  for (int odd = 0; odd < 4; odd++) {
    for (final (usual, other) in [
      (brighterOut, darkerOut),
      (darkerOut, brighterOut),
    ]) {
      final sides = [
        for (int i = 0; i < 4; i++) i == odd ? other[i] : usual[i],
      ];
      evidence = max(evidence, _kMixedPolarity * geo(sides));
    }
  }

  final area = polygonArea(quad.points) / (width * height);
  final square = 1 - maxAngleDeviationFraction(quad);
  final cx = quad.points.fold<double>(0, (s, p) => s + p.x) / 4;
  final cy = quad.points.fold<double>(0, (s, p) => s + p.y) / 4;
  final offCentre =
      sqrt(pow(cx - width / 2, 2) + pow(cy - height / 2, 2)) /
      (sqrt(width * width + height * height) / 2);
  // Of two equally good outlines, the one being pointed at.
  final central = 1 - 0.3 * offCentre.clamp(0.0, 1.0);
  return (
    evidence: evidence,
    score: evidence * evidence * sqrt(area) * square * central,
  );
}

/// One straight line, as a Hough peak: unit normal (cos theta, sin theta)
/// and distance [rho] from the origin along it.
class _Line {
  _Line(this.theta, this.rho, this.votes) : nx = cos(theta), ny = sin(theta);

  final double theta;
  final double rho;
  final int votes;
  final double nx, ny;

  /// Direction along the line, chosen so that (dy, -dx) is the normal.
  double get dx => -ny;
  double get dy => nx;

  _Profile? _profile;

  /// The line's evidence across the whole frame, sampled once and then
  /// shared by every quad it is a side of.
  _Profile profile(EdgeMap edges) => _profile ??= _sampleAcross(edges, this);

  /// Line parameter of a point on it.
  double paramOf(Pt p) => (p.x - rho * nx) * dx + (p.y - rho * ny) * dy;
}

_Profile _sampleAcross(EdgeMap edges, _Line line) {
  // Where the line enters and leaves the frame.
  final ox = line.rho * line.nx, oy = line.rho * line.ny;
  var lo = double.negativeInfinity, hi = double.infinity;
  void clip(double o, double d, double limit) {
    if (d.abs() < 1e-9) {
      if (o < 0 || o > limit) lo = hi = 0;
      return;
    }
    final t0 = (0 - o) / d, t1 = (limit - o) / d;
    lo = max(lo, min(t0, t1));
    hi = min(hi, max(t0, t1));
  }

  clip(ox, line.dx, edges.width - 1.0);
  clip(oy, line.dy, edges.height - 1.0);
  if (!(hi > lo)) return _Profile(0, Int32List(1), Int32List(1));
  return _Profile.sample(edges, ox, oy, line.dx, line.dy, lo, hi);
}

/// Angle bins of the Hough transform: one per degree.
const int _kThetaBins = 180;

/// Bins either side of its edge's direction an edge pixel votes in, for
/// that direction being a little off on a soft edge.
const int _kVoteSpread = 3;

/// Lines kept for building quads from.
const int _kMaxLines = 24;

/// Radius of the neighbourhood an edge's direction is averaged over for
/// voting ([_houghLines]).
const int _kOrientationRadius = 2;

/// The frame's strongest straight lines, by a Hough transform over its
/// thinned edges in which each pixel only votes for lines running across
/// its edge direction.
///
/// That direction is not the pixel's own gradient but the dominant one of
/// the pixels around it (the structure tensor): along a deckled print's
/// scalloped edge single gradients swing tens of degrees either way and
/// their votes would scatter over as many lines, while their average
/// follows the edge.
List<_Line> _houghLines(EdgeMap edges) {
  final w = edges.width, h = edges.height;
  final diag = sqrt(w * w + h * h).ceil();
  final rhoBins = 2 * diag + 1;
  final acc = Int32List(_kThetaBins * rhoBins);
  final cosT = Float64List(_kThetaBins), sinT = Float64List(_kThetaBins);
  for (int b = 0; b < _kThetaBins; b++) {
    cosT[b] = cos(b * pi / _kThetaBins);
    sinT[b] = sin(b * pi / _kThetaBins);
  }

  final mag = edges.magnitude, gx = edges.gx, gy = edges.gy;
  final xx = Float32List(w * h), xy = Float32List(w * h);
  final yy = Float32List(w * h);
  for (int i = 0; i < xx.length; i++) {
    final x = gx[i].toDouble(), y = gy[i].toDouble();
    xx[i] = x * x;
    xy[i] = x * y;
    yy[i] = y * y;
  }
  final sxx = _boxBlur(xx, w, h, _kOrientationRadius);
  final sxy = _boxBlur(xy, w, h, _kOrientationRadius);
  final syy = _boxBlur(yy, w, h, _kOrientationRadius);

  for (int y = _kBorder; y < h - _kBorder; y++) {
    for (int x = _kBorder; x < w - _kBorder; x++) {
      final i = y * w + x;
      final m = mag[i];
      if (m < kEdgeThreshold) continue;
      var theta = 0.5 * atan2(2 * sxy[i], sxx[i] - syy[i]);
      if (theta < 0) theta += pi;
      final c = cos(theta).abs(), s = sin(theta).abs();
      // Thin the edges first: only the strongest pixel across each one.
      final int step;
      if (s * 2.414 < c) {
        step = 1;
      } else if (c * 2.414 < s) {
        step = w;
      } else {
        step = theta < pi / 2 ? w + 1 : w - 1;
      }
      if (m < mag[i - step] || m < mag[i + step]) continue;

      final bin = (theta / pi * _kThetaBins).round() % _kThetaBins;
      for (int k = -_kVoteSpread; k <= _kVoteSpread; k++) {
        final b = (bin + k) % _kThetaBins;
        final rho = (x * cosT[b] + y * sinT[b]).round() + diag;
        acc[b * rhoBins + rho]++;
      }
    }
  }

  final minVotes = max(10, (0.08 * min(w, h)).round());
  final peaks = <_Line>[];
  for (int b = 0; b < _kThetaBins; b++) {
    for (int r = 0; r < rhoBins; r++) {
      final v = acc[b * rhoBins + r];
      if (v < minVotes) continue;
      var isPeak = true;
      for (int db = -2; db <= 2 && isPeak; db++) {
        var nb = b + db, nr0 = r;
        // Past either end of the angle range the same line comes back
        // with its normal flipped, and rho with it.
        if (nb < 0 || nb >= _kThetaBins) {
          nb = (nb + _kThetaBins) % _kThetaBins;
          nr0 = 2 * diag - r;
        }
        for (int dr = -4; dr <= 4; dr++) {
          if (db == 0 && dr == 0) continue;
          final nr = nr0 + dr;
          if (nr < 0 || nr >= rhoBins) continue;
          final nv = acc[nb * rhoBins + nr];
          if (nv > v || (nv == v && (nb * rhoBins + nr) < b * rhoBins + r)) {
            isPeak = false;
            break;
          }
        }
      }
      if (isPeak) {
        peaks.add(_Line(b * pi / _kThetaBins, (r - diag).toDouble(), v));
      }
    }
  }
  peaks.sort((a, b) => b.votes.compareTo(a.votes));

  final lines = <_Line>[];
  for (final p in peaks) {
    if (lines.length >= _kMaxLines) break;
    if (lines.any((l) => _sameLine(l, p))) continue;
    lines.add(p);
  }
  return lines;
}

/// Mean of [src] over the (2 * [radius] + 1) square around each pixel,
/// the frame's border repeated outwards.
Float32List _boxBlur(Float32List src, int w, int h, int radius) {
  final rows = Float32List(w * h);
  for (int y = 0; y < h; y++) {
    final row = y * w;
    for (int x = 0; x < w; x++) {
      var sum = 0.0;
      for (int d = -radius; d <= radius; d++) {
        sum += src[row + (x + d).clamp(0, w - 1)];
      }
      rows[row + x] = sum;
    }
  }
  final out = Float32List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      var sum = 0.0;
      for (int d = -radius; d <= radius; d++) {
        sum += rows[(y + d).clamp(0, h - 1) * w + x];
      }
      out[y * w + x] = sum;
    }
  }
  return out;
}

/// Angle between two lines' directions, 0 to 90 degrees.
double _angleBetween(_Line a, _Line b) {
  var d = (a.theta - b.theta).abs() * 180 / pi;
  if (d > 90) d = 180 - d;
  return d;
}

/// [b]'s rho with its normal turned to agree with [a]'s.
double _alignedRho(_Line a, _Line b) =>
    (a.nx * b.nx + a.ny * b.ny) >= 0 ? b.rho : -b.rho;

bool _sameLine(_Line a, _Line b) =>
    _angleBetween(a, b) < 3 && (a.rho - _alignedRho(a, b)).abs() < 5;

Pt? _intersect(_Line a, _Line b) {
  final det = a.nx * b.ny - a.ny * b.nx;
  if (det.abs() < 1e-6) return null;
  return Pt(
    (a.rho * b.ny - a.ny * b.rho) / det,
    (a.nx * b.rho - a.rho * b.nx) / det,
  );
}

bool _convexInOrder(List<Pt> p) {
  int sign = 0;
  for (int i = 0; i < 4; i++) {
    final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
    final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
    if (s == 0) return false;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

/// Quads made of four of the frame's straight lines — two roughly
/// parallel pairs, crossing each other — best first by [assessQuad]'s
/// score, at most [maxCandidates] of them.
List<Quad> lineQuadCandidates(EdgeMap edges, {int maxCandidates = 6}) {
  final w = edges.width, h = edges.height;
  final lines = _houghLines(edges);
  final minSide = 0.15 * min(w, h);

  // Opposite sides: near parallel, and far enough apart.
  final pairs = <(int, int)>[];
  for (int i = 0; i < lines.length; i++) {
    for (int j = i + 1; j < lines.length; j++) {
      if (_angleBetween(lines[i], lines[j]) > 30) continue;
      if ((lines[i].rho - _alignedRho(lines[i], lines[j])).abs() < minSide) {
        continue;
      }
      pairs.add((i, j));
    }
  }

  final tolerance = 0.02 * max(w, h);
  bool inFrame(Pt p) =>
      p.x >= -tolerance &&
      p.y >= -tolerance &&
      p.x <= w - 1 + tolerance &&
      p.y <= h - 1 + tolerance;

  final scored = <({Quad quad, double score})>[];
  for (int p = 0; p < pairs.length; p++) {
    for (int q = p + 1; q < pairs.length; q++) {
      final a = lines[pairs[p].$1], b = lines[pairs[p].$2];
      final c = lines[pairs[q].$1], d = lines[pairs[q].$2];
      if (_angleBetween(a, c) < 45 || _angleBetween(b, d) < 45) continue;
      final p1 = _intersect(a, c), p2 = _intersect(a, d);
      final p3 = _intersect(b, d), p4 = _intersect(b, c);
      if (p1 == null || p2 == null || p3 == null || p4 == null) continue;
      final ring = [p1, p2, p3, p4];
      if (!ring.every(inFrame) || !_convexInOrder(ring)) continue;
      final quad = sortCorners(ring);
      if (!isPlausibleQuad(quad, w, h)) continue;

      // Each side straight off its line's shared profile: a from p1 to
      // p2, d from p2 to p3, b from p3 to p4, c from p4 to p1.
      final cx = (p1.x + p2.x + p3.x + p4.x) / 4;
      final cy = (p1.y + p2.y + p3.y + p4.y) / 4;
      final brighterOut = <double>[], darkerOut = <double>[];
      for (final (line, from, to) in [
        (a, p1, p2),
        (d, p2, p3),
        (b, p3, p4),
        (c, p4, p1),
      ]) {
        final shares = line
            .profile(edges)
            .between(line.paramOf(from), line.paramOf(to));
        // The line's normal points out of the quad when the centre is on
        // its other side.
        final outIsPlus = cx * line.nx + cy * line.ny < line.rho;
        brighterOut.add(
          outIsPlus ? shares.brighterTowards : shares.darkerTowards,
        );
        darkerOut.add(
          outIsPlus ? shares.darkerTowards : shares.brighterTowards,
        );
      }
      final assessed = _assess(quad, brighterOut, darkerOut, w, h);
      if (assessed.evidence < kMinQuadEvidence) continue;
      scored.add((quad: quad, score: assessed.score));
    }
  }
  scored.sort((x, y) => y.score.compareTo(x.score));
  return [for (final s in scored.take(maxCandidates)) s.quad];
}

/// [quad] with each side moved onto the edge it lies along, to a fraction
/// of a pixel, and the corners where those edges cross. A side with too
/// little edge under it to go by stays where it was; so does the whole
/// quad, if the result would no longer be a plausible one.
Quad refineQuad(EdgeMap edges, Quad quad) {
  final pts = quad.points;
  final sides = <({double px, double py, double dx, double dy})>[];
  for (int i = 0; i < 4; i++) {
    final a = pts[i], b = pts[(i + 1) % 4];
    final len = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
    if (len < 8) return quad;
    final dx = (b.x - a.x) / len, dy = (b.y - a.y) / len;
    final nx = dy, ny = -dx;
    final shares = _Profile.sample(
      edges,
      a.x,
      a.y,
      dx,
      dy,
      0,
      len,
    ).between(0, len);
    final sign = shares.plus >= shares.minus ? 1.0 : -1.0;

    final xs = <double>[], ys = <double>[];
    var expected = 0;
    for (double t = len * 0.1; t <= len * 0.9; t += 1) {
      expected++;
      final px = a.x + t * dx, py = a.y + t * dy;
      var best = kEdgeThreshold, bestOff = 0;
      var found = false;
      for (int off = -3; off <= 3; off++) {
        final v = sign * edges._across(px + off * nx, py + off * ny, nx, ny);
        if (v >= best) {
          best = v;
          bestOff = off;
          found = true;
        }
      }
      if (!found) continue;
      // Where the parabola through the peak and its neighbours tops out.
      final l =
          sign *
          edges._across(
            px + (bestOff - 1) * nx,
            py + (bestOff - 1) * ny,
            nx,
            ny,
          );
      final r =
          sign *
          edges._across(
            px + (bestOff + 1) * nx,
            py + (bestOff + 1) * ny,
            nx,
            ny,
          );
      final curve = l - 2 * best + r;
      final shift = curve < 0 ? (0.5 * (l - r) / curve).clamp(-0.5, 0.5) : 0.0;
      xs.add(px + (bestOff + shift) * nx);
      ys.add(py + (bestOff + shift) * ny);
    }

    var fit = _fitLine(xs, ys);
    if (fit != null) {
      // Once more without the points the first fit left furthest out.
      final keepX = <double>[], keepY = <double>[];
      for (int k = 0; k < xs.length; k++) {
        final off = (xs[k] - fit.px) * fit.dy - (ys[k] - fit.py) * fit.dx;
        if (off.abs() <= 1.5) {
          keepX.add(xs[k]);
          keepY.add(ys[k]);
        }
      }
      fit = keepX.length >= 0.3 * expected ? _fitLine(keepX, keepY) : null;
    }
    sides.add(fit ?? (px: a.x, py: a.y, dx: dx, dy: dy));
  }

  final corners = <Pt>[];
  final diag = sqrt(pow(edges.width, 2) + pow(edges.height, 2));
  for (int i = 0; i < 4; i++) {
    final s = sides[(i + 3) % 4], t = sides[i];
    final det = s.dx * t.dy - s.dy * t.dx;
    if (det.abs() < 1e-6) return quad;
    final u = ((t.px - s.px) * t.dy - (t.py - s.py) * t.dx) / det;
    final p = Pt(s.px + u * s.dx, s.py + u * s.dy);
    if (sqrt(pow(p.x - pts[i].x, 2) + pow(p.y - pts[i].y, 2)) > 0.05 * diag) {
      return quad;
    }
    corners.add(p);
  }
  final refined = Quad(
    topLeft: corners[0],
    topRight: corners[1],
    bottomRight: corners[2],
    bottomLeft: corners[3],
  );
  return isPlausibleQuad(refined, edges.width, edges.height) ? refined : quad;
}

/// Total-least-squares line through the points: their centroid and main
/// direction. Null for fewer than a handful.
({double px, double py, double dx, double dy})? _fitLine(
  List<double> xs,
  List<double> ys,
) {
  if (xs.length < 5) return null;
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  double sxx = 0, sxy = 0, syy = 0;
  for (int k = 0; k < n; k++) {
    final x = xs[k] - mx, y = ys[k] - my;
    sxx += x * x;
    sxy += x * y;
    syy += y * y;
  }
  final angle = 0.5 * atan2(2 * sxy, sxx - syy);
  return (px: mx, py: my, dx: cos(angle), dy: sin(angle));
}

/// The outline among [candidates] the frame backs up best ([assessQuad]),
/// moved onto its edges ([refineQuad]) and kept inside the frame; null
/// when none of them has [kMinQuadEvidence].
///
/// [previousQuad], from the live scan's last frame, nudges the choice
/// towards whatever was found there and keeps each corner in the slot it
/// had, as [pickBestQuad] does for the contour pipeline alone.
Quad? pickBestOutline(
  EdgeMap edges,
  List<Quad> candidates, {
  Quad? previousQuad,
}) {
  final w = edges.width, h = edges.height;
  final diagonal = sqrt(w * w + h * h).toDouble();
  Quad? best;
  var bestScore = 0.0;
  for (final candidate in candidates) {
    final assessed = assessQuad(edges, candidate);
    if (assessed.evidence < kMinQuadEvidence) continue;
    var score = assessed.score;
    if (previousQuad != null) {
      final match = bestCornerAssignment(candidate.points, previousQuad);
      final proximity = 1 - (match.totalDistance / diagonal).clamp(0.0, 1.0);
      score *= 1 + kPreviousQuadProximityWeight * proximity;
    }
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  if (best == null) return null;

  final outline = settleOutline(edges, best);
  return previousQuad == null
      ? outline
      : bestCornerAssignment(outline.points, previousQuad).quad;
}

/// [quad] moved onto its edges ([refineQuad]) and kept inside the frame.
Quad settleOutline(EdgeMap edges, Quad quad) {
  final w = edges.width, h = edges.height;
  Pt inFrame(Pt p) => Pt(p.x.clamp(0.0, w - 1.0), p.y.clamp(0.0, h - 1.0));
  final refined = refineQuad(edges, quad);
  return Quad(
    topLeft: inFrame(refined.topLeft),
    topRight: inFrame(refined.topRight),
    bottomRight: inFrame(refined.bottomRight),
    bottomLeft: inFrame(refined.bottomLeft),
  );
}
