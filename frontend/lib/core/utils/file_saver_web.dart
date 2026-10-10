import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation using browser Blob and Anchor elements.
void downloadFile(List<int> bytes, String filename, String mimeType) {
  final uint8List = Uint8List.fromList(bytes);
  final blobParts = [uint8List.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

String? createBlobUrl(List<int> bytes, String mimeType) {
  final uint8List = Uint8List.fromList(bytes);
  final blobParts = [uint8List.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  return web.URL.createObjectURL(blob);
}

void openInNewTab(List<int> bytes, String mimeType) {
  final uint8List = Uint8List.fromList(bytes);
  final blobParts = [uint8List.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
}
