// Copyright (c) 2024 Espresso Systems Inc.
// This file is part of pdfrx.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'pdf_viewer.dart';
import 'pdf_viewer_params.dart';

/// Helper class to hold layout calculation results.
class LayoutResult {
  LayoutResult({required this.pageLayouts, required this.documentSize});
  final List<Rect> pageLayouts;
  final Size documentSize;
}

/// Helper class to hold facing pages layout calculation results.
/// Private to FacingPagesLayout implementation.
class _FacingPagesLayoutResult {
  _FacingPagesLayoutResult({required this.pageLayouts, required this.documentSize, required this.maxSpreadWidth});
  final List<Rect> pageLayouts;
  final Size documentSize;
  final double maxSpreadWidth;
}

/// Defines page layout.
///
/// **Simple usage (backward compatible):**
/// Create instances directly with pre-computed page layouts:
/// ```dart
/// return PdfPageLayout(
///   pageLayouts: pageLayouts,  // List<Rect> of page positions
///   documentSize: Size(width, height),
/// );
/// ```
///
/// **Advanced usage (subclassing):**
/// For dynamic layouts that respond to viewport changes or fit modes:
/// 1. Extend this class and override [layoutBuilder] for custom positioning logic
/// 2. Override [primaryAxis] if not vertical scrolling
/// 3. Override [calculateFitScale] for custom scaling logic
/// 4. Store layout-specific metadata as fields (see [FacingPagesLayout.maxSpreadWidth])
///
/// **Document size considerations:**
/// - For fit/fill modes with viewport sizing: exclude boundary margins from document size
/// - For none mode with natural dimensions: include only content margins, not boundary margins
/// - Boundary margins are applied by the viewer outside the document
///
/// **Scaling considerations:**
/// - [calculateFitScale] returns the scale based on [FitMode] strategy
/// - This is typically used as the minimum scale for the InteractiveViewer
/// - Override only if default implementation doesn't fit your layout's needs
class PdfPageLayout {
  PdfPageLayout({required this.pageLayouts, required this.documentSize});

  final List<Rect> pageLayouts;
  final Size documentSize;

