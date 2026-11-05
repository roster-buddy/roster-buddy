import 'dart:js_interop';
import 'dart:typed_data';

@JS('rosterPrepareCloudImage')
external JSPromise<JSUint8Array> _prepare(JSUint8Array bytes, JSString name);

Future<Uint8List> prepareCloudImage(Uint8List bytes, String name) async =>
    (await _prepare(bytes.toJS, name.toJS).toDart).toDart;

@JS('rosterPrepareCloudStamp')
external JSPromise<JSUint8Array> _stamp(JSUint8Array bytes, JSString name);

Future<Uint8List?> prepareCloudStamp(Uint8List bytes, String name) async =>
    (await _stamp(bytes.toJS, name.toJS).toDart).toDart;
