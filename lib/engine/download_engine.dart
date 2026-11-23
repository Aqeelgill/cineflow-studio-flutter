import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

import '../core/app_categories.dart';
import '../core/download_paths.dart';
import 'handlers/download_handler.dart';
import 'handlers/handler_registry.dart';

enum DownloadQuality { best4k, p1080, p720, audioMp3 }

extension DownloadQualityX on DownloadQuality {
  String get label {
    switch (this) {
      case DownloadQuality.best4k: return 'Best / 4K';
      case DownloadQuality.p1080: return '1080p';
      case DownloadQuality.p720: return '720p';
      case DownloadQuality.audioMp3: return 'Audio MP3';
    }
  }
}

class DownloadItem {
  final String id;
  String url;
  String title;
  String platform;
  double progress;
  String speed;
  String status;
  String filePath;
  String? error;
  bool selected;
  DownloadQuality quality;
  AppCategory category;
  Map<String, String> headers;
  String? proxyUrl;
  CancelToken? cancelToken;
  Process? ytProcess;
  bool paused;
  int retries;
  DateTime createdAt;

  DownloadItem({
    required this.id,
    required this.url,
    this.title = 'Ready',
    this.platform = 'Web',
    this.progress = 0.0,
    this.speed = '--',
    this.status = 'Queued',
    this.filePath = '',
    this.error,
    this.selected = false,
    this.quality = DownloadQuality.best4k,
    AppCategory? category,
    Map<String, String>? headers,
    this.proxyUrl,
    this.paused = false,
    this.retries = 0,
    DateTime? createdAt,
  }) : category = category ?? AppCategories.webSeries,
       headers = headers ?? {},
       createdAt = createdAt ?? DateTime.now();
}

class EpisodeInfo {
  final String url;
  final String title;
  final String duration;
  final int index;
  bool selected;
  EpisodeInfo({required this.url, required this.title, required this.duration, required this.index, this.selected = true});
}

class UniversalDownloadEngine {
  final HandlerRegistry handlers;

  UniversalDownloadEngine({HandlerRegistry? registry}) : handlers = registry ?? HandlerRegistry();

  static const Set<String> directExts = {
    '.pdf','.docx','.xlsx','.csv','.xml','.svg','.gif','.jpg','.jpeg','.png','.webp','.zip','.mp4','.mp3'
  };

  bool isDirectFile(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase().split('?').first;
    return directExts.any((ext) => path.endsWith(ext));
  }

  String getDefaultSaveDirectory({bool? windows}) {
    final isWin = windows ?? Platform.isWindows;
    return DownloadPaths.rootFor(isWindows: isWin);
  }

  Future<String> ensureCategoryDir(String root, AppCategory category) async {
    final dir = await DownloadPaths.ensureCategoryDir(root, category, isWindows: Platform.isWindows);
    return dir.path;
  }

  Future<List<String>> scanWebpage(String pageUrl) async {
    final res = await http.get(Uri.parse(pageUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    });
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final doc = html_parser.parse(res.body);
    final baseUri = Uri.parse(pageUrl);
    final Set<String> found = {};
    void addCandidate(String? raw) {
      if (raw == null) return;
      final v = raw.trim();
      if (v.isEmpty || v.startsWith('#') || v.startsWith('javascript:') || v.startsWith('mailto:') || v.startsWith('tel:')) return;
      try {
        final abs = baseUri.resolve(v);
        if (abs.scheme != 'http' && abs.scheme != 'https') return;
        final low = abs.toString().toLowerCase();
        final p = abs.path.toLowerCase();
        if (directExts.any((e) => p.endsWith(e)) || low.contains('youtube.com/watch') || low.contains('youtu.be/') || low.contains('/video') || low.contains('playlist') || low.contains('dailymotion.com') || low.contains('facebook.com')) {
          found.add(abs.toString());
        }
      } catch (_) {}
    }
    for (final el in doc.querySelectorAll('[href],[src],[data-src]')) {
      addCandidate(el.attributes['href']);
      addCandidate(el.attributes['src']);
      addCandidate(el.attributes['data-src']);
    }
    return found.toList();
  }

  Future<List<String>> parseFileLinks(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('File not found: $filePath');
    final lower = filePath.toLowerCase();
    String content;
    if ({'.txt','.csv','.xml','.svg'}.any((e) => lower.endsWith(e))) {
      content = await file.readAsString();
    } else {
      content = latin1.decode(await file.readAsBytes(), allowInvalid: true);
    }
    final regex = RegExp(r'https?://[^\s<>"\x27\)\]\}]+', caseSensitive: false);
    return regex.allMatches(content).map((m) => m.group(0)!.replaceAll(RegExp(r'''[.,;:!?]+$'''), '')).where((u) => Uri.tryParse(u) != null).toSet().toList();
  }

