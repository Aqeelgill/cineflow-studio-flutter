import 'dart:async';
import 'dart:io';

enum RamMode { low, standard, maximumAllowed }

extension RamModeX on RamMode {
  String get id {
    switch (this) {
      case RamMode.low: return 'low';
      case RamMode.standard: return 'standard';
      case RamMode.maximumAllowed: return 'maximum';
    }
  }
  String get label {
    switch (this) {
      case RamMode.low: return 'Low (25%)';
      case RamMode.standard: return 'Standard (45%)';
      case RamMode.maximumAllowed: return 'Maximum (65%)';
    }
  }
  int get targetPercent {
    switch (this) {
      case RamMode.low: return 25;
      case RamMode.standard: return 45;
      case RamMode.maximumAllowed: return 65;
    }
  }
  int get maxConcurrency {
    switch (this) {
      case RamMode.low: return 2;
      case RamMode.standard: return 4;
      case RamMode.maximumAllowed: return 8;
    }
  }
  static RamMode fromId(String? id) {
    for (final m in RamMode.values) { if (m.id == id) return m; }
    return RamMode.standard;
  }
}

class RamDecision {
  final int usedPercent;
  final RamMode mode;
  final bool alert;
  final bool shouldPauseNewStarts;
  final bool shouldReduceConcurrency;
  final int allowedConcurrency;
  const RamDecision({
    required this.usedPercent,
    required this.mode,
    required this.alert,
    required this.shouldPauseNewStarts,
    required this.shouldReduceConcurrency,
    required this.allowedConcurrency,
  });
}

class RamGuard {
  RamGuard({this.interval = const Duration(seconds: 5), RamMode initialMode = RamMode.standard})
      : _mode = initialMode;

  final Duration interval;
  Timer? _timer;
  final _controller = StreamController<RamDecision>.broadcast();
  RamMode _mode;
  int _lastPercent = 0;

  Stream<RamDecision> get stream => _controller.stream;
  RamMode get mode => _mode;
  int get lastPercent => _lastPercent;

  void setMode(RamMode mode) {
    _mode = mode;
    _emit(_lastPercent);
  }

  void start() {
    _timer?.cancel();
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  Future<void> _poll() async {
    final pct = await readUsagePercent();
    _lastPercent = pct;
    _emit(pct);
  }

  void _emit(int pct) {
    if (_controller.isClosed) return;
    _controller.add(evaluate(pct, _mode));
  }

  static RamDecision evaluate(int usedPercent, RamMode mode) {
    final limit = 65;
    final overLimit = usedPercent >= limit;
    final overTarget = usedPercent >= mode.targetPercent;
    int allowed = mode.maxConcurrency;
    if (overLimit) {
      allowed = 1;
    } else if (overTarget) {
      allowed = max(1, (mode.maxConcurrency / 2).floor());
      if (allowed < 1) allowed = 1;
    }
    return RamDecision(
      usedPercent: usedPercent,
      mode: mode,
      alert: overLimit,
      shouldPauseNewStarts: overLimit,
      shouldReduceConcurrency: overLimit || overTarget,
      allowedConcurrency: allowed,
    );
  }

  static int max(int a, int b) => a > b ? a : b;

  static Future<int> readUsagePercent() async {
    try {
      if (Platform.isLinux) {
        final lines = await File('/proc/meminfo').readAsLines();
        int? total; int? avail;
        for (final l in lines) {
          if (l.startsWith('MemTotal:')) total = _kb(l);
          if (l.startsWith('MemAvailable:')) avail = _kb(l);
          if (total != null && avail != null) break;
        }
        if (total == null || total == 0 || avail == null) return 0;
        return (((total - avail) / total) * 100).round().clamp(0, 100);
      }
      if (Platform.isWindows) {
        final res = await Process.run('wmic', ['OS', 'get', 'FreePhysicalMemory,TotalVisibleMemorySize', '/Value']);
        if (res.exitCode != 0) return 0;
        int? free; int? total;
        for (final l in res.stdout.toString().split(RegExp(r'\r?\n'))) {
          if (l.startsWith('FreePhysicalMemory=')) free = int.tryParse(l.split('=').last.trim());
          if (l.startsWith('TotalVisibleMemorySize=')) total = int.tryParse(l.split('=').last.trim());
        }
        if (total == null || total == 0 || free == null) return 0;
        return (((total - free) / total) * 100).round().clamp(0, 100);
      }
    } catch (_) {}
    return 0;
  }

  static int? _kb(String line) {
    final m = RegExp(r'(\d+)').firstMatch(line);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  void dispose() { _timer?.cancel(); _controller.close(); }
}