  /// Each layout implements its own calculation logic.
  /// Optional [viewportSize] can be used for fit mode calculations.
  ///
  /// The default implementation returns the existing layout, which supports
  /// backward compatibility with pre-computed layouts.
  LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {Size? viewportSize}) {
    return LayoutResult(pageLayouts: pageLayouts, documentSize: documentSize);
  }

  /// Layout knows its primary scroll axis.
  /// Defaults to vertical scrolling.
  Axis get primaryAxis => Axis.vertical;

  /// Gets the maximum page width across all pages.
  double getMaxPageWidth() {
    return pageLayouts.fold(0.0, (maximum, rect) => max(maximum, rect.width));
  }

  /// Gets the maximum page height across all pages.
  double getMaxPageHeight() {
    return pageLayouts.fold(0.0, (maximum, rect) => max(maximum, rect.height));
  }

  /// Helper to create a fit mode layout where each page is sized to fit the viewport.
  ///
  /// This is a convenience method for implementing [FitMode.fit] in custom layouts
  /// for single-direction scrolling. It handles the math of sizing each page to fit
  /// within the viewport while preserving aspect ratios.
  ///
  /// **When to use this helper:**
  /// - You're implementing a simple vertical or horizontal scrolling layout
  /// - You want each page to fit within the viewport (with letterboxing)
  /// - Different page orientations should each maximize their viewport usage
  ///
  /// **What this helper does:**
  /// 1. Calculates how to scale each page to fit within the available viewport space
  /// 2. Positions pages along the scroll axis
  /// 3. Centers pages perpendicular to the scroll direction
  /// 4. Returns page rectangles already sized to their final display dimensions
  ///
  /// Because pages are returned at their final size, [calculateFitScale] will naturally
  /// return approximately 1.0 for these layouts.
  ///
  /// **Example usage:**
  /// ```dart
  /// @override
  /// LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {Size? viewportSize}) {
  ///   switch (params.fitMode) {
  ///     case FitMode.fit:
  ///       if (viewportSize != null) {
  ///         return createViewportFitLayout(
  ///           pages: pages,
  ///           margin: params.margin,
  ///           boundaryMargin: params.boundaryMargin,
  ///           viewportSize: viewportSize,
  ///           scrollAxis: primaryAxis,
  ///         );
  ///       }
  ///       // Fallback if viewport size unknown
  ///       // ...
  ///
  ///     case FitMode.fill:
  ///       // Use page's natural dimensions, let calculateFitScale handle fitting
  ///       // ...
  ///   }
  /// }
  /// ```
  ///
  /// **Alternative approach:**
  /// You can also create layouts using each page's natural dimensions (e.g., 8.5"×11")
  /// and let [calculateFitScale] compute the appropriate scaling factor. Both approaches
  /// work correctly - use whichever is clearer for your layout logic.
  LayoutResult createViewportFitLayout({
    required List<PdfPage> pages,
    required double margin,
    required EdgeInsets? boundaryMargin,
    required Size viewportSize,
    required Axis scrollAxis,
  }) {
    final bmh = boundaryMargin?.horizontal == double.infinity ? 0 : boundaryMargin?.horizontal ?? 0;
    final bmv = boundaryMargin?.vertical == double.infinity ? 0 : boundaryMargin?.vertical ?? 0;

    final availableWidth = viewportSize.width - bmh - margin * 2;
    final availableHeight = viewportSize.height - bmv - margin * 2;

    final pageLayouts = <Rect>[];
    final isVertical = scrollAxis == Axis.vertical;
    var scrollPosition = margin;
    var maxCrossAxis = 0.0;

    for (var page in pages) {
      // Scale each page to fit available space (letterbox as needed)
      final scale = min(availableWidth / page.width, availableHeight / page.height);
      final scaledWidth = page.width * scale;
      final scaledHeight = page.height * scale;

      maxCrossAxis = max(maxCrossAxis, isVertical ? scaledWidth : scaledHeight);

      if (isVertical) {
        pageLayouts.add(Rect.fromLTWH(margin, scrollPosition, scaledWidth, scaledHeight));
        scrollPosition += scaledHeight + margin;
      } else {
        pageLayouts.add(Rect.fromLTWH(scrollPosition, margin, scaledWidth, scaledHeight));
        scrollPosition += scaledWidth + margin;
      }
    }

    // Center pages perpendicular to scroll direction
    final centeredLayouts = <Rect>[];
    for (var rect in pageLayouts) {
      if (isVertical) {
        final xOffset = (maxCrossAxis - rect.width) / 2;
        centeredLayouts.add(rect.translate(xOffset, 0));
      } else {
        final yOffset = (maxCrossAxis - rect.height) / 2;
        centeredLayouts.add(rect.translate(0, yOffset));
      }
    }

    final docSize = isVertical
        ? Size(maxCrossAxis + margin * 2, scrollPosition)
        : Size(scrollPosition, maxCrossAxis + margin * 2);

    return LayoutResult(pageLayouts: centeredLayouts, documentSize: docSize);
  }

  /// Calculates the scale to display content according to the [FitMode] strategy.
  ///
  /// This value determines how content should be scaled based on the fit mode and is
  /// typically used as the minimum scale for the InteractiveViewer (though an explicit
  /// minScale parameter may override this if set higher).
  ///
  /// **Return value behavior by mode:**
  /// - [FitMode.fit]: Scale to show entire content within viewport (letterboxing acceptable)
  /// - [FitMode.fill]: Scale to fill viewport in one dimension (cropping acceptable in the other)
  /// - [FitMode.none]: Scale to fit width, allowing vertical/horizontal scrolling
  ///
  /// **For layouts that pre-size pages to viewport (like fit mode with [createViewportFitLayout]):**
  /// Return 1.0 since pages are already at their target size.
  ///
  /// **For layouts using natural dimensions:**
  /// Calculate the scale needed to fit/fill the viewport based on page dimensions.
  ///
  /// The [pageTransition] mode affects fill behavior:
  /// - [PageTransition.continuous]: Fill perpendicular to scroll direction
  /// - [PageTransition.discrete]: Always fill width
  ///
  /// Override this method if your layout needs custom scaling logic (e.g., [FacingPagesLayout]
  /// uses spread width instead of individual page width).
  double calculateFitScale(
    Size viewportSize,
    FitMode mode, {
    EdgeInsets? boundaryMargin,
    double margin = 0.0,
    PageTransition pageTransition = PageTransition.continuous,
  }) {
    final bmh = boundaryMargin?.horizontal == double.infinity ? 0 : boundaryMargin?.horizontal ?? 0;
    final bmv = boundaryMargin?.vertical == double.infinity ? 0 : boundaryMargin?.vertical ?? 0;
    final m2 = margin * 2;
    final maxPageWidth = getMaxPageWidth();
    final maxPageHeight = getMaxPageHeight();

    switch (mode) {
      case FitMode.fit:
        // Calculate scale to fit largest page dimensions within viewport
        // Works for both viewport-coordinate layouts (returns ~1.0) and
        // document-coordinate layouts (returns appropriate scale)
        return min(viewportSize.width / (maxPageWidth + bmh + m2), viewportSize.height / (maxPageHeight + bmv + m2));

      case FitMode.fill:
      case FitMode.none:
        if (pageTransition == PageTransition.discrete) {
          // Always fill width regardless of scroll direction
          return viewportSize.width / (maxPageWidth + bmh + m2);
        } else {
          // For vertical scroll: fill width, allow vertical overflow
          // For horizontal scroll: fill height, allow horizontal overflow
          if (primaryAxis == Axis.vertical) {
            return viewportSize.width / (maxPageWidth + bmh + m2);
          } else {
            return viewportSize.height / (maxPageHeight + bmv + m2);
          }
        }
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfPageLayout) return false;
    return listEquals(pageLayouts, other.pageLayouts) && documentSize == other.documentSize;
  }

  @override
  int get hashCode => pageLayouts.hashCode ^ documentSize.hashCode;
}

