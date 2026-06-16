import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Minimal [PdfPage] — only width/height are read by resolve().
class _FakePage implements PdfPage {
  _FakePage(this.width, this.height);
  @override
  final double width;
  @override
  final double height;
  @override
  int get pageNumber => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PdfSpreadLayout _resolve(
  FacingPagesLayout layout,
  List<PdfPage> pages, {
  Size viewport = const Size(432, 1000),
  PdfFitMode fitMode = PdfFitMode.fill,
}) => layout.resolve(
  pages: pages,
  viewport: viewport,
  params: PdfViewerParams(fitMode: fitMode),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // viewport 432×1000, margin 8 ⇒ availWidth 416, halfTarget (416-8)/2 = 204.
  List<PdfPage> portraits(int n) => [for (var i = 0; i < n; i++) _FakePage(100, 200)];

  group('FacingPagesLayout value equality', () {
    test('default is const; equal configs == with equal hashCode', () {
      const a = FacingPagesLayout();
      const b = FacingPagesLayout();
      expect(identical(a, b), isTrue);
      expect(a, equals(const FacingPagesLayout()));
      expect(a.hashCode, const FacingPagesLayout().hashCode);
    });

    test('each differing field breaks equality', () {
      const base = FacingPagesLayout();
      expect(base, isNot(equals(const FacingPagesLayout(margin: 9))));
      expect(base, isNot(equals(const FacingPagesLayout(spacing: 9))));
      expect(base, isNot(equals(const FacingPagesLayout(gutter: 9))));
      expect(base, isNot(equals(const FacingPagesLayout(firstPageIsCoverPage: true))));
      expect(base, isNot(equals(const FacingPagesLayout(isRightToLeftReadingOrder: true))));
      expect(base, isNot(equals(const FacingPagesLayout(singlePagesFillAvailableWidth: false))));
    });

    test('equality ignores viewport (resolved geometry differs, config stays equal)', () {
      const layout = FacingPagesLayout();
      final pages = portraits(2);
      final a = _resolve(layout, pages, viewport: const Size(432, 1000));
      final b = _resolve(layout, pages, viewport: const Size(864, 1000));
      expect(a.documentSize, isNot(equals(b.documentSize)));
      expect(layout, equals(const FacingPagesLayout()));
    });
  });

  group('resolve() geometry', () {
    test('two pages form one spread filling the viewport width', () {
      final r = _resolve(const FacingPagesLayout(), portraits(2));
      // each page filled to halfTarget 204 ⇒ 204×408; spread = 204+8+204 = 416 = availWidth.
      expect(r.pageLayouts[0], const Rect.fromLTWH(8, 8, 204, 408));
      expect(r.pageLayouts[1], const Rect.fromLTWH(220, 8, 204, 408)); // 8 + 204 + gutter 8
      expect(r.documentSize, const Size(432, 424)); // width tracks viewport; height = 8+408+8
    });

    test('right-to-left swaps the sides (page i on the right)', () {
      final r = _resolve(const FacingPagesLayout(isRightToLeftReadingOrder: true), portraits(2));
      expect(r.pageLayouts[0], const Rect.fromLTWH(220, 8, 204, 408)); // leading page on the right
      expect(r.pageLayouts[1], const Rect.fromLTWH(8, 8, 204, 408));
    });

    test('cover page is a standalone full-width spread; rest pair up', () {
      final r = _resolve(const FacingPagesLayout(firstPageIsCoverPage: true), portraits(3));
      // cover filled to availWidth 416 ⇒ 416×832, centered at x=8.
      expect(r.pageLayouts[0], const Rect.fromLTWH(8, 8, 416, 832));
      // next pair below: y = 8 + 832 + spacing 8 = 848.
      expect(r.pageLayouts[1], const Rect.fromLTWH(8, 848, 204, 408));
      expect(r.pageLayouts[2], const Rect.fromLTWH(220, 848, 204, 408));
    });

    test('exposes spreads for discrete mode (cover = its own spread, then a pair)', () {
      final r = _resolve(const FacingPagesLayout(firstPageIsCoverPage: true), portraits(3));
      expect(r.spreadCount, 2);
      // page 1 → spread 0 (cover); pages 2 & 3 → spread 1 (the pair).
      expect(r.pageToSpread, [0, 1, 1]);
      expect(r.spreadIndexOfPage(1), 0);
      expect(r.spreadIndexOfPage(3), 1);
      expect(r.firstPageOfSpread(1), 2);
      // spread bounds: cover rect, then the pair's bounding box (spreadX 8, y 848, w 416, h 408).
      expect(r.spreadBounds[0], const Rect.fromLTWH(8, 8, 416, 832));
      expect(r.spreadBounds[1], const Rect.fromLTWH(8, 848, 416, 408));
      expect(r.spreadBoundsOfPage(2), const Rect.fromLTWH(8, 848, 416, 408));
    });

    test('pagesOfSpread groups pages per spread (drives the page-range API)', () {
      final r = _resolve(const FacingPagesLayout(firstPageIsCoverPage: true), portraits(3));
      expect(r.pagesOfSpread(0), [1]); // lone cover
      expect(r.pagesOfSpread(1), [2, 3]); // facing pair → range "2–3"
      // simple two-up: each consecutive pair is a spread.
      final r2 = _resolve(const FacingPagesLayout(), portraits(4));
      expect(r2.pagesOfSpread(0), [1, 2]);
      expect(r2.pagesOfSpread(1), [3, 4]);
    });

    test('one spread per pair for a simple two-page document', () {
      final r = _resolve(const FacingPagesLayout(), portraits(2));
      expect(r.spreadCount, 1);
      expect(r.pageToSpread, [0, 0]);
      expect(r.spreadBounds[0], const Rect.fromLTWH(8, 8, 416, 408));
    });

    test('trailing odd page: fills width centered by default', () {
      final r = _resolve(const FacingPagesLayout(), portraits(3));
      expect(r.pageLayouts[2], const Rect.fromLTWH(8, 424, 416, 832)); // y = 8+408+8
    });

    test('trailing odd page: pinned to the left half (LTR) when not filling width', () {
      final r = _resolve(const FacingPagesLayout(singlePagesFillAvailableWidth: false), portraits(3));
      // half-width 204, left-aligned at margin 8.
      expect(r.pageLayouts[2], const Rect.fromLTWH(8, 424, 204, 408));
    });

    test('PdfFitMode.fit: each page fits within its half (whole page visible); the pair is centred', () {
      // viewport 432×300 ⇒ availWidth 416, halfTarget 204, availHeight 284.
      final r = _resolve(
        const FacingPagesLayout(),
        [_FakePage(100, 800), _FakePage(100, 800)],
        viewport: const Size(432, 300),
        fitMode: PdfFitMode.fit,
      );
      // fit: min(204/100, 284/800)=0.355 ⇒ 35.5×284 (fits the viewport height).
      expect(r.pageLayouts[0].width, closeTo(35.5, 0.01));
      expect(r.pageLayouts[0].height, closeTo(284, 0.01), reason: 'whole page fits the viewport');
      // pair packed (content 35.5+8+35.5=79) and centred: spreadX = 8 + (416-79)/2 = 176.5.
      expect(r.pageLayouts[0].left, closeTo(176.5, 0.01));
      expect(r.pageLayouts[1].left, closeTo(220, 0.01)); // 176.5 + 35.5 + gutter 8
      expect(r.spreadBounds[0], const Rect.fromLTWH(8, 8, 416, 284));
    });

    test('different-aspect pages each fit their half; the packed pair is centred in the viewport', () {
      final r = _resolve(
        const FacingPagesLayout(),
        [_FakePage(100, 800), _FakePage(100, 200)], // tall portrait + short
        viewport: const Size(432, 300),
        fitMode: PdfFitMode.fit,
      );
      // left fit 0.355 ⇒ 35.5×284; right fit min(2.04, 284/200=1.42)=1.42 ⇒ 142×284.
      // content = 35.5+8+142 = 185.5; spreadX = 8 + (416-185.5)/2 = 123.25.
      expect(r.pageLayouts[0].width, closeTo(35.5, 0.01));
      expect(r.pageLayouts[1].width, closeTo(142, 0.01));
      expect(r.pageLayouts[0].height, closeTo(284, 0.01));
      expect(r.pageLayouts[1].height, closeTo(284, 0.01));
      expect(r.pageLayouts[0].left, closeTo(123.25, 0.01));
      expect(r.pageLayouts[1].left, closeTo(166.75, 0.01)); // 123.25 + 35.5 + 8
      // the pair is centred on the viewport: its midpoint is 432/2 = 216.
      expect((r.pageLayouts[0].left + r.pageLayouts[1].right) / 2, closeTo(216, 0.01));
      expect(r.spreadBounds[0], const Rect.fromLTWH(8, 8, 416, 284));
    });

    test('PdfFitMode.none does not scale paired pages (native size), pair centred', () {
      // viewport 432×1000, two native 100×200 pages: content 100+8+100 = 208, centred.
      final r = _resolve(const FacingPagesLayout(), [
        _FakePage(100, 200),
        _FakePage(100, 200),
      ], fitMode: PdfFitMode.none);
      expect(r.pageLayouts[0], const Rect.fromLTWH(112, 8, 100, 200)); // 8 + (416-208)/2 = 112
      expect(r.pageLayouts[1], const Rect.fromLTWH(220, 8, 100, 200)); // 112 + 100 + gutter 8
      expect(r.spreadBounds[0], const Rect.fromLTWH(112, 8, 208, 200)); // native content bounds
    });

    test('PdfFitMode.none keeps native size even when the spread is wider than the viewport', () {
      // two native 300×400 pages: content 608 > availWidth 416 ⇒ left-aligned, scrolls.
      final r = _resolve(const FacingPagesLayout(), [
        _FakePage(300, 400),
        _FakePage(300, 400),
      ], fitMode: PdfFitMode.none);
      expect(r.pageLayouts[0], const Rect.fromLTWH(8, 8, 300, 400)); // not scaled down to half
      expect(r.pageLayouts[1], const Rect.fromLTWH(316, 8, 300, 400));
      expect(r.documentSize.width, closeTo(624, 0.01)); // 8 + 608 + 8, wider than the viewport
    });

    test('PdfFitMode.none: a single (cover) is native and centred, ignoring singlePagesFillAvailableWidth', () {
      final r = _resolve(
        // singlePagesFillAvailableWidth: false would normally pin the cover to a side.
        const FacingPagesLayout(firstPageIsCoverPage: true, singlePagesFillAvailableWidth: false),
        [_FakePage(100, 200), _FakePage(100, 200), _FakePage(100, 200)],
        fitMode: PdfFitMode.none,
      );
      // cover stays native 100×200 and is centred (8 + (416-100)/2 = 166), not pinned/scaled.
      expect(r.pageLayouts[0], const Rect.fromLTWH(166, 8, 100, 200));
    });

    test('empty pages resolve without throwing', () {
      final r = _resolve(const FacingPagesLayout(), const []);
      expect(r.pageLayouts, isEmpty);
      expect(r.documentSize, Size.zero);
    });
  });
}
