import 'dart:async';

class ProbeResult {
  final Uri resolvedUrl;
  final String fileName;
  final int? totalBytes;
  final String? mimeType;
  final bool supportsRange;
  final bool isStream;
  final List<Map<String, dynamic>> subEntries;
  final Map<String, String> headers;

  const ProbeResult({
    required this.resolvedUrl,
    required this.fileName,
    required this.totalBytes,
    required this.mimeType,
    required this.supportsRange,
    required this.isStream,
    this.subEntries = const [],
    this.headers = const {},
  });

  ProbeResult copyWith({
    Uri? resolvedUrl,
    String? fileName,
    int? totalBytes,
    bool clearTotalBytes = false,
    String? mimeType,
    bool? supportsRange,
    bool? isStream,
    List<Map<String, dynamic>>? subEntries,
    Map<String, String>? headers,
  }) {
    return ProbeResult(
      resolvedUrl: resolvedUrl ?? this.resolvedUrl,
      fileName: fileName ?? this.fileName,
      totalBytes: clearTotalBytes ? null : (totalBytes ?? this.totalBytes),
      mimeType: mimeType ?? this.mimeType,
      supportsRange: supportsRange ?? this.supportsRange,
      isStream: isStream ?? this.isStream,
      subEntries: subEntries ?? this.subEntries,
      headers: headers ?? this.headers,
    );
  }
}

class DownloadTaskContext {
  final String taskId;
  Uri url;
  Map<String, String> headers;
  String? proxyUrl;
  final String saveDir;
  final String fileName;
  final ProbeResult probe;
  final void Function(double progress, String speed, String status) onProgress;
  final void Function(String status, {String? error, String? filePath}) onDone;
  final bool Function() isPaused;
  final bool Function() isCancelled;
  final int maxConcurrentChunks;

  DownloadTaskContext({
    required this.taskId,
    required this.url,
    required this.headers,
    required this.proxyUrl,
    required this.saveDir,
    required this.fileName,
    required this.probe,
    required this.onProgress,
    required this.onDone,
    required this.isPaused,
    required this.isCancelled,
    required this.maxConcurrentChunks,
  });
}

abstract class DownloadHandler {
  int get priority;
  String get name;
  bool canHandle(Uri uri, {String? mimeType});
  Future<ProbeResult> probe(Uri uri, {Map<String, String>? headers});
  Future<void> execute(DownloadTaskContext ctx);
}

class DownloadCancelled implements Exception {
  final String message;
  DownloadCancelled([this.message = 'Cancelled']);
  @override
  String toString() => message;
}

class DownloadPaused implements Exception {
  final String message;
  DownloadPaused([this.message = 'Paused']);
  @override
  String toString() => message;
}