/// Vertical page layout implementation.
class VerticalPageLayout extends PdfPageLayout {
  VerticalPageLayout({required super.pageLayouts, required super.documentSize});

  /// Create a vertical layout from pages and parameters.
  factory VerticalPageLayout.fromPages(List<PdfPage> pages, PdfViewerParams params, {Size? viewportSize}) {
    final layout = VerticalPageLayout(pageLayouts: [], documentSize: Size.zero);
    final result = layout.layoutBuilder(pages, params, viewportSize: viewportSize);
    return VerticalPageLayout(pageLayouts: result.pageLayouts, documentSize: result.documentSize);
  }

  @override
  Axis get primaryAxis => Axis.vertical;

  @override
  LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {Size? viewportSize}) {
    switch (params.fitMode) {
      case FitMode.fill:
        // FILL: Each page scales to fill width
        final maxWidth = pages.fold(0.0, (w, p) => max(w, p.width));
        final width = maxWidth + params.margin * 2;

        final pageLayouts = <Rect>[];
        var y = params.margin;
        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          final rect = Rect.fromLTWH(params.margin, y, maxWidth, page.height * (maxWidth / page.width));
          pageLayouts.add(rect);
          y += rect.height + params.margin;
        }

        return LayoutResult(pageLayouts: pageLayouts, documentSize: Size(width, y));

      case FitMode.fit:
        // FIT: Each page scales to fit within viewport (both dimensions)
        // Requires viewport size to calculate proper fit
        if (viewportSize == null) {
          // Viewport not sized yet - return placeholder layout
          // This should only occur briefly during initialization
          return LayoutResult(pageLayouts: [], documentSize: Size.zero);
        }

        return createViewportFitLayout(
          pages: pages,
          margin: params.margin,
          boundaryMargin: params.boundaryMargin,
          viewportSize: viewportSize,
          scrollAxis: Axis.vertical,
        );

      case FitMode.none:
        // NONE: Use original page dimensions
        final width = pages.fold(0.0, (w, p) => max(w, p.width)) + params.margin * 2;
        final pageLayouts = <Rect>[];
        var y = params.margin;
        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          final rect = Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height);
          pageLayouts.add(rect);
          y += page.height + params.margin;
        }
        return LayoutResult(pageLayouts: pageLayouts, documentSize: Size(width, y));
    }
  }
}

/// Horizontal page layout implementation.
class HorizontalPageLayout extends PdfPageLayout {
  HorizontalPageLayout({required super.pageLayouts, required super.documentSize});

