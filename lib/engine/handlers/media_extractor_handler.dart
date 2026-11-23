import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'download_handler.dart';

class MediaExtractorHandler extends DownloadHandler {
  @override
  int get priority => 20;
  @override
  String get name => 'media-extractor';

  static const _hosts = [
    'youtube.com', 'youtu.be', 'facebook.com', 'fb.watch',
    'dailymotion.com', 'vimeo.com', 'tiktok.com', 'instagram.com',
    'twitter.com', 'x.com', 'twitch.tv', 'soundcloud.com',
  ];

  @override
  bool canHandle(Uri uri, {String? mimeType}) {
    final host = uri.host.toLowerCase();
    return _hosts.any((h) => host == h || host.endsWith('.$h')) ||
        uri.path.toLowerCase().contains('/playlist');
  }

  @override
  Future<ProbeResult> probe(Uri uri, {Map<String, String>? headers}) async {
    final name = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? uri.host;
    return ProbeResult(
      resolvedUrl: uri,
      fileName: '$name.mp4',
      totalBytes: null,
      mimeType: 'video/mp4',
      supportsRange: false,
      isStream: false,
      headers: headers ?? const {},
    );
  }

  @override
  Future<void> execute(DownloadTaskContext ctx) async {
    final ytdlp = await _resolveYtDlp();
    if (ytdlp == null) {
      ctx.onDone('Failed', error: 'yt-dlp not found on PATH');
      return;
    }
    final ffmpeg = await _which('ffmpeg');
    final args = <String>[
      '--newline', '--no-playlist',
      '-f', 'bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b',
      if (ffmpeg != null) ...['--merge-output-format', 'mp4'],
      '-o', '${ctx.saveDir}${Platform.pathSeparator}%(title)s.%(ext)s',
      ctx.url.toString(),
    ];
    final proc = await Process.start(ytdlp, args);
    final pct = RegExp(r'\[download\]\s+(\d+\.?\d*)%.*?at\s+(\S+)');
    final dest = RegExp(r'Destination:\s+(.*)$');
    final merge = RegExp(r'Merging formats into "(.+)"');
    final err = <String>[];
    String? outPath;
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final m = pct.firstMatch(line);
      if (m != null) {
        final p = double.tryParse(m.group(1) ?? '0') ?? 0;
        ctx.onProgress(p, m.group(2) ?? '--', 'Downloading');
      }
      final d = dest.firstMatch(line); if (d != null) outPath = d.group(1)!.trim();
      final mg = merge.firstMatch(line); if (mg != null) outPath = mg.group(1)!.trim();
    });
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) { if (l.trim().isNotEmpty) err.add(l.trim()); });
    while (true) {
      final code = await proc.exitCode.timeout(const Duration(milliseconds: 300), onTimeout: () => -999);
      if (ctx.isPaused() || ctx.isCancelled()) { try { proc.kill(); } catch (_) {} ctx.onDone('Paused', filePath: outPath); return; }
      if (code != -999) {
        if (code == 0) { ctx.onProgress(100, '0 KB/s', 'Completed'); ctx.onDone('Completed', filePath: outPath); }
        else { ctx.onDone('Failed', error: err.isNotEmpty ? err.last : 'yt-dlp exit $code'); }
        return;
      }
    }
  }

  Future<String?> _resolveYtDlp() async {
    for (final c in ['yt-dlp', '/usr/local/bin/yt-dlp', '/usr/bin/yt-dlp']) {
      if (!c.contains('/')) { final w = await _which(c); if (w != null) return w; }
      else if (await File(c).exists()) return c;
    }
    return null;
  }

  Future<String?> _which(String cmd) async {
    try { final r = await Process.run(Platform.isWindows ? 'where' : 'which', [cmd]); if (r.exitCode == 0) return cmd; } catch (_) {}
    return null;
  }
}
