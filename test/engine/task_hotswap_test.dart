import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/engine/download_engine.dart';
import 'package:cineflow_flutter/core/app_categories.dart';

void main() {
  test('updateTaskSource preserves progress/offset intent by keeping item queued with new source', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://old.example.com/file.bin',
      progress: 42,
      status: 'Downloading',
    );
    item.category = AppCategories.mp4Songs;
    final engine = UniversalDownloadEngine();
    engine.updateTaskSource(item, newUrl: 'https://new.example.com/file.bin', newHeaders: {'Referer': 'https://site'}, proxyUrl: 'http://127.0.0.1:7890');
    expect(item.progress, 42);
    expect(item.status, 'Queued');
    expect(item.url, 'https://new.example.com/file.bin');
    expect(item.headers['Referer'], 'https://site');
    expect(item.proxyUrl, 'http://127.0.0.1:7890');
  });
}