  /// Create a horizontal layout from pages and parameters.
  factory HorizontalPageLayout.fromPages(List<PdfPage> pages, PdfViewerParams params, {Size? viewportSize}) {
    final layout = HorizontalPageLayout(pageLayouts: [], documentSize: Size.zero);
    final result = layout.layoutBuilder(pages, params, viewportSize: viewportSize);
    return HorizontalPageLayout(pageLayouts: result.pageLayouts, documentSize: result.documentSize);
  }

  @override
  Axis get primaryAxis => Axis.horizontal;

  @override
  LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {Size? viewportSize}) {
    // Find the maximum page height for horizontal layout
    final maxPageHeight = pages.fold(0.0, (prev, page) => max(prev, page.height));

    switch (params.fitMode) {
      case FitMode.fill:
        // FILL: Each page scales to fill available height (horizontal scroll direction)
        // Width extends as needed (may exceed viewport)
        final height = maxPageHeight + params.margin * 2;

        final pageLayouts = <Rect>[];
        var x = params.margin;
        for (var page in pages) {
          // Scale each page to fill the maximum height
          final scale = maxPageHeight / page.height;
          final scaledWidth = page.width * scale;
          pageLayouts.add(Rect.fromLTWH(x, params.margin, scaledWidth, maxPageHeight));
          x += scaledWidth + params.margin;
        }
        return LayoutResult(pageLayouts: pageLayouts, documentSize: Size(x, height));

      case FitMode.fit:
        // FIT: Each page scales to fit within viewport (both dimensions)
        // Requires viewport size to calculate proper fit
        if (viewportSize == null) {
          // Viewport not sized yet - return placeholder layout
          // This should only occur briefly during initialization
          return LayoutResult(pageLayouts: [], documentSize: Size.zero);
        }

        return createViewportFitLayout(
          pages: pages,
          margin: params.margin,
          boundaryMargin: params.boundaryMargin,
          viewportSize: viewportSize,
          scrollAxis: Axis.horizontal,
        );

      case FitMode.none:
        // NONE: No scaling, use original page dimensions
        final height = maxPageHeight + params.margin * 2;

        final pageLayouts = <Rect>[];
        var x = params.margin;
        for (var page in pages) {
          pageLayouts.add(
            Rect.fromLTWH(
              x,
              params.margin + (maxPageHeight - page.height) / 2, // center vertically
              page.width,
              page.height,
            ),
          );
          x += page.width + params.margin;
        }
        return LayoutResult(pageLayouts: pageLayouts, documentSize: Size(x, height));
    }
  }
}

/// Facing pages layout implementation with intelligent aspect ratio handling.
class FacingPagesLayout extends PdfPageLayout {
  FacingPagesLayout({required super.pageLayouts, required super.documentSize, required this.maxSpreadWidth});

  /// Create a facing pages layout from pages and parameters.
  factory FacingPagesLayout.fromPages(
    List<PdfPage> pages,
    PdfViewerParams params, {
    Size? viewportSize,
    bool firstPageIsCoverPage = false,
    bool isRightToLeftReadingOrder = false,
  }) {
    final layout = FacingPagesLayout(pageLayouts: [], documentSize: Size.zero, maxSpreadWidth: 0);
    final result = layout._layoutBuilderWithOptions(
      pages,
      params,
      viewportSize: viewportSize,
      firstPageIsCoverPage: firstPageIsCoverPage,
      isRightToLeftReadingOrder: isRightToLeftReadingOrder,
    );
    return FacingPagesLayout(
      pageLayouts: result.pageLayouts,
      documentSize: result.documentSize,
      maxSpreadWidth: result.maxSpreadWidth,
    );
  }

  final double maxSpreadWidth;

  @override
  Axis get primaryAxis => Axis.vertical; // Typically vertical for facing pages

