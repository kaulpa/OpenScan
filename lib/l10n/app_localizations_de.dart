// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get about => 'Über';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get open => 'Öffnen';

  @override
  String get share => 'Teilen';

  @override
  String get export => 'Exportieren';

  @override
  String get clear => 'Leeren';

  @override
  String get delete => 'Löschen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get crop => 'Zuschneiden';

  @override
  String get done => 'Fertig';

  @override
  String get next => 'Weiter';

  @override
  String get skip => 'Überspringen';

  @override
  String get loading => 'Wird geladen';

  @override
  String get home => 'Start';

  @override
  String get demo => 'Demo';

  @override
  String get quality => 'Qualität';

  @override
  String get version => 'Version';

  @override
  String get select => 'Auswählen';

  @override
  String get select_all => 'Alle auswählen';

  @override
  String get select_pages => 'Seiten auswählen';

  @override
  String get reorder_pages => 'Seiten neu ordnen';

  @override
  String get try_again => 'Erneut versuchen';

  @override
  String get undo => 'RÜCKGÄNGIG';

  @override
  String get not_now => 'Nicht jetzt';

  @override
  String get open_settings => 'Einstellungen öffnen';

  @override
  String get more => 'Mehr';

  @override
  String get sort => 'Sortieren';

  @override
  String get settings => 'Einstellungen';

  @override
  String get tutorial => 'Anleitung';

  @override
  String get library => 'Bibliothek';

  @override
  String get scan => 'Scannen';

  @override
  String get image => 'Bild';

  @override
  String get images => 'Bilder';

  @override
  String get developers => 'Entwickler';

  @override
  String get view_on_linkedin => 'Auf LinkedIn ansehen';

  @override
  String get tutorial_title => 'Wie funktioniert die App?';

  @override
  String get cant_be_undone => 'Das kann nicht rückgängig gemacht werden.';

  @override
  String get rotate => 'Drehen';

  @override
  String get rotate_left => 'Nach links drehen';

  @override
  String get rotate_right => 'Nach rechts drehen';

  @override
  String pages_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '1 Seite',
    );
    return '$_temp0';
  }

  @override
  String get scan_options => 'Scan-Optionen';

  @override
  String get live_scan => 'Live-Scan';

  @override
  String get import_from_gallery => 'Aus Galerie importieren';

  @override
  String get import_from_gallery_short => 'Aus Galerie importieren';

  @override
  String get refresh => 'Zum Aktualisieren nach unten ziehen';

  @override
  String get last_updated => 'Zuletzt aktualisiert';

  @override
  String get sort_order => 'Sortierung';

  @override
  String get search_documents => 'Dokumente durchsuchen';

  @override
  String get no_documents_yet => 'Noch keine Dokumente';

  @override
  String get no_documents_body =>
      'Scanne deine erste Seite – das dauert etwa zwei Sekunden und bleibt nur auf diesem Gerät.';

  @override
  String get start_scanning => 'Scannen starten';

  @override
  String no_results_for(String query) {
    return 'Keine Ergebnisse für «$query»';
  }

  @override
  String get refreshing => 'Wird aktualisiert…';

  @override
  String get exporting => 'Wird exportiert…';

  @override
  String n_selected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get delete_document_q => 'Dokument löschen?';

  @override
  String delete_n_documents_q(int count) {
    return '$count Dokumente löschen?';
  }

  @override
  String get document_deleted => 'Dokument gelöscht';

  @override
  String n_documents_deleted(int count) {
    return '$count Dokumente gelöscht';
  }

  @override
  String saved_n_to_device(int count) {
    return '$count auf dem Gerät gespeichert';
  }

  @override
  String couldnt_export_n(int count) {
    return '$count konnten nicht exportiert werden';
  }

  @override
  String date_and_pages(String date, String pages) {
    return '$date · $pages';
  }

  @override
  String get sort_last_modified => 'Zuletzt geändert';

  @override
  String get sort_date_created => 'Erstellt am';

  @override
  String get sort_name => 'Name (A–Z)';

  @override
  String get sort_page_count => 'Seitenzahl';

  @override
  String get scanning => 'Scannen';

  @override
  String get live_detection => 'Dokumentränder erkennen';

  @override
  String get live_detection_desc =>
      'Umrandet die Seite in der Kamera und schneidet jede Aufnahme darauf zu. Ausschalten, um normale Fotos aufzunehmen und erst danach zuzuschneiden.';

  @override
  String get auto_capture => 'Automatisch auslösen';

  @override
  String get auto_capture_desc => 'Löst aus, sobald die Seite stillhält.';

  @override
  String get batch_capture => 'Serienmodus';

  @override
  String get batch_capture_desc =>
      'Die Kamera bleibt für mehrere Seiten offen, Zuschnitte korrigierst du danach. Aus: Jede Aufnahme öffnet vor dem Speichern den Zuschnitt.';

  @override
  String get scan_mode_single => 'Einzeln';

  @override
  String get scan_mode_batch => 'Serie';

  @override
  String get capture_sound => 'Auslöseton';

  @override
  String get keep_original => 'Originalbild behalten';

  @override
  String get keep_original_desc =>
      'Behält das unbeschnittene Foto, damit eine Seite aus der vollen Aufnahme neu zugeschnitten werden kann. Braucht etwa doppelt so viel Speicher.';

  @override
  String get avoid_gesture_strip => 'Zurück-Gestenbereich meiden';

  @override
  String get avoid_gesture_strip_desc =>
      'Hält die Zuschnittecken vom Bildschirmrand fern, wo ein Ziehen sonst die Zurück-Geste des Systems auslöst. Die Seite wird dadurch etwas schmaler.';

  @override
  String get default_filter => 'Standardfilter';

  @override
  String get appearance => 'Darstellung';

  @override
  String get theme => 'Design';

  @override
  String get language => 'Sprache';

  @override
  String get accent_color => 'Akzentfarbe';

  @override
  String get privacy_storage => 'Datenschutz & Speicher';

  @override
  String get privacy_body =>
      'OpenScan Foto sendet deine Fotos nirgendwohin. Keine Konten, keine Cloud – die Texterkennung läuft auf dem Telefon.';

  @override
  String get cache => 'Cache';

  @override
  String get clear_cache_q => 'Cache leeren?';

  @override
  String clear_cache_body(String size) {
    return 'Gibt $size an Vorschaubildern frei. Deine Dokumente sind nicht betroffen.';
  }

  @override
  String cache_clear_action(String size) {
    return '$size · Leeren';
  }

  @override
  String get cache_cleared => 'Cache geleert';

  @override
  String get couldnt_clear_cache => 'Der Cache konnte nicht geleert werden';

  @override
  String get theme_system => 'System';

  @override
  String get theme_light => 'Hell';

  @override
  String get theme_dark => 'Dunkel';

  @override
  String get filters => 'Filter';

  @override
  String get filter_original => 'Original';

  @override
  String get filter_auto => 'Auto';

  @override
  String get filter_lighten => 'Aufhellen';

  @override
  String get filter_grayscale => 'Graustufen';

  @override
  String get filter_bw => 'S/W';

  @override
  String get filter_whiteboard => 'Whiteboard';

  @override
  String get filter_action => 'Filter';

  @override
  String get apply_to_all_pages => 'Auf alle Seiten anwenden';

  @override
  String apply_to_all_n_pages(int count) {
    return 'Auf alle $count Seiten anwenden';
  }

  @override
  String get adjust_edges => 'Ränder anpassen';

  @override
  String get automatic_crop => 'Automatisch';

  @override
  String get no_crop => 'Kein Zuschnitt';

  @override
  String get rescan => 'Neu scannen';

  @override
  String get couldnt_crop =>
      'Das Bild konnte nicht zugeschnitten werden – bitte erneut versuchen.';

  @override
  String get looking_for_document => 'Suche Dokument…';

  @override
  String get document_detected => 'Dokument erkannt';

  @override
  String get hold_still => 'STILL HALTEN…';

  @override
  String get auto_on => 'AUTO · EIN';

  @override
  String get auto_off => 'AUTO · AUS';

  @override
  String get low_light => 'Wenig Licht – ruhig halten oder Licht einschalten';

  @override
  String get torch_on => 'Licht an';

  @override
  String get torch_off => 'Licht aus';

  @override
  String get torch_unavailable => 'Auf diesem Gerät gibt es kein Kameralicht.';

  @override
  String get auto_capture_on => 'Automatisch auslösen an';

  @override
  String get auto_capture_off => 'Automatisch auslösen aus';

  @override
  String get auto_capture_needs_detection =>
      'Schalte zuerst die Randerkennung ein – das automatische Auslösen wartet auf die erkannte Seite.';

  @override
  String get undo_last_capture => 'Letzte Aufnahme rückgängig';

  @override
  String get composition_grid => 'Gitternetz';

  @override
  String get turn_captures => 'Aufnahmen drehen';

  @override
  String captures_turned(int degrees) {
    return 'Aufnahmen werden um $degrees° gedreht';
  }

  @override
  String get captures_not_turned => 'Aufnahmen werden nicht gedreht';

  @override
  String get switch_camera => 'Kamera wechseln';

  @override
  String get couldnt_capture =>
      'Aufnahme fehlgeschlagen – bitte erneut versuchen.';

  @override
  String get couldnt_open_gallery =>
      'Die Galerie konnte nicht geöffnet werden.';

  @override
  String get couldnt_start_camera =>
      'Die Kamera konnte nicht gestartet werden – bitte zurückgehen und erneut versuchen.';

  @override
  String get camera_access_needed => 'Kamerazugriff nötig';

  @override
  String get camera_access_body =>
      'OpenScan nutzt die Kamera nur zum Scannen – nichts verlässt dein Gerät. Erlaube den Zugriff in den Einstellungen, um fortzufahren.';

  @override
  String done_count(int count) {
    return 'Fertig · $count';
  }

  @override
  String get delete_document => 'Dokument löschen';

  @override
  String get delete_document_body =>
      'Alle Seiten werden mitgelöscht. Das kann nicht rückgängig gemacht werden.';

  @override
  String get delete_page_q => 'Seite löschen?';

  @override
  String delete_n_pages_q(int count) {
    return '$count Seiten löschen?';
  }

  @override
  String get no_pages_title => 'Dieses Dokument hat keine Seiten';

  @override
  String get no_pages_body =>
      'Benannt nach deiner ersten Seite – zum Umbenennen jederzeit auf den Titel tippen.';

  @override
  String get continue_scanning => 'Weiter scannen';

  @override
  String get add_pages => 'Seiten hinzufügen';

  @override
  String get export_selected => 'Auswahl exportieren';

  @override
  String export_n_selected(int count) {
    return '$count ausgewählte exportieren';
  }

  @override
  String skipped_files(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien übersprungen, die diese App nicht lesen kann.',
      one: '1 Datei übersprungen, die diese App nicht lesen kann.',
    );
    return '$_temp0';
  }

  @override
  String hold_to_select(String pages) {
    return '$pages · zum Auswählen eine Seite gedrückt halten';
  }

  @override
  String export_title(String name) {
    return 'Exportieren · $name';
  }

  @override
  String get quality_caps => 'QUALITÄT';

  @override
  String get page_size => 'Seitengrösse';

  @override
  String get page_size_letter => 'Letter';

  @override
  String get page_size_legal => 'Legal';

  @override
  String get all_pages => 'Alle Seiten';

  @override
  String get selected_pages => 'Ausgewählte Seiten';

  @override
  String page_x_of_y(int current, int total) {
    return 'Seite $current von $total';
  }

  @override
  String get exported => 'Exportiert';

  @override
  String saved_to_folder(String folder) {
    return 'In $folder gespeichert';
  }

  @override
  String saved_n_to_folder(int count, String folder) {
    return '$count in $folder gespeichert';
  }

  @override
  String get saved_privately =>
      'In der App gespeichert, wo andere Apps es nicht sehen. Mit «Teilen» kannst du es woandershin senden.';

  @override
  String get export_failed => 'Export fehlgeschlagen';

  @override
  String get no_pages_to_export => 'Es gibt keine Seiten zum Exportieren.';

  @override
  String get pdf_not_written => 'PDF konnte nicht geschrieben werden';

  @override
  String get not_enough_storage =>
      'Nicht genug Speicherplatz auf diesem Gerät.';

  @override
  String get export_went_wrong => 'Beim Exportieren ist etwas schiefgelaufen.';

  @override
  String couldnt_open_file(String message) {
    return 'Datei konnte nicht geöffnet werden: $message';
  }

  @override
  String get no_app_opens_file =>
      'Keine App auf diesem Telefon kann diese Art von Datei öffnen';

  @override
  String get quality_ultra_low => 'Sehr niedrig';

  @override
  String get quality_low => 'Niedrig';

  @override
  String get quality_medium => 'Mittel';

  @override
  String get quality_high => 'Hoch';

  @override
  String result_and_more(String name, int count) {
    return '$name + $count weitere';
  }

  @override
  String get rename_file => 'Datei umbenennen';

  @override
  String get file_name_empty => 'Der Dateiname darf nicht leer sein';

  @override
  String get special_chars_not_allowed => 'Sonderzeichen sind nicht erlaubt';

  @override
  String get save_to_device => 'Auf dem Gerät speichern';

  @override
  String get share_pdf => 'PDF teilen';

  @override
  String get share_images => 'Bilder teilen';

  @override
  String get demo_scan_title => 'Auf die Seite richten';

  @override
  String get demo_scan_body =>
      'OpenScan findet die Ränder der Seite – tippe auf den Auslöser. Mit «Automatisch auslösen» macht die App die Aufnahme selbst, sobald du stillhältst.';

  @override
  String get demo_pages_title => 'Weitere Seiten aufnehmen';

  @override
  String get demo_pages_body =>
      'Jede Aufnahme kommt ins selbe Dokument. Tippe auf «Fertig», wenn du alle hast.';

  @override
  String get demo_adjust_title => 'Ausrichten und aufbereiten';

  @override
  String get demo_adjust_body =>
      'Ziehe die Ecken, falls die Ränder nicht stimmen, und wähle dann einen Filter – Auto, Graustufen oder S/W.';

  @override
  String get demo_organise_title => 'Seiten ordnen und hinzufügen';

  @override
  String get demo_organise_body =>
      'Halte eine Seite gedrückt, um sie auszuwählen, ordne Seiten über das ⋮-Menü neu und füge jederzeit weitere hinzu.';

  @override
  String get demo_export_title => 'Als PDF speichern oder teilen';

  @override
  String get demo_export_body =>
      'Wähle Qualität und Seitengrösse, dann speichere es auf dem Telefon oder sende es, wohin du willst.';

  @override
  String get demo_privacy_title => 'Es verlässt nie dein Telefon';

  @override
  String get demo_privacy_body =>
      'Keine Konten, keine Cloud, keine Werbung, kein Tracking. Die Kamera wird nur zum Scannen verwendet.';

  @override
  String get allow_camera_access => 'Kamerazugriff erlauben';

  @override
  String get app_description =>
      'ist eine Open-Source-App, mit der du Papierdokumente scannen und in eine PDF-Datei umwandeln kannst.';

  @override
  String get app_description_2 =>
      'Keine Werbung. Wir sammeln keine Daten.\n Wir respektieren deine Privatsphäre.';

  @override
  String get open_source_github => 'Open Source auf GitHub';

  @override
  String get couldnt_launch_url => 'Der Link konnte nicht geöffnet werden';

  @override
  String get mark_text => 'Text';

  @override
  String get mark_caption => 'Beschriftung markieren';

  @override
  String get mark_text_hint =>
      'Ziehe einen Rahmen um die Beschriftung – sie wird gelesen und zum Foto gespeichert.';

  @override
  String get reading_text => 'Text wird erkannt…';

  @override
  String get caption_empty_hint =>
      'Noch keine Beschreibung. Tippe auf «Text» und ziehe einen Rahmen darum.';

  @override
  String get clear_caption => 'Beschreibung löschen';

  @override
  String get text_recognition_unavailable =>
      'Die Texterkennung ist auf diesem Gerät nicht verfügbar.';

  @override
  String get no_text_found => 'Im markierten Bereich wurde kein Text erkannt.';

  @override
  String get edit_caption => 'Beschreibung & Datum';

  @override
  String get caption => 'Beschreibung';

  @override
  String get caption_action => 'Text';

  @override
  String get photo_date => 'Aufnahmedatum';

  @override
  String get photo_date_hint => 'z. B. 1968, 7.1968 oder 12.7.1968';

  @override
  String get photo_date_invalid =>
      'Jahr, Monat.Jahr oder Tag.Monat.Jahr eingeben';

  @override
  String use_date_from_caption(String date) {
    return '$date übernehmen';
  }
}
