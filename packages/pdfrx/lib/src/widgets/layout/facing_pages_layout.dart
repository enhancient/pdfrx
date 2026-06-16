import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../pdf_viewer_params.dart';
import 'pdf_fit_mode.dart';
import 'pdf_layout.dart';
import 'pdf_spread_layout.dart';

/// Facing-page (two-up) layout: pages are paired left/right into spreads that stack
/// vertically.
///
/// A value-type [PdfLayout] strategy ported from #589's `FacingPagesLayout`, reduced to
/// the independent-scaling path (the legacy max-page-width path is dropped). Each spread
/// is scaled to the viewport width, so this layout is legitimately viewport-aware — the
/// viewport enters only via [resolve], never as a stored field.
///
/// Sizing follows [PdfViewerParams.fitMode]: pages fill their half-column width, and
/// [PdfFitMode.fit] additionally caps each page to the viewport height.
///
/// Equality is over the configuration fields only ([margin], [spacing], [gutter],
/// [firstPageIsCoverPage], [isRightToLeftReadingOrder], [singlePagesFillAvailableWidth]) —
/// the produced geometry and the viewport never participate, so a resize relayouts without
/// [PdfViewerParams] equality churn. See [PdfLayout].
@immutable
class FacingPagesLayout extends PdfLayout {
  const FacingPagesLayout({
    this.margin = 8.0,
    this.spacing = 8.0,
    this.gutter = 8.0,
    this.firstPageIsCoverPage = false,
    this.isRightToLeftReadingOrder = false,
    this.singlePagesFillAvailableWidth = true,
  });

  /// Outer margin around the document, in document units.
  final double margin;

  /// Gap between consecutive spreads along the (vertical) scroll axis, in document units.
  final double spacing;

  /// Gap between the left and right page of a spread, in document units.
  final double gutter;

  /// Treat the first page as a standalone cover (its own one-page spread), so the
  /// remaining pages pair up as 2&3, 4&5, … — like a book whose cover is a right-hand page.
  final bool firstPageIsCoverPage;

  /// Right-to-left reading order (e.g. manga): the first page of a pair sits on the right.
  final bool isRightToLeftReadingOrder;

  /// When a spread has only one page (the cover, or a trailing odd page), fill the whole
  /// width and centre it. When false, the single page occupies one half (the side that
  /// matches the reading order), leaving the facing half blank.
  final bool singlePagesFillAvailableWidth;

