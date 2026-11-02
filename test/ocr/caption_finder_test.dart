import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openscan/core/ocr/caption_finder.dart';

/// A photo's corners from its bounds, as fractions of the page.
List<Offset> _photo(double l, double t, double r, double b) => [
  Offset(l, t),
  Offset(r, t),
  Offset(r, b),
  Offset(l, b),
];

TextLine _line(
  String text,
  double l,
  double t,
  double r,
  double b, [
  int block = 0,
]) => TextLine(text, Rect.fromLTRB(l, t, r, b), block);

void main() {
  // A 3:4 page, as a phone takes it.
  const aspect = 0.75;

  test('takes the handwritten lines under the print, and only those', () {
    // The holiday photo: two lines written under it, the picture's own
    // writing (a T-shirt print) inside it.
    final caption = findCaption(
      [
        _line('Rhein Rhein', 0.62, 0.62, 0.72, 0.64),
        _line('Sommerferien 1986', 0.12, 0.82, 0.66, 0.85),
        _line('Ausflug nach Brand', 0.13, 0.87, 0.69, 0.9),
      ],
      _photo(0.13, 0.24, 0.88, 0.76),
      aspect: aspect,
    )!;

    expect(caption.top, greaterThanOrEqualTo(0.76));
    expect(caption.top, lessThan(0.82));
    expect(caption.bottom, greaterThan(0.9));
    expect(caption.left, lessThan(0.12));
    expect(caption.right, greaterThan(0.69));
  });

  test('a magazine photo: the caption set under it, not the page round it', () {
    final caption = findCaption(
      [
        _line('Volg', 0.45, 0.35, 0.52, 0.37),
        _line('33', 0.12, 0.47, 0.22, 0.52),
        _line('Öise Volg', 0.13, 0.565, 0.32, 0.585),
        _line(
          'Ein fröhliches «guete Zmorge» für Pendler',
          0.13,
          0.59,
          0.65,
          0.61,
        ),
        _line('und Dorfbewohner im Volg Däniken', 0.13, 0.615, 0.57, 0.635),
        // The next article, in the column to the left and further down.
        _line('gut:', 0.0, 0.76, 0.06, 0.78, 1),
        _line('Jogurts', 0.0, 0.79, 0.09, 0.81, 1),
        _line('FEINS VOM DORF', 0.25, 0.97, 0.55, 0.99, 2),
      ],
      _photo(0.12, 0.2, 0.78, 0.55),
      aspect: aspect,
    )!;

    expect(caption.top, greaterThanOrEqualTo(0.55));
    expect(caption.top, lessThan(0.565));
    expect(caption.bottom, greaterThan(0.635));
    expect(caption.bottom, lessThan(0.7));
    expect(caption.right, greaterThan(0.65));
  });

  test('leaves the next print\'s caption to the next print', () {
    final caption = findCaption(
      [
        _line('Grindelwald 1971', 0.1, 0.62, 0.4, 0.65),
        _line('Mürren, ohne Nebel', 0.58, 0.6, 0.92, 0.63),
      ],
      _photo(0.06, 0.2, 0.46, 0.55),
      aspect: aspect,
    )!;

    expect(caption.left, lessThan(0.1));
    expect(caption.right, greaterThan(0.4));
    expect(caption.right, lessThan(0.58));
  });

  test('takes a caption written above when there is none below', () {
    final caption = findCaption(
      [_line('Weihnachten 1958', 0.2, 0.08, 0.6, 0.11)],
      _photo(0.15, 0.15, 0.85, 0.7),
      aspect: aspect,
    )!;

    expect(caption.bottom, lessThanOrEqualTo(0.15));
    expect(caption.top, lessThan(0.08));
  });

  test('finds nothing when no writing is near the print', () {
    expect(
      findCaption(
        [
          _line('Seite 12', 0.4, 0.97, 0.6, 0.99),
          _line('Logo', 0.4, 0.4, 0.5, 0.43),
        ],
        _photo(0.1, 0.1, 0.9, 0.6),
        aspect: aspect,
      ),
      isNull,
    );
    expect(findCaption([], _photo(0.1, 0.1, 0.9, 0.6), aspect: aspect), isNull);
  });

  test('a caption under a print lying askew is not taken for its picture', () {
    // Turned a little on the page: its bounding box reaches over the
    // first line, the print itself doesn't.
    final caption = findCaption(
      [_line('Ostern 1964', 0.2, 0.66, 0.5, 0.69)],
      const [
        Offset(0.2, 0.12),
        Offset(0.84, 0.18),
        Offset(0.8, 0.7),
        Offset(0.16, 0.64),
      ],
      aspect: aspect,
    );

    expect(caption, isNotNull);
    expect(caption!.bottom, greaterThan(0.69));
  });

  test('turning fractions round and back lands where it started', () {
    const p = Offset(0.2, 0.7);
    for (int turns = 0; turns < 4; turns++) {
      final back = unturnFraction(turnFraction(p, turns), turns);
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    }
    // One turn clockwise takes the top left corner to the top right.
    expect(turnFraction(Offset.zero, 1), const Offset(1, 0));
  });
}
