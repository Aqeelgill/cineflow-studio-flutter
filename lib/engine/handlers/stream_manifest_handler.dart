import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'download_handler.dart';

class StreamManifestHandler extends DownloadHandler {
  @override
  int get priority => 10;
  @override
  String get name => 'stream-manifest';

  @override
  bool canHandle(Uri uri, {String? mimeType}) {
    final p = uri.path.toLowerCase();
    final m = (mimeType ?? '').toLowerCase();
    return p.endsWith('.m3u8') || p.endsWith('.mpd') ||
        m.contains('mpegurl') || m.contains('dash+xml') || m.contains('application/dash');
  }

  @override
  Future<ProbeResult> probe(Uri uri, {Map<String, String>? headers}) async {
    final h = _headers(headers, uri);
    final res = await http.get(uri, headers: h).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Manifest HTTP ${res.statusCode}');
    final body = res.body;
    final isM3u8 = uri.path.toLowerCase().endsWith('.m3u8') || body.contains('#EXTM3U');
    final segments = isM3u8 ? _parseM3u8(uri, body) : _parseMpd(uri, body);
    final name = _name(uri, isM3u8 ? '.mp4' : '.mp4');
    return ProbeResult(
      resolvedUrl: uri,
      fileName: name,
      totalBytes: null,
      mimeType: isM3u8 ? 'application/vnd.apple.mpegurl' : 'application/dash+xml',
      supportsRange: false,
      isStream: true,
      subEntries: segments.map((s) => {'url': s.toString()}).toList(),
      headers: h,
    );
  }

  @override
  Future<void> execute(DownloadTaskContext ctx) async {
    final ffmpeg = await _which('ffmpeg');
    if (ffmpeg == null) {
      ctx.onDone('Failed', error: 'ffmpeg is required for HLS/DASH manifests');
      return;
    }
    final segUrls = ctx.probe.subEntries
        .map((e) => Uri.tryParse(e['url']?.toString() ?? ''))
        .whereType<Uri>()
        .toList();
    if (segUrls.isEmpty) { ctx.onDone('Failed', error: 'No segments found in manifest'); return; }

    final tmp = await Directory.systemTemp.createTemp('cineflow_seg_');
    try {
      final segFiles = <File>[];
      for (var i = 0; i < segUrls.length; i++) {
        if (ctx.isPaused()) { ctx.onDone('Paused'); return; }
        if (ctx.isCancelled()) { ctx.onDone('Failed', error: 'Cancelled'); return; }
        final seg = segUrls[i];
        final resp = await http.get(seg, headers: ctx.headers).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) throw Exception('Segment $i HTTP ${resp.statusCode}');
        final f = File('${tmp.path}${Platform.pathSeparator}seg_${i.toString().padLeft(5, '0')}.ts');
        await f.writeAsBytes(resp.bodyBytes);
        segFiles.add(f);
        ctx.onProgress((i + 1) / segUrls.length * 90, '--', 'Downloading segments ${i + 1}/${segUrls.length}');
      }
      final listFile = File('${tmp.path}${Platform.pathSeparator}list.txt');
      await listFile.writeAsString(segFiles.map((f) => "file '${f.path.replaceAll("'", "'\\''")}'").join('\n'));
      final outPath = '${ctx.saveDir}${Platform.pathSeparator}${_safe(ctx.fileName)}';
      final proc = await Process.run(ffmpeg, ['-y', '-f', 'concat', '-safe', '0', '-i', listFile.path, '-c', 'copy', outPath]);
      if (proc.exitCode == 0) {
        ctx.onProgress(100, '0 KB/s', 'Completed');
        ctx.onDone('Completed', filePath: outPath);
      } else {
        ctx.onDone('Failed', error: 'ffmpeg exit ${proc.exitCode}: ${proc.stderr}');
      }
    } finally {
      try { await tmp.delete(recursive: true); } catch (_) {}
    }
  }

  List<Uri> _parseM3u8(Uri base, String body) {
    final out = <Uri>[];
    for (final line in LineSplitter.split(body)) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      try { out.add(base.resolve(t)); } catch (_) {}
    }
    return out;
  }

  List<Uri> _parseMpd(Uri base, String body) {
    final out = <Uri>[];
    final re = RegExp(r'<BaseURL[^>]*>([^<]+)</BaseURL>');
    for (final m in re.allMatches(body)) {
      final v = m.group(1)?.trim();
      if (v != null && v.isNotEmpty) {
        try { out.add(base.resolve(v)); } catch (_) {}
      }
    }
    return out;
  }

  Map<String, String> _headers(Map<String, String>? input, Uri uri) => {
        'User-Agent': 'Mozilla/5.0',
        'Accept': '*/*',
        'Referer': input?['Referer'] ?? uri.origin,
        ...?input,
      };

  String _name(Uri uri, String ext) {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    var n = seg.isNotEmpty ? seg.last : 'stream';
    n = n.replaceAll(RegExp(r'\.(m3u8|mpd)$', caseSensitive: false), '');
    if (!n.endsWith('.mp4')) n += ext;
    return n;
  }

  Future<String?> _which(String cmd) async {
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [cmd]);
      if (r.exitCode == 0) return cmd;
    } catch (_) {}
    return null;
  }

  String _safe(String n) {
    final c = n.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return c.isEmpty ? 'stream.mp4' : c;
  }
}
