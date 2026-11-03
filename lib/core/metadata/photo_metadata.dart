/// What a digitised photo says about itself beyond its pixels: the caption
/// written beside it in the album, and when it was taken.
///
/// [date] is a partial ISO 8601 date — `1968`, `1968-07` or `1968-07-12` —
/// because an album rarely knows more than the year, and inventing a day
/// it doesn't know would put the photo in the wrong place on a timeline
/// that sorts by it. Both fields are empty strings, never null, when
/// unknown, so a page record can store them as they are.
class PhotoMetadata {
  final String caption;
  final String date;

  const PhotoMetadata({this.caption = '', this.date = ''});

  static const empty = PhotoMetadata();

  bool get isEmpty => caption.trim().isEmpty && date.trim().isEmpty;

  PhotoMetadata copyWith({String? caption, String? date}) =>
      PhotoMetadata(caption: caption ?? this.caption, date: date ?? this.date);

  /// Adds text read from one more marked region below what is already
  /// there, and takes a date from it when none is known yet — the date is
  /// usually part of the caption ("Rimini, Sommer 1968"), and a date the
  /// user typed themselves is never overwritten by a guess.
  PhotoMetadata withRecognizedText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return this;
    final current = caption.trim();
    return PhotoMetadata(
      caption: current.isEmpty ? trimmed : '$current\n$trimmed',
      date: date.isNotEmpty ? date : (findPhotoDate(trimmed) ?? ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoMetadata && other.caption == caption && other.date == date;

  @override
  int get hashCode => Object.hash(caption, date);

  @override
  String toString() => 'PhotoMetadata($caption, $date)';
}

/// The earliest year a photo is assumed to be from. Anything before is
/// read as some other number — a house number, a count — not a date.
const int _kEarliestYear = 1826;

const Map<String, int> _kMonths = {
  'januar': 1,
  'jan': 1,
  'jänner': 1,
  'january': 1,
  'februar': 2,
  'febr': 2,
  'feb': 2,
  'february': 2,
  'märz': 3,
  'maerz': 3,
  'mär': 3,
  'mar': 3,
  'march': 3,
  'april': 4,
  'apr': 4,
  'mai': 5,
  'may': 5,
  'juni': 6,
  'jun': 6,
  'june': 6,
  'juli': 7,
  'jul': 7,
  'july': 7,
  'august': 8,
  'aug': 8,
  'september': 9,
  'sept': 9,
  'sep': 9,
  'oktober': 10,
  'okt': 10,
  'october': 10,
  'oct': 10,
  'november': 11,
  'nov': 11,
  'dezember': 12,
  'dez': 12,
  'december': 12,
  'dec': 12,
};

String _two(int n) => n.toString().padLeft(2, '0');

bool _plausibleYear(int year) =>
    year >= _kEarliestYear && year <= DateTime.now().year;

bool _validDay(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return false;
  return day <= DateTime(year, month + 1, 0).day;
}

/// The most precise date mentioned in [text], as a partial ISO date
/// (`1968`, `1968-07`, `1968-07-12`), or null when there is none.
///
/// Full dates win over a month and year, which win over a bare year, so
/// "Juli 1968, Rimini – 12.7.1968" yields `1968-07-12`.
///
/// Only when there is no four-digit year are two-digit ones read, the way
/// albums write them: `12.7.68`, `Febr. 87`, `'72`, and a school year,
/// `86-87` or `86/87`, as its first year. They are taken as the most
/// recent year they can be: `05` is 2005, `87` 1987. A pair of numbers
/// that isn't a school year (`12-14`), or a day and month with no year
/// (`12.07`), is no date.
String? findPhotoDate(String text) {
  final lower = text.toLowerCase();

  // 12.7.1968, 12. 7. 1968, 12/07/1968, 12-07-1968
  for (final m in RegExp(
    r'(?<!\d)(\d{1,2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{4})(?!\d)',
  ).allMatches(lower)) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    if (_plausibleYear(year) && _validDay(year, month, day)) {
      return '$year-${_two(month)}-${_two(day)}';
    }
  }

  // 1968-07-12
  for (final m in RegExp(
    r'(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)',
  ).allMatches(lower)) {
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (_plausibleYear(year) && _validDay(year, month, day)) {
      return '$year-${_two(month)}-${_two(day)}';
    }
  }

  // 12. Juli 1968
  for (final m in RegExp(
    r'(?<!\d)(\d{1,2})\.?\s*([a-zäöü]+)\.?\s*(\d{4})(?!\d)',
  ).allMatches(lower)) {
    final month = _kMonths[m.group(2)!];
    final day = int.parse(m.group(1)!);
    final year = int.parse(m.group(3)!);
    if (month != null && _plausibleYear(year) && _validDay(year, month, day)) {
      return '$year-${_two(month)}-${_two(day)}';
    }
  }

  // Juli 1968, Jul. 1968
  for (final m in RegExp(r'([a-zäöü]+)\.?\s*(\d{4})(?!\d)').allMatches(lower)) {
    final month = _kMonths[m.group(1)!];
    final year = int.parse(m.group(2)!);
    if (month != null && _plausibleYear(year)) {
      return '$year-${_two(month)}';
    }
  }

  // 7.1968, 07/1968
  for (final m in RegExp(
    r'(?<![\d.])(\d{1,2})\s*[./]\s*(\d{4})(?!\d)',
  ).allMatches(lower)) {
    final month = int.parse(m.group(1)!);
    final year = int.parse(m.group(2)!);
    if (month >= 1 && month <= 12 && _plausibleYear(year)) {
      return '$year-${_two(month)}';
    }
  }

  // 1968
  for (final m in RegExp(r'(?<!\d)(\d{4})(?!\d)').allMatches(lower)) {
    final year = int.parse(m.group(1)!);
    if (_plausibleYear(year)) return '$year';
  }

  // 12.7.68
  for (final m in RegExp(
    r'(?<![\d.])(\d{1,2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{2})(?![\d.])',
  ).allMatches(lower)) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = _fromTwoDigits(int.parse(m.group(3)!));
    if (_plausibleYear(year) && _validDay(year, month, day)) {
      return '$year-${_two(month)}-${_two(day)}';
    }
  }

