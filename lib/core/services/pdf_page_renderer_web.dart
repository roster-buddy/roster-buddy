import 'dart:js_interop';
import 'dart:typed_data';

@JS('rosterRenderJobCardPage')
external JSPromise<JSUint8Array> _renderPage(JSUint8Array bytes, JSNumber page);

class PdfPageRenderer {
  const PdfPageRenderer();

  Future<Uint8List> renderPage(Uint8List pdfBytes, int pageNumber) async {
    final image = await _renderPage(pdfBytes.toJS, pageNumber.toJS).toDart;
    return image.toDart;
  }
}
