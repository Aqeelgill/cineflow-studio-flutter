import 'dart:io';

import 'package:cineflow_flutter/core/media_scan_models.dart';
import 'package:cineflow_flutter/services/file_filter_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters media links from JSON content', () async {
    final dir = await Directory.systemTemp.createTemp('cineflow_media_');
    final file = File('${dir.path}/links.json');
    await file.writeAsString('[{"url":"https://example.com/movie.1080p.mkv","title":"Movie"},{"url":"https://example.com/cover.jpg"},{"url":"https://example.com/song.mp3"}]');
    final items = await FileFilterBridge.scanMedia(filePath: file.path);
    expect(items.any((i) => i.url.contains('movie.1080p.mkv')), true);
    expect(items.any((i) => i.url.contains('song.mp3')), true);
    expect(items.any((i) => i.url.contains('cover.jpg')), false);
    await dir.delete(recursive: true);
  });

  test('media filter categories apply correctly', () {
    final items = [
      ScannedMediaItem(url: 'https://x/movie.mkv', title: 'Movie', format: 'MKV', tag: 'Dual Audio / 1080p'),
      ScannedMediaItem(url: 'https://x/song.mp3', title: 'Song', format: 'MP3', tag: ''),
      ScannedMediaItem(url: 'https://youtube.com/watch?v=1', title: 'YT', format: 'MEDIA', tag: ''),
    ];
    expect(items.where((i)=>i.matches(MediaFilter.audioOnly)).length, 1);
    expect(items.where((i)=>i.matches(MediaFilter.moviesVideo)).length, 2);
    expect(items.where((i)=>i.matches(MediaFilter.dualAudio)).length, 1);
    expect(items.where((i)=>i.matches(MediaFilter.hd4k1080)).length, 1);
  });
}
