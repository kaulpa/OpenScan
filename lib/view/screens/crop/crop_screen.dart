import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:openscan/core/cv/models/detection_result.dart';
import 'package:openscan/core/cv/models/quad.dart';
import 'package:openscan/core/metadata/photo_metadata.dart';
import 'package:openscan/core/settings/app_settings.dart';
import 'package:openscan/core/theme/appTheme.dart';
import 'package:openscan/core/theme/os_colors.dart';
import 'package:openscan/core/theme/os_tokens.dart';
import 'package:openscan/core/theme/os_typography.dart';
import 'package:openscan/l10n/app_localizations.dart';
import 'package:openscan/view/Widgets/cropper/polygon_painter.dart';
import 'package:openscan/view/Widgets/cropper/text_region_painter.dart';
import 'package:openscan/view/Widgets/metadata/metadata_dialog.dart';
import 'package:openscan/view/screens/crop/crop_screen_state.dart';

/// What the crop screen hands back: the cropped [file] and the caption
/// and date gathered alongside it.
class CropOutcome {
  final File file;
  final PhotoMetadata metadata;

  const CropOutcome(this.file, this.metadata);
}

/// Pushes the crop screen for [image].
///
/// Returns the cropped file (the same path — the crop is written in
/// place) with the photo's caption, or null if the user backed out
/// without cropping. Callers that want "unchanged image" semantics on
/// cancel can fall back to [image] themselves; callers re-cropping an
/// existing page use the null to leave that page alone.
///
/// [initialQuad], in the live-scan overlay's fractional portrait
/// coordinates, places the corners where the viewfinder had them; they
/// then move onto the same outline as found on the still, if it is there.
/// [initialTurns] opens the page already turned that many quarter turns
/// clockwise, as if Rotate had been pressed — the corners stay on the page
/// either way. [metadata] is the caption the page already has, for a
/// re-crop.
Future<CropOutcome?> imageCropper(BuildContext context, File image,
    {Quad? initialQuad,
    int initialTurns = 0,
    PhotoMetadata metadata = PhotoMetadata.empty}) async {
  return await Navigator.push<CropOutcome?>(
    context,
    MaterialPageRoute(
      builder: (context) => CropImage(
        file: image,
        initialQuad: initialQuad,
        initialTurns: initialTurns,
        initialMetadata: metadata,
      ),
    ),
  );
}

/// Breathing room between the page and the edge of the screen.
const double _kCanvasPadding = 20.0;

/// Radius of the corner handles the polygon painter draws, so the side
/// padding can keep the whole dot out of the system gesture strip.
const double _kHandleRadius = 10.0;

/// Side of the square loupe shown while a corner is being dragged.
const double _kMagnifierSize = 80.0;

/// Space between the dragged corner and the nearest edge of the loupe, so
/// the finger doesn't cover it.
const double _kMagnifierGap = 40.0;

/// Height of the caption line above the action row. Fixed whatever it
/// says: the page is measured once, so the space around it can't change.
const double _kCaptionStripHeight = 52.0;

class CropImage extends StatefulWidget {
  final File? file;
  final Quad? initialQuad;
  final int initialTurns;
  final PhotoMetadata initialMetadata;

  CropImage({
    this.file,
    this.initialQuad,
    this.initialTurns = 0,
    this.initialMetadata = PhotoMetadata.empty,
  });

  _CropImageState createState() => _CropImageState();
}

