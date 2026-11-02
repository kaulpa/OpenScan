import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:openscan/core/metadata/photo_metadata.dart';

/// Names this app in the files it writes (EXIF Software, XMP CreatorTool).
const String kMetadataSoftware = 'OpenScan Foto';

/// Longest caption written into a file. A JPEG metadata segment holds at
/// most 64KB and the caption is written there three times over, in UTF-8
/// and twice in UTF-16; no album caption comes anywhere near this.
const int _kMaxCaptionLength = 2000;

const List<int> _exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
final List<int> _xmpHeader = ascii.encode('http://ns.adobe.com/xap/1.0/\x00');
final List<int> _xmpExtensionHeader = ascii.encode(
  'http://ns.adobe.com/xmp/extension/\x00',
);

/// Returns [jpeg] with [metadata] written into it, without touching a
/// single pixel: only the metadata segments are replaced, the compressed
/// image data is copied through byte for byte.
///
/// The caption goes everywhere a photo library might look for it — EXIF
/// ImageDescription (Google Photos, most viewers), EXIF UserComment, the
/// Windows XPComment tag (Explorer's "Comments"), and XMP dc:description
/// (digiKam, Lightroom, Immich). The date goes to EXIF DateTimeOriginal,
/// which is what libraries sort by, and to XMP photoshop:DateCreated,
/// which can say "only the year is known" where EXIF can't.
///
/// Whatever EXIF and XMP the file carried before is dropped: for a scanned
/// print it describes the scan — the phone, the moment, the place — not
/// the photo. The one thing kept is the orientation, which says how the
/// stored pixels are meant to be shown.
///
/// Returns [jpeg] unchanged when [metadata] is empty, and throws a
/// [FormatException] when it isn't a JPEG this can parse.
Uint8List writeJpegMetadata(
  Uint8List jpeg,
  PhotoMetadata metadata, {
  String software = kMetadataSoftware,
}) {
  if (metadata.isEmpty) return jpeg;
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    throw const FormatException('Not a JPEG');
  }

  int? orientation;
  try {
    orientation = img.decodeJpgExif(jpeg)?.imageIfd.orientation;
  } catch (_) {
    // Unreadable EXIF is about to be replaced anyway.
  }

  Uint8List? jfif;
  int? width, height;
  final kept = BytesBuilder(copy: false);
  Uint8List? imageData;
  int pos = 2;
  while (pos < jpeg.length) {
    if (jpeg[pos] != 0xFF) {
      throw FormatException('Expected a marker', jpeg, pos);
    }
    // Any number of 0xFF fill bytes may come before a marker.
    while (pos < jpeg.length && jpeg[pos] == 0xFF) {
      pos++;
    }
    if (pos >= jpeg.length) throw const FormatException('Truncated JPEG');
    final marker = jpeg[pos++];

    // Start of scan: everything from here on is image data.
    if (marker == 0xDA || marker == 0xD9) {
      imageData = Uint8List.sublistView(jpeg, pos - 2);
      break;
    }
    // Markers that stand alone, without a length.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      kept.add([0xFF, marker]);
      continue;
    }
    if (pos + 2 > jpeg.length) throw const FormatException('Truncated JPEG');
    final length = (jpeg[pos] << 8) | jpeg[pos + 1];
    final end = pos + length;
    if (length < 2 || end > jpeg.length) {
      throw FormatException('Bad segment length', jpeg, pos);
    }
    final payload = Uint8List.sublistView(jpeg, pos + 2, end);
    final segment = Uint8List.sublistView(jpeg, pos, end);
    pos = end;

    // A start-of-frame says how big the image is, which EXIF repeats.
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC &&
        payload.length >= 5) {
      height = (payload[1] << 8) | payload[2];
      width = (payload[3] << 8) | payload[4];
    }
    if (marker == 0xE1 &&
        (_startsWith(payload, _exifHeader) ||
            _startsWith(payload, _xmpHeader) ||
            _startsWith(payload, _xmpExtensionHeader))) {
      continue;
    }
    if (marker == 0xE0 && jfif == null && kept.isEmpty) {
      jfif = Uint8List.fromList([0xFF, marker, ...segment]);
      continue;
    }
    kept
      ..add([0xFF, marker])
      ..add(segment);
  }
  if (imageData == null) throw const FormatException('No image data');

  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  // JFIF has to stay first if it was there; EXIF follows it, which every
  // reader accepts even though the EXIF spec would rather be first.
  if (jfif != null) out.add(jfif);
  out
    ..add(
      _segment(0xE1, [
        ..._exifHeader,
        ..._exifTiff(metadata, software, orientation ?? 1, width, height),
      ]),
    )
    ..add(
      _segment(0xE1, [
        ..._xmpHeader,
        ...utf8.encode(xmpPacket(metadata, software: software)),
      ]),
    )
    ..add(kept.takeBytes())
    ..add(imageData);
  return out.takeBytes();
}

