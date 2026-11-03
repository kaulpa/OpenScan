import 'dart:math';
import 'dart:ui';

/// Finding the caption that belongs to a photo among the lines of text the
/// recognizer finds on the page around it (`locateCaption`), so it can be
/// marked and read without the user drawing a box round it.

/// One line of text found on a page.
class TextLine {
  const TextLine(this.text, this.box, this.block);

  final String text;

  /// Where it is, as fractions of the page as it was read: turned the way
  /// it was asked to be, top left (0, 0).
  final Rect box;

  /// The paragraph it belongs to, as the recognizer grouped them.
  final int block;
}

/// [p], as fractions of a page, after the page is turned [quarterTurns]
/// clockwise.
Offset turnFraction(Offset p, int quarterTurns) {
  switch (quarterTurns % 4) {
    case 1:
      return Offset(1 - p.dy, p.dx);
    case 2:
      return Offset(1 - p.dx, 1 - p.dy);
    case 3:
      return Offset(p.dy, 1 - p.dx);
    default:
      return p;
  }
}

/// The inverse of [turnFraction].
Offset unturnFraction(Offset p, int quarterTurns) =>
    turnFraction(p, (4 - quarterTurns % 4) % 4);

/// How far from the photo, as a share of its height (below or above it) or
/// width (beside it), the first line of its caption may start.
const double _kReach = 0.35;

/// How much nearer than a line below the photo one above or beside it has
/// to be to be taken instead: albums write captions underneath.
const double _kAbove = 1.4;
const double _kBeside = 1.6;

