import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../pdf_viewer.dart';
import '../pdf_viewer_params.dart';
import 'pdf_fit_mode.dart';
import 'pdf_layout.dart';

/// Cross-axis alignment of pages that are narrower than the widest page.
///
/// Only observable when pages differ in cross-axis size — i.e. with
/// [PdfFitMode.none]. With [PdfFitMode.fill] all pages share one cross-axis extent, so
/// alignment has no visible effect.
enum PdfCrossAxisAlignment { start, center, end }

/// Continuous layout that places pages end-to-end along [scrollDirection].
///
/// A declarative, value-type [PdfLayout] strategy ported from the author's #589
/// `SequentialPagesLayout`, reduced to the document-space + cross-axis-fill concerns
/// (no whole-page fit, no spreads, no discrete transitions — those arrive in later PRs).
///
/// ### Fit
/// The fit behaviour comes from the orthogonal [PdfViewerParams.fitMode], not from a
/// field on this layout (ported from #589, which applies all four modes in continuous
/// scroll):
/// * [PdfFitMode.none] — native page sizes.
/// * [PdfFitMode.fill] — each page scaled so its cross axis fills the viewport.
/// * [PdfFitMode.fit] — each page scaled to fit entirely within the viewport (letterbox)
///   so one page occupies at most one screen; pages then stack.
/// * [PdfFitMode.cover] — native page geometry. The "cover" effect (fill the viewport
///   with the whole document, may crop) is a zoom bound owned by the size delegate, not
///   baked into geometry here, so geometrically this matches [PdfFitMode.none].
///
/// Margins are **uniform document-space gaps applied outside the per-page fit**: a single
/// [margin] is subtracted from the viewport once (not folded into each page's scale), so
/// every cross-axis-constrained page lands at exactly `viewportCross - margin*2` and they
/// share one cross extent — no separate normalization pass is needed. Because the margin
/// lives in document coordinates, the viewer's zoom scales it on screen along with the
/// pages (it is fixed in document space, not in pixels). Pages constrained by the main
/// axis under [PdfFitMode.fit] (very tall pages) stay narrower and are positioned per
/// [crossAxisAlignment].
///
/// ### Equality (the value-type invariant)
/// Equality is over the **configuration fields only** — [scrollDirection], [spacing],
/// [margin], [crossAxisAlignment]. The produced [PdfPageLayout] geometry, the viewport,
/// and the (params-level) fit mode never participate in equality. Two equal configs
/// resolved at different viewport sizes are still equal, so a resize relayouts without
/// any [PdfViewerParams] equality churn. See [PdfLayout].
@immutable
class SequentialPagesLayout extends PdfLayout {
  const SequentialPagesLayout({
    this.scrollDirection = Axis.vertical,
    this.spacing = 8.0,
    this.margin = 8.0,
    this.crossAxisAlignment = PdfCrossAxisAlignment.center,
  });

  /// The axis pages are laid out and scrolled along. Vertical stacks top-to-bottom;
  /// horizontal places pages left-to-right.
  final Axis scrollDirection;

  /// Gap between consecutive pages along [scrollDirection], in document units.
  ///
  /// A document-space gap, so it scales with the viewer's zoom on screen.
  final double spacing;

  /// Uniform margin around the document, in document units.
  ///
  /// Applied *outside* the per-page fit (subtracted from the viewport once, not folded
  /// into each page's scale), so every page gets the same margin regardless of its fit
  /// scale. Being in document space, it scales with the viewer's zoom on screen.
  final double margin;

  /// How narrower pages are aligned within the cross axis. See [PdfCrossAxisAlignment].
  final PdfCrossAxisAlignment crossAxisAlignment;

  @override
  PdfPageLayout resolve({required List<PdfPage> pages, required Size viewport, required PdfViewerParams params}) {
    final isVertical = scrollDirection == Axis.vertical;
    // Cross-axis / main-axis extent selectors (cross = perpendicular to scrolling).
    double crossOf(double width, double height) => isVertical ? width : height;
    double mainOf(double width, double height) => isVertical ? height : width;

    final scales = _pageScales(pages, viewport, crossOf, mainOf, params.fitMode);

    // Bake each page's cross-axis fit scale into its size. Rendering scales by the
    // rect/native ratio, so upscaled pages still rasterize at full resolution.
    final sizes = <Size>[
      for (var i = 0; i < pages.length; i++) Size(pages[i].width * scales[i], pages[i].height * scales[i]),
    ];

    var maxCross = 0.0;
    for (final s in sizes) {
      maxCross = max(maxCross, crossOf(s.width, s.height));
    }

    final rects = <Rect>[];
    var main = margin;
    for (var i = 0; i < sizes.length; i++) {
      final s = sizes[i];
      final cross = crossOf(s.width, s.height);
      final crossOffset =
          margin +
          switch (crossAxisAlignment) {
            PdfCrossAxisAlignment.start => 0.0,
            PdfCrossAxisAlignment.center => (maxCross - cross) / 2,
            PdfCrossAxisAlignment.end => maxCross - cross,
          };
      rects.add(
        isVertical
            ? Rect.fromLTWH(crossOffset, main, s.width, s.height)
            : Rect.fromLTWH(main, crossOffset, s.width, s.height),
      );
      main += isVertical ? s.height : s.width;
      if (i < sizes.length - 1) main += spacing;
    }
    main += margin;

    final documentSize = isVertical ? Size(maxCross + margin * 2, main) : Size(main, maxCross + margin * 2);
    return PdfPageLayout(pageLayouts: rects, documentSize: documentSize);
  }

  /// Per-page scale to bake into geometry for the given [fitMode].
  ///
  /// [PdfFitMode.none] and [PdfFitMode.cover] keep native sizes (cover's zoom is the size
  /// delegate's concern). [PdfFitMode.fill] fills the cross axis; [PdfFitMode.fit] fits
  /// the whole page within the viewport. A not-yet-ready viewport (zero extent) falls
  /// back to native sizes; the next layout pass with a real viewport recomputes.
  List<double> _pageScales(
    List<PdfPage> pages,
    Size viewport,
    double Function(double, double) crossOf,
    double Function(double, double) mainOf,
    PdfFitMode fitMode,
  ) {
    switch (fitMode) {
      case PdfFitMode.none:
      case PdfFitMode.cover:
        return List<double>.filled(pages.length, 1.0);
      case PdfFitMode.fill:
        final availCross = crossOf(viewport.width, viewport.height) - margin * 2;
        if (availCross <= 0) return List<double>.filled(pages.length, 1.0);
        return [for (final p in pages) availCross / crossOf(p.width, p.height)];
      case PdfFitMode.fit:
        final availCross = crossOf(viewport.width, viewport.height) - margin * 2;
        final availMain = mainOf(viewport.width, viewport.height) - margin * 2;
        if (availCross <= 0 || availMain <= 0) return List<double>.filled(pages.length, 1.0);
        return [
          for (final p in pages) min(availCross / crossOf(p.width, p.height), availMain / mainOf(p.width, p.height)),
        ];
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SequentialPagesLayout &&
          other.scrollDirection == scrollDirection &&
          other.spacing == spacing &&
          other.margin == margin &&
          other.crossAxisAlignment == crossAxisAlignment;

  @override
  int get hashCode => Object.hash(scrollDirection, spacing, margin, crossAxisAlignment);
}
