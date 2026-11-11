import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

class PdfRenderedPage {
  const PdfRenderedPage({required this.pageNumber, required this.pngBytes});

  final int pageNumber;
  final Uint8List pngBytes;
}

class PdfPageRenderer {
  const PdfPageRenderer();

  Future<Uint8List> renderPage(Uint8List pdfBytes, int pageNumber) async {
    final document = await PdfDocument.openData(pdfBytes);
    try {
      final page = await document.getPage(pageNumber);
      try {
        final image = await page.render(
          width: page.width * 2.5,
          height: page.height * 2.5,
          format: PdfPageImageFormat.png,
        );
        if (image == null) throw StateError('The PDF page could not be rendered.');
        return image.bytes;
      } finally {
        await page.close();
      }
    } finally {
      await document.close();
    }
  }

  Future<List<PdfRenderedPage>> render(Uint8List pdfBytes) async {
    final document = await PdfDocument.openData(pdfBytes);

    final pages = <PdfRenderedPage>[];

    try {
      for (int i = 1; i <= document.pagesCount; i++) {
        final page = await document.getPage(i);

        try {
          final image = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.png,
          );

          if (image != null) {
            pages.add(PdfRenderedPage(pageNumber: i, pngBytes: image.bytes));
          }
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }

    return pages;
  }
}
