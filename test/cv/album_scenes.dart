import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:openscan/core/cv/models/point.dart';
import 'package:openscan/core/cv/models/quad.dart';

/// Synthetic photos of album pages — and one document — for the detector
/// to find its target in, with the target's true corners. Drawn the way a
/// phone sees them: in perspective, slightly soft, with sensor noise, the
/// prints with rounded corners. The pictures on the prints are made up to
/// hold what makes real ones hard: a pale sky that fades into the page, a
/// straight horizon, a neighbouring print in line with the target, a
/// caption below it, the edge of the page and the table behind it.
class AlbumScene {
  AlbumScene(this.name, this.image, this.target, {this.alternative});

  final String name;
  final img.Image image;

  /// The target print's corners (before rounding), clockwise from the top
  /// left, in [image]'s pixels.
  final Quad target;

  /// Another outline that is just as right a crop, if there is one: the
  /// picture inside a print's white border.
  final Quad? alternative;
}

typedef _Paint = (int, int, int) Function(double u, double v);

/// Deterministic value noise in [0, 1) at integer lattice points.
double _hash(int x, int y, int seed) {
  var h = x * 374761393 + y * 668265263 + seed * 2147483647;
  h = (h ^ (h >> 13)) * 1274126177;
  h = h ^ (h >> 16);
  return (h & 0xffffff) / 0x1000000;
}

/// Smooth value noise at ([x], [y]) in lattice units.
double _noise(double x, double y, int seed) {
  final xi = x.floor(), yi = y.floor();
  final fx = x - xi, fy = y - yi;
  final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  final a = _hash(xi, yi, seed), b = _hash(xi + 1, yi, seed);
  final c = _hash(xi, yi + 1, seed), d = _hash(xi + 1, yi + 1, seed);
  return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
}

/// A few octaves of [_noise]: rock, grass, foliage.
double _fractal(double x, double y, int seed) {
  var sum = 0.0, amp = 0.5, f = 1.0;
  for (int o = 0; o < 4; o++) {
    sum += amp * _noise(x * f, y * f, seed + o);
    amp *= 0.5;
    f *= 2;
  }
  return sum;
}

(int, int, int) _mix((int, int, int) a, (int, int, int) b, double t) => (
  (a.$1 + (b.$1 - a.$1) * t).round(),
  (a.$2 + (b.$2 - a.$2) * t).round(),
  (a.$3 + (b.$3 - a.$3) * t).round(),
);

/// The alpine holiday photo: haze at the top barely darker than the page,
/// a mountainside with a diagonal ridge, a meadow, three people.
(int, int, int) _alpine(double u, double v) {
  const sky = (206, 209, 212);
  final ridge = 0.12 + 0.45 * u; // the ridge falls from left to right
  if (v < ridge - 0.03 * _noise(u * 9, 0, 3)) {
    return _mix(sky, (198, 202, 206), v / max(ridge, 0.01));
  }
  if (v < 0.68) {
    final rock = _fractal(u * 18, v * 18, 7);
    final g = (70 + 110 * rock).round();
    return (g, g + 4, g + 8);
  }
  for (final (x0, x1, y0, colour) in [
    (0.30, 0.38, 0.62, (225, 225, 225)),
    (0.42, 0.48, 0.70, (60, 70, 120)),
    (0.55, 0.68, 0.50, (200, 60, 55)),
  ]) {
    if (u > x0 && u < x1 && v > y0) return colour;
  }
  final grass = _fractal(u * 30, v * 30, 11);
  return ((110 + 50 * grass).round(), (140 + 50 * grass).round(), 70);
}

/// The beach photo: sky, and the sea from a dead straight horizon down.
(int, int, int) _seaside(double u, double v) {
  if (v < 0.42) return _mix((150, 190, 230), (190, 215, 240), v / 0.42);
  final wave = _fractal(u * 40, v * 12, 5);
  return (
    (30 + 30 * wave).round(),
    (70 + 40 * wave).round(),
    (120 + 50 * wave).round(),
  );
}