  @override
  PdfSpreadLayout resolve({required List<PdfPage> pages, required Size viewport, required PdfViewerParams params}) {
    if (pages.isEmpty) {
      return PdfSpreadLayout(
        pageLayouts: const [],
        documentSize: Size.zero,
        spreadBounds: const [],
        pageToSpread: const [],
      );
    }

    final availWidth = viewport.width - margin * 2;
    final availHeight = viewport.height - margin * 2;
    final ready = availWidth > 0 && availHeight > 0;
    final fitMode = params.fitMode;
    final halfTarget = (availWidth - gutter) / 2;

    // Scale a page to a target width; PdfFitMode.fit also caps to the viewport height.
    // PdfFitMode.none never scales (native size); a not-ready viewport also falls back to
    // native (the next pass recomputes).
    Size sizeFor(PdfPage p, double target) {
      if (!ready || target <= 0 || fitMode == PdfFitMode.none) return Size(p.width, p.height);
      if (fitMode == PdfFitMode.fit) {
        final s = min(target / p.width, availHeight / p.height);
        return Size(p.width * s, p.height * s);
      }
      final s = target / p.width;
      return Size(target, p.height * s);
    }

    // x for a one-page spread. With none (native) or singlePagesFillAvailableWidth the page is
    // centred (left-aligned if it is wider than the viewport); otherwise it is pinned to one
    // side. singlePagesFillAvailableWidth is a scaling concept, so it is ignored under none.
    double singleX(double width, {required bool rightAligned}) {
      if (fitMode == PdfFitMode.none || singlePagesFillAvailableWidth) {
        return margin + (max(availWidth, width) - width) / 2;
      }
      return rightAligned ? margin + (availWidth - width) : margin;
    }

    final rects = List<Rect?>.filled(pages.length, null);
    final spreadBounds = <Rect>[];
    final pageToSpread = List<int>.filled(pages.length, 0);
    var y = margin;
    var i = 0;

    if (firstPageIsCoverPage) {
      final size = sizeFor(pages[0], singlePagesFillAvailableWidth ? availWidth : halfTarget);
      // The cover is the leading page: right side in LTR, left side in RTL.
      final rect = Rect.fromLTWH(
        singleX(size.width, rightAligned: !isRightToLeftReadingOrder),
        y,
        size.width,
        size.height,
      );
      rects[0] = rect;
      pageToSpread[0] = spreadBounds.length;
      spreadBounds.add(rect);
      y += size.height + spacing;
      i = 1;
    }

    while (i < pages.length) {
      if (i + 1 >= pages.length) {
        final size = sizeFor(pages[i], singlePagesFillAvailableWidth ? availWidth : halfTarget);
        // A trailing odd page is the trailing page: left side in LTR, right side in RTL.
        final rect = Rect.fromLTWH(
          singleX(size.width, rightAligned: isRightToLeftReadingOrder),
          y,
          size.width,
          size.height,
        );
        rects[i] = rect;
        pageToSpread[i] = spreadBounds.length;
        spreadBounds.add(rect);
        y += size.height + spacing;
        i += 1;
        continue;
      }

      // Transient: viewport not measured yet — pack natively (recomputed next pass).
      if (!ready) {
        final lh = pages[i].height, rh = pages[i + 1].height;
        final sh = max(lh, rh);
        rects[i] = Rect.fromLTWH(margin, y + (sh - lh) / 2, pages[i].width, lh);
        rects[i + 1] = Rect.fromLTWH(margin + pages[i].width + gutter, y + (sh - rh) / 2, pages[i + 1].width, rh);
        pageToSpread[i] = pageToSpread[i + 1] = spreadBounds.length;
        spreadBounds.add(Rect.fromLTWH(margin, y, pages[i].width + gutter + pages[i + 1].width, sh));
        y += sh + spacing;
        i += 2;
        continue;
      }

      // Each page is fit within its half-slot (whole page visible), so each consumes at most
      // half. PdfFitMode.fit caps each page to the viewport height; fill fills the half width;
      // none leaves both pages at native size (a paired spread is never scaled).
      final native = fitMode == PdfFitMode.none;
      final leftSize = sizeFor(pages[i], halfTarget);
      final rightSize = sizeFor(pages[i + 1], halfTarget);
      final spreadHeight = max(leftSize.height, rightSize.height);

      // Pack the two pages (gutter between them) and centre the pair — within the viewport for
      // scaled modes, or within the native content when it is wider than the viewport.
      final contentWidth = leftSize.width + gutter + rightSize.width;
      final spreadX = margin + (max(availWidth, contentWidth) - contentWidth) / 2;
      // pages[i] leads: on the left in LTR, on the right in RTL.
      final double leadingX;
      final double trailingX;
      if (isRightToLeftReadingOrder) {
        leadingX = spreadX + rightSize.width + gutter;
        trailingX = spreadX;
      } else {
        leadingX = spreadX;
        trailingX = spreadX + leftSize.width + gutter;
      }
      rects[i] = Rect.fromLTWH(leadingX, y + (spreadHeight - leftSize.height) / 2, leftSize.width, leftSize.height);
      rects[i + 1] = Rect.fromLTWH(
        trailingX,
        y + (spreadHeight - rightSize.height) / 2,
        rightSize.width,
        rightSize.height,
      );
      // Scaled modes fill the half-slot allocation (= availWidth) so the delegate floors the
      // zoom at fit-width; none bounds the (unscaled) native content.
      pageToSpread[i] = pageToSpread[i + 1] = spreadBounds.length;
      spreadBounds.add(
        native
            ? Rect.fromLTWH(spreadX, y, contentWidth, spreadHeight)
            : Rect.fromLTWH(margin, y, availWidth, spreadHeight),
      );
      y += spreadHeight + spacing;
      i += 2;
    }

    final pageLayouts = [for (final r in rects) r!];
    final maxRight = spreadBounds.fold(0.0, (m, r) => max(m, r.right));
    // When the viewport is known the spreads fill its width (availWidth, centred), so the
    // document is the full viewport width — otherwise a narrow spread would make the size
    // delegate zoom in. Replace the trailing inter-spread spacing with the bottom margin.
    final documentWidth = ready ? max(maxRight + margin, availWidth + margin * 2) : maxRight + margin;
    final documentSize = Size(documentWidth, y - spacing + margin);
    return PdfSpreadLayout(
      pageLayouts: pageLayouts,
      documentSize: documentSize,
      spreadBounds: spreadBounds,
      pageToSpread: pageToSpread,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FacingPagesLayout &&
          other.margin == margin &&
          other.spacing == spacing &&
          other.gutter == gutter &&
          other.firstPageIsCoverPage == firstPageIsCoverPage &&
          other.isRightToLeftReadingOrder == isRightToLeftReadingOrder &&
          other.singlePagesFillAvailableWidth == singlePagesFillAvailableWidth;

  @override
  int get hashCode => Object.hash(
    margin,
    spacing,
    gutter,
    firstPageIsCoverPage,
    isRightToLeftReadingOrder,
    singlePagesFillAvailableWidth,
  );
}
