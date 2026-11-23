import 'dart:io';

import 'download_handler.dart';

class FtpHandler extends DownloadHandler {
  @override
  int get priority => 30;
  @override
  String get name => 'ftp';

  @override
  bool canHandle(Uri uri, {String? mimeType}) {
    final s = uri.scheme.toLowerCase();
    return s == 'ftp' || s == 'ftps';
  }

  @override
  Future<ProbeResult> probe(Uri uri, {Map<String, String>? headers}) async {
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'ftp_download.bin';
    // FTP probing is best-effort; execution uses curl/wget/ftp client availability.
    return ProbeResult(
      resolvedUrl: uri,
      fileName: fileName.isEmpty ? 'ftp_download.bin' : fileName,
      totalBytes: null,
      mimeType: 'application/octet-stream',
      supportsRange: false,
      isStream: false,
      headers: headers ?? const {},
    );
  }

  @override
  Future<void> execute(DownloadTaskContext ctx) async {
    final outPath = '${ctx.saveDir}${Platform.pathSeparator}${_safe(ctx.fileName)}';
    final out = File(outPath);
    await out.parent.create(recursive: true);
    int existing = await out.exists() ? await out.length() : 0;

    final curl = await _which('curl');
    if (curl != null) {
      final args = <String>['-L', '--fail', '--continue-at', '$existing', '-o', outPath, ctx.url.toString()];
      final proc = await Process.start(curl, args);
      await _drain(proc, ctx, out);
      final code = await proc.exitCode;
      if (ctx.isPaused()) { ctx.onDone('Paused', filePath: outPath); return; }
      if (code == 0) { ctx.onDone('Completed', filePath: outPath); } else { ctx.onDone('Failed', error: 'curl exit $code'); }
      return;
    }
    final wget = await _which('wget');
    if (wget != null) {
      final args = <String>['-c', '-O', outPath, ctx.url.toString()];
      final proc = await Process.start(wget, args);
      await _drain(proc, ctx, out);
      final code = await proc.exitCode;
      if (ctx.isPaused()) { ctx.onDone('Paused', filePath: outPath); return; }
      if (code == 0) { ctx.onDone('Completed', filePath: outPath); } else { ctx.onDone('Failed', error: 'wget exit $code'); }
      return;
    }
    ctx.onDone('Failed', error: 'FTP download requires curl or wget on PATH');
  }

  Future<void> _drain(Process proc, DownloadTaskContext ctx, File out) async {
    proc.stdout.drain();
    proc.stderr.drain();
    while (true) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (ctx.isPaused() || ctx.isCancelled()) {
        try { proc.kill(); } catch (_) {}
        return;
      }
      if (await out.exists()) {
        final len = await out.length();
        ctx.onProgress(0, '--', 'Downloading FTP ${len ~/ 1024} KB');
      }
      // break when process exits
      final exited = await proc.exitCode.timeout(const Duration(milliseconds: 1), onTimeout: () => -999);
      if (exited != -999) return;
    }
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
    return c.isEmpty ? 'ftp_download.bin' : c;
  }
}
