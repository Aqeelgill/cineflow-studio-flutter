import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../core/lead_models.dart';
import '../core/media_scan_models.dart';

class FileFilterBridge {
  static Future<List<ScannedMediaItem>> scanMedia({String? filePath, String? url}) async {
    final jsonText = await _run(mode: 'media', filePath: filePath, url: url);
    if (jsonText != null) return Isolate.run(() => _mediaFromJson(jsonText));
    return Isolate.run(() => _mediaFallback(filePath: filePath, url: url));
  }

  static Future<List<LeadEntry>> scanLeads({String? filePath, String? url, String? rawContent}) async {
    final jsonText = await _run(mode: 'leads', filePath: filePath, url: url, rawContent: rawContent);
    if (jsonText != null) return Isolate.run(() => _leadsFromJson(jsonText));
    return Isolate.run(() => _leadsFallback(filePath: filePath, url: url, rawContent: rawContent));
  }

  static Future<String?> _run({required String mode, String? filePath, String? url, String? rawContent}) async {
    for (final cmd in ['python3', 'python']) {
      try {
        final args = ['scripts/file_filter_processor.py', '--mode', mode];
        if (filePath != null) args.addAll(['--file', filePath]);
        if (url != null) args.addAll(['--url', url]);
        final proc = await Process.start(cmd, args, workingDirectory: Directory.current.path);
        if (rawContent != null) { proc.stdin.write(rawContent); await proc.stdin.close(); }
        else { await proc.stdin.close(); }
        final outFuture = proc.stdout.transform(utf8.decoder).join();
        final errFuture = proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(const Duration(seconds: 30));
        final out = await outFuture;
        await errFuture;
        if (code == 0 && out.trim().isNotEmpty) return out.trim();
      } catch (_) {}
    }
    return null;
  }

  static List<ScannedMediaItem> _mediaFromJson(String text) {
    try {
      final list = json.decode(text);
      if (list is! List) return [];
      final out = <ScannedMediaItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final item = ScannedMediaItem.fromJson(Map<String, dynamic>.from(e));
        if (item.url.isNotEmpty) out.add(item);
      }
      return out;
    } catch (_) { return []; }
  }

  static List<LeadEntry> _leadsFromJson(String text) {
    try {
      final list = json.decode(text);
      if (list is! List) return [];
      final out = <LeadEntry>[];
      for (final e in list) {
        if (e is! Map) continue;
        final item = LeadEntry.fromJson(Map<String, dynamic>.from(e));
        if (item.email.isNotEmpty || item.phone.isNotEmpty || item.website.isNotEmpty || item.social.isNotEmpty || item.name.isNotEmpty) out.add(item);
      }
      return out;
    } catch (_) { return []; }
  }

  static final _urlRe = RegExp("https?://[^\\s\"'<>\\]\\)]+", caseSensitive: false);
  static final _mediaRe = RegExp(r'\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|ts|m3u8|mpd|mp3|m4a|aac|flac|wav|ogg)(\?|$)', caseSensitive: false);
  static final _mediaKeywords = ['dual audio','multi audio','1080p','720p','480p','2160p','4k','web-dl','hdrip','bluray','x264','x265','hevc','hindi','urdu','dubbed','season','episode'];

  static Future<List<ScannedMediaItem>> _mediaFallback({String? filePath, String? url}) async {
    String content = '';
    if (filePath != null) content = await File(filePath).readAsString();
    else if (url != null) {
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        content = await utf8.decoder.bind(resp).join();
        client.close(force: true);
      } catch (_) {}
    }
    final seen = <String>{};
    final out = <ScannedMediaItem>[];
    for (final m in _urlRe.allMatches(content)) {
      final u = m.group(0)!;
      final low = u.toLowerCase();
      final isMedia = _mediaRe.hasMatch(low) || _mediaKeywords.any((k) => low.contains(k)) || low.contains('youtube.com/watch') || low.contains('youtu.be/');
      if (!isMedia || seen.contains(u)) continue;
      seen.add(u);
      final fmt = _mediaRe.firstMatch(low)?.group(1)?.toUpperCase() ?? 'MEDIA';
      final tag = _mediaKeywords.where((k) => low.contains(k)).take(2).join(' / ');
      final title = u.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => u);
      out.add(ScannedMediaItem(url: u, title: title, format: fmt, tag: tag));
    }
    return out;
  }

  static Future<List<LeadEntry>> _leadsFallback({String? filePath, String? url, String? rawContent}) async {
    String content = rawContent ?? '';
    if (filePath != null) content = await File(filePath).readAsString();
    else if (url != null) {
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        content = await utf8.decoder.bind(resp).join();
        client.close(force: true);
      } catch (_) {}
    }
    final email = RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false);
    final phone = RegExp(r'(?:\+?\d[\d\s().-]{7,}\d)');
    final out = <LeadEntry>[];
    final seen = <String>{};
    for (final m in email.allMatches(content)) { final v = m.group(0)!; if (seen.add('e:$v')) out.add(LeadEntry(email: v)); }
    for (final m in phone.allMatches(content)) { final v = m.group(0)!; if (seen.add('p:$v')) out.add(LeadEntry(phone: v)); }
    for (final m in _urlRe.allMatches(content)) { final v = m.group(0)!; if (v.contains('facebook.com') || v.contains('linkedin.com')) { if (seen.add('s:$v')) out.add(LeadEntry(social: v)); } }
    return out;
  }
}