/// The part of the page that captions the photo with corners [photo]: the
/// line of text nearest it outside it — below it by preference, otherwise
/// above or beside it — and the lines that carry on from that one. Null
/// when no line is near enough.
///
/// Lines whose middle is inside the photo are writing in the picture and
/// left alone, as is anything further off: the next photo's caption, a
/// page number. Everything is in fractions of the page as read; [aspect]
/// is its width over its height.
Rect? findCaption(
  List<TextLine> lines,
  List<Offset> photo, {
  required double aspect,
}) {
  // Worked out in units of the page's height, so across and down compare.
  Offset unit(Offset p) => Offset(p.dx * aspect, p.dy);
  Rect unitRect(Rect r) =>
      Rect.fromLTRB(r.left * aspect, r.top, r.right * aspect, r.bottom);
  final corners = [for (final p in photo) unit(p)];
  final bounds = _boundsOf(corners);

  final outside = <Rect>[
    for (final line in lines)
      if (line.text.trim().isNotEmpty &&
          !_inside(unitRect(line.box).center, corners))
        unitRect(line.box),
  ];
  if (outside.isEmpty) return null;

  // The nearest line, weighed by which side of the photo it is on.
  final across = (
    from: bounds.left - _kReach * bounds.width,
    to: bounds.right + _kReach * bounds.width,
  );
  final down = (from: bounds.top, to: bounds.bottom);
  ({Rect line, _Side side})? seed;
  var seedCost = double.infinity;
  for (final r in outside) {
    final slack = 0.3 * r.height;
    final c = r.center;
    // The photo's own edge where the line is, not its bounds: a print
    // lying askew has page inside those.
    final column =
        _span(corners, c.dx, vertical: true) ??
        (from: bounds.top, to: bounds.bottom);
    final row =
        _span(corners, c.dy, vertical: false) ??
        (from: bounds.left, to: bounds.right);
    final candidates = <(_Side, double, double)>[
      if (c.dx >= across.from && c.dx <= across.to) ...[
        if (r.top >= column.to - slack)
          (_Side.below, r.top - column.to, bounds.height),
        if (r.bottom <= column.from + slack)
          (_Side.above, column.from - r.bottom, bounds.height),
      ],
      if (c.dy >= down.from && c.dy <= down.to) ...[
        if (r.left >= row.to - slack)
          (_Side.right, r.left - row.to, bounds.width),
        if (r.right <= row.from + slack)
          (_Side.left, row.from - r.right, bounds.width),
      ],
    ];
    for (final (side, gap, size) in candidates) {
      final reach = gap / max(size, 1e-6);
      if (reach > _kReach) continue;
      final cost =
          max(reach, 0.0) *
          switch (side) {
            _Side.below => 1.0,
            _Side.above => _kAbove,
            _Side.left || _Side.right => _kBeside,
          };
      if (cost < seedCost) {
        seedCost = cost;
        seed = (line: r, side: side);
      }
    }
  }
  if (seed == null) return null;

  // The lines that carry on from it: close underneath or above, and
  // overlapping it across.
  var caption = seed.line;
  final taken = {seed.line};
  var grew = true;
  while (grew) {
    grew = false;
    for (final r in outside) {
      if (taken.contains(r)) continue;
      final lineHeight = min(r.height, seed.line.height);
      final gapDown = max(
        r.top - caption.bottom,
        caption.top - r.bottom,
      ).clamp(0.0, 1.0);
      final overlapAcross =
          min(r.right, caption.right + 2 * lineHeight) -
          max(r.left, caption.left - 2 * lineHeight);
      if (gapDown <= 1.2 * lineHeight && overlapAcross > 0) {
        caption = caption.expandToInclude(r);
        taken.add(r);
        grew = true;
      }
    }
  }

  // A little room round the writing for the recognizer, but not past the
  // photo's edge where the caption starts.
  final pad = 0.4 * seed.line.height;
  var box = caption.inflate(pad);
  final mid = seed.line.center;
  final column =
      _span(corners, mid.dx, vertical: true) ??
      (from: bounds.top, to: bounds.bottom);
  final row =
      _span(corners, mid.dy, vertical: false) ??
      (from: bounds.left, to: bounds.right);
  box = switch (seed.side) {
    _Side.below => Rect.fromLTRB(
      box.left,
      max(box.top, column.to),
      box.right,
      box.bottom,
    ),
    _Side.above => Rect.fromLTRB(
      box.left,
      box.top,
      box.right,
      min(box.bottom, column.from),
    ),
    _Side.right => Rect.fromLTRB(
      max(box.left, row.to),
      box.top,
      box.right,
      box.bottom,
    ),
    _Side.left => Rect.fromLTRB(
      box.left,
      box.top,
      min(box.right, row.from),
      box.bottom,
    ),
  };
  box = Rect.fromLTRB(
    max(box.left, 0),
    max(box.top, 0),
    min(box.right, aspect),
    min(box.bottom, 1),
  );
  if (box.width <= 0 || box.height <= 0) return null;
  return Rect.fromLTRB(
    box.left / aspect,
    box.top,
    box.right / aspect,
    box.bottom,
  );
}

enum _Side { below, above, left, right }

Rect _boundsOf(List<Offset> points) {
  var r = Rect.fromPoints(points.first, points.first);
  for (final p in points.skip(1)) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r;
}

/// Where the line x = [at] ([vertical]) or y = [at] crosses into and out
/// of the convex polygon [corners]: the smallest and largest y, or x, it
/// covers there. Null when it misses the polygon.
({double from, double to})? _span(
  List<Offset> corners,
  double at, {
  required bool vertical,
}) {
  double? lo, hi;
  for (int i = 0; i < corners.length; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    final (a0, a1) = vertical ? (a.dx, a.dy) : (a.dy, a.dx);
    final (b0, b1) = vertical ? (b.dx, b.dy) : (b.dy, b.dx);
    if ((a0 - at) * (b0 - at) > 0 || a0 == b0) continue;
    final v = a1 + (b1 - a1) * (at - a0) / (b0 - a0);
    lo = lo == null ? v : min(lo, v);
    hi = hi == null ? v : max(hi, v);
  }
  return lo == null ? null : (from: lo, to: hi!);
}

/// Whether [p] is inside the polygon [corners] (even-odd rule).
bool _inside(Offset p, List<Offset> corners) {
  var inside = false;
  for (int i = 0, j = corners.length - 1; i < corners.length; j = i++) {
    final a = corners[i], b = corners[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
