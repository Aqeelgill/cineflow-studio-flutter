import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/core/ram_guard.dart';

void main() {
  test('RAM mode targets and max 65', () {
    expect(RamMode.low.targetPercent, 25);
    expect(RamMode.standard.targetPercent, 45);
    expect(RamMode.maximumAllowed.targetPercent, 65);
  });

  test('65 percent triggers alert and pauses new starts', () {
    final d = RamGuard.evaluate(65, RamMode.maximumAllowed);
    expect(d.alert, true);
    expect(d.shouldPauseNewStarts, true);
    expect(d.allowedConcurrency, 1);
  });

  test('over target reduces concurrency but under 65 does not pause starts', () {
    final d = RamGuard.evaluate(50, RamMode.standard);
    expect(d.alert, false);
    expect(d.shouldPauseNewStarts, false);
    expect(d.shouldReduceConcurrency, true);
    expect(d.allowedConcurrency, 2);
  });
}
