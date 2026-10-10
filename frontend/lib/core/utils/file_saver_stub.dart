/// Stub implementation for non-web environments (tests, VM).
void downloadFile(List<int> bytes, String filename, String mimeType) {
  // No-op in headless test environment
}

String? createBlobUrl(List<int> bytes, String mimeType) {
  return null;
}

void openInNewTab(List<int> bytes, String mimeType) {
  // No-op in headless test environment
}
