import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/engine/chunk_downloader.dart';

void main() {
  test('builds non-overlapping ranges for chunking', () {
    final ranges = ChunkDownloader.buildRangesForTest(10 * 1024 * 1024, 4);
    expect(ranges.length, 4);
    for (var i = 0; i < ranges.length; i++) {
      expect(ranges[i].startByte <= ranges[i].endByte, true);
      if (i > 0) expect(ranges[i].startByte, ranges[i - 1].endByte + 1);
    }
    expect(ranges.last.endByte, 10 * 1024 * 1024 - 1);
  });

  test('cfstate json roundtrip', () {
    final state = ChunkState(
      url: 'https://example.com/f.bin',
      headers: {'A': 'B'},
      proxyUrl: null,
      totalBytes: 1000,
      etag: 'e',
      lastModified: 'm',
      chunks: [ChunkRange(startByte: 0, currentByte: 100, endByte: 999)],
    );
    final json = jsonEncode(state.toJson());
    final loaded = ChunkState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(loaded.url, 'https://example.com/f.bin');
    expect(loaded.chunks.first.currentByte, 100);
  });
}
