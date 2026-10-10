import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// Trigger a file download in the browser (or save on supported platforms).
void downloadFile(List<int> bytes, String filename, String mimeType) =>
    impl.downloadFile(bytes, filename, mimeType);

/// Create an object URL from bytes (web only).
String? createBlobUrl(List<int> bytes, String mimeType) =>
    impl.createBlobUrl(bytes, mimeType);

/// Open file in new browser tab (web only).
void openInNewTab(List<int> bytes, String mimeType) =>
    impl.openInNewTab(bytes, mimeType);
