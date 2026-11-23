import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'handlers/download_handler.dart';

class ChunkRange {
  int startByte;
  int currentByte;
  int endByte;
  double bytesPerSecond;
  bool active;
  bool done;
  ChunkRange({
    required this.startByte,
    required this.currentByte,
    required this.endByte,
    this.bytesPerSecond = 0,
    this.active = false,
    this.done = false,
  });

  int get remaining => max(0, endByte - currentByte + 1);
  Map<String, dynamic> toJson() => {
        'startByte': startByte,
        'currentByte': currentByte,
        'endByte': endByte,
      };
  static ChunkRange fromJson(Map<String, dynamic> j) => ChunkRange(
        startByte: (j['startByte'] as num).toInt(),
        currentByte: (j['currentByte'] as num).toInt(),
        endByte: (j['endByte'] as num).toInt(),
        done: (j['currentByte'] as num).toInt() > (j['endByte'] as num).toInt(),
      );
}

class ChunkState {
  final String url;
  final Map<String, String> headers;
  final String? proxyUrl;
  final int? totalBytes;
  final String? etag;
  final String? lastModified;
  final List<ChunkRange> chunks;
  ChunkState({
    required this.url,
    required this.headers,
    required this.proxyUrl,
    required this.totalBytes,
    required this.etag,
    required this.lastModified,
    required this.chunks,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'headers': headers,
        'proxyUrl': proxyUrl,
        'totalBytes': totalBytes,
        'etag': etag,
        'lastModified': lastModified,
        'chunks': chunks.map((c) => c.toJson()).toList(),
      };

  static ChunkState fromJson(Map<String, dynamic> j) => ChunkState(
        url: j['url']?.toString() ?? '',
        headers: (j['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? {},
        proxyUrl: j['proxyUrl']?.toString(),
        totalBytes: (j['totalBytes'] as num?)?.toInt(),
        etag: j['etag']?.toString(),
        lastModified: j['lastModified']?.toString(),
        chunks: ((j['chunks'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => ChunkRange.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class _WriteMutex {
  Future<void> _last = Future.value();
  Future<T> synchronized<T>(Future<T> Function() fn) {
    final next = _last.catchError((_) {}).then((_) => fn());
    _last = next.then((_) {}, onError: (_) {});
    return next;
  }
}

class ChunkDownloader {
  final Dio _dio;
  ChunkDownloader({Dio? dio}) : _dio = dio ?? Dio();

  static String statePathFor(String filePath) => '$filePath.cfstate.json';

  Future<void> download({
    required String url,
    required File outputFile,
    required int? totalBytes,
    required bool supportsRange,
    required Map<String, String> headers,
    String? proxyUrl,
    required int maxConcurrentChunks,
    required void Function(double progress, String speed, String status) onProgress,
    required bool Function() isPaused,
    required bool Function() isCancelled,
  }) async {
    if (proxyUrl != null && proxyUrl.isNotEmpty) {
      _dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
        final c = HttpClient();
        c.findProxy = (_) => 'PROXY ${Uri.parse(proxyUrl).host}:${Uri.parse(proxyUrl).port}';
        return c;
      });
    }

    final stateFile = File(statePathFor(outputFile.path));
    ChunkState? state = await _loadState(stateFile);

    if (totalBytes != null && supportsRange && totalBytes > 1024 * 1024) {
      await _chunkedDownload(
        url: url, outputFile: outputFile, totalBytes: totalBytes,
        headers: headers, proxyUrl: proxyUrl, maxConcurrentChunks: maxConcurrentChunks,
        onProgress: onProgress, isPaused: isPaused, isCancelled: isCancelled,
        stateFile: stateFile, existing: state,
      );
      return;
    }
    await _singleStreamDownload(
      url: url, outputFile: outputFile, headers: headers,
      onProgress: onProgress, isPaused: isPaused, isCancelled: isCancelled,
    );
  }

  Future<void> _singleStreamDownload({
    required String url, required File outputFile, required Map<String, String> headers,
    required void Function(double, String, String) onProgress,
    required bool Function() isPaused, required bool Function() isCancelled,
  }) async {
    final resp = await _dio.get<ResponseBody>(url,
        options: Options(responseType: ResponseType.stream, headers: headers, followRedirects: true));
    final total = int.tryParse(resp.headers.value('content-length') ?? '') ?? 0;
    final sink = outputFile.openWrite();
    int received = 0; int last = 0; var lastT = DateTime.now();
    await for (final chunk in resp.data!.stream) {
      if (isCancelled()) { await sink.close(); throw DownloadCancelled(); }
      if (isPaused()) { await sink.close(); throw DownloadPaused(); }
      sink.add(chunk);
      received += chunk.length;
      final now = DateTime.now();
      final ms = now.difference(lastT).inMilliseconds;
      if (ms >= 500) {
        final bps = (received - last) * 1000 / ms;
        onProgress(total > 0 ? received / total * 100 : 0, _speed(bps), 'Downloading');
        last = received; lastT = now;
      }
    }
    await sink.flush(); await sink.close();
    onProgress(100, '0 KB/s', 'Completed');
  }

  Future<void> _chunkedDownload({
    required String url, required File outputFile, required int totalBytes,
    required Map<String, String> headers, String? proxyUrl, required int maxConcurrentChunks,
    required void Function(double, String, String) onProgress,
    required bool Function() isPaused, required bool Function() isCancelled,
    required File stateFile, ChunkState? existing,
  }) async {
    final n = max(1, min(maxConcurrentChunks, 8));
    List<ChunkRange> chunks;
    if (existing != null && existing.totalBytes == totalBytes && existing.chunks.isNotEmpty) {
      chunks = existing.chunks;
    } else {
      chunks = _buildRanges(totalBytes, n);
    }
    // Pre-allocate file
    final raf = await outputFile.open(mode: FileMode.write);
    await raf.truncate(totalBytes);
    await raf.close();

    final writeMutex = _WriteMutex();
    final state = ChunkState(url: url, headers: headers, proxyUrl: proxyUrl,
        totalBytes: totalBytes, etag: null, lastModified: null, chunks: chunks);
    var lastSave = DateTime.now();
    int downloaded = chunks.fold(0, (p, c) => p + (c.currentByte - c.startByte).clamp(0, c.endByte - c.startByte + 1));

    Future<void> saveState() async {
      await stateFile.writeAsString(json.encode(state.toJson()));
    }

    void updateProgress() {
      final doneBytes = chunks.fold<int>(0, (p, c) {
        final d = c.currentByte > c.endByte ? (c.endByte - c.startByte + 1) : (c.currentByte - c.startByte);
        return p + max(0, d);
      });
      downloaded = doneBytes;
      final bps = chunks.where((c) => c.active).fold<double>(0, (p, c) => p + c.bytesPerSecond);
      onProgress((downloaded / totalBytes) * 100, _speed(bps), 'Downloading');
    }

    Future<void> worker(ChunkRange chunk) async {
      chunk.active = true;
      while (chunk.currentByte <= chunk.endByte) {
        if (isCancelled()) throw DownloadCancelled();
        if (isPaused()) throw DownloadPaused();
        final end = chunk.endByte;
        final start = chunk.currentByte;
        final reqHeaders = {...headers, 'Range': 'bytes=$start-$end'};
        final resp = await _dio.get<ResponseBody>(url,
            options: Options(responseType: ResponseType.stream, headers: reqHeaders, followRedirects: true,
                validateStatus: (s) => s != null && s < 500));
        if (resp.statusCode != 206 && resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        int last = 0; var lastT = DateTime.now();
        await for (final data in resp.data!.stream) {
          if (isCancelled()) throw DownloadCancelled();
          if (isPaused()) throw DownloadPaused();
          final writeOffset = chunk.currentByte;
          await writeMutex.synchronized(() async {
            final rafw = await outputFile.open(mode: FileMode.writeOnlyAppend);
            await rafw.setPosition(writeOffset);
            await rafw.writeFrom(data);
            await rafw.close();
          });
          chunk.currentByte += data.length;
          last += data.length;
          final now = DateTime.now();
          final ms = now.difference(lastT).inMilliseconds;
          if (ms >= 500) {
            chunk.bytesPerSecond = last * 1000 / ms;
            last = 0; lastT = now;
            updateProgress();
          }
          if (DateTime.now().difference(lastSave).inSeconds >= 2) {
            lastSave = DateTime.now();
            await saveState();
          }
          if (chunk.currentByte > chunk.endByte) break;
        }
      }
      chunk.active = false;
      chunk.done = true;
      chunk.bytesPerSecond = 0;
      await saveState();
    }

    Future<void> scheduler() async {
      final active = <Future<void>>[];
      void startChunk(ChunkRange c) {
        final f = worker(c).catchError((e) { if (e is DownloadPaused || e is DownloadCancelled) throw e; throw e; });
        active.add(f);
        f.whenComplete(() => active.remove(f));
      }

      for (final c in chunks) {
        if (c.currentByte <= c.endByte) startChunk(c);
      }

      while (active.isNotEmpty) {
        if (isCancelled()) throw DownloadCancelled();
        if (isPaused()) { await saveState(); throw DownloadPaused(); }
        await Future.delayed(const Duration(milliseconds: 300));
        updateProgress();
        await _stealWork(chunks, startChunk);
        if (DateTime.now().difference(lastSave).inSeconds >= 2) {
          lastSave = DateTime.now(); await saveState();
        }
        if (chunks.every((c) => c.currentByte > c.endByte)) break;
      }
      await Future.wait(List.of(active), eagerError: true);
    }

    try {
      await scheduler();
    } on DownloadPaused {
      await saveState(); rethrow;
    } on DownloadCancelled {
      await saveState(); rethrow;
    }
    await saveState();
    if (chunks.every((c) => c.currentByte > c.endByte)) {
      final len = await outputFile.length();
      if (len == totalBytes) {
        try { await stateFile.delete(); } catch (_) {}
      }
      onProgress(100, '0 KB/s', 'Completed');
    }
  }

  static List<ChunkRange> buildRangesForTest(int totalBytes, int n) => _buildRanges(totalBytes, n);

  static List<ChunkRange> _buildRanges(int totalBytes, int n) {
    final size = (totalBytes / n).ceil();
    final ranges = <ChunkRange>[];
    for (var i = 0; i < n; i++) {
      final start = i * size;
      final end = min(totalBytes - 1, start + size - 1);
      if (start > end) break;
      ranges.add(ChunkRange(startByte: start, currentByte: start, endByte: end));
    }
    return ranges;
  }

  static Future<void> _stealWork(List<ChunkRange> chunks, void Function(ChunkRange) startChunk) async {
    final idle = chunks.where((c) => c.done || (!c.active && c.currentByte > c.endByte)).toList();
    for (final doneChunk in idle) {
      ChunkRange? slow;
      int maxRem = 0;
      for (final c in chunks) {
        if (!c.active) continue;
        final rem = c.endByte - c.currentByte;
        if (rem > maxRem) { maxRem = rem; slow = c; }
      }
      if (slow == null || maxRem <= 2 * 1024 * 1024) return;
      final mid = slow.currentByte + (maxRem ~/ 2);
      final newChunk = ChunkRange(startByte: mid + 1, currentByte: mid + 1, endByte: slow.endByte);
      slow.endByte = mid;
      chunks.add(newChunk);
      startChunk(newChunk);
      doneChunk.done = true;
    }
  }

  static Future<ChunkState?> _loadState(File f) async {
    try {
      if (!await f.exists()) return null;
      return ChunkState.fromJson(json.decode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  static String _speed(double bps) {
    if (bps <= 0) return '0 KB/s';
    if (bps >= 1024 * 1024) return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    return '${(bps / 1024).toStringAsFixed(1)} KB/s';
  }
}
