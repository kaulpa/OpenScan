import 'package:flutter/material.dart';
import 'package:openscan/core/metadata/photo_metadata.dart';
import 'package:openscan/core/theme/os_colors.dart';
import 'package:openscan/core/theme/os_tokens.dart';
import 'package:openscan/core/theme/os_typography.dart';
import 'package:openscan/l10n/app_localizations.dart';

/// Opens the caption editor on [initial]. Resolves with what the user
/// saved, or null if they cancelled.
Future<PhotoMetadata?> editPhotoMetadata(
  BuildContext context,
  PhotoMetadata initial,
) => showDialog<PhotoMetadata>(
  context: context,
  builder: (_) => MetadataDialog(initial: initial),
);

/// Caption and date of one photo, following the same dialog spec as
/// Rename: title, the fields, cancel + save.
///
/// The caption is whatever text recognition read, so it opens ready to be
/// corrected rather than retyped. The date takes the spellings people
/// write on the back of a photo — `1968`, `7.1968`, `12.7.1968`, `Juli
/// 1968` — and when it is empty but the caption mentions one, offers that.
class MetadataDialog extends StatefulWidget {
  const MetadataDialog({Key? key, required this.initial}) : super(key: key);

  final PhotoMetadata initial;

  @override
  State<MetadataDialog> createState() => _MetadataDialogState();
}

class _MetadataDialogState extends State<MetadataDialog> {
  late final TextEditingController _caption = TextEditingController(
    text: widget.initial.caption,
  );
  late final TextEditingController _date = TextEditingController(
    text: widget.initial.date.isEmpty
        ? ''
        : formatPhotoDate(widget.initial.date),
  );
  String? _dateError;

  @override
  void initState() {
    super.initState();
    // Rebuilt on every edit, for the date suggestion below the field.
    _caption.addListener(_changed);
    _date.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _caption.dispose();
    _date.dispose();
    super.dispose();
  }

  /// A date the caption mentions, offered while the date field is empty.
  String? get _suggestedDate =>
      _date.text.trim().isEmpty ? findPhotoDate(_caption.text) : null;

  void _save() {
    final date = parsePhotoDateInput(_date.text);
    if (date == null) {
      setState(
        () => _dateError = AppLocalizations.of(context)!.photo_date_invalid,
      );
      return;
    }
    Navigator.pop(
      context,
      PhotoMetadata(caption: _caption.text.trim(), date: date),
    );
  }

  @override
  Widget build(BuildContext context) {
    final os = context.os;
    final l10n = AppLocalizations.of(context)!;
    final suggestion = _suggestedDate;
    final fieldStyle = OSTypography.body.copyWith(color: os.onSurface);

    return AlertDialog(
      backgroundColor: os.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OSRadius.sheet),
      ),
      title: Text(
        l10n.edit_caption,
        style: OSTypography.subtitle.copyWith(color: os.onSurface),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _caption,
              autofocus: widget.initial.caption.isEmpty,
              minLines: 2,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: fieldStyle,
              decoration: InputDecoration(labelText: l10n.caption),
            ),
            const SizedBox(height: OSSpace.md),
            TextField(
              controller: _date,
              keyboardType: TextInputType.datetime,
              style: fieldStyle,
              onSubmitted: (_) => _save(),
              onChanged: (_) {
                if (_dateError != null) setState(() => _dateError = null);
              },
              decoration: InputDecoration(
                labelText: l10n.photo_date,
                hintText: l10n.photo_date_hint,
                errorText: _dateError,
                errorStyle: OSTypography.caption.copyWith(color: os.danger),
              ),
            ),
            if (suggestion != null)
              Padding(
                padding: const EdgeInsets.only(top: OSSpace.xs),
                child: ActionChip(
                  avatar: Icon(Icons.event_rounded, size: 16, color: os.accent),
                  label: Text(
                    l10n.use_date_from_caption(formatPhotoDate(suggestion)),
                    style: OSTypography.caption.copyWith(color: os.onSurface),
                  ),
                  onPressed: () => _date.text = formatPhotoDate(suggestion),
                ),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        OSSpace.sm,
        0,
        OSSpace.sm,
        OSSpace.sm,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.cancel,
            style: OSTypography.label.copyWith(
              fontWeight: FontWeight.w700,
              color: os.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: _save,
          child: Text(
            l10n.save,
            style: OSTypography.label.copyWith(
              fontWeight: FontWeight.w700,
              color: os.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// One line saying what a photo's metadata holds — date first, since it is
/// the shorter and the one a glance looks for — or null when it is empty.
String? metadataSummary(PhotoMetadata metadata) {
  final caption = metadata.caption.trim().replaceAll(
    RegExp(r'\s*\n\s*'),
    ' · ',
  );
  final date = metadata.date.isEmpty ? '' : formatPhotoDate(metadata.date);
  if (caption.isEmpty && date.isEmpty) return null;
  if (date.isEmpty) return caption;
  if (caption.isEmpty) return date;
  return '$date · $caption';
}
