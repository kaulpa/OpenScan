import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openscan/core/cv/document_detector.dart';
import 'package:openscan/core/cv/edge_detection.dart';
import 'package:openscan/core/cv/line_quads.dart';
import 'package:openscan/core/cv/models/point.dart';
import 'package:openscan/core/cv/models/quad.dart';

import 'album_scenes.dart';

/// [image] as detection sees it: scaled to [longEdge] on its long side
/// (the crop screen works at [kDetectionMaxDimension], the live scan at
/// 320) and turned grey.
({Uint8List gray, int width, int height, double scale}) _working(
  img.Image image,
  int longEdge,
) {
  final scale = longEdge / max(image.width, image.height);
  final small = img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
  final rgba = small
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  return (
    gray: rgbaToGrayscale(rgba, small.width, small.height),
    width: small.width,
    height: small.height,
    scale: scale,
  );
}

Quad? _detect(img.Image image, int longEdge, {Quad? previousQuad}) {
  final w = _working(image, longEdge);
  return detectQuadFromGrayscale(
    w.gray,
    w.width,
    w.height,
    previousQuad: previousQuad?.scaled(w.scale, w.scale),
  )?.scaled(1 / w.scale, 1 / w.scale);
}

/// Furthest any corner of [found] is from its counterpart in [truth], as a
/// share of [image]'s diagonal.
double _worstCorner(Quad found, Quad truth, img.Image image) {
  var worst = 0.0;
  for (int i = 0; i < 4; i++) {
    final a = found.points[i], b = truth.points[i];
    worst = max(worst, sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)));
  }
  return worst / sqrt(pow(image.width, 2) + pow(image.height, 2));
}

img.Image _page({int width = 900, int height = 1200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(236, 233, 224));
  return image;
}

void main() {
  final scenes = albumScenes();

  group('finds the print', () {
    for (final scene in scenes) {
      for (final longEdge in [kDetectionMaxDimension, 320]) {
        test('${scene.name}, at $longEdge px', () {
          final found = _detect(scene.image, longEdge);
          expect(found, isNotNull);
          var error = _worstCorner(found!, scene.target, scene.image);
          if (scene.alternative != null) {
            error = min(
              error,
              _worstCorner(found, scene.alternative!, scene.image),
            );
          }
          expect(
            error,
            lessThan(0.015),
            reason:
                'corners ${found.points.map((p) => '(${p.x.round()}, '
                    '${p.y.round()})').join(' ')}',
          );
        });
      }
    }
  });

  group('reports nothing', () {
    test('on an empty page with a caption', () {
      final page = _page();
      for (int i = 0; i < 12; i++) {
        img.drawLine(
          page,
          x1: 200 + 30 * i,
          y1: 620,
          x2: 210 + 30 * i,
          y2: 600,
          color: img.ColorRgb8(70, 70, 90),
          thickness: 2,
        );
      }
      expect(_detect(img.gaussianBlur(page, radius: 2), 320), isNull);
    });

    test('on graph paper, however many squares its lines make', () {
      final paper = _page();
      for (int x = 0; x < 900; x += 40) {
        img.drawLine(
          paper,
          x1: x,
          y1: 0,
          x2: x + 30,
          y2: 1199,
          color: img.ColorRgb8(160, 170, 190),
          thickness: 2,
        );
      }
      for (int y = 0; y < 1200; y += 40) {
        img.drawLine(
          paper,
          x1: 0,
          y1: y,
          x2: 899,
          y2: y - 30,
          color: img.ColorRgb8(160, 170, 190),
          thickness: 2,
        );
      }
      final soft = img.gaussianBlur(paper, radius: 1);
      expect(_detect(soft, 320), isNull);
      expect(_detect(soft, kDetectionMaxDimension), isNull);
    });

    test('for the frame itself, when it ends in a dark line', () {
      final page = _page();
      img.drawRect(
        page,
        x1: 0,
        y1: 0,
        x2: 899,
        y2: 1199,
        color: img.ColorRgb8(40, 40, 40),
      );
      expect(_detect(page, kDetectionMaxDimension), isNull);
      expect(_detect(page, 320), isNull);
    });
  });

  test('a quad borrowing the next print\'s edge loses to the print', () {
    final scene = scenes.firstWhere((s) => s.name == 'alpine');
    final w = _working(scene.image, 320);
    final edges = EdgeMap.fromBlurred(
      gaussianBlur3(w.gray, w.width, w.height),
      w.width,
      w.height,
    );
    final print = scene.target.scaled(w.scale, w.scale);
    // Its right side on the neighbour's left edge instead of its own.
    final wider = Quad(
      topLeft: print.topLeft,
      topRight: Pt(768 * w.scale, 305 * w.scale),
      bottomRight: Pt(786 * w.scale, 1079 * w.scale),
      bottomLeft: print.bottomLeft,
    );
    expect(
      assessQuad(edges, wider).score,
      lessThan(assessQuad(edges, print).score),
    );
  });

  test('refineQuad moves a rough outline onto the print\'s edges', () {
    final scene = scenes.firstWhere((s) => s.name == 'seaside');
    final w = _working(scene.image, kDetectionMaxDimension);
    final edges = EdgeMap.fromBlurred(
      gaussianBlur3(w.gray, w.width, w.height),
      w.width,
      w.height,
    );
    final truth = scene.target.scaled(w.scale, w.scale);
    Pt off(Pt p, double dx, double dy) => Pt(p.x + dx, p.y + dy);
    final rough = Quad(
      topLeft: off(truth.topLeft, 2, 2),
      topRight: off(truth.topRight, -2, 1),
      bottomRight: off(truth.bottomRight, 1, -2),
      bottomLeft: off(truth.bottomLeft, 2, -1),
    );
    final refined = refineQuad(edges, rough);
    for (int i = 0; i < 4; i++) {
      final a = refined.points[i], b = truth.points[i];
      // Rounded corners: the sides' lines meet a little outside the print.
      expect(
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)),
        lessThan(1.5),
        reason: 'corner $i',
      );
    }
  });

  test('keeps the corners in the slots the previous frame had them in', () {
    final scene = scenes.firstWhere((s) => s.name == 'pair');
    final t = scene.target;
    // The same outline, labelled starting one corner further round.
    final previous = Quad(
      topLeft: t.topRight,
      topRight: t.bottomRight,
      bottomRight: t.bottomLeft,
      bottomLeft: t.topLeft,
    );
    final found = _detect(scene.image, 320, previousQuad: previous)!;
    expect(_worstCorner(found, previous, scene.image), lessThan(0.015));
  });
}