/// Foliage, for the neighbouring prints.
(int, int, int) _foliage(double u, double v) {
  final f = _fractal(u * 14, v * 14, 21);
  return ((70 + 90 * f).round(), (90 + 80 * f).round(), (50 + 50 * f).round());
}

/// A sheet of typed text.
(int, int, int) _letter(double u, double v) {
  if (u > 0.1 && u < 0.9 && v > 0.1 && v < 0.85) {
    final line = (v * 40) % 1;
    final word = _noise(u * 30, (v * 40).floorToDouble(), 2);
    if (line > 0.55 && line < 0.85 && word > 0.35) return (40, 40, 45);
  }
  return (238, 238, 235);
}

/// A print on [quad] (corners of the unit square's TL, TR, BR, BL) with
/// corners rounded by [radius] (in u/v), showing [paint], with a plain
/// [border] of [borderColour] around the picture.
class _Print {
  _Print(
    this.quad,
    this.paint, {
    this.radius = 0.035,
    this.border = 0,
    this.borderColour = (240, 240, 236),
    this.deckle = 0,
  });

  final Quad quad;
  final _Paint paint;
  final double radius;
  final double border;
  final (int, int, int) borderColour;

  /// Depth (in u/v) of a deckled edge's scallops; 0 for a cut one.
  final double deckle;

  bool covers(double u, double v) {
    if (deckle > 0) {
      // Scallops along every side, about forty to a side.
      final inset = [u, v, 1 - u, 1 - v].reduce(min);
      final along = (inset == u || inset == 1 - u) ? v : u;
      final wave = deckle * (0.5 + 0.5 * sin(along * 2 * pi * 40));
      if (inset < wave) return false;
    }
    return _insideRounded(u, v, radius);
  }
}

/// [paint] as a faded sepia print.
_Paint _sepia(_Paint paint) => (u, v) {
  final (r, g, b) = paint(u, v);
  final l = 0.3 * r + 0.59 * g + 0.11 * b;
  final faded = 70 + 0.7 * l;
  return (
    (faded * 1.08).clamp(0, 255).round(),
    (faded * 0.97).round(),
    (faded * 0.80).round(),
  );
};

/// Square-to-quad homography (Heckbert), with its inverse.
class _Homography {
  _Homography(Quad q) {
    final x0 = q.topLeft.x, y0 = q.topLeft.y;
    final x1 = q.topRight.x, y1 = q.topRight.y;
    final x2 = q.bottomRight.x, y2 = q.bottomRight.y;
    final x3 = q.bottomLeft.x, y3 = q.bottomLeft.y;
    final dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
    final dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
    final den = dx1 * dy2 - dx2 * dy1;
    final g = (dx3 * dy2 - dx2 * dy3) / den;
    final h = (dx1 * dy3 - dx3 * dy1) / den;
    final m = [
      x1 - x0 + g * x1, x3 - x0 + h * x3, x0, //
      y1 - y0 + g * y1, y3 - y0 + h * y3, y0, //
      g, h, 1.0,
    ];
    _forward = m;
    // Inverse by the adjugate.
    final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5];
    final gg = m[6], hh = m[7], i = m[8];
    _inv = [
      e * i - f * hh, c * hh - b * i, b * f - c * e, //
      f * gg - d * i, a * i - c * gg, c * d - a * f, //
      d * hh - e * gg, b * gg - a * hh, a * e - b * d,
    ];
  }

  late final List<double> _inv;
  late final List<double> _m = _forward;
  List<double> _forward = const [];

  Pt fromUnit(double u, double v) {
    final w = _m[6] * u + _m[7] * v + _m[8];
    return Pt(
      (_m[0] * u + _m[1] * v + _m[2]) / w,
      (_m[3] * u + _m[4] * v + _m[5]) / w,
    );
  }

  (double, double) toUnit(double x, double y) {
    final w = _inv[6] * x + _inv[7] * y + _inv[8];
    return (
      (_inv[0] * x + _inv[1] * y + _inv[2]) / w,
      (_inv[3] * x + _inv[4] * y + _inv[5]) / w,
    );
  }
}

