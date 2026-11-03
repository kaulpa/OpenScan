import 'package:flutter_test/flutter_test.dart';
import 'package:openscan/core/metadata/photo_metadata.dart';

void main() {
  group('findPhotoDate', () {
    test('finds a bare year', () {
      expect(findPhotoDate('Rimini, Sommer 1968'), '1968');
      expect(findPhotoDate('Weihnachten 1954 bei Oma'), '1954');
    });

    test('finds a month and year, German and English', () {
      expect(findPhotoDate('Juli 1968'), '1968-07');
      expect(findPhotoDate('im Dez. 1971 in Davos'), '1971-12');
      expect(findPhotoDate('März 1960'), '1960-03');
      expect(findPhotoDate('June 1975, Cornwall'), '1975-06');
      expect(findPhotoDate('7.1968'), '1968-07');
      expect(findPhotoDate('07/1968'), '1968-07');
    });

    test('finds a full date in the usual spellings', () {
      expect(findPhotoDate('12.7.1968'), '1968-07-12');
      expect(findPhotoDate('12. 7. 1968'), '1968-07-12');
      expect(findPhotoDate('Hochzeit 03.05.1952'), '1952-05-03');
      expect(findPhotoDate('12. Juli 1968'), '1968-07-12');
      expect(findPhotoDate('1968-07-12'), '1968-07-12');
    });

    test('prefers the most precise date mentioned', () {
      expect(findPhotoDate('Juli 1968, Rimini – 12.7.1968'), '1968-07-12');
      expect(findPhotoDate('1968, Juli 1968'), '1968-07');
    });

    test('ignores numbers that are not plausible photo dates', () {
      expect(findPhotoDate('Hausnummer 12'), isNull);
      expect(findPhotoDate('Zimmer 1204'), isNull);
      expect(findPhotoDate('Postleitzahl 8050'), isNull);
      expect(findPhotoDate('31.02.1968'), '1968');
      expect(findPhotoDate('Wanderung'), isNull);
    });

    test('reads two-digit years the way albums write them', () {
      expect(findPhotoDate('Bachtelabfahrt Febr. 87'), '1987-02');
      expect(findPhotoDate('Juli 68'), '1968-07');
      expect(findPhotoDate('12.7.68'), '1968-07-12');
      expect(findPhotoDate('Kindergarten 86-87'), '1986');
      expect(findPhotoDate('86/87'), '1986');
      expect(findPhotoDate("Sommer '72"), '1972');
      expect(findPhotoDate('1.1.05'), '2005-01-01');
      // A four-digit year anywhere wins.
      expect(findPhotoDate('Febr. 87, eigentlich 1988'), '1988');
    });

    test('does not take any pair of numbers for a two-digit year', () {
      expect(findPhotoDate('Zimmer 12-14'), isNull);
      expect(findPhotoDate('Geburtstag 12.07'), isNull);
      expect(findPhotoDate('Gruppe 3 von 12'), isNull);
      expect(findPhotoDate('Wagen 34'), isNull);
    });

    test('does not take a month name out of a longer word', () {
      expect(findPhotoDate('Familie Maier 1968'), '1968');
    });
  });

  group('parsePhotoDateInput', () {
    test('blank means no date, garbage means invalid', () {
      expect(parsePhotoDateInput('  '), '');
      expect(parsePhotoDateInput('irgendwann'), isNull);
      expect(parsePhotoDateInput('1968'), '1968');
      expect(parsePhotoDateInput('12.07.1968'), '1968-07-12');
    });
  });

  test('formatPhotoDate writes the date day first', () {
    expect(formatPhotoDate('1968'), '1968');
    expect(formatPhotoDate('1968-07'), '07.1968');
    expect(formatPhotoDate('1968-07-12'), '12.07.1968');
  });

  test('exifDateTime fills unknown parts with the first, at noon', () {
    expect(exifDateTime('1968'), '1968:01:01 12:00:00');
    expect(exifDateTime('1968-07'), '1968:07:01 12:00:00');
    expect(exifDateTime('1968-07-12'), '1968:07:12 12:00:00');
    expect(exifDateTime(''), isNull);
    expect(exifDateTime('Juli'), isNull);
  });

  group('withRecognizedText', () {
    test('appends below the caption and picks up a date', () {
      const start = PhotoMetadata();
      final first = start.withRecognizedText('  Rimini  ');
      expect(first, const PhotoMetadata(caption: 'Rimini'));
      final second = first.withRecognizedText('Sommer 1968');
      expect(second.caption, 'Rimini\nSommer 1968');
      expect(second.date, '1968');
    });

    test('never replaces a date that is already set', () {
      const typed = PhotoMetadata(date: '1970-05');
      expect(typed.withRecognizedText('Ostern 1969').date, '1970-05');
    });

    test('ignores empty recognition results', () {
      const meta = PhotoMetadata(caption: 'Rimini');
      expect(meta.withRecognizedText('   '), same(meta));
    });
  });
}
