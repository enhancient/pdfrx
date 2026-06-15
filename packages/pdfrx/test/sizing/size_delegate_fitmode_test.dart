import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// `calculateMetrics` is pure computation (no engine), so we can drive the delegates
/// directly with a hand-built layout and assert how `fitMode` floors the min scale.
///
/// Scenario: a `fill`-style layout — one tall portrait page sized to the viewport width,
/// in a short (landscape) window, so fit-page < fit-width.
///   viewport 500×400, margin 8, document 500×800, page rect (8,8,484,784).
///   ⇒ coverScale (fit-width) = max(500/500, 400/800) = 1.0
///     alternativeFitScale (fit-page) = min(500/500, 400/800) = 0.5
final _layout = PdfPageLayout(pageLayouts: [const Rect.fromLTWH(8, 8, 484, 784)], documentSize: const Size(500, 800));

PdfViewerLayoutMetrics _metrics(PdfViewerSizeDelegate delegate, PdfFitMode fitMode) => delegate.calculateMetrics(
  viewSize: const Size(500, 400),
  layout: _layout,
  pageNumber: 1,
  pageMargin: 8,
  boundaryMargin: null,
  fitMode: fitMode,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Legacy delegate minScale by fitMode (useAlternativeFitScaleAsMinScale: true)', () {
    final delegate = const PdfViewerSizeDelegateProviderLegacy(useAlternativeFitScaleAsMinScale: true).create();

    test('the raw scalars are independent of fitMode', () {
      for (final mode in PdfFitMode.values) {
        final m = _metrics(delegate, mode);
        expect(m.coverScale, 1.0, reason: 'coverScale for $mode');
        expect(m.alternativeFitScale, 0.5, reason: 'alternativeFitScale for $mode');
      }
    });

    test('none keeps legacy behavior: floor at fit-page', () {
      expect(_metrics(delegate, PdfFitMode.none).minScale, 0.5);
    });

    test('fill floors at fit-width (coverScale), not fit-page', () {
      expect(_metrics(delegate, PdfFitMode.fill).minScale, 1.0);
    });

    test('cover floors at fit-width (coverScale)', () {
      expect(_metrics(delegate, PdfFitMode.cover).minScale, 1.0);
    });

    test('fit floors at fit-page', () {
      expect(_metrics(delegate, PdfFitMode.fit).minScale, 0.5);
    });
  });

  test('Legacy with useAlternativeFitScaleAsMinScale: false — none uses default minScale, fill still fit-width', () {
    final delegate = const PdfViewerSizeDelegateProviderLegacy(
      useAlternativeFitScaleAsMinScale: false,
      minScale: 0.1,
    ).create();
    expect(_metrics(delegate, PdfFitMode.none).minScale, 0.1, reason: 'none ⇒ explicit default');
    expect(_metrics(delegate, PdfFitMode.fill).minScale, 1.0, reason: 'fill ⇒ fit-width regardless of the flag');
  });

  group('Smart delegate minScale by fitMode', () {
    final delegate = const PdfViewerSizeDelegateProviderSmart().create(); // maxPagesVisible 3, minScale 0.1

    test('none keeps smart behavior: fit-page / maxPagesVisible', () {
      // max(0.1, 0.5 / 3) = 0.1667
      expect(_metrics(delegate, PdfFitMode.none).minScale, closeTo(0.5 / 3, 1e-9));
    });

    test('fill floors at fit-width (coverScale)', () {
      expect(_metrics(delegate, PdfFitMode.fill).minScale, 1.0);
    });
  });

  group('spread-aware fit (fit the whole spread, not a half-spread page)', () {
    // A facing spread 416 wide made of two 204-wide pages; viewport 432×1000, margin 8.
    final spread = PdfSpreadLayout(
      pageLayouts: [const Rect.fromLTWH(8, 8, 204, 200), const Rect.fromLTWH(220, 8, 204, 200)],
      documentSize: const Size(432, 216),
      spreadBounds: [const Rect.fromLTWH(8, 8, 416, 200)],
      pageToSpread: [0, 0],
    );

    PdfViewerLayoutMetrics metrics(PdfViewerSizeDelegate d) => d.calculateMetrics(
      viewSize: const Size(432, 1000),
      layout: spread,
      pageNumber: 1,
      pageMargin: 8,
      boundaryMargin: null,
      fitMode: PdfFitMode.fit,
    );

    test('legacy fit-page uses the spread width (1.0), not the page width (~1.96)', () {
      final m = metrics(const PdfViewerSizeDelegateProviderLegacy().create());
      // min(432/(416+16), 1000/(200+16)) = min(1.0, 4.63) = 1.0; a half-page would give ~1.96.
      expect(m.alternativeFitScale, closeTo(1.0, 1e-9));
      expect(m.minScale, closeTo(1.0, 1e-9));
    });

    test('smart fit-page also fits the spread', () {
      final m = metrics(const PdfViewerSizeDelegateProviderSmart().create());
      expect(m.alternativeFitScale, closeTo(1.0, 1e-9));
    });
  });
}