bool _insideRounded(double u, double v, double r) {
  if (u < 0 || v < 0 || u > 1 || v > 1) return false;
  final cu = u < r ? r : (u > 1 - r ? 1 - r : u);
  final cv = v < r ? r : (v > 1 - r ? 1 - r : v);
  return (u - cu) * (u - cu) + (v - cv) * (v - cv) <= r * r;
}

Quad _quad(List<double> v) => Quad(
  topLeft: Pt(v[0], v[1]),
  topRight: Pt(v[2], v[3]),
  bottomRight: Pt(v[4], v[5]),
  bottomLeft: Pt(v[6], v[7]),
);

/// Renders a page of [pageColour] — below [pageTop], with a wooden table
/// above it, when given — carrying [prints] and a handwritten-looking
/// caption under [captionAt], then softens and adds noise.
img.Image _render(
  int width,
  int height,
  (int, int, int) pageColour,
  List<_Print> prints, {
  double? pageTop,
  Pt? captionAt,
  int seed = 1,
}) {
  final image = img.Image(width: width, height: height);
  final maps = [for (final p in prints) _Homography(p.quad)];
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      // Uneven light across the page.
      final light = 0.94 + 0.06 * (1 - (x / width + y / height) / 2);
      var colour = pageColour;
      if (pageTop != null && y < pageTop + 0.04 * x) {
        final wood = _fractal(x / 40, y / 6, 31);
        colour = ((150 + 40 * wood).round(), (105 + 30 * wood).round(), 60);
      }
      for (int k = 0; k < prints.length; k++) {
        final (u, v) = maps[k].toUnit(x + 0.5, y + 0.5);
        final p = prints[k];
        if (!p.covers(u, v)) continue;
        final b = p.border;
        colour = (u < b || v < b || u > 1 - b || v > 1 - b)
            ? p.borderColour
            : p.paint((u - b) / (1 - 2 * b), (v - b) / (1 - 2 * b));
      }
      image.setPixelRgb(
        x,
        y,
        (colour.$1 * light).round(),
        (colour.$2 * light).round(),
        (colour.$3 * light).round(),
      );
    }
  }

  if (captionAt != null) {
    final rnd = Random(seed);
    var x = captionAt.x;
    for (int letter = 0; letter < 18; letter++) {
      final h = 14 + rnd.nextDouble() * 10;
      img.drawLine(
        image,
        x1: x.round(),
        y1: (captionAt.y + h).round(),
        x2: (x + 6 + rnd.nextDouble() * 6).round(),
        y2: (captionAt.y + rnd.nextDouble() * 6).round(),
        color: img.ColorRgb8(70, 70, 90),
        thickness: 2,
      );
      x += 14 + rnd.nextDouble() * 8;
    }
  }

  final soft = img.gaussianBlur(image, radius: 2);
  final rnd = Random(seed);
  for (final px in soft) {
    final n = (rnd.nextDouble() - 0.5) * 10;
    px
      ..r = (px.r + n).clamp(0, 255)
      ..g = (px.g + n).clamp(0, 255)
      ..b = (px.b + n).clamp(0, 255);
  }
  return soft;
}