  Future<void> startDownload(DownloadItem item, String rootSaveDir, void Function() onUpdate, {int maxConcurrentChunks = 4}) async {
    item.paused = false;
    item.error = null;
    item.status = 'Downloading';
    item.progress = item.progress < 0 ? 0 : item.progress;
    onUpdate();
    final saveDir = await ensureCategoryDir(rootSaveDir, item.category);
    final uri = Uri.parse(item.url);
    ProbeResult probe;
    try {
      probe = await handlers.probeUrl(item.url, headers: item.headers);
    } catch (_) {
      probe = ProbeResult(resolvedUrl: uri, fileName: item.title, totalBytes: null, mimeType: null, supportsRange: false, isStream: false, headers: item.headers);
    }
    final handler = handlers.resolveHandler(uri, probe);
    item.platform = handler.name;
    final ctx = DownloadTaskContext(
      taskId: item.id,
      url: Uri.parse(item.url),
      headers: item.headers,
      proxyUrl: item.proxyUrl,
      saveDir: saveDir,
      fileName: probe.fileName.isNotEmpty ? probe.fileName : item.title,
      probe: probe,
      maxConcurrentChunks: maxConcurrentChunks,
      isPaused: () => item.paused,
      isCancelled: () => false,
      onProgress: (p, speed, status) {
        item.progress = p; item.speed = speed; item.status = status; onUpdate();
      },
      onDone: (status, {error, filePath}) {
        item.status = status;
        if (error != null) item.error = error;
        if (filePath != null) item.filePath = filePath;
        if (status == 'Completed') { item.progress = 100; item.speed = '0 KB/s'; }
        onUpdate();
      },
    );
    try {
      if (isDirectFile(item.url) || handler.name == 'http-range') {
        await handler.execute(ctx);
      } else {
        await handler.execute(ctx);
      }
    } on DownloadPaused {
      item.status = 'Paused'; onUpdate();
    } on DownloadCancelled {
      item.status = 'Paused'; onUpdate();
    } catch (e) {
      if (item.paused) { item.status = 'Paused'; onUpdate(); return; }
      item.status = 'Failed'; item.error = e.toString(); onUpdate();
    }
  }

  void pauseItem(DownloadItem item) {
    item.paused = true;
    item.status = 'Paused';
    item.speed = '--';
    try { item.cancelToken?.cancel('Paused'); } catch (_) {}
    item.cancelToken = null;
    try { item.ytProcess?.kill(); } catch (_) {}
    item.ytProcess = null;
  }

  void updateTaskSource(DownloadItem item, {String? newUrl, Map<String, String>? newHeaders, String? proxyUrl}) {
    pauseItem(item);
    if (newUrl != null && newUrl.trim().isNotEmpty) item.url = newUrl.trim();
    if (newHeaders != null) item.headers = {...item.headers, ...newHeaders};
    if (proxyUrl != null) item.proxyUrl = proxyUrl.trim().isEmpty ? null : proxyUrl.trim();
    item.status = 'Queued';
    item.error = null;
  }

  Future<List<EpisodeInfo>> fetchPlaylist(String url) async {
    final yt = await _resolveYtDlp();
    final res = await Process.run(yt, ['--flat-playlist', '-J', url]);
    if (res.exitCode != 0) throw Exception((res.stderr as String?)?.trim() ?? 'yt-dlp failed');
    final data = json.decode((res.stdout as String).trim());
    final entries = (data is Map && data['entries'] is List) ? data['entries'] as List : (data is List ? data : const []);
    final out = <EpisodeInfo>[]; var i = 0;
    for (final e in entries) {
      if (e is! Map) continue; i++;
      final id = '${e['id'] ?? ''}';
      var epUrl = '${e['webpage_url'] ?? ''}';
      if (epUrl.isEmpty) {
        final raw = '${e['url'] ?? ''}';
        if (raw.startsWith('http')) epUrl = raw;
        else if (id.isNotEmpty) epUrl = 'https://www.youtube.com/watch?v=$id';
      }
      if (epUrl.isEmpty) continue;
      final durVal = e['duration'];
      String dur = '--:--';
      if (durVal is num) {
        final t = durVal.round();
        final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
        dur = h > 0 ? '$h:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}' : '$m:${s.toString().padLeft(2,'0')}';
      }
      out.add(EpisodeInfo(url: epUrl, title: '${e['title'] ?? 'Episode $i'}', duration: dur, index: i));
    }
    return out;
  }

  Future<String> _resolveYtDlp() async {
    for (final c in ['yt-dlp', '/usr/local/bin/yt-dlp', '/usr/bin/yt-dlp']) {
      if (c.contains('/')) { if (await File(c).exists()) return c; }
      else { try { final r = await Process.run(Platform.isWindows ? 'where' : 'which', [c]); if (r.exitCode == 0) return c; } catch (_) {} }
    }
    return 'yt-dlp';
  }
}
