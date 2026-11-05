export 'smart_scan_engine_stub.dart'
    if (dart.library.js_interop) 'smart_scan_engine_web.dart'
    if (dart.library.io) 'smart_scan_engine_mobile.dart';
