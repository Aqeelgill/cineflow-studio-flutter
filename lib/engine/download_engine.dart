import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

enum DownloadQuality { best4k, p1080, p720, audioMp3 }

extension DownloadQualityX on DownloadQuality {
  String get label {
    switch (this) {
      case DownloadQuality.best4k:
        return 'Best / 4K';
      case DownloadQuality.p1080:
        return '1080p';
      case DownloadQuality.p720:
        return '720p';
      case DownloadQuality.audioMp3:
        return 'Audio MP3';
    }
  }

  static DownloadQuality fromLabel(String label) {
    for (final q in DownloadQuality.values) {
      if (q.label == label) return q;
    }
    return DownloadQuality.best4k;
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
  CancelToken? cancelToken;
  Process? ytProcess;
  bool paused;

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
    this.paused = false,
  });
}

class EpisodeInfo {
  final String url;
  final String title;
  final String duration;
  final int index;
  bool selected;

  EpisodeInfo({
    required this.url,
    required this.title,
    required this.duration,
    required this.index,
    this.selected = true,
  });
}

class UniversalDownloadEngine {
  final Dio _dio = Dio();
  bool? _ffmpegAvailable;

  static const Set<String> directExts = {
    '.pdf',
    '.docx',
    '.xlsx',
    '.csv',
    '.xml',
    '.svg',
    '.gif',
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.zip',
    '.mp4',
    '.mp3',
  };

  static const Set<String> textLinkExts = {
    '.txt',
    '.csv',
    '.xml',
    '.svg',
  };

  bool isDirectFile(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase().split('?').first;
    return directExts.any((ext) => path.endsWith(ext));
  }

  Future<String> getDefaultSaveDirectory() async {
    String base;
    if (Platform.isWindows) {
      base = Platform.environment['USERPROFILE'] ?? Directory.current.path;
      base = '$base\\Downloads';
    } else {
      base = Platform.environment['HOME'] ?? Directory.current.path;
      base = '$base/Downloads';
    }
    final cineDir = Directory('$base${Platform.pathSeparator}CineFlow');
    if (!await cineDir.exists()) {
      await cineDir.create(recursive: true);
    }
    return cineDir.path;
  }

  Future<List<String>> scanWebpage(String pageUrl) async {
    final res = await http.get(Uri.parse(pageUrl), headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    });
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final doc = html_parser.parse(res.body);
    final baseUri = Uri.parse(pageUrl);
    final Set<String> found = {};

    void addCandidate(String? raw) {
      if (raw == null) return;
      final v = raw.trim();
      if (v.isEmpty ||
          v.startsWith('#') ||
          v.toLowerCase().startsWith('javascript:') ||
          v.toLowerCase().startsWith('mailto:') ||
          v.toLowerCase().startsWith('tel:')) {
        return;
      }
      Uri abs;
      try {
        abs = baseUri.resolve(v);
      } catch (_) {
        return;
      }
      if (abs.scheme != 'http' && abs.scheme != 'https') return;
      final s = abs.toString();
      final low = s.toLowerCase();
      final path = abs.path.toLowerCase();
      if (directExts.any((ext) => path.endsWith(ext)) ||
          low.contains('youtube.com/watch') ||
          low.contains('youtu.be/') ||
          low.contains('dailymotion.com/video') ||
          low.contains('facebook.com/') ||
          low.contains('/video/') ||
          low.contains('/watch') ||
          low.contains('playlist')) {
        found.add(s);
      }
    }

    for (final el in doc.querySelectorAll('[href], [src], [data-src]')) {
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
    if (textLinkExts.any((ext) => lower.endsWith(ext))) {
      content = await file.readAsString();
    } else {
      final bytes = await file.readAsBytes();
      content = latin1.decode(bytes, allowInvalid: true);
    }
    final regex = RegExp(r'https?://[^\s<>"\x27\)\]\}]+', caseSensitive: false);
    final matches = regex.allMatches(content).map((m) {
      var url = m.group(0)!;
      url = url.replaceAll(RegExp(r'''[.,;:!?]+$'''), '');
      return url;
    }).where((u) => Uri.tryParse(u) != null);
    return matches.toSet().toList();
  }