  @override
  LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {Size? viewportSize}) {
    // For the base layoutBuilder, use default parameters
    final result = _layoutBuilderWithOptions(
      pages,
      params,
      viewportSize: viewportSize,
      firstPageIsCoverPage: false,
      isRightToLeftReadingOrder: false,
    );
    return LayoutResult(pageLayouts: result.pageLayouts, documentSize: result.documentSize);
  }

  /// Calculate facing pages layout arrangement with additional options.
  ///
  /// **Cover page handling:**
  /// When [firstPageIsCoverPage] is true, the first page is treated as a cover that spans
  /// the full spread width (both left and right page areas).
  ///
  /// **Layout modes:**
  /// - Fill + Continuous: Pages fill height, width is half viewport (or matched pair width on mobile)
  /// - Fill + Discrete: Pages fill width, each gets half viewport width
  /// - Fit + Continuous/Discrete: Pages must fit side-by-side, each gets half viewport width
  _FacingPagesLayoutResult _layoutBuilderWithOptions(
    List<PdfPage> pages,
    PdfViewerParams params, {
    required Size? viewportSize,
    required bool firstPageIsCoverPage,
    required bool isRightToLeftReadingOrder,
  }) {
    if (pages.isEmpty) {
      return _FacingPagesLayoutResult(pageLayouts: [], documentSize: Size.zero, maxSpreadWidth: 0);
    }

    // For fit mode, we need viewport size to calculate proper dimensions
    if (params.fitMode == FitMode.fit && viewportSize == null) {
      return _FacingPagesLayoutResult(pageLayouts: [], documentSize: Size.zero, maxSpreadWidth: 0);
    }

    final pageLayouts = <Rect>[];
    var y = params.margin;
    var maxLeftWidth = 0.0;
    var maxRightWidth = 0.0;
    var maxSpreadWidth = 0.0;

    // Determine if we should scale pages to viewport
    final scaleToViewport = (params.fitMode == FitMode.fit) || (params.fitMode == FitMode.fill && viewportSize != null);

    final bmh = params.boundaryMargin?.horizontal == double.infinity ? 0 : params.boundaryMargin?.horizontal ?? 0;
    final bmv = params.boundaryMargin?.vertical == double.infinity ? 0 : params.boundaryMargin?.vertical ?? 0;

    // Calculate available space once if needed
    final availableWidth = scaleToViewport && viewportSize != null
        ? viewportSize.width - bmh - params.margin * 2
        : null;
    final availableHeight = scaleToViewport && viewportSize != null
        ? viewportSize.height - bmv - params.margin * 2
        : null;

    var pageIndex = 0;

    // Handle cover page if needed
    if (firstPageIsCoverPage && pages.isNotEmpty) {
      final coverPage = pages[0];
      final double coverWidth, coverHeight;

      if (scaleToViewport && availableWidth != null && availableHeight != null) {
        if (params.fitMode == FitMode.fit) {
          // Fit: cover must fit in both width and height
          final scale = min(availableWidth / coverPage.width, availableHeight / coverPage.height);
          coverWidth = coverPage.width * scale;
          coverHeight = coverPage.height * scale;
        } else {
          // Fill: cover fills width, height scales proportionally
          final scale = availableWidth / coverPage.width;
          coverWidth = availableWidth;
          coverHeight = coverPage.height * scale;
        }

        // Center cover page horizontally
        final coverX = params.margin + (availableWidth - coverWidth) / 2;
        pageLayouts.add(Rect.fromLTWH(coverX, y, coverWidth, coverHeight));
      } else {
        // Use natural dimensions
        coverWidth = coverPage.width;
        coverHeight = coverPage.height;
        pageLayouts.add(Rect.fromLTWH(params.margin, y, coverWidth, coverHeight));
      }

      y += coverHeight + params.margin;
      maxLeftWidth = max(maxLeftWidth, coverWidth / 2);
      maxRightWidth = max(maxRightWidth, coverWidth / 2);
      maxSpreadWidth = max(maxSpreadWidth, coverWidth);
      pageIndex = 1;
    }

    // Process remaining pages as spreads (pairs)
    while (pageIndex < pages.length) {
      final leftPage = pages[pageIndex];
      final rightPageIndex = pageIndex + 1;
      final rightPage = rightPageIndex < pages.length ? pages[rightPageIndex] : null;

      double leftWidth, leftHeight, rightWidth, rightHeight;

      if (scaleToViewport && availableWidth != null && availableHeight != null) {
        // Each page gets equal horizontal space (half the available width)
        final halfWidth = availableWidth / 2;

        if (rightPage != null) {
          // Pair: each page gets half width
          if (params.fitMode == FitMode.fit) {
            // Fit: each page must fit in its half-width AND the available height
            final leftScale = min(halfWidth / leftPage.width, availableHeight / leftPage.height);
            leftWidth = leftPage.width * leftScale;
            leftHeight = leftPage.height * leftScale;

            final rightScale = min(halfWidth / rightPage.width, availableHeight / rightPage.height);
            rightWidth = rightPage.width * rightScale;
            rightHeight = rightPage.height * rightScale;
          } else {
            // Fill: each page fills its half-width, height scales proportionally
            leftWidth = halfWidth;
            leftHeight = leftPage.height * (halfWidth / leftPage.width);
            rightWidth = halfWidth;
            rightHeight = rightPage.height * (halfWidth / rightPage.width);
          }
        } else {
          // Single page: gets full width
          if (params.fitMode == FitMode.fit) {
            final scale = min(availableWidth / leftPage.width, availableHeight / leftPage.height);
            leftWidth = leftPage.width * scale;
            leftHeight = leftPage.height * scale;
          } else {
            // Fill: fills full width
            leftWidth = availableWidth;
            leftHeight = leftPage.height * (availableWidth / leftPage.width);
          }
          rightWidth = 0;
          rightHeight = 0;
        }
      } else {
        // Use natural dimensions
        leftWidth = leftPage.width;
        leftHeight = leftPage.height;
        rightWidth = rightPage?.width ?? 0;
        rightHeight = rightPage?.height ?? 0;
      }

      maxLeftWidth = max(maxLeftWidth, leftWidth);
      maxRightWidth = max(maxRightWidth, rightWidth);

      final spreadWidth = leftWidth + rightWidth;
      maxSpreadWidth = max(maxSpreadWidth, spreadWidth);
      final spreadHeight = max(leftHeight, rightHeight);

      // Center spread horizontally when scaling to viewport
      final spreadX = scaleToViewport && availableWidth != null
          ? params.margin + (availableWidth - spreadWidth) / 2
          : params.margin;

      // Layout left page
      if (isRightToLeftReadingOrder) {
        // RTL: left page on right side of spread
        pageLayouts.add(
          Rect.fromLTWH(spreadX + rightWidth, y + (spreadHeight - leftHeight) / 2, leftWidth, leftHeight),
        );
      } else {
        // LTR: left page on left side of spread
        pageLayouts.add(Rect.fromLTWH(spreadX, y + (spreadHeight - leftHeight) / 2, leftWidth, leftHeight));
      }

      // Layout right page if it exists
      if (rightPage != null) {
        if (isRightToLeftReadingOrder) {
          // RTL: right page on left side of spread
          pageLayouts.add(Rect.fromLTWH(spreadX, y + (spreadHeight - rightHeight) / 2, rightWidth, rightHeight));
        } else {
          // LTR: right page on right side of spread
          pageLayouts.add(
            Rect.fromLTWH(spreadX + leftWidth, y + (spreadHeight - rightHeight) / 2, rightWidth, rightHeight),
          );
        }
      }

      y += spreadHeight + params.margin;
      pageIndex += rightPage != null ? 2 : 1;
    }

    // Calculate document width based on content
    // For fit/fill modes: use actual content width (available width used for sizing)
    // For none mode: use max spread width plus margins
    final documentWidth = scaleToViewport && viewportSize != null && availableWidth != null
        ? availableWidth + params.margin * 2
        : maxSpreadWidth + params.margin * 2;

    return _FacingPagesLayoutResult(
      pageLayouts: pageLayouts,
      documentSize: Size(documentWidth, y),
      maxSpreadWidth: maxSpreadWidth,
    );
  }

  @override
  double calculateFitScale(
    Size viewportSize,
    FitMode mode, {
    EdgeInsets? boundaryMargin,
    double margin = 0.0,
    PageTransition pageTransition = PageTransition.continuous,
  }) {
    if (mode == FitMode.fit) {
      // For fit mode, pages are already sized to viewport in layoutBuilder
      // Return 1.0 since no additional scaling is needed
      return 1.0;
    }

    if (mode == FitMode.fill) {
      // Fill: use base implementation
      return super.calculateFitScale(
        viewportSize,
        mode,
        boundaryMargin: boundaryMargin,
        margin: margin,
        pageTransition: pageTransition,
      );
    }

    // None: calculate scale based on maximum spread width
    // Use the widest individual spread, plus boundary margins and edge margins
    final bmh = boundaryMargin?.horizontal == double.infinity ? 0 : boundaryMargin?.horizontal ?? 0;
    final m2 = margin * 2;

    return viewportSize.width / (maxSpreadWidth + bmh + m2);
  }
}
