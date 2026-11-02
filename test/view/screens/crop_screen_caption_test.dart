import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openscan/core/cv/models/point.dart';
import 'package:openscan/core/cv/models/quad.dart';
import 'package:openscan/core/metadata/photo_metadata.dart';
import 'package:openscan/core/theme/appTheme.dart';
import 'package:openscan/core/theme/os_tokens.dart';
import 'package:openscan/l10n/app_localizations.dart';
import 'package:openscan/view/screens/crop/crop_screen.dart';

/// Pumps with real time passing in between, until [done] — the crop
/// screen decodes its page and detects edges for real, which fake time
/// alone never finishes.
Future<void> _settleUntil(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'timed out waiting for the crop screen');
}

/// Corners handed in, as the live scan does, so the screen skips edge
/// detection: that runs on behind the page with a timeout of its own, and
/// a test that ends before it has settled leaves the timer pending.
const _corners = Quad(
  topLeft: Pt(0.1, 0.1),
  topRight: Pt(0.9, 0.1),
  bottomRight: Pt(0.9, 0.9),
  bottomLeft: Pt(0.1, 0.9),
);

bool _nextEnabled(WidgetTester tester) => tester
    .widgetList<TextButton>(find.widgetWithText(TextButton, 'Weiter'))
    .any((b) => b.onPressed != null);

void main() {
  late Directory dir;
  late File page;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('crop_caption');
    final image = img.Image(width: 600, height: 900);
    img.fill(image, color: img.ColorRgb8(245, 245, 240));
    page = File('${dir.path}/page.jpg')
      ..writeAsBytesSync(img.encodeJpg(image, quality: 90));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(
    WidgetTester tester,
    void Function(CropOutcome?) onDone, {
    PhotoMetadata metadata = PhotoMetadata.empty,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(OSAccents.ember),
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => onDone(
                await imageCropper(
                  context,
                  page,
                  initialQuad: _corners,
                  metadata: metadata,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settleUntil(tester, () => _nextEnabled(tester));
  }

  testWidgets('opens with four actions and an empty caption line', (
    tester,
  ) async {
    await open(tester, (_) {});

    for (final label in ['Automatisch', 'Kein Zuschnitt', 'Drehen', 'Text']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('Noch keine Beschreibung'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text mode turns a drag into a marked region, and says when it '
      'cannot be read', (tester) async {
    await open(tester, (_) {});

    await tester.tap(find.text('Text'));
    await tester.pump();
    expect(find.text('Beschriftung markieren'), findsOneWidget);
    expect(find.textContaining('Ziehe einen Rahmen'), findsOneWidget);

    final box = tester.getRect(find.byType(Image));
    await tester.dragFrom(box.center, const Offset(120, 60));
    await tester.pump();
    // Recognition needs the phone; here it reports itself unavailable,
    // and the box goes again.
    await _settleUntil(
      tester,
      () => find
          .textContaining('Texterkennung ist auf diesem Gerät')
          .evaluate()
          .isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hands back the caption the page arrived with', (tester) async {
    CropOutcome? outcome;
    var done = false;
    await open(tester, (o) {
      outcome = o;
      done = true;
    }, metadata: const PhotoMetadata(caption: 'Oma in Bern', date: '1952'));

    expect(find.text('1952 · Oma in Bern'), findsOneWidget);
    await tester.tap(find.text('Weiter'));
    await _settleUntil(tester, () => done);

    expect(outcome, isNotNull);
    expect(
      outcome!.metadata,
      const PhotoMetadata(caption: 'Oma in Bern', date: '1952'),
    );
    expect(outcome!.file.existsSync(), isTrue);
  });
}
