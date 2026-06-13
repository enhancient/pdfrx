import 'package:flutter/widgets.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../pdf_viewer.dart';
import '../pdf_viewer_params.dart';

/// A declarative, value-type strategy that computes page geometry for the viewer.
///
/// A [PdfLayout] is the **configuration** for how pages are positioned — it is *not*
/// the resulting geometry. It produces a [PdfPageLayout] (the list of page rects plus
/// the document size) on demand via [resolve].
///
/// ### Relationship to [PdfViewerParams.layoutPages]
/// [PdfLayout] is the value-type successor to the [PdfViewerParams.layoutPages] closure.
/// Both ultimately yield a [PdfPageLayout], and dispatch precedence at the single
/// layout call site is:
///
/// ```text
/// params.layout?.resolve(...)  →  params.layoutPages(...)  →  built-in default
/// ```
///
/// Adding a [PdfLayout] is additive and non-breaking: [PdfViewerParams.layoutPages] is
/// untouched and continues to work when [PdfViewerParams.layout] is null.
///
/// ### Equality invariant (why this is a value type, not a closure)
/// A closure (like [PdfViewerParams.layoutPages]) cannot participate in
/// [PdfViewerParams] equality, so changing it has no effect until a manual
/// [PdfViewerController.invalidate]. [PdfLayout] fixes this:
///
/// * Implementations **must** be value types with correct [operator ==]/[hashCode]
///   over their configuration fields, and a `const` constructor where possible.
/// * Configuration fields **must** be comparable scalars/enums — **no closures, no
///   captured viewport.** The viewport is supplied *only* as a call-time argument to
///   [resolve]; it is never stored on the strategy and therefore never participates
///   in equality. Two strategies with identical configuration resolved at different
///   viewport sizes must still be equal.
///
/// This lets [PdfViewerParams] fold [PdfViewerParams.layout] into its own equality so
/// that a layout change relayouts automatically (cheaply, position-preserving), while a
/// viewport resize relayouts without any equality churn.
abstract class PdfLayout {
  const PdfLayout();

  /// Computes the page geometry for [pages] given the current [viewport] and [params].
  ///
  /// Returns a [PdfPageLayout] — the list of per-page rects in document coordinates
  /// plus the overall document size.
  ///
  /// [viewport] is a runtime input only. Implementations must not retain it; doing so
  /// would break the equality invariant described on the class.
  PdfPageLayout resolve({required List<PdfPage> pages, required Size viewport, required PdfViewerParams params});

  /// Subclasses must implement value equality over their configuration fields.
  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}
