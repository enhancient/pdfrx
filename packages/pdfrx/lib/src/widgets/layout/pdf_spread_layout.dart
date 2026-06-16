import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../pdf_viewer.dart';

/// A [PdfPageLayout] **result** that also groups pages into spreads.
///
/// A "spread" is the unit that discrete (page-at-a-time) mode pages between: a single page
/// for a one-up layout, a left/right pair for a facing layout, a lone cover, or a trailing
/// odd page. Each spread has a document-space bounding [Rect] ([spreadBounds]) — that rect
/// is what discrete mode fits to the viewport and clamps the view to.
///
/// Produced by spread strategies such as `FacingPagesLayout.resolve()`. It is a *result*
/// type (computed geometry), distinct from the value-type layout *strategy*; equality is
/// over the computed geometry, used only for the relayout short-circuit.
class PdfSpreadLayout extends PdfPageLayout {
  PdfSpreadLayout({
    required super.pageLayouts,
    required super.documentSize,
    required this.spreadBounds,
    required this.pageToSpread,
  });

  /// Bounding rect of each spread, in document coordinates (indexed by spread index).
  final List<Rect> spreadBounds;

  /// Maps a 0-based page index to its 0-based spread index (`pageToSpread[pageNumber - 1]`).
  final List<int> pageToSpread;

  /// Number of spreads.
  int get spreadCount => spreadBounds.length;

  /// The 0-based spread index containing the 1-based [pageNumber].
  int spreadIndexOfPage(int pageNumber) => pageToSpread[pageNumber - 1];

  /// The bounding rect of the spread containing the 1-based [pageNumber], or null if the
  /// page number is out of range.
  Rect? spreadBoundsOfPage(int pageNumber) {
    if (pageNumber < 1 || pageNumber > pageToSpread.length) return null;
    return spreadBounds[pageToSpread[pageNumber - 1]];
  }

  /// The first page (1-based) of the spread at [spreadIndex].
  int firstPageOfSpread(int spreadIndex) {
    for (var i = 0; i < pageToSpread.length; i++) {
      if (pageToSpread[i] == spreadIndex) return i + 1;
    }
    throw RangeError.index(spreadIndex, spreadBounds, 'spreadIndex');
  }

  /// The 1-based page numbers that make up the spread at [spreadIndex], in document order (e.g.
  /// `[2, 3]` for a facing pair, `[1]` for a lone cover).
  List<int> pagesOfSpread(int spreadIndex) {
    final pages = <int>[];
    for (var i = 0; i < pageToSpread.length; i++) {
      if (pageToSpread[i] == spreadIndex) pages.add(i + 1);
    }
    return pages;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfSpreadLayout &&
          listEquals(pageLayouts, other.pageLayouts) &&
          documentSize == other.documentSize &&
          listEquals(spreadBounds, other.spreadBounds) &&
          listEquals(pageToSpread, other.pageToSpread);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(pageLayouts),
    documentSize,
    Object.hashAll(spreadBounds),
    Object.hashAll(pageToSpread),
  );
}
