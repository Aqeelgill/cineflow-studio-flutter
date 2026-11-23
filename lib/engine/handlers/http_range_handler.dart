import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../chunk_downloader.dart';
import 'download_handler.dart';

class HttpRangeHandler extends DownloadHandler {
  @override
  int get priority => 50;
  @override
  String get name => 'http-range';

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  @override
  bool canHandle(Uri uri, {String? mimeType}) {
    final s = uri.scheme.toLowerCase();
    return s == 'http' || s == 'https';
  }

  Map<String, String> _realisticHeaders(Map<String, String>? input, Uri uri) {
    return <String, String>{
      'User-Agent': _ua,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': input?['Referer'] ?? input?['referer'] ?? uri.origin,
      ...?input,
    };
  }

  @override
  Future<ProbeResult> probe(Uri uri, {Map<String, String>? headers}) async {
    final h = _realisticHeaders(headers, uri);
    int? total;
    String? mime;
    bool supportsRange = false;
    String fileName = _nameFromUri(uri);
    Uri resolved = uri;

    try {
      final head = await http.head(uri, headers: h).timeout(const Duration(seconds: 15));
      resolved = head.request?.url ?? uri;
      mime = head.headers['content-type']?.split(';').first.trim();
      total = int.tryParse(head.headers['content-length'] ?? '');
      supportsRange = (head.headers['accept-ranges'] ?? '').toLowerCase().contains('bytes');
      fileName = _fileNameFromHeaders(head.headers, resolved) ?? fileName;
      if (!supportsRange || total == null) {
        final range = await http.get(uri, headers: {...h, 'Range': 'bytes=0-0'})
            .timeout(const Duration(seconds: 15));
        supportsRange = range.statusCode == 206;
        final cr = range.headers['content-range'];
        final m = RegExp(r'/(\d+)').firstMatch(cr ?? '');
        if (m != null) total = int.tryParse(m.group(1)!);
        mime ??= range.headers['content-type']?.split(';').first.trim();
        fileName = _fileNameFromHeaders(range.headers, resolved) ?? fileName;
      }
    } catch (_) {}

    return ProbeResult(
      resolvedUrl: resolved,
      fileName: fileName,
      totalBytes: total,
      mimeType: mime,
      supportsRange: supportsRange && (total ?? 0) > 0,
      isStream: false,
      headers: h,
    );
  }

  @override
  Future<void> execute(DownloadTaskContext ctx) async {
    final out = File('${ctx.saveDir}${Platform.pathSeparator}${_safe(ctx.fileName)}');
    await out.parent.create(recursive: true);
    final dl = ChunkDownloader();
    await dl.download(
      url: ctx.url.toString(),
      outputFile: out,
      totalBytes: ctx.probe.totalBytes,
      supportsRange: ctx.probe.supportsRange,
      headers: _realisticHeaders(ctx.headers, ctx.url),
      proxyUrl: ctx.proxyUrl,
      maxConcurrentChunks: ctx.maxConcurrentChunks,
      onProgress: ctx.onProgress,
      isPaused: ctx.isPaused,
      isCancelled: ctx.isCancelled,
    );
    ctx.onDone('Completed', filePath: out.path);
  }

  static String _safe(String n) {
    final c = n.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return c.isEmpty ? 'download.bin' : c;
  }

  static String _nameFromUri(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return 'download.bin';
    return Uri.decodeComponent(segs.last);
  }

  static String? _fileNameFromHeaders(Map<String, String> headers, Uri uri) {
    final cd = headers['content-disposition'] ?? headers['Content-Disposition'];
    if (cd != null) {
      final m = RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^"';]+)''').firstMatch(cd);
      if (m != null) return Uri.decodeComponent(m.group(1)!.trim());
    }
    final n = _nameFromUri(uri);
    return n.contains('.') ? n : null;
  }
}