  // Febr. 87, Juli 68
  for (final m in RegExp(r"([a-zäöü]+)\.?\s*['’]?(\d{2})(?![\d.])")
      .allMatches(lower)) {
    final month = _kMonths[m.group(1)!];
    final year = _fromTwoDigits(int.parse(m.group(2)!));
    if (month != null && _plausibleYear(year)) {
      return '$year-${_two(month)}';
    }
  }

  // 86-87, 86/87: a school year
  for (final m in RegExp(r'(?<![\d.])(\d{2})\s*[-/]\s*(\d{2})(?![\d.])')
      .allMatches(lower)) {
    final first = int.parse(m.group(1)!), second = int.parse(m.group(2)!);
    final year = _fromTwoDigits(first);
    if (second == (first + 1) % 100 && _plausibleYear(year)) return '$year';
  }

  // '72
  for (final m in RegExp(r"['’](\d{2})(?![\d.])").allMatches(lower)) {
    final year = _fromTwoDigits(int.parse(m.group(1)!));
    if (_plausibleYear(year)) return '$year';
  }
  return null;
}

/// The most recent year ending in [twoDigits].
int _fromTwoDigits(int twoDigits) {
  final now = DateTime.now().year;
  final year = now - now % 100 + twoDigits;
  return year > now ? year - 100 : year;
}

/// Reads a date the user typed into the partial ISO form [PhotoMetadata]
/// stores, accepting the same spellings [findPhotoDate] finds in a
/// caption. Returns '' for blank input and null for input that isn't a
/// date, so the editor can tell "no date" from "not a date".
String? parsePhotoDateInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  return findPhotoDate(trimmed);
}

/// [isoDate] the way a person writes it: `1968`, `07.1968`, `12.07.1968`.
String formatPhotoDate(String isoDate) {
  final parts = isoDate.split('-');
  return parts.reversed.join('.');
}

/// [isoDate] as an EXIF DateTimeOriginal (`YYYY:MM:DD HH:MM:SS`), or null
/// when it isn't one of the partial ISO forms. EXIF has no way to say
/// "only the year is known", so the missing parts become the first of the
/// month and of the year. Noon rather than midnight, so a viewer that
/// shifts the time into another zone still shows the right day.
String? exifDateTime(String isoDate) {
  final m = RegExp(r'^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?$').firstMatch(isoDate);
  if (m == null) return null;
  final month = m.group(2) ?? '01';
  final day = m.group(3) ?? '01';
  return '${m.group(1)}:$month:$day 12:00:00';
}
