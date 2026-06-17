//
// Super simple thumbnails view
//
// Groups pages into spreads using [PdfViewerController.pageRangeOf], so a facing/spread layout
// shows one thumbnail per spread with a page range (e.g. "2–3"). For single-page layouts every
// range collapses to a single page, so it behaves exactly like a per-page thumbnail list.
//
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class ThumbnailsView extends StatelessWidget {
  const ThumbnailsView({required this.documentRef, required this.controller, super.key});

  final PdfDocumentRef? documentRef;
  final PdfViewerController? controller;

  /// Groups consecutive pages into spread ranges using the controller. Falls back to one page per
  /// range when the controller is unavailable or the layout doesn't group pages.
  List<PdfPageRange> _ranges(int pageCount) {
    final ranges = <PdfPageRange>[];
    var page = 1;
    while (page <= pageCount) {
      final r = controller?.pageRangeOf(page) ?? PdfPageRange(page, page);
      final last = r.lastPageNumber >= page ? r.lastPageNumber : page;
      ranges.add(PdfPageRange(page, last));
      page = last + 1;
    }
    return ranges;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey,
      child: documentRef == null
          ? null
          : PdfDocumentViewBuilder(
              documentRef: documentRef!,
              builder: (context, document) {
                if (document == null) return const SizedBox();
                // Rebuild as the viewer's layout resolves (single-page → spreads) so the ranges and
                // the current-range highlight stay in sync.
                final listenable = controller ?? ValueNotifier(0);
                return ListenableBuilder(
                  listenable: listenable,
                  builder: (context, _) {
                    final ranges = _ranges(document.pages.length);
                    final current = controller?.currentPageRange;
                    return ListView.builder(
                      itemCount: ranges.length,
                      itemBuilder: (context, index) {
                        final range = ranges[index];
                        // Highlight every spread/page that overlaps the range currently visible in
                        // the viewport (current can span several spreads when more than one is on
                        // screen).
                        final isCurrent =
                            current != null &&
                            range.firstPageNumber <= current.lastPageNumber &&
                            range.lastPageNumber >= current.firstPageNumber;
                        final label = range.label;
                        return Container(
                          margin: const EdgeInsets.all(8),
                          height: 240,
                          child: Column(
                            children: [
                              SizedBox(
                                key: ValueKey('thumb_${document.hashCode}_${range.firstPageNumber}_${range.lastPageNumber}'),
                                height: 220,
                                child: InkWell(
                                  onTap: () =>
                                      controller?.goToPage(pageNumber: range.firstPageNumber, anchor: PdfPageAnchor.top),
                                  onDoubleTap: () => onDoubleTap(document, range.firstPageNumber),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: isCurrent ? Colors.blue : Colors.transparent, width: 2),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        for (var p = range.firstPageNumber; p <= range.lastPageNumber; p++)
                                          Expanded(
                                            child: PdfPageView(
                                              document: document,
                                              pageNumber: p,
                                              alignment: Alignment.center,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Text(label),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  void onDoubleTap(PdfDocument document, int pageNumber) {
    final pages = document.pages.toList();
    //pages[pageNumber - 1] = pages[pageNumber - 1].rotatedCCW90();
    document.pages = pages..removeAt(pageNumber - 1);
  }
}