/// Every scene, at roughly the proportions of a phone photo (3:4).
List<AlbumScene> albumScenes() {
  const cream = (236, 233, 224);
  final scenes = <AlbumScene>[];

  // The case from the field: a print whose sky fades into the page, the
  // next print just to its right and in line with it, the table above the
  // page, the caption below.
  final alpine = _quad([128, 330, 742, 306, 760, 1080, 146, 1090]);
  scenes.add(
    AlbumScene(
      'alpine',
      _render(
        900,
        1200,
        cream,
        [
          _Print(alpine, _alpine),
          _Print(_quad([768, 305, 1100, 292, 1120, 1070, 786, 1079]), _foliage),
        ],
        pageTop: 150,
        captionAt: const Pt(170, 1130),
      ),
      alpine,
    ),
  );

  // A dead straight horizon across the whole print.
  final seaside = _quad([170, 260, 740, 280, 730, 900, 150, 880]);
  scenes.add(
    AlbumScene(
      'seaside',
      _render(
        900,
        1200,
        cream,
        [_Print(seaside, _seaside)],
        captionAt: const Pt(180, 960),
        seed: 2,
      ),
      seaside,
    ),
  );

  // Two prints side by side, tops and bottoms in line, a narrow strip of
  // page between them. The target is the one in the middle of the frame.
  final pair = _quad([250, 380, 690, 372, 700, 860, 258, 866]);
  scenes.add(
    AlbumScene(
      'pair',
      _render(900, 1200, cream, [
        _Print(_quad([-260, 389, 222, 381, 230, 867, -250, 875]), _foliage),
        _Print(pair, _alpine),
      ], seed: 3),
      pair,
    ),
  );

  // Prints in a column, left and right edges in line.
  final column = _quad([190, 360, 720, 350, 728, 760, 196, 768]);
  scenes.add(
    AlbumScene(
      'column',
      _render(900, 1200, cream, [
        _Print(_quad([186, -150, 716, -160, 721, 320, 190, 330]), _foliage),
        _Print(column, _seaside),
        _Print(_quad([197, 800, 729, 792, 736, 1300, 203, 1310]), _foliage),
      ], seed: 4),
      column,
    ),
  );

  // A black page, the print with a white border of its own, turned on the
  // page and seen at more of an angle.
  final framed = _quad([210, 250, 760, 330, 680, 980, 100, 880]);
  scenes.add(
    AlbumScene(
      'black_page',
      _render(
        900,
        1200,
        (28, 28, 30),
        [_Print(framed, _alpine, radius: 0.02, border: 0.05)],
        seed: 5,
      ),
      framed,
    ),
  );

  // A faded sepia print with deckled edges.
  final deckled = _quad([200, 300, 700, 290, 712, 900, 206, 912]);
  scenes.add(
    AlbumScene(
      'deckled',
      _render(
        900,
        1200,
        cream,
        [_Print(deckled, _sepia(_alpine), radius: 0, deckle: 0.012)],
        captionAt: const Pt(220, 960),
        seed: 7,
      ),
      deckled,
    ),
  );

  // A print with a white border of its own on a light page: the border's
  // edge is barely there, the picture's inside it is plain. Either is a
  // fair crop; the test accepts both.
  final bordered = _quad([180, 280, 720, 270, 730, 940, 186, 950]);
  final picture = _Homography(bordered);
  scenes.add(
    AlbumScene(
      'white_border',
      _render(900, 1200, cream, [
        _Print(
          bordered,
          _seaside,
          radius: 0.015,
          border: 0.06,
          borderColour: (244, 243, 238),
        ),
      ], seed: 8),
      bordered,
      alternative: Quad(
        topLeft: picture.fromUnit(0.06, 0.06),
        topRight: picture.fromUnit(0.94, 0.06),
        bottomRight: picture.fromUnit(0.94, 0.94),
        bottomLeft: picture.fromUnit(0.06, 0.94),
      ),
    ),
  );

  // The scanner's first job: a typed letter on a wooden table.
  final letter = _quad([110, 140, 790, 120, 840, 1100, 70, 1120]);
  scenes.add(
    AlbumScene(
      'letter',
      _render(
        900,
        1200,
        (120, 84, 50),
        [_Print(letter, _letter, radius: 0)],
        seed: 6,
      ),
      letter,
    ),
  );
  return scenes;
}