  Future<void> startDownload(
    DownloadItem item,
    String saveDir,
    void Function() onUpdate,
  ) async {
    item.paused = false;
    item.error = null;
    item.status = 'Downloading';
    if (item.progress < 0) item.progress = 0;
    onUpdate();

    if (isDirectFile(item.url) || Platform.isAndroid || Platform.isIOS) {
      await _downloadDirect(item, saveDir, onUpdate);
    } else {
      await _downloadWithYtDlp(item, saveDir, onUpdate);
    }
  }

  String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return cleaned.trim().isEmpty ? 'download' : cleaned.trim();
  }

  Future<void> _downloadDirect(
    DownloadItem item,
    String saveDir,
    void Function() onUpdate,
  ) async {
    try {
      final uri = Uri.parse(item.url);
      var name = uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
          ? uri.pathSegments.last
          : 'cineflow_${DateTime.now().millisecondsSinceEpoch}.bin';
      name = _safeFileName(Uri.decodeComponent(name));
      item.title = name;
      item.platform = 'Direct';
      final fullPath = '$saveDir${Platform.pathSeparator}$name';
      final partPath = '$fullPath.part';
      item.filePath = fullPath;
      item.cancelToken = CancelToken();
      item.paused = false;

      final partFile = File(partPath);
      int existing = 0;
      if (await partFile.exists()) {
        existing = await partFile.length();
      }

      final headers = <String, dynamic>{};
      if (existing > 0) {
        headers['Range'] = 'bytes=$existing-';
      }

      final response = await _dio.get<ResponseBody>(
        item.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
        cancelToken: item.cancelToken,
      );

      if (response.statusCode == 416) {
        if (await partFile.exists()) {
          await partFile.rename(fullPath);
        }
        item.progress = 100;
        item.status = 'Completed';
        item.speed = '0 KB/s';
        onUpdate();
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('HTTP ${response.statusCode}');
      }

      int startAt = existing;
      IOSink sink;
      if (response.statusCode == 206 && existing > 0) {
        sink = partFile.openWrite(mode: FileMode.append);
      } else {
        startAt = 0;
        sink = partFile.openWrite(mode: FileMode.write);
      }

      final totalHeader = response.headers.value('content-length');
      final contentLen = int.tryParse(totalHeader ?? '') ?? 0;
      final total = contentLen > 0 ? contentLen + startAt : 0;

      int received = startAt;
      int lastBytes = startAt;
      DateTime lastTime = DateTime.now();

      final stream = response.data?.stream;
      if (stream == null) {
        await sink.close();
        throw Exception('Empty response stream');
      }

      await for (final chunk in stream) {
        if (item.paused) {
          await sink.close();
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          item.progress = (received / total) * 100;
        } else if (item.progress < 99) {
          item.progress = item.progress;
        }
        final now = DateTime.now();
        final diffMs = now.difference(lastTime).inMilliseconds;
        if (diffMs >= 500) {
          final bps = ((received - lastBytes) * 1000) / diffMs;
          item.speed = _formatSpeed(bps);
          lastBytes = received;
          lastTime = now;
          onUpdate();
        }
      }

      await sink.flush();
      await sink.close();

      if (item.paused) return;

      final finalFile = File(fullPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(fullPath);

      item.progress = 100;
      item.status = 'Completed';
      item.speed = '0 KB/s';
      item.error = null;
      onUpdate();
    } catch (e) {
      if (item.paused || item.status == 'Paused') {
        item.status = 'Paused';
        onUpdate();
        return;
      }
      if (e is DioException && CancelToken.isCancel(e)) {
        if (item.paused) {
          item.status = 'Paused';
        }
        onUpdate();
        return;
      }
      item.status = 'Failed';
      item.error = e.toString();
      onUpdate();
    }
  }

  String _formatSpeed(double bps) {
    if (bps <= 0) return '0 KB/s';
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(bps / 1024).toStringAsFixed(1)} KB/s';
  }

  Future<bool> _hasFfmpeg() async {
    if (_ffmpegAvailable != null) return _ffmpegAvailable!;
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final res = await Process.run(cmd, ['ffmpeg']);
      _ffmpegAvailable = res.exitCode == 0;
    } catch (_) {
      _ffmpegAvailable = false;
    }
    return _ffmpegAvailable!;
  }

  Future<String> _resolveYtDlp() async {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[
      if (home.isNotEmpty) '$home/CineFlow_Windows_Prototype/venv/bin/yt-dlp',
      if (home.isNotEmpty) '$home/.local/bin/yt-dlp',
      '/usr/local/bin/yt-dlp',
      '/usr/bin/yt-dlp',
      'yt-dlp',
      'yt-dlp.exe',
    ];
    for (final c in candidates) {
      if (c.contains(Platform.pathSeparator) || c.contains('/')) {
        if (await File(c).exists()) return c;
      }
    }
    return Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
  }

  List<String> _formatArgs(DownloadQuality quality, bool ffmpeg) {
    switch (quality) {
      case DownloadQuality.p1080:
        return ['-f', 'bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b'];
      case DownloadQuality.p720:
        return ['-f', 'bv*[height<=720]+ba/b[height<=720]/bv*+ba/b'];
      case DownloadQuality.audioMp3:
        if (ffmpeg) {
          return ['-x', '--audio-format', 'mp3', '-f', 'ba/b'];
        }
        return ['-f', 'ba/b'];
      case DownloadQuality.best4k:
        return ['-f', 'bv*+ba/b'];
    }
  }

  Future<void> _downloadWithYtDlp(
    DownloadItem item,
    String saveDir,
    void Function() onUpdate,
  ) async {
    try {
      item.platform = 'Web Video';
      item.paused = false;
      final ytCmd = await _resolveYtDlp();
      final ffmpeg = await _hasFfmpeg();
      final args = <String>[
        '--newline',
        '--no-playlist',
        ..._formatArgs(item.quality, ffmpeg),
        if (ffmpeg && item.quality != DownloadQuality.audioMp3) ...[
          '--merge-output-format',
          'mp4',
        ],
        '-o',
        '$saveDir${Platform.pathSeparator}%(title)s.%(ext)s',
        item.url,
      ];

      Future<int> runOnce(List<String> runArgs) async {
        final proc = await Process.start(ytCmd, runArgs);
        item.ytProcess = proc;
        final List<String> errLines = [];
        final pctRegex = RegExp(
          r'\[download\]\s+(\d+\.?\d*)%.*?at\s+(\S+)',
          caseSensitive: false,
        );
        final destRegex = RegExp(r'Destination:\s+(.*)$');
        final mergerRegex = RegExp(r'\[Merger\] Merging formats into "(.+)"');

        proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          final m = pctRegex.firstMatch(line);
          if (m != null) {
            item.progress = double.tryParse(m.group(1) ?? '0') ?? item.progress;
            item.speed = m.group(2) ?? '--';
            item.status = 'Downloading';
            onUpdate();
          }
          final d = destRegex.firstMatch(line);
          if (d != null) {
            final p = d.group(1)!.trim();
            item.filePath = p;
            item.title = p.split(Platform.pathSeparator).last;
            onUpdate();
          }
          final mg = mergerRegex.firstMatch(line);
          if (mg != null) {
            final p = mg.group(1)!.trim();
            item.filePath = p;
            item.title = p.split(Platform.pathSeparator).last;
            onUpdate();
          }
          if (line.contains('has already been downloaded')) {
            item.progress = 100;
          }
        });

        proc.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          final t = line.trim();
          if (t.isNotEmpty) errLines.add(t);
        });

        final code = await proc.exitCode;
        item.ytProcess = null;
        if (code != 0 && item.error == null && errLines.isNotEmpty) {
          item.error = errLines.last;
        }
        return code;
      }

      var code = await runOnce(args);

      if (item.paused || item.status == 'Paused') return;

      if (code != 0 && ffmpeg && item.quality != DownloadQuality.audioMp3) {
        final err = (item.error ?? '').toLowerCase();
        if (err.contains('merg') ||
            err.contains('ffmpeg') ||
            err.contains('postprocess') ||
            err.contains('requested format')) {
          item.error = null;
          final fallbackArgs = <String>[
            '--newline',
            '--no-playlist',
            '-f',
            'best',
            '-o',
            '$saveDir${Platform.pathSeparator}%(title)s.%(ext)s',
            item.url,
          ];
          code = await runOnce(fallbackArgs);
        }
      }

      if (item.paused || item.status == 'Paused') return;

      if (code == 0) {
        item.progress = 100;
        item.status = 'Completed';
        item.speed = '0 KB/s';
        item.error = null;
      } else {
        item.status = 'Failed';
        item.error ??= 'Exit code $code';
      }
      onUpdate();
    } catch (e) {
      if (item.paused || item.status == 'Paused') {
        item.status = 'Paused';
        onUpdate();
        return;
      }
      item.status = 'Failed';
      item.error = e.toString();
      onUpdate();
    }
  }

  Future<List<EpisodeInfo>> fetchPlaylist(String url) async {
    final ytCmd = await _resolveYtDlp();
    final res = await Process.run(ytCmd, ['--flat-playlist', '-J', url]);
    if (res.exitCode != 0) {
      final err = (res.stderr as String?)?.trim() ?? 'yt-dlp failed';
      throw Exception(err);
    }
    final out = (res.stdout as String).trim();
    final data = json.decode(out);
    final List<dynamic> entries = (data is Map && data['entries'] is List)
        ? (data['entries'] as List)
        : (data is List ? data : <dynamic>[]);
    final List<EpisodeInfo> episodes = [];
    var i = 0;
    for (final e in entries) {
      if (e == null) continue;
      i++;
      final map = e as Map;
      final id = (map['id'] ?? '').toString();
      final rawUrl = (map['url'] ?? '').toString();
      final webpage = (map['webpage_url'] ?? '').toString();
      String epUrl = webpage;
      if (epUrl.isEmpty) {
        if (rawUrl.startsWith('http')) {
          epUrl = rawUrl;
        } else if (id.isNotEmpty) {
          final extractor = (map['ie_key'] ?? '').toString().toLowerCase();
          if (extractor.contains('dailymotion')) {
            epUrl = 'https://www.dailymotion.com/video/$id';
          } else {
            epUrl = 'https://www.youtube.com/watch?v=$id';
          }
        }
      }
      final title = (map['title'] ?? 'Episode $i').toString();
      final durVal = map['duration'];
      String dur = '--:--';
      if (durVal is num) {
        final total = durVal.round();
        final h = total ~/ 3600;
        final m = (total % 3600) ~/ 60;
        final s = total % 60;
        if (h > 0) {
          dur = '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
        } else {
          dur = '$m:${s.toString().padLeft(2, '0')}';
        }
      } else if (durVal is String && durVal.isNotEmpty) {
        dur = durVal;
      }
      if (epUrl.isEmpty) continue;
      episodes.add(EpisodeInfo(url: epUrl, title: title, duration: dur, index: i));
    }
    return episodes;
  }

  void pauseItem(DownloadItem item) {
    item.paused = true;
    item.status = 'Paused';
    item.speed = '--';
    try {
      item.cancelToken?.cancel('Paused');
    } catch (_) {}
    item.cancelToken = null;
    try {
      item.ytProcess?.kill();
    } catch (_) {}
    item.ytProcess = null;
  }
}