class _CropImageState extends State<CropImage>
    with SingleTickerProviderStateMixin {
  CropScreenState _cropScreen = CropScreenState();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool cropLoading = false;

  /// Marking the caption rather than moving the corners: a drag on the
  /// page draws a box around text, which is then read into the caption.
  bool _textMode = false;

  /// Drives the quarter-turn animation. One controller for the whole
  /// screen, rather than an implicit animation on the image alone: the
  /// polygon overlay and the magnifier are painted outside the image's
  /// subtree and have to be redrawn at the same angle on every frame of
  /// the turn, or they visibly lag the page they belong to.
  late final AnimationController _turnController = AnimationController(
    vsync: this,
    duration: OSMotion.standard,
  );
  Animation<double> _turnAnimation = const AlwaysStoppedAnimation(0);

  double get _animatedTurns => _turnAnimation.value;

  @override
  void dispose() {
    _turnController.dispose();
    super.dispose();
  }

  @override
  initState() {
    super.initState();
    _cropScreen.imageFile = widget.file;
    _cropScreen.turns = widget.initialTurns;
    _cropScreen.metadata.value = widget.initialMetadata;
    _turnAnimation = AlwaysStoppedAnimation(widget.initialTurns.toDouble());

    /// Takes the viewfinder's corners, or measures the page so detection
    /// can run behind it, then waits for the page to be decoded and laid
    /// out before computing canvas geometry and initial points exactly once
    /// — replacing the old pattern of doing this inside the widget's
    /// build() callback on every rebuild.
    ///
    /// The wait for the decode matters: an [Image] that hasn't loaded yet
    /// lays out at zero size, and measured then, every corner lands on the
    /// same point.
    ///
    /// Detection doesn't hold the screen up: the page is shown with its
    /// corners at the edges, and they move to the page once it is found —
    /// unless the user has started moving them first.
    final initialQuad = widget.initialQuad;
    (initialQuad != null
            ? _cropScreen.useQuad(initialQuad)
            : _cropScreen.prepareForSearch())
        .then((_) async {
      if (!mounted) return;
      try {
        await precacheImage(_cropScreen.displayImage, context);
      } catch (e) {
        debugPrint('Could not preload ${_cropScreen.imageFile}: $e');
      }
      if (!mounted) return;
      // A frame with the decoded page in it, then measure.
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _cropScreen.getRenderedBoxSize();
          _cropScreen.initPoints();
        });
        if (initialQuad == null) {
          _detectBehindPage();
        } else {
          _refineBehindPage();
        }
      });
    });

    _cropScreen.canvasSize = Size(0, 0);
    _cropScreen.originalCanvasSize = Size(0, 0);
    _cropScreen.tl = Offset(0, 0);
    _cropScreen.tr = Offset(0, 0);
    _cropScreen.bl = Offset(0, 0);
    _cropScreen.br = Offset(0, 0);
    _cropScreen.t = Offset(0, 0);
    _cropScreen.l = Offset(0, 0);
    _cropScreen.b = Offset(0, 0);
    _cropScreen.r = Offset(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    _cropScreen.screenSize = MediaQuery.of(context).size;
    debugPrint(
        'Screen size=> ${_cropScreen.screenSize.width} / ${_cropScreen.screenSize.height}');

    // On gesture navigation the system reserves a strip down each side of
    // the display for the back swipe. A touch that starts inside that
    // strip never reaches this screen's GestureDetector — dragging a
    // corner there pops the route instead of moving the point. Widening
    // the inset past that strip fixes it, at the cost of page width on
    // every scan, so it is the "Avoid back-gesture strip" setting rather
    // than the default. The dot's own radius is added on top of the strip
    // so the whole handle (not just its centre) sits clear of it.
    final gestureInsets = MediaQuery.of(context).systemGestureInsets;
    final avoidStrip = AppSettings.instance.avoidGestureStrip;
    final sidePadding = EdgeInsets.only(
      left: avoidStrip
          ? max(_kCanvasPadding, gestureInsets.left + _kHandleRadius)
          : _kCanvasPadding,
      right: avoidStrip
          ? max(_kCanvasPadding, gestureInsets.right + _kHandleRadius)
          : _kCanvasPadding,
      top: _kCanvasPadding,
      bottom: _kCanvasPadding,
    );
    return SafeArea(
      child: PopScope(
        canPop: true,
        child: Scaffold(
          // Fixed-dark chrome, like the viewfinder this screen follows on
          // from: the captured page is the brightest thing on screen and
          // shouldn't sit inside a warm-white frame.
          backgroundColor: OSColors.chromeBackground,
          key: _scaffoldKey,
          // The page is measured once, when it is first laid out; a
          // keyboard opening for the caption editor must not squeeze it.
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: Text(
              _textMode
                  ? AppLocalizations.of(context)!.mark_caption
                  : AppLocalizations.of(context)!.adjust_edges,
              style: OSTypography.subtitle
                  .copyWith(color: OSColors.chromeOnBackground),
            ),
            centerTitle: true,
            elevation: 0.0,
            backgroundColor: OSColors.chromeBackground,
            systemOverlayStyle: AppTheme.chromeOverlayStyle,
            leading: IconButton(
              icon: Icon(Icons.close_rounded,
                  color: OSColors.chromeOnBackground),
              onPressed: () {
                Navigator.pop(context, null);
              },
            ),
            actions: [nextAction()],
          ),
          body: GestureDetector(
            key: _cropScreen.bodyKey,
            onPanUpdate: (updateDetails) {
              if (_textMode) {
                _cropScreen.updateTextRegion(
                    _cropScreen.fromDisplay(updateDetails.localPosition));
                return;
              }
              // Touches land on the page as it is being shown; the polygon
              // lives in the page's own unrotated coordinates.
              _cropScreen.updatedPoint.value = DragUpdateDetails(
                globalPosition: updateDetails.globalPosition,
                localPosition:
                    _cropScreen.fromDisplay(updateDetails.localPosition) +
                        _cropScreen.grabOffset,
                delta: updateDetails.delta,
              );
              _cropScreen.updatePolygon();
            },
            onPanStart: (startDetails) {
              if (_textMode) {
                if (!_cropScreen.imageRendered.value) return;
                _cropScreen.startTextRegion(
                    _cropScreen.fromDisplay(startDetails.localPosition));
                return;
              }
              _cropScreen.calculateAllSlopes();
              _cropScreen.getMovingPoint(DragStartDetails(
                globalPosition: startDetails.globalPosition,
                localPosition:
                    _cropScreen.fromDisplay(startDetails.localPosition),
              ));
              if (_cropScreen.movingPoint.name != 'none') {
                _cropScreen.userAdjusted = true;
                _cropScreen.showMagnifier.value = true;
              }
            },
            onPanEnd: (details) {
              if (_textMode) {
                final region = _cropScreen.finishTextRegion();
                if (region != null) _readRegion(region);
                return;
              }
              _cropScreen.movingPoint.name = 'none';
              _cropScreen.movingPoint.offset = Offset.zero;
              _cropScreen.showMagnifier.value = false;
            },
            child: Container(
              // width: _cropScreen.screenSize.width,
              // height: _cropScreen.screenSize.height,
              color: OSColors.chromeBackground,
              child: Stack(
                children: [
                  Container(
                    padding: sidePadding,
                    alignment: Alignment.center,
                    child: !cropLoading
                        ? AnimatedBuilder(
                            animation: _turnController,
                            builder: ((_, __) {
                              return Transform.rotate(
                                angle: _animatedTurns * pi / 2,
                                child: Transform.scale(
                                  scale:
                                      _cropScreen.scaleForTurns(_animatedTurns),
                                  child: Image(
                                    key: _cropScreen.imageKey,
                                    image: _cropScreen.displayImage,
                                    loadingBuilder:
                                        ((context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      );
                                    }),
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Icon(
                                          Icons.error_rounded,
                                          color: Colors.red,
                                          size: 30,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            }),
                          )
                        : CircularProgressIndicator(
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation(
                              Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _cropScreen.detectionState,
                    builder: (context, CropDetectionState state, _) {
                      if (state == CropDetectionState.loading) {
                        return Positioned.fill(
                          child: Container(
                            color: OSColors.chromeBackground
                                .withValues(alpha: 0.7),
                            child: Center(
                              child:
                                  CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                        );
                      }

                      if (!_cropScreen.imageRendered.value) return Container();

                      return Positioned.fill(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              // Still shown while marking text, faded, so
                              // the caption can be found relative to the
                              // photo it belongs to.
                              child: Opacity(
                                opacity: _textMode ? 0.35 : 1,
                                child: ValueListenableBuilder(
                                  valueListenable: _cropScreen.updatedPoint,
                                  builder: (context, _updatedPoint, _) {
                                    return AnimatedBuilder(
                                      animation: _turnController,
                                      builder: (context, _) {
                                        // The polygon is stored unrotated
                                        // and turned on its way to the
                                        // screen, so it describes the same
                                        // part of the photo at any angle.
                                        Offset at(Offset p) =>
                                            _cropScreen.toDisplay(p,
                                                turns: _animatedTurns);
                                        return CustomPaint(
                                          painter: PolygonPainter(
                                            accent: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            tl: at(_cropScreen.tl),
                                            tr: at(_cropScreen.tr),
                                            bl: at(_cropScreen.bl),
                                            br: at(_cropScreen.br),
                                            t: at(_cropScreen.t),
                                            l: at(_cropScreen.l),
                                            b: at(_cropScreen.b),
                                            r: at(_cropScreen.r),
                                          ),
                                        );
                                      },
                                    );
                                  }),
                              ),
                            ),
                            Positioned.fill(child: _textRegionOverlay()),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_textMode) _textModeHint(),
                  ValueListenableBuilder(
                    valueListenable: _cropScreen.showMagnifier,
                    builder: (context, bool _showMagnifier, _) {
                      if (_showMagnifier)
                        return ValueListenableBuilder(
                          valueListenable: _cropScreen.updatedPoint,
                          builder:
                              (context, DragUpdateDetails _updatedPoint, _) {
                            final at = _cropScreen
                                .toDisplay(_cropScreen.movingPoint.offset!);
                            final bounds = _cropScreen.bodySize;
                            // Sits above the finger by default, flips below
                            // when there is no room above, and is clamped so
                            // it never slides off the body and gets clipped.
                            // The focal offset follows wherever the loupe
                            // ended up, so it still shows the dragged corner.
                            double top =
                                at.dy - _kMagnifierGap - _kMagnifierSize;
                            if (top < 0) top = at.dy + _kMagnifierGap;
                            top = top.clamp(0.0,
                                max(0.0, bounds.height - _kMagnifierSize));
                            final double left =
                                (at.dx - _kMagnifierSize / 2).clamp(0.0,
                                    max(0.0, bounds.width - _kMagnifierSize));
                            final focalPointOffset = at -
                                Offset(left + _kMagnifierSize / 2,
                                    top + _kMagnifierSize / 2);
                            return Positioned(
                              left: left,
                              top: top,
                              child: RawMagnifier(
                                decoration: MagnifierDecoration(
                                  shadows: const <BoxShadow>[
                                    BoxShadow(
                                        blurRadius: 1.5,
                                        offset: Offset(0, 2),
                                        spreadRadius: 1,
                                        color: Color.fromARGB(25, 0, 0, 0))
                                  ],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    side: BorderSide(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      width: .15,
                                    ),
                                  ),
                                ),
                                size: Size.square(_kMagnifierSize),
                                magnificationScale: 1.5,
                                focalPointOffset: focalPointOffset,
                              ),
                            );
                          },
                        );
                      return Container();
                    },
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: bottomBar(),
        ),
      ),
    );
  }

  /// Runs detection with the page already on screen, and moves the corners
  /// to what it finds if the user hasn't moved them in the meantime.
  Future<void> _detectBehindPage() async {
    await _cropScreen.detectDocument();
    if (!mounted || _cropScreen.detectedQuad == null) return;
    if (!_cropScreen.userAdjusted) setState(_cropScreen.initPoints);
    await _markCaptionBehindPage();
  }

  /// With corners handed in from the viewfinder: looks for the same
  /// outline on the photo itself, which is sharper and was taken a moment
  /// later, and moves the corners onto it if the user hasn't moved them in
  /// the meantime.
  Future<void> _refineBehindPage() async {
    final refined = await _cropScreen.refineDetectedQuad();
    if (!mounted) return;
    if (refined && !_cropScreen.userAdjusted) {
      setState(_cropScreen.initPoints);
    }
    await _markCaptionBehindPage();
  }

  /// Once the corners have settled: finds the photo's caption on the page
  /// by itself, marks it and reads it — unless the page has a caption
  /// already or the user has started marking one. Next waits for it, as
  /// for a region marked by hand.
  Future<void> _markCaptionBehindPage() async {
    bool untouched() =>
        _cropScreen.metadata.value.isEmpty && _cropScreen.textRegions.isEmpty;
    if (!untouched()) return;
    _cropScreen.regionsBeingRead.value++;
    try {
      final region = await _cropScreen.findCaptionRegion();
      if (!mounted || region == null || !untouched()) return;
      _cropScreen.textRegions.add(region);
      _cropScreen.textRegionsChanged.value++;
      await _readRegion(region, quietly: true);
    } finally {
      _cropScreen.regionsBeingRead.value--;
    }
  }

  /// The primary action, in the app bar rather than the bottom row: the
  /// row below is for adjusting the quad, and Next is the thing you press
  /// when you are done adjusting it.
  Widget nextAction() {
    return ValueListenableBuilder(
      valueListenable: _cropScreen.regionsBeingRead,
      builder: (context, int reading, _) => ValueListenableBuilder(
      valueListenable: _cropScreen.imageRendered,
      builder: (context, bool imageRendered, _) {
        // Not while a caption is still being read: the crop writes over
        // the photo it is being read from, and the text would be lost.
        final enabled = imageRendered && !cropLoading && reading == 0;
        return TextButton(
          onPressed: enabled ? _cropAndPop : null,
          child: Text(
            AppLocalizations.of(context)!.next,
            style: OSTypography.label.copyWith(
              fontWeight: FontWeight.w700,
              color: enabled
                  ? Theme.of(context).colorScheme.primary
                  : OSColors.chromeMuted,
            ),
          ),
        );
      },
      ),
    );
  }

  Future<void> _cropAndPop() async {
    setState(() => cropLoading = true);
    final result = await _cropScreen.crop();
    if (!mounted) return;
    setState(() => cropLoading = false);

    if (result is CropSuccess) {
      Navigator.pop(
        context,
        CropOutcome(_cropScreen.imageFile!, _cropScreen.metadata.value),
      );
    } else if (result is CropFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.couldnt_crop)),
      );
    }
  }

  /// Turns the page a quarter turn clockwise. The polygon is not rotated
  /// with it — it stays in the page's own unrotated coordinates and is
  /// transformed on its way to the screen, so the corners keep describing
  /// the same part of the photo however the page is being shown.
  void _rotate() {
    final from = _animatedTurns;
    setState(() => _cropScreen.turns++);
    _turnAnimation = Tween(
      begin: from,
      end: _cropScreen.turns.toDouble(),
    ).animate(CurvedAnimation(
      parent: _turnController,
      curve: OSMotion.emphasizedDecel,
    ));
    _turnController.forward(from: 0);
  }

  Widget bottomBar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: OSColors.chromeBackground,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _captionStrip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  OSSpace.xs, 0, OSSpace.xs, OSSpace.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _CropAction(
                    icon: Icons.auto_awesome_rounded,
                    label: l10n.automatic_crop,
                    accent: !_textMode,
                    // Asking for the automatic crop is asking for
                    // detection's corners, including ones that arrive
                    // after the tap.
                    onPressed: () => setState(() {
                      _textMode = false;
                      _cropScreen.userAdjusted = false;
                      _cropScreen.initPoints();
                    }),
                  ),
                  _CropAction(
                    icon: Icons.crop_free_rounded,
                    label: l10n.no_crop,
                    onPressed: () => setState(() {
                      _textMode = false;
                      _cropScreen.userAdjusted = true;
                      _cropScreen.resetPointsToCorners();
                    }),
                  ),
                  _CropAction(
                    icon: Icons.rotate_right_rounded,
                    label: l10n.rotate,
                    onPressed: _rotate,
                  ),
                  _CropAction(
                    icon: Icons.text_fields_rounded,
                    label: l10n.mark_text,
                    accent: _textMode,
                    onPressed: () => setState(() => _textMode = !_textMode),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // <=========================== Caption ===========================>

  /// The caption so far, above the actions: what was read or typed, or how
  /// to get one. Tapping it opens the editor.
  Widget _captionStrip() {
    final l10n = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder(
      valueListenable: _cropScreen.regionsBeingRead,
      builder: (context, int reading, _) => ValueListenableBuilder(
        valueListenable: _cropScreen.metadata,
        builder: (context, PhotoMetadata metadata, _) {
          final summary = metadataSummary(metadata);
          return InkWell(
            onTap: reading > 0 ? null : _editMetadata,
            child: SizedBox(
              height: _kCaptionStripHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: OSSpace.md),
                child: Row(
                  children: [
                    if (reading > 0)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    else
                      Icon(Icons.notes_rounded,
                          size: 18,
                          color: summary == null
                              ? OSColors.chromeMuted
                              : accent),
                    const SizedBox(width: OSSpace.sm),
                    Expanded(
                      child: Text(
                        reading > 0
                            ? l10n.reading_text
                            : summary ?? l10n.caption_empty_hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: OSTypography.caption.copyWith(
                          color: summary == null || reading > 0
                              ? OSColors.chromeMuted
                              : OSColors.chromeOnBackground,
                        ),
                      ),
                    ),
                    if (summary != null && reading == 0)
                      IconButton(
                        tooltip: l10n.clear_caption,
                        icon: const Icon(Icons.close_rounded,
                            size: 18, color: OSColors.chromeMuted),
                        onPressed: _clearCaption,
                      )
                    else
                      const SizedBox(width: OSSpace.md),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The marked caption regions, drawn turned with the page.
  Widget _textRegionOverlay() {
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: _cropScreen.textRegionsChanged,
        builder: (context, int _, __) => AnimatedBuilder(
          animation: _turnController,
          builder: (context, _) {
            List<Offset> corners(Rect r) => [
                  for (final p in [
                    r.topLeft,
                    r.topRight,
                    r.bottomRight,
                    r.bottomLeft,
                  ])
                    _cropScreen.toDisplay(p, turns: _animatedTurns),
                ];
            final draft = _cropScreen.draftTextRegion;
            return CustomPaint(
              painter: TextRegionPainter(
                regions: [for (final r in _cropScreen.textRegions) corners(r)],
                draft: draft == null ? null : corners(draft),
              ),
            );
          },
        ),
      ),
    );
  }

  /// What to do in text mode, until the first box is drawn.
  Widget _textModeHint() {
    return ValueListenableBuilder(
      valueListenable: _cropScreen.textRegionsChanged,
      builder: (context, int _, __) {
        if (_cropScreen.textRegions.isNotEmpty ||
            _cropScreen.draftTextRegion != null) {
          return const SizedBox.shrink();
        }
        return Positioned(
          top: OSSpace.sm,
          left: OSSpace.md,
          right: OSSpace.md,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: OSSpace.md, vertical: OSSpace.xs),
                decoration: BoxDecoration(
                  color: OSColors.chromeScrim,
                  borderRadius: BorderRadius.circular(OSRadius.pill),
                ),
                child: Text(
                  AppLocalizations.of(context)!.mark_text_hint,
                  textAlign: TextAlign.center,
                  style: OSTypography.caption
                      .copyWith(color: OSColors.chromeOnBackground),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Reads the text in a region just marked and adds it to the caption.
  /// [quietly], for one marked by the screen itself, says nothing when
  /// there turns out to be nothing to read.
  Future<void> _readRegion(Rect region, {bool quietly = false}) async {
    _cropScreen.regionsBeingRead.value++;
    String? text;
    try {
      text = await _cropScreen.readTextRegion(region);
    } finally {
      _cropScreen.regionsBeingRead.value--;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (text == null || text.isEmpty) {
      // Nothing to add: the box goes again, so what is left on the page
      // still matches what the caption says.
      _cropScreen.textRegions.remove(region);
      _cropScreen.textRegionsChanged.value++;
      if (quietly) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(text == null
              ? l10n.text_recognition_unavailable
              : l10n.no_text_found),
        ));
      return;
    }
    _cropScreen.metadata.value =
        _cropScreen.metadata.value.withRecognizedText(text);
  }

  Future<void> _editMetadata() async {
    final edited =
        await editPhotoMetadata(context, _cropScreen.metadata.value);
    if (edited != null && mounted) _cropScreen.metadata.value = edited;
  }

  void _clearCaption() {
    _cropScreen.metadata.value = PhotoMetadata.empty;
    _cropScreen.clearTextRegions();
  }
}

/// One control in the crop screen's action row.
class _CropAction extends StatelessWidget {
  const _CropAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Marks the suggested action, so "Automatic crop" reads as the one to
  /// reach for when the corners have been dragged somewhere wrong — or
  /// the active one, for the text mode toggle.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color =
        accent ? Theme.of(context).colorScheme.primary : OSColors.chromeOnBackground;
    // Icon over label, so four of them fit across a phone in any
    // language.
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(OSRadius.card),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(
              horizontal: OSSpace.xxs, vertical: OSSpace.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: OSSpace.xxs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: OSTypography.caption.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