/// The pixel size a JPEG's start-of-frame declares, read from the header
/// alone, or null when [jpeg] isn't a JPEG this can parse.
({int width, int height})? jpegDimensions(Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return null;
  int pos = 2;
  while (pos + 4 <= jpeg.length) {
    if (jpeg[pos] != 0xFF) return null;
    final marker = jpeg[pos + 1];
    if (marker == 0xFF) {
      pos++;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) return null;
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      pos += 2;
      continue;
    }
    final length = (jpeg[pos + 2] << 8) | jpeg[pos + 3];
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC &&
        pos + 9 <= jpeg.length) {
      return (
        width: (jpeg[pos + 7] << 8) | jpeg[pos + 8],
        height: (jpeg[pos + 5] << 8) | jpeg[pos + 6],
      );
    }
    pos += 2 + length;
  }
  return null;
}

/// The XMP packet [writeJpegMetadata] embeds.
String xmpPacket(
  PhotoMetadata metadata, {
  String software = kMetadataSoftware,
}) {
  final caption = _clip(metadata.caption);
  final date = metadata.date.trim();
  final b = StringBuffer()
    ..write('<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>\n')
    ..write('<x:xmpmeta xmlns:x="adobe:ns:meta/">\n')
    ..write(
      ' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n',
    )
    ..write('  <rdf:Description rdf:about=""\n')
    ..write('    xmlns:dc="http://purl.org/dc/elements/1.1/"\n')
    ..write('    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"\n')
    ..write('    xmlns:xmp="http://ns.adobe.com/xap/1.0/"\n')
    ..write('    xmp:CreatorTool="${_xmlEscape(software)}"');
  if (exifDateTime(date) != null) {
    b.write('\n    photoshop:DateCreated="$date"');
  }
  b.write('>\n');
  if (caption.isNotEmpty) {
    b
      ..write('   <dc:description>\n')
      ..write('    <rdf:Alt>\n')
      ..write(
        '     <rdf:li xml:lang="x-default">${_xmlEscape(caption)}</rdf:li>\n',
      )
      ..write('    </rdf:Alt>\n')
      ..write('   </dc:description>\n');
  }
  b
    ..write('  </rdf:Description>\n')
    ..write(' </rdf:RDF>\n')
    ..write('</x:xmpmeta>\n')
    ..write('<?xpacket end="w"?>');
  return b.toString();
}

// <=============================== EXIF ===============================>

const int _typeByte = 1;
const int _typeAscii = 2;
const int _typeShort = 3;
const int _typeLong = 4;
const int _typeRational = 5;
const int _typeUndefined = 7;

/// One IFD entry with its value already encoded, big-endian.
class _Entry {
  final int tag;
  final int type;
  final List<int> data;

  _Entry(this.tag, this.type, this.data);

  _Entry.ascii(this.tag, String value)
    : type = _typeAscii,
      data = [...utf8.encode(value), 0];

  _Entry.short(this.tag, int value) : type = _typeShort, data = _u16(value);

  _Entry.long(this.tag, int value) : type = _typeLong, data = _u32(value);

  _Entry.rational(this.tag, int numerator, int denominator)
    : type = _typeRational,
      data = [..._u32(numerator), ..._u32(denominator)];

  int get count {
    switch (type) {
      case _typeShort:
        return data.length ~/ 2;
      case _typeLong:
        return data.length ~/ 4;
      case _typeRational:
        return data.length ~/ 8;
      default:
        return data.length;
    }
  }
}

