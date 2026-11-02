import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openscan/core/cv/models/point.dart';
import 'package:openscan/core/cv/models/quad.dart';
import 'package:openscan/view/screens/crop/crop_screen_state.dart';

import '../../cv/album_scenes.dart';

void main() {
  final scene = albumScenes().firstWhere((s) => s.name == 'seaside');
  final width = scene.image.width.toDouble();
  final height = scene.image.height.toDouble();
  final diagonal = sqrt(width * width + height * height);
  late Directory dir;
  late File shot;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('crop_refine');
    shot = File('${dir.path}/shot.jpg')
      ..writeAsBytesSync(img.encodeJpg(scene.image, quality: 92));
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  /// [quad], in the photo's pixels, nudged by [dx], [dy] and given as the
  /// live scan hands corners over: fractions of the frame.
  Quad viewfinder(Quad quad, double dx, double dy) {
    Pt at(Pt p) => Pt((p.x + dx) / width, (p.y + dy) / height);
    return Quad(
      topLeft: at(quad.topLeft),
      topRight: at(quad.topRight),
      bottomRight: at(quad.bottomRight),
      bottomLeft: at(quad.bottomLeft),
    );
  }

  Future<({bool refined, Quad quad})> refine(
    WidgetTester tester,
    Quad handedIn,
  ) async {
    final state = CropScreenState()..imageFile = shot;
    late bool refined;
    await tester.runAsync(() async {
      await state.useQuad(handedIn);
      refined = await state.refineDetectedQuad();
    });
    return (refined: refined, quad: state.detectedQuad!);
  }

  testWidgets('moves the viewfinder\'s corners onto the print in the photo', (
    tester,
  ) async {
    // A moment before the shutter the print sat a little further over.
    final result = await refine(tester, viewfinder(scene.target, 16, -12));

    expect(result.refined, isTrue);
    for (int i = 0; i < 4; i++) {
      final a = result.quad.points[i], b = scene.target.points[i];
      expect(
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)) / diagonal,
        lessThan(0.005),
        reason: 'corner $i',
      );
    }
  });

  testWidgets('keeps them when what the photo shows is somewhere else', (
    tester,
  ) async {
    // Corners nowhere near the print: whatever the viewfinder had, the
    // print found on the photo is not a sharper view of it.
    final elsewhere = Quad(
      topLeft: const Pt(0.05, 0.78),
      topRight: const Pt(0.6, 0.78),
      bottomRight: const Pt(0.6, 0.97),
      bottomLeft: const Pt(0.05, 0.97),
    );
    final result = await refine(tester, elsewhere);

    expect(result.refined, isFalse);
    expect(result.quad.topLeft.x, closeTo(0.05 * width, 0.5));
    expect(result.quad.bottomRight.y, closeTo(0.97 * height, 0.5));
  });
}
