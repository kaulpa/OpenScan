import 'dart:convert';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openscan/core/metadata/jpeg_metadata.dart';
import 'package:openscan/core/metadata/photo_metadata.dart';

Uint8List _jpeg({int? orientation}) {
  final image = img.Image(width: 40, height: 24);
  img.fill(image, color: img.ColorRgb8(200, 120, 40));
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(image, quality: 90);
}

/// Offset of the start-of-scan marker: everything from there on is the
/// compressed image.
int _sosOffset(Uint8List jpeg) {
  int pos = 2;
  while (true) {
    final marker = jpeg[pos + 1];
    if (marker == 0xDA) return pos;
    pos += 2 + ((jpeg[pos + 2] << 8) | jpeg[pos + 3]);
  }
}

/// The APP1 payloads of [jpeg], in order.
List<Uint8List> _app1(Uint8List jpeg) {
  final out = <Uint8List>[];
  int pos = 2;
  while (jpeg[pos + 1] != 0xDA) {
    final length = (jpeg[pos + 2] << 8) | jpeg[pos + 3];
    if (jpeg[pos + 1] == 0xE1) {
      out.add(Uint8List.sublistView(jpeg, pos + 4, pos + 2 + length));
    }
    pos += 2 + length;
  }
  return out;
}

void main() {
  const meta = PhotoMetadata(
    caption: 'Rimini, Sommer 1968 <Strand> & Meer',
    date: '1968-07',
  );

  test('leaves the file alone when there is nothing to write', () {
    final jpeg = _jpeg();
    expect(writeJpegMetadata(jpeg, PhotoMetadata.empty), same(jpeg));
  });

  test('copies the compressed image through byte for byte', () {
    final jpeg = _jpeg();
    final out = writeJpegMetadata(jpeg, meta);
    final before = jpeg.sublist(_sosOffset(jpeg));
    final after = out.sublist(_sosOffset(out));
    expect(after, before);

    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, 40);
    expect(decoded.height, 24);
  });

  test('writes caption and date where EXIF readers find them', () async {
    final out = writeJpegMetadata(_jpeg(), meta);
    final tags = await readExifFromBytes(out);
    expect(tags['Image ImageDescription']?.printable, meta.caption);
    expect(tags['Image Software']?.printable, kMetadataSoftware);
    expect(tags['EXIF DateTimeOriginal']?.printable, '1968:07:01 12:00:00');
    expect(tags['Image Orientation']?.values.firstAsInt(), 1);

    // A second, independent reader agrees.
    final exif = img.decodeJpgExif(out)!;
    expect(exif.imageIfd[0x010E].toString(), meta.caption);
    expect(exif.exifIfd[0x9003].toString(), '1968:07:01 12:00:00');
  });

  test('writes umlauts as UTF-8, and UTF-16 for UserComment and Windows', () {
    const umlauts = PhotoMetadata(caption: 'Grossmutter Käthi in Zürich');
    final out = writeJpegMetadata(_jpeg(), umlauts);
    final exif = _app1(out).first;
    String hex(List<int> b) =>
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final asHex = hex(exif);
    expect(asHex, contains(hex(utf8.encode(umlauts.caption))));
    expect(
      asHex,
      contains(
        hex([
          ...ascii.encode('UNICODE\x00'),
          for (final u in umlauts.caption.codeUnits) ...[u >> 8, u & 0xFF],
        ]),
      ),
    );
    expect(
      asHex,
      contains(
        hex([
          for (final u in umlauts.caption.codeUnits) ...[u & 0xFF, u >> 8],
        ]),
      ),
    );
  });

  test('embeds an escaped XMP packet with a partial date', () {
    final out = writeJpegMetadata(_jpeg(), meta);
    final xmp = _app1(out)
        .map((p) => utf8.decode(p, allowMalformed: true))
        .firstWhere((s) => s.startsWith('http://ns.adobe.com/xap/1.0/'));
    expect(xmp, contains('photoshop:DateCreated="1968-07"'));
    expect(
      xmp,
      contains(
        '<rdf:li xml:lang="x-default">'
        'Rimini, Sommer 1968 &lt;Strand&gt; &amp; Meer</rdf:li>',
      ),
    );
  });

  test('replaces earlier metadata instead of stacking it', () {
    final once = writeJpegMetadata(_jpeg(), meta);
    final twice = writeJpegMetadata(
      once,
      const PhotoMetadata(caption: 'Neu', date: '1970'),
    );
    expect(_app1(twice), hasLength(2));
    final exif = img.decodeJpgExif(twice)!;
    expect(exif.imageIfd[0x010E].toString(), 'Neu');
    expect(exif.exifIfd[0x9003].toString(), '1970:01:01 12:00:00');
  });

  test('keeps the orientation the file had', () {
    final out = writeJpegMetadata(_jpeg(orientation: 6), meta);
    expect(img.decodeJpgExif(out)!.imageIfd.orientation, 6);
  });

  test('a date alone is enough, and leaves the description out', () async {
    final out = writeJpegMetadata(
      _jpeg(),
      const PhotoMetadata(date: '1955-12-24'),
    );
    final tags = await readExifFromBytes(out);
    expect(tags['EXIF DateTimeOriginal']?.printable, '1955:12:24 12:00:00');
    expect(tags.containsKey('Image ImageDescription'), isFalse);
  });

  test('rejects what is not a JPEG', () {
    expect(
      () => writeJpegMetadata(Uint8List.fromList([1, 2, 3, 4]), meta),
      throwsFormatException,
    );
  });
}
