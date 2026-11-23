import '../core/ram_guard.dart';
export '../core/ram_guard.dart' show RamMode, RamModeX, RamDecision;

class RamGuardService extends RamGuard {
  RamGuardService({super.interval, super.initialMode});
}
