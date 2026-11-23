import 'download_handler.dart';
import 'ftp_handler.dart';
import 'http_range_handler.dart';
import 'media_extractor_handler.dart';
import 'stream_manifest_handler.dart';

class HandlerRegistry {
  final List<DownloadHandler> _handlers;

  HandlerRegistry({List<DownloadHandler>? handlers})
      : _handlers = handlers ??
            [
              StreamManifestHandler(),
              MediaExtractorHandler(),
              FtpHandler(),
              HttpRangeHandler(),
            ] {
    _handlers.sort((a, b) => a.priority.compareTo(b.priority));
  }

  List<DownloadHandler> get handlers => List.unmodifiable(_handlers);

  void register(DownloadHandler handler) {
    _handlers.add(handler);
    _handlers.sort((a, b) => a.priority.compareTo(b.priority));
  }

  Future<ProbeResult> probeUrl(String rawUrl,
      {Map<String, String>? headers}) async {
    final uri = Uri.parse(rawUrl.trim());
    final handler = resolveHandlerForUri(uri);
    return handler.probe(uri, headers: headers);
  }

  DownloadHandler resolveHandler(Uri uri, ProbeResult probe) {
    for (final h in _handlers) {
      if (h.canHandle(uri, mimeType: probe.mimeType)) return h;
    }
    return _handlers.last;
  }

  DownloadHandler resolveHandlerForUri(Uri uri, {String? mimeType}) {
    for (final h in _handlers) {
      if (h.canHandle(uri, mimeType: mimeType)) return h;
    }
    return _handlers.last;
  }
}