/// A big-endian TIFF structure: IFD0 for the description, orientation and
/// software, pointing at an Exif IFD for the date and the user comment.
///
/// Alongside what this app has to say, it carries the handful of tags
/// the EXIF spec requires in every JPEG — resolution, colour space,
/// dimensions — so strict readers take the block as well-formed.
///
/// Big-endian on purpose: UserComment's UNICODE text follows the byte
/// order of the file, and most readers assume big-endian there whatever
/// the file says. The Windows XP tags are UTF-16LE in any byte order.
List<int> _exifTiff(
  PhotoMetadata metadata,
  String software,
  int orientation,
  int? width,
  int? height,
) {
  final caption = _clip(metadata.caption);
  final dateTime = exifDateTime(metadata.date.trim());

  final ifd0 = <_Entry>[
    if (caption.isNotEmpty) _Entry.ascii(0x010E, caption),
    _Entry.short(0x0112, orientation),
    _Entry.rational(0x011A, 72, 1),
    _Entry.rational(0x011B, 72, 1),
    _Entry.short(0x0128, 2),
    _Entry.ascii(0x0131, software),
    _Entry.short(0x0213, 1),
    if (caption.isNotEmpty)
      _Entry(0x9C9C, _typeByte, [..._utf16le(caption), 0, 0]),
  ];
  final exif = <_Entry>[
    _Entry(0x9000, _typeUndefined, ascii.encode('0232')),
    if (dateTime != null) _Entry.ascii(0x9003, dateTime),
    _Entry(0x9101, _typeUndefined, const [1, 2, 3, 0]),
    if (caption.isNotEmpty)
      _Entry(0x9286, _typeUndefined, [
        ...ascii.encode('UNICODE\x00'),
        ..._utf16be(caption),
      ]),
    _Entry(0xA000, _typeUndefined, ascii.encode('0100')),
    _Entry.short(0xA001, 1),
    if (width != null) _Entry.long(0xA002, width),
    if (height != null) _Entry.long(0xA003, height),
  ];

  // The Exif IFD sits right after IFD0 and the values IFD0 stores out of
  // line; the pointer to it is the one entry added once that is known.
  final exifOffset = 8 + _ifdSize(ifd0.length + 1) + _outOfLineSize(ifd0);
  ifd0.add(_Entry.long(0x8769, exifOffset));

  final out = <int>[0x4D, 0x4D, 0x00, 0x2A, ..._u32(8)];
  _writeIfd(out, ifd0);
  _writeIfd(out, exif);
  return out;
}

int _ifdSize(int entries) => 2 + 12 * entries + 4;

int _outOfLineSize(List<_Entry> entries) => entries.fold(
  0,
  (sum, e) =>
      e.data.length > 4 ? sum + e.data.length + (e.data.length & 1) : sum,
);

/// Appends one IFD, followed by the values too long to sit in their
/// entries, to [out]. Offsets count from the start of [out], which is the
/// TIFF header.
void _writeIfd(List<int> out, List<_Entry> entries) {
  entries.sort((a, b) => a.tag.compareTo(b.tag));
  final dataStart = out.length + _ifdSize(entries.length);
  final data = <int>[];
  out.addAll(_u16(entries.length));
  for (final e in entries) {
    out
      ..addAll(_u16(e.tag))
      ..addAll(_u16(e.type))
      ..addAll(_u32(e.count));
    if (e.data.length <= 4) {
      out
        ..addAll(e.data)
        ..addAll(List.filled(4 - e.data.length, 0));
    } else {
      out.addAll(_u32(dataStart + data.length));
      data.addAll(e.data);
      // Values start on a word boundary.
      if (data.length.isOdd) data.add(0);
    }
  }
  out
    ..addAll(_u32(0))
    ..addAll(data);
}

// <============================== Helpers ==============================>

Uint8List _segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  if (length > 0xFFFF) {
    throw ArgumentError('Metadata does not fit in a JPEG segment');
  }
  return Uint8List.fromList([
    0xFF,
    marker,
    length >> 8,
    length & 0xFF,
    ...payload,
  ]);
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (int i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String _clip(String caption) {
  // A NUL would end the EXIF string early.
  final text = caption.replaceAll('\u0000', '').trim();
  if (text.length <= _kMaxCaptionLength) return text;
  var end = _kMaxCaptionLength;
  // Not between the two halves of a surrogate pair.
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return text.substring(0, end);
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> _utf16le(String s) => [
  for (final unit in s.codeUnits) ...[unit & 0xFF, unit >> 8],
];

List<int> _utf16be(String s) => [
  for (final unit in s.codeUnits) ...[unit >> 8, unit & 0xFF],
];
