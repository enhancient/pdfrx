/// How the viewer moves between pages or spreads.
///
/// A top-level axis of `PdfViewerParams` (`params.pageTransition`), orthogonal to
/// `scrollDirection`, `layout` and `fitMode`. Modelled on the author's #589 `PageTransition`.
enum PdfPageTransition {
  /// Free, continuous scrolling — pages flow and the view pans/zooms without snapping.
  /// This is the default and matches the historical behaviour.
  continuous,

  /// One page or spread at a time. The view is confined to the current spread and a swipe
  /// past the edge commits a translate-and-fit transition to the neighbouring spread.
  ///
  /// The spread unit comes from the layout (a `PdfSpreadLayout` groups pages into spreads;
  /// any other layout is treated as one spread per page).
  discrete,
}
