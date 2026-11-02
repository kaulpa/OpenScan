import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openscan/core/metadata/photo_metadata.dart';
import 'package:openscan/core/theme/appTheme.dart';
import 'package:openscan/core/theme/os_tokens.dart';
import 'package:openscan/l10n/app_localizations.dart';
import 'package:openscan/view/Widgets/metadata/metadata_dialog.dart';

/// What the dialog closed with, once it has.
class _Result {
  bool closed = false;
  PhotoMetadata? value;
}

/// Opens the caption editor on [initial] in German, the way a page's
/// preview does.
Future<_Result> _open(WidgetTester tester, PhotoMetadata initial) async {
  final result = _Result();
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
            onPressed: () async {
              result.value = await editPhotoMetadata(context, initial);
              result.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('offers the date the caption mentions, and saves both', (
    tester,
  ) async {
    final result = await _open(tester, const PhotoMetadata(caption: 'Rimini'));

    expect(find.text('Beschreibung & Datum'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Rimini, Juli 1968');
    await tester.pump();
    await tester.tap(find.text('07.1968 übernehmen'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(result.closed, isTrue);
    expect(
      result.value,
      const PhotoMetadata(caption: 'Rimini, Juli 1968', date: '1968-07'),
    );
  });

  testWidgets('refuses a date it cannot read', (tester) async {
    final result = await _open(tester, PhotoMetadata.empty);

    await tester.enterText(find.byType(TextField).last, 'irgendwann');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(result.closed, isFalse);
    expect(
      find.text('Jahr, Monat.Jahr oder Tag.Monat.Jahr eingeben'),
      findsOneWidget,
    );
  });

  testWidgets('cancel leaves the caption as it was', (tester) async {
    final result = await _open(
      tester,
      const PhotoMetadata(caption: 'Oma', date: '1950'),
    );

    expect(find.text('1950'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'etwas anderes');
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(result.closed, isTrue);
    expect(result.value, isNull);
  });
}
